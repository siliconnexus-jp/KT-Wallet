import 'dart:convert';
import 'dart:typed_data';

import 'package:chains/chains.dart'
    show
        Chain,
        decodeJsonWithUniqueObjectMembers,
        tronSignedTransactionJsonMaxBytes;
import 'package:chains/rpc.dart';

import '../market/balance_service.dart'
    show RpcEndpointResolver, defaultRpcEndpointFor;
import '../market/gateway_client.dart';
import '../observability/experience_metrics.dart';
import '../rpc/http_transport.dart';
import 'airgap_codec.dart' show hexEncode;
import 'chain_params_service.dart' show rpcCoinForChain;

/// How a broadcast attempt ended.
enum BroadcastStatus {
  /// Accepted by a real node whose answer matched the locally verified hash;
  /// [BroadcastOutcome.txHash] is the local canonical transaction identity.
  ok,

  /// A real node returned a definitive protocol rejection for this exact
  /// payload. It is safe to show a failed state. Ambiguous responses such as
  /// `already known` and `nonce too low` are [unknown], not [error].
  error,

  /// The request started, but no authoritative node answer reached the app.
  /// The transaction may already be on-chain and MUST NOT be submitted again.
  unknown,

  /// The signed payload cannot be submitted with the clients we have — see
  /// the TRON note on [BroadcastService.broadcast].
  unsupported,
}

/// Result of [BroadcastService.broadcast]. [txHash] is non-null exactly for
/// [BroadcastStatus.ok].
class BroadcastOutcome {
  const BroadcastOutcome._(
    this.status, {
    this.txHash,
    this.message,
    this.rejectionKind,
  });
  const BroadcastOutcome.ok(String txHash)
    : this._(BroadcastStatus.ok, txHash: txHash);
  BroadcastOutcome.error(RpcRejectionKind rejectionKind)
    : this._(
        BroadcastStatus.error,
        message: publicRpcRejectionMessage(rejectionKind),
        rejectionKind: rejectionKind,
      );
  const BroadcastOutcome.unknown(String message)
    : this._(BroadcastStatus.unknown, message: message);
  const BroadcastOutcome.unsupported(String message)
    : this._(BroadcastStatus.unsupported, message: message);

  final BroadcastStatus status;
  final String? txHash;
  final String? message;
  final RpcRejectionKind? rejectionKind;
}

/// Compares a node-returned transaction identity with the hash or signature
/// independently derived from the signed bytes before submission.
///
/// EVM and TRON identities are hexadecimal and therefore case-insensitive.
/// Solana transaction signatures are base58 and remain case-sensitive.
bool transactionHashesMatch(Chain chain, String expected, String actual) =>
    switch (chain) {
      Chain.solana => expected == actual,
      Chain.ethereum ||
      Chain.polygon ||
      Chain.base ||
      Chain.arbitrum ||
      Chain.avalanche ||
      Chain.bnb ||
      Chain.tron => expected.toLowerCase() == actual.toLowerCase(),
    };

/// Pushes a signed transaction to the chain's node via the tested
/// `chains/rpc` clients over injectable transports (production defaults to
/// the http-backed ones, which own the 10s timeouts). Endpoints resolve
/// through the same prefs-aware resolver as the market services.
///
/// Broadcast is never auto-retried (INV-15); one call posts at most once.
class BroadcastService {
  BroadcastService({
    JsonRpcTransport? jsonRpcTransport,
    RestTransport? restTransport,
    RpcEndpointResolver? endpoints,
    GatewayResolver? gateway,
  }) : _jsonRpc = jsonRpcTransport ?? HttpJsonRpcTransport(),
       _rest = restTransport ?? HttpRestTransport(),
       _endpoints = endpoints ?? defaultRpcEndpointFor,
       _gateway = gateway ?? _noGateway;

  static GatewayClient? _noGateway() => null;

  final JsonRpcTransport _jsonRpc;
  final RestTransport _rest;
  final RpcEndpointResolver _endpoints;

  /// Optional gateway (null in direct mode), resolved on every broadcast.
  final GatewayResolver _gateway;

  /// Broadcasts [signedTx] on [chain] and returns [expectedTxHash] only after
  /// the node's transaction identity matches it. Outcomes are returned, never
  /// thrown. A node rejection is [error], while response loss, timeout,
  /// malformed responses, identity mismatches and ambiguous node responses
  /// (`already known` / `nonce too low`) are [unknown] because the signed
  /// bytes may already have reached the chain or the nonce may be consumed.
  ///
  /// GATEWAY SEMANTICS: with a gateway configured, `kt_broadcast` is tried
  /// first. No Gateway error can prove that an intermediary did not forward
  /// the signed bytes before returning, including -32000 upstream_error and
  /// -32003 submission_unknown. Every answered error is therefore
  /// outcome-unknown and is never re-posted, regardless of its claimed code.
  /// Only a local [GatewayNetworkUnsupported] raised before `kt_broadcast` may
  /// use the direct path. A direct node may return a definitive rejection,
  /// but `already known` and `nonce too low` still require hash/nonce
  /// reconciliation rather than a terminal failure.
  Future<BroadcastOutcome> broadcast(
    Chain chain,
    Uint8List signedTx, {
    required String expectedTxHash,
  }) => ExperienceMetrics.instance.measure(
    ExperienceMetricNames.transactionBroadcast,
    () => _broadcastBound(chain, signedTx, expectedTxHash: expectedTxHash),
    isSuccess: (outcome) => outcome.status == BroadcastStatus.ok,
  );

  Future<BroadcastOutcome> _broadcastBound(
    Chain chain,
    Uint8List signedTx, {
    required String expectedTxHash,
  }) async {
    if (expectedTxHash.trim().isEmpty) {
      return const BroadcastOutcome.unsupported(
        'Missing locally verified transaction hash',
      );
    }
    final outcome = await _broadcast(chain, signedTx);
    if (outcome.status != BroadcastStatus.ok) return outcome;
    final nodeHash = outcome.txHash;
    if (nodeHash == null ||
        !transactionHashesMatch(chain, expectedTxHash, nodeHash)) {
      return const BroadcastOutcome.unknown(
        'Node returned an inconsistent transaction hash',
      );
    }
    return BroadcastOutcome.ok(expectedTxHash);
  }

  Future<BroadcastOutcome> _broadcast(Chain chain, Uint8List signedTx) async {
    final gateway = _gateway();
    if (gateway != null) {
      final payload = _gatewayPayload(chain, signedTx);
      if (payload == null && chain == Chain.tron) {
        // Same honesty rule as the direct path: a TRON payload that is not
        // the TronGrid JSON transaction cannot be submitted anywhere.
        return const BroadcastOutcome.unsupported(
          'TRON signed payload is not the TronGrid JSON transaction',
        );
      }
      if (payload != null) {
        try {
          return BroadcastOutcome.ok(
            await gateway.broadcast(
              chain: rpcCoinForChain(chain),
              payload: payload,
            ),
          );
        } on GatewayException {
          // An HTTP answer cannot prove the signed payload stayed local to the
          // Gateway process. Even a response claiming upstream rejection,
          // unsupported, or rate-limiting may be stale, malformed, or emitted
          // after a proxy/upstream write. Only GatewayNetworkUnsupported below
          // is a local pre-request fact; every answered error therefore remains
          // unknown and must reconcile by hash instead of becoming a terminal
          // failure or submitting the same bytes to a second node.
          return const BroadcastOutcome.unknown('Gateway response unavailable');
        } on GatewayNetworkUnsupported {
          // Local/health-manifest preflight: no HTTP request was made, so the
          // direct path below remains the one and only submission.
        } on Object {
          return const BroadcastOutcome.unknown('Gateway response unavailable');
        }
      }
    }
    try {
      switch (chain) {
        case Chain.ethereum ||
            Chain.polygon ||
            Chain.base ||
            Chain.arbitrum ||
            Chain.avalanche ||
            Chain.bnb:
          final rpc = EvmRpc(
            url: _endpoints(rpcCoinForChain(chain)),
            transport: _jsonRpc,
          );
          return BroadcastOutcome.ok(
            await rpc.sendRawTransaction('0x${hexEncode(signedTx)}'),
          );
        case Chain.solana:
          final rpc = SolanaRpc(
            url: _endpoints(rpcCoinForChain(chain)),
            transport: _jsonRpc,
          );
          return BroadcastOutcome.ok(
            await rpc.sendTransaction(base64Encode(signedTx)),
          );
        case Chain.tron:
          // TronRpc.broadcast posts the signed transaction as TronGrid's
          // JSON body (`/wallet/broadcasttransaction`). Until the real TRON
          // signing integration (wallet-core) produces that JSON, a signed
          // payload in any other shape honestly cannot be submitted with the
          // client we have — reported as unsupported, never guessed at.
          final Object? decoded;
          try {
            decoded = _decodeTronSignedJson(signedTx);
          } on FormatException {
            return const BroadcastOutcome.unsupported(
              'TRON signed payload is not the TronGrid JSON transaction',
            );
          }
          if (decoded is! Map) {
            return const BroadcastOutcome.unsupported(
              'TRON signed payload is not the TronGrid JSON transaction',
            );
          }
          final rpc = TronRpc(
            baseUrl: _endpoints(rpcCoinForChain(chain)),
            transport: _rest,
          );
          return BroadcastOutcome.ok(await rpc.broadcast(decoded));
      }
    } on RpcRejectedException catch (e) {
      if (_rejectionRequiresReconciliation(e.kind)) {
        // `already known` explicitly says the network has seen this exact raw
        // transaction. `nonce too low` can mean this transaction was mined or
        // another transaction consumed the nonce. Neither response proves the
        // locally verified hash failed, so retain the durable submitted row
        // and let hash/nonce reconciliation determine the terminal outcome.
        return const BroadcastOutcome.unknown(
          'RPC submission may already be known',
        );
      }
      return BroadcastOutcome.error(e.kind);
    } on RpcException {
      return const BroadcastOutcome.unknown('RPC response unavailable');
    } on Object {
      // Timeouts, connection loss and malformed responses are not proof that
      // a signed transaction was rejected. Preserve it for hash polling, and
      // never surface exception text that may contain a keyed custom RPC URL.
      return const BroadcastOutcome.unknown('RPC response unavailable');
    }
  }

  static bool _rejectionRequiresReconciliation(RpcRejectionKind kind) =>
      kind == RpcRejectionKind.alreadyKnown ||
      kind == RpcRejectionKind.nonceTooLow;

  /// Encodes [signedTx] as the contract's `kt_broadcast` payload: 0x-hex for
  /// EVM, base64 for Solana, the TronGrid JSON string for TRON. Returns null
  /// for a TRON payload that is not the TronGrid JSON transaction (the same
  /// shapes the direct path reports as unsupported).
  static String? _gatewayPayload(Chain chain, Uint8List signedTx) {
    switch (chain) {
      case Chain.ethereum ||
          Chain.polygon ||
          Chain.base ||
          Chain.arbitrum ||
          Chain.avalanche ||
          Chain.bnb:
        return '0x${hexEncode(signedTx)}';
      case Chain.solana:
        return base64Encode(signedTx);
      case Chain.tron:
        final String text;
        try {
          text = utf8.decode(signedTx);
          if (_decodeTronSignedJson(signedTx) is! Map) return null;
        } on FormatException {
          return null;
        }
        return text;
    }
  }

  static Object? _decodeTronSignedJson(Uint8List signedTx) {
    if (signedTx.isEmpty ||
        signedTx.length > tronSignedTransactionJsonMaxBytes) {
      throw const FormatException('TRON signed JSON size');
    }
    return decodeJsonWithUniqueObjectMembers(
      utf8.decode(signedTx),
      maxChars: tronSignedTransactionJsonMaxBytes,
    );
  }
}

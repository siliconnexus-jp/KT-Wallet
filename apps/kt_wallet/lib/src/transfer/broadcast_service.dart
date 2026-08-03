import 'dart:convert';
import 'dart:typed_data';

import 'package:chains/chains.dart' show Chain;
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
  /// Accepted by a real node; [BroadcastOutcome.txHash] is the node's answer.
  ok,

  /// A real node returned a syntactically valid response that explicitly
  /// rejected the transaction. It is safe to show a failed state.
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

  /// Broadcasts [signedTx] on [chain] and returns the node's transaction
  /// hash. Outcomes are returned, never thrown. A node rejection is [error],
  /// while response loss, timeout and malformed transport responses are
  /// [unknown] because the signed bytes may already have reached the chain.
  ///
  /// GATEWAY SEMANTICS: with a gateway configured, `kt_broadcast` is tried
  /// first. A -32000 upstream error means a real node explicitly REJECTED the
  /// transaction; -32003 explicitly means the gateway attempted submission
  /// but lost the authoritative answer. Unsupported-network preflight and
  /// gateway rate limiting are known to happen before forwarding, so only
  /// those may use the direct path. Any other gateway failure is
  /// outcome-unknown and is never re-posted.
  Future<BroadcastOutcome> broadcast(Chain chain, Uint8List signedTx) =>
      ExperienceMetrics.instance.measure(
        ExperienceMetricNames.transactionBroadcast,
        () => _broadcast(chain, signedTx),
        isSuccess: (outcome) => outcome.status == BroadcastStatus.ok,
      );

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
        } on GatewayException catch (e) {
          if (e.isUpstreamError) {
            return BroadcastOutcome.error(
              publicRpcRejectionKind(e.upstreamMessage ?? e.message),
            );
          }
          if (e.isSubmissionUnknown) {
            return const BroadcastOutcome.unknown(
              'Gateway response unavailable',
            );
          }
          if (e.isUnsupported || e.isRateLimited) {
            // Both contract errors are emitted before any upstream write.
            // Falling through is therefore still a single node submission.
          } else {
            return const BroadcastOutcome.unknown(
              'Gateway response unavailable',
            );
          }
        } on GatewayNetworkUnsupported {
          // Local/health-manifest preflight: no request was forwarded.
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
            decoded = json.decode(utf8.decode(signedTx));
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
          if (json.decode(text) is! Map) return null;
        } on FormatException {
          return null;
        }
        return text;
    }
  }
}

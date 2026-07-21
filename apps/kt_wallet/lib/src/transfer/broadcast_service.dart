import 'dart:convert';
import 'dart:typed_data';

import 'package:chains/chains.dart' show Chain, sha256;
import 'package:chains/rpc.dart';

import '../market/balance_service.dart'
    show RpcEndpointResolver, defaultRpcEndpointFor;
import '../rpc/http_transport.dart';
import 'airgap_codec.dart' show hexEncode;
import 'chain_params_service.dart' show rpcCoinForChain;

/// How a broadcast attempt ended.
enum BroadcastStatus {
  /// Accepted by a real node; [BroadcastOutcome.txHash] is the node's answer.
  ok,

  /// Demo-signature short-circuit: nothing touched the network, the flow
  /// proceeds on the simulated-success path exactly as before.
  simulated,

  /// A node (or the transport) rejected the transaction;
  /// [BroadcastOutcome.message] carries the reason for the failed UI.
  error,

  /// The signed payload cannot be submitted with the clients we have — see
  /// the TRON note on [BroadcastService.broadcast].
  unsupported,
}

/// Result of [BroadcastService.broadcast]. [txHash] is non-null exactly for
/// [BroadcastStatus.ok] and [BroadcastStatus.simulated].
class BroadcastOutcome {
  const BroadcastOutcome._(this.status, {this.txHash, this.message});
  const BroadcastOutcome.ok(String txHash)
      : this._(BroadcastStatus.ok, txHash: txHash);
  const BroadcastOutcome.simulated(String txHash)
      : this._(BroadcastStatus.simulated, txHash: txHash);
  const BroadcastOutcome.error(String message)
      : this._(BroadcastStatus.error, message: message);
  const BroadcastOutcome.unsupported(String message)
      : this._(BroadcastStatus.unsupported, message: message);

  final BroadcastStatus status;
  final String? txHash;
  final String? message;
}

/// Pushes a signed transaction to the chain's node via the tested
/// `chains/rpc` clients over injectable transports (production defaults to
/// the http-backed ones, which own the 10s timeouts). Endpoints resolve
/// through the same prefs-aware resolver as the market services.
///
/// GATE: demo signatures — the `SIGNED-V1:` bytes produced by
/// `buildDemoSignResult` — are NEVER sent to a real node. The service detects
/// the prefix and short-circuits to the current simulated-success path; real
/// signatures arrive with the wallet-core signing integration.
///
/// Broadcast is never auto-retried (INV-15); one call posts at most once.
class BroadcastService {
  BroadcastService({
    JsonRpcTransport? jsonRpcTransport,
    RestTransport? restTransport,
    RpcEndpointResolver? endpoints,
  })  : _jsonRpc = jsonRpcTransport ?? HttpJsonRpcTransport(),
        _rest = restTransport ?? HttpRestTransport(),
        _endpoints = endpoints ?? defaultRpcEndpointFor;

  final JsonRpcTransport _jsonRpc;
  final RestTransport _rest;
  final RpcEndpointResolver _endpoints;

  /// The demo signature marker (see `buildDemoSignResult`).
  static final Uint8List _demoPrefix =
      Uint8List.fromList(utf8.encode('SIGNED-V1:'));

  /// True when [signedTx] is a simulated-signer payload, not a real signature.
  static bool isDemoSignature(Uint8List signedTx) {
    if (signedTx.length < _demoPrefix.length) return false;
    for (var i = 0; i < _demoPrefix.length; i++) {
      if (signedTx[i] != _demoPrefix[i]) return false;
    }
    return true;
  }

  /// Broadcasts [signedTx] on [chain] and returns the node's transaction
  /// hash. Errors are returned, never thrown — the caller maps them onto the
  /// flow's broadcastError → failed transition.
  Future<BroadcastOutcome> broadcast(Chain chain, Uint8List signedTx) async {
    if (isDemoSignature(signedTx)) {
      // Simulated success, no network: the demo hash matches what
      // buildDemoSignResult put in the SignResult (sha256 of the bytes).
      return BroadcastOutcome.simulated(hexEncode(sha256(signedTx)));
    }
    try {
      switch (chain) {
        case Chain.ethereum || Chain.polygon:
          final rpc = EvmRpc(
              url: _endpoints(rpcCoinForChain(chain)), transport: _jsonRpc);
          return BroadcastOutcome.ok(
              await rpc.sendRawTransaction('0x${hexEncode(signedTx)}'));
        case Chain.solana:
          final rpc = SolanaRpc(
              url: _endpoints(rpcCoinForChain(chain)), transport: _jsonRpc);
          return BroadcastOutcome.ok(
              await rpc.sendTransaction(base64Encode(signedTx)));
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
                'TRON signed payload is not the TronGrid JSON transaction');
          }
          if (decoded is! Map) {
            return const BroadcastOutcome.unsupported(
                'TRON signed payload is not the TronGrid JSON transaction');
          }
          final rpc = TronRpc(
              baseUrl: _endpoints(rpcCoinForChain(chain)), transport: _rest);
          return BroadcastOutcome.ok(await rpc.broadcast(decoded));
      }
    } on RpcException catch (e) {
      return BroadcastOutcome.error(e.message);
    } catch (e) {
      // Timeouts, transport failures, malformed responses.
      return BroadcastOutcome.error('$e');
    }
  }
}

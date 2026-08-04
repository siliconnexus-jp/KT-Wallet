import 'package:chains/chains.dart' show Chain;
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;

import '../market/balance_service.dart'
    show RpcEndpointResolver, defaultRpcEndpointFor;
import '../market/gateway_client.dart';
import '../rpc/http_transport.dart';
import 'chain_params_service.dart' show rpcCoinForChain;

class NetworkIdentityException implements Exception {
  const NetworkIdentityException({
    required this.chain,
    required this.expected,
    required this.actual,
  });

  final Chain chain;
  final String expected;
  final String? actual;

  @override
  String toString() =>
      'RPC network identity mismatch for ${chain.name}: '
      'expected $expected, got ${actual ?? 'unavailable'}';
}

abstract interface class NetworkIdentityVerifier {
  Future<void> verifyEvm(Chain chain, int expectedChainId);
  Future<void> verifySolana(String expectedGenesisHash);
  Future<void> verifyTron(String expectedGenesisBlockId);
}

/// Re-checks the active endpoint immediately before transaction construction.
///
/// Endpoint health alone is insufficient: a healthy URL can be reconfigured
/// to another chain, and signing against it would produce a valid transaction
/// for the wrong network. The comparison is fail-closed and happens before
/// native key access.
class RpcNetworkIdentityVerifier implements NetworkIdentityVerifier {
  RpcNetworkIdentityVerifier({
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
  final GatewayResolver _gateway;

  Future<String?> _gatewayIdentity(Coin coin) async {
    final gateway = _gateway();
    if (gateway == null) return null;
    try {
      return await gateway.getNetworkIdentity(chain: coin);
    } on GatewayNetworkUnsupported {
      // Custom or newer networks are deliberately absent from the Gateway
      // manifest and must verify against their explicit direct endpoint.
      return null;
    } on GatewayTransportException {
      // No trustworthy Gateway response existed, so the privacy-safe direct
      // identity probe is the only remaining source of evidence.
      return null;
    } on GatewayException catch (error) {
      // A deployed pre-1.16.17 Gateway legitimately does not know the new
      // method. Every other answered protocol/upstream error fails closed:
      // in particular, a malformed response or a server-detected wrong
      // upstream must never be hidden by a successful direct fallback.
      if (error.code == -32601) return null;
      rethrow;
    }
  }

  void _requireMatch(Chain chain, String expected, String? actual) {
    if (actual == expected) return;
    throw NetworkIdentityException(
      chain: chain,
      expected: expected,
      actual: actual,
    );
  }

  @override
  Future<void> verifyEvm(Chain chain, int expectedChainId) async {
    final expected = '$expectedChainId';
    final gatewayIdentity = await _gatewayIdentity(rpcCoinForChain(chain));
    if (gatewayIdentity != null) {
      _requireMatch(chain, expected, gatewayIdentity);
      return;
    }
    final endpoint = _endpoints(rpcCoinForChain(chain));
    final response = await _jsonRpc.post(endpoint, {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'eth_chainId',
      'params': const <Object?>[],
    });
    final result = response is Map ? response['result'] : null;
    final actual = result is String && result.startsWith('0x')
        ? int.tryParse(result.substring(2), radix: 16)
        : null;
    _requireMatch(chain, expected, actual?.toString());
  }

  @override
  Future<void> verifySolana(String expectedGenesisHash) async {
    final gatewayIdentity = await _gatewayIdentity(Coin.solana);
    if (gatewayIdentity != null) {
      _requireMatch(Chain.solana, expectedGenesisHash, gatewayIdentity);
      return;
    }
    final endpoint = _endpoints(Coin.solana);
    final response = await _jsonRpc.post(endpoint, {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'getGenesisHash',
      'params': const <Object?>[],
    });
    final actual = response is Map ? response['result'] : null;
    _requireMatch(
      Chain.solana,
      expectedGenesisHash,
      actual is String ? actual : null,
    );
  }

  @override
  Future<void> verifyTron(String expectedGenesisBlockId) async {
    final gatewayIdentity = await _gatewayIdentity(Coin.tron);
    if (gatewayIdentity != null) {
      _requireMatch(Chain.tron, expectedGenesisBlockId, gatewayIdentity);
      return;
    }
    var endpoint = _endpoints(Coin.tron);
    while (endpoint.endsWith('/')) {
      endpoint = endpoint.substring(0, endpoint.length - 1);
    }
    final response = await _rest.postJson(
      '$endpoint/wallet/getblockbynum',
      const {'num': 0},
    );
    final actual = response is Map ? response['blockID'] : null;
    _requireMatch(
      Chain.tron,
      expectedGenesisBlockId,
      actual is String ? actual : null,
    );
  }
}

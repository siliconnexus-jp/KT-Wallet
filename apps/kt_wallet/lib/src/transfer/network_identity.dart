import 'package:chains/chains.dart' show Chain;
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;

import '../market/balance_service.dart'
    show RpcEndpointResolver, defaultRpcEndpointFor;
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
  }) : _jsonRpc = jsonRpcTransport ?? HttpJsonRpcTransport(),
       _rest = restTransport ?? HttpRestTransport(),
       _endpoints = endpoints ?? defaultRpcEndpointFor;

  final JsonRpcTransport _jsonRpc;
  final RestTransport _rest;
  final RpcEndpointResolver _endpoints;

  @override
  Future<void> verifyEvm(Chain chain, int expectedChainId) async {
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
    if (actual != expectedChainId) {
      throw NetworkIdentityException(
        chain: chain,
        expected: '$expectedChainId',
        actual: actual?.toString(),
      );
    }
  }

  @override
  Future<void> verifySolana(String expectedGenesisHash) async {
    final endpoint = _endpoints(Coin.solana);
    final response = await _jsonRpc.post(endpoint, {
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'getGenesisHash',
      'params': const <Object?>[],
    });
    final actual = response is Map ? response['result'] : null;
    if (actual != expectedGenesisHash) {
      throw NetworkIdentityException(
        chain: Chain.solana,
        expected: expectedGenesisHash,
        actual: actual is String ? actual : null,
      );
    }
  }

  @override
  Future<void> verifyTron(String expectedGenesisBlockId) async {
    var endpoint = _endpoints(Coin.tron);
    while (endpoint.endsWith('/')) {
      endpoint = endpoint.substring(0, endpoint.length - 1);
    }
    final response = await _rest.postJson(
      '$endpoint/wallet/getblockbynum',
      const {'num': 0},
    );
    final actual = response is Map ? response['blockID'] : null;
    if (actual != expectedGenesisBlockId) {
      throw NetworkIdentityException(
        chain: Chain.tron,
        expected: expectedGenesisBlockId,
        actual: actual is String ? actual : null,
      );
    }
  }
}

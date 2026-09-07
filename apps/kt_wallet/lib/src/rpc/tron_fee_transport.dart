import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;

import '../market/gateway_client.dart';

/// A read-only adapter for transaction preparation, never used for broadcast.
/// Only custom networks / older gateways fall back to the user's direct node.
/// Rate limits and malformed responses must not cause an anonymous retry burst.
class TronFeeTransport implements RestTransport {
  TronFeeTransport({
    required this.baseUrl,
    required this.gateway,
    required this.direct,
  }) : _network = gateway.activeNetworkId(Coin.tron) ?? 'tron-mainnet';

  final String baseUrl;
  final GatewayClient gateway;
  final RestTransport direct;
  final String _network;
  bool _directOnly = false;

  Future<Object?> _read(
    Future<Object?> Function() read,
    Future<Object?> Function() fallback,
  ) async {
    if (_directOnly) return fallback();
    try {
      return await read();
    } on GatewayNetworkUnsupported {
      _directOnly = true;
    } on GatewayException catch (error) {
      if (error.code != -32601 && !error.isUnsupported) rethrow;
      _directOnly = true;
    }
    return fallback();
  }

  @override
  Future<Object?> getJson(String url) {
    final prefix = '$baseUrl/v1/accounts/';
    if (!url.startsWith(prefix)) {
      throw ArgumentError('unsupported TRON fee read');
    }
    final address = url.substring(prefix.length);
    return _read(
      () => gateway.getTronFeeData(
        operation: 'account',
        address: address,
        networkOverride: _network,
      ),
      () => direct.getJson(url),
    );
  }

  @override
  Future<Object?> postJson(String url, Object body) {
    if (body is! Map) throw ArgumentError('invalid TRON fee request');
    final operation = switch (url) {
      _ when url == '$baseUrl/wallet/getnowblock' => 'block',
      _ when url == '$baseUrl/wallet/getchainparameters' => 'parameters',
      _ when url == '$baseUrl/wallet/getaccountresource' => 'resources',
      _ when url == '$baseUrl/wallet/triggerconstantcontract' => 'constant',
      _ => throw ArgumentError('unsupported TRON fee read'),
    };
    return _read(
      () => gateway.getTronFeeData(
        operation: operation,
        networkOverride: _network,
        address: (body['address'] ?? body['owner_address'] ?? '') as String,
        contract: (body['contract_address'] ?? '') as String,
        selector: (body['function_selector'] ?? '') as String,
        parameter: (body['parameter'] ?? '') as String,
      ),
      () => direct.postJson(url, body),
    );
  }
}

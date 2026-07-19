/// Transport abstraction so `chains` never depends on an HTTP library directly
/// — that keeps the offline signer's dependency tree network-free even though
/// it links `chains` for transaction parsing (tech-plan.md §4). The online app
/// injects a concrete http-backed implementation.
abstract class JsonRpcTransport {
  /// POSTs a JSON body to [url] and returns the decoded JSON response.
  Future<Object?> post(String url, Object body);
}

/// REST GET/POST transport (TronGrid).
abstract class RestTransport {
  Future<Object?> getJson(String url);
  Future<Object?> postJson(String url, Object body);
}

class RpcException implements Exception {
  RpcException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => 'RpcException($code): $message';
}

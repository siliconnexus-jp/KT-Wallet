/// Returns whether [response] is a JSON-RPC 2.0 envelope bound to [request].
///
/// HTTP ordering is not request identity. Providers, proxies and caches can
/// return stale or reordered payloads, so callers must require the exact id
/// value and scalar type before trusting a result or error. JSON-RPC also
/// requires exactly one result/error member and a closed minimum error shape.
bool isBoundJsonRpcResponse(Object request, Object? response) {
  if (request is! Map ||
      request['jsonrpc'] != '2.0' ||
      !request.containsKey('id')) {
    return false;
  }
  final requestId = request['id'];
  if (requestId is! int && requestId is! String) return false;

  if (response is! Map ||
      response['jsonrpc'] != '2.0' ||
      !response.containsKey('id')) {
    return false;
  }
  final responseId = response['id'];
  final idMatches = switch (requestId) {
    int() => responseId is int && responseId == requestId,
    String() => responseId is String && responseId == requestId,
    _ => false,
  };
  if (!idMatches) return false;

  final hasResult = response.containsKey('result');
  final hasError = response.containsKey('error');
  if (hasResult == hasError) return false;
  if (!hasError) return true;

  final error = response['error'];
  return error is Map && error['code'] is int && error['message'] is String;
}

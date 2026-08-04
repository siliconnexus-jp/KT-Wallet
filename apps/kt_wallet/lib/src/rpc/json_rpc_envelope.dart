import 'dart:convert';

/// Decodes JSON while rejecting duplicate object member names at every depth.
///
/// Dart's standard decoder keeps the last value for a duplicate key. That is
/// unsafe at an RPC trust boundary: a proxy and a node could interpret two
/// `result`, `id`, or nested `error.code` members differently. Escaped names
/// are decoded before comparison, so `result` and `re\u0073ult` also collide.
Object? decodeJsonWithoutDuplicateKeys(String source) {
  final scanner = _DuplicateJsonKeyScanner(source);
  if (scanner.scan()) {
    throw const FormatException('duplicate JSON object member');
  }
  return jsonDecode(source);
}

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
  const responseMembers = {'jsonrpc', 'id', 'result', 'error'};
  if (response.keys.any(
    (key) => key is! String || !responseMembers.contains(key),
  )) {
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
  if (error is! Map) return false;
  const errorMembers = {'code', 'message', 'data'};
  if (error.keys.any((key) => key is! String || !errorMembers.contains(key))) {
    return false;
  }
  return error.length >= 2 &&
      error['code'] is int &&
      error['message'] is String;
}

class _DuplicateJsonKeyScanner {
  _DuplicateJsonKeyScanner(this.source);

  static const _maximumDepth = 128;
  final String source;
  int _offset = 0;

  bool scan() {
    _skipWhitespace();
    final duplicate = _scanValue(0);
    _skipWhitespace();
    if (_offset != source.length) {
      throw const FormatException('trailing JSON data');
    }
    return duplicate;
  }

  bool _scanValue(int depth) {
    if (depth > _maximumDepth) {
      throw const FormatException('JSON nesting exceeds limit');
    }
    _skipWhitespace();
    if (_offset >= source.length) {
      throw const FormatException('missing JSON value');
    }
    return switch (source.codeUnitAt(_offset)) {
      0x7b => _scanObject(depth), // {
      0x5b => _scanArray(depth), // [
      0x22 => (_scanString(), false).$2, // "
      _ => _scanPrimitive(),
    };
  }

  bool _scanObject(int depth) {
    _offset++; // {
    _skipWhitespace();
    if (_consume(0x7d)) return false; // }
    final keys = <String>{};
    var duplicate = false;
    while (true) {
      _skipWhitespace();
      if (_offset >= source.length || source.codeUnitAt(_offset) != 0x22) {
        throw const FormatException('JSON object key must be a string');
      }
      final key = _scanString();
      if (!keys.add(key)) duplicate = true;
      _skipWhitespace();
      if (!_consume(0x3a)) {
        throw const FormatException('missing JSON object colon');
      }
      if (_scanValue(depth + 1)) duplicate = true;
      _skipWhitespace();
      if (_consume(0x7d)) return duplicate;
      if (!_consume(0x2c)) {
        throw const FormatException('missing JSON object comma');
      }
    }
  }

  bool _scanArray(int depth) {
    _offset++; // [
    _skipWhitespace();
    if (_consume(0x5d)) return false; // ]
    var duplicate = false;
    while (true) {
      if (_scanValue(depth + 1)) duplicate = true;
      _skipWhitespace();
      if (_consume(0x5d)) return duplicate;
      if (!_consume(0x2c)) {
        throw const FormatException('missing JSON array comma');
      }
    }
  }

  String _scanString() {
    final start = _offset;
    _offset++; // opening quote
    while (_offset < source.length) {
      final code = source.codeUnitAt(_offset++);
      if (code == 0x5c) {
        if (_offset >= source.length) {
          throw const FormatException('truncated JSON escape');
        }
        _offset++;
        continue;
      }
      if (code == 0x22) {
        final decoded = jsonDecode(source.substring(start, _offset));
        if (decoded is! String) {
          throw const FormatException('invalid JSON object key');
        }
        return decoded;
      }
    }
    throw const FormatException('unterminated JSON string');
  }

  bool _scanPrimitive() {
    final start = _offset;
    while (_offset < source.length) {
      final code = source.codeUnitAt(_offset);
      if (code == 0x2c || code == 0x5d || code == 0x7d || _isWhitespace(code)) {
        break;
      }
      _offset++;
    }
    if (_offset == start) throw const FormatException('missing JSON value');
    return false;
  }

  bool _consume(int code) {
    if (_offset < source.length && source.codeUnitAt(_offset) == code) {
      _offset++;
      return true;
    }
    return false;
  }

  void _skipWhitespace() {
    while (_offset < source.length &&
        _isWhitespace(source.codeUnitAt(_offset))) {
      _offset++;
    }
  }

  static bool _isWhitespace(int code) =>
      code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d;
}

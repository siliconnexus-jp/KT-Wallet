import 'dart:convert';

/// Decodes a small local JSON record only after bounding its size and proving
/// that every object member has one unambiguous name. `jsonDecode` otherwise
/// accepts duplicate members and silently keeps the last value.
Object? decodeStrictLocalJson(String source, {required int maxChars}) {
  if (maxChars < 0 || source.length > maxChars) {
    throw const FormatException('JSON record exceeds limit');
  }
  final scanner = _DuplicateJsonKeyScanner(source);
  if (scanner.scan()) {
    throw const FormatException('duplicate JSON object member');
  }
  return jsonDecode(source);
}

class _DuplicateJsonKeyScanner {
  _DuplicateJsonKeyScanner(this.source);

  static const _maximumDepth = 32;
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
      0x7b => _scanObject(depth),
      0x5b => _scanArray(depth),
      0x22 => (_scanString(), false).$2,
      _ => _scanPrimitive(),
    };
  }

  bool _scanObject(int depth) {
    _offset++;
    _skipWhitespace();
    if (_consume(0x7d)) return false;
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
    _offset++;
    _skipWhitespace();
    if (_consume(0x5d)) return false;
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
    _offset++;
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

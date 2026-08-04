/// Validation boundary for user-configurable Gateway and RPC endpoints.
///
/// Wallet traffic contains addresses, balances and unsigned transaction
/// metadata. Public endpoints therefore have to use TLS. Plain HTTP remains
/// available only for loopback development endpoints; credentials embedded in
/// a URL are never accepted because they are easily leaked by logs or UI.
final class EndpointPolicy {
  const EndpointPolicy._();

  /// Large enough for ordinary RPC paths and API query parameters, while
  /// preventing preferences/UI input from turning URL parsing or persistence
  /// into unbounded local work.
  static const maxUrlChars = 2048;

  /// Returns a trimmed, validated endpoint or throws [FormatException].
  static String requireSafeUrl(String value) {
    final normalized = value.trim();
    final uri = Uri.tryParse(normalized);
    if (normalized.isEmpty ||
        normalized.length > maxUrlChars ||
        uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.hasFragment ||
        _rawAuthorityContainsAt(normalized)) {
      throw const FormatException('Invalid endpoint URL');
    }

    final scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') return normalized;
    if (scheme == 'http' && _isLoopback(uri.host)) return normalized;
    throw const FormatException('Endpoint must use HTTPS');
  }

  static bool isSafeUrl(String value) {
    try {
      requireSafeUrl(value);
      return true;
    } on FormatException {
      return false;
    }
  }

  static bool _isLoopback(String host) {
    final normalized = host.toLowerCase();
    return normalized == 'localhost' ||
        normalized == '127.0.0.1' ||
        normalized == '::1';
  }

  static bool _rawAuthorityContainsAt(String value) {
    final start = value.indexOf('://');
    if (start < 0) return false;
    final authorityStart = start + 3;
    var authorityEnd = value.length;
    for (final delimiter in const ['/', '?', '#']) {
      final index = value.indexOf(delimiter, authorityStart);
      if (index >= 0 && index < authorityEnd) authorityEnd = index;
    }
    return value.substring(authorityStart, authorityEnd).contains('@');
  }
}

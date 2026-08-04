import 'package:chains/chains.dart'
    show Base58Error, base58Decode, base58Encode;

final _canonicalEvmChainId = RegExp(r'^0x[1-9a-fA-F][0-9a-fA-F]{0,15}$');
final _canonicalEvmDecimalChainId = RegExp(r'^[1-9][0-9]{0,18}$');
final _canonicalTronGenesis = RegExp(r'^[0-9a-f]{64}$');
final _maximumDartChainId = BigInt.from(0x7fffffffffffffff);

/// Parses a non-zero, canonical EVM JSON-RPC quantity into the app's signed
/// 64-bit chain-id domain. Leading zeroes, signs and uppercase `0X` aliases
/// are rejected; accepted hex letter case is normalized by callers.
int? parseCanonicalEvmChainId(Object? value) {
  if (value is! String || !_canonicalEvmChainId.hasMatch(value)) return null;
  final parsed = BigInt.tryParse(value.substring(2), radix: 16);
  if (parsed == null || parsed <= BigInt.zero || parsed > _maximumDartChainId) {
    return null;
  }
  return parsed.toInt();
}

/// Parses the Gateway's normalized positive decimal EVM chain id into the
/// same signed 64-bit domain used by custom networks and transaction models.
int? parseCanonicalEvmDecimalChainId(Object? value) {
  if (value is! String || !_canonicalEvmDecimalChainId.hasMatch(value)) {
    return null;
  }
  final parsed = BigInt.tryParse(value);
  if (parsed == null || parsed <= BigInt.zero || parsed > _maximumDartChainId) {
    return null;
  }
  return parsed.toInt();
}

/// Returns a canonical Solana genesis hash only when Base58 decodes to the
/// exact 32-byte cluster identity used by `getGenesisHash`.
String? parseCanonicalSolanaGenesisHash(Object? value) {
  if (value is! String) return null;
  try {
    final decoded = base58Decode(value);
    if (decoded.length != 32 || base58Encode(decoded) != value) return null;
    return value;
  } on Base58Error {
    return null;
  }
}

/// Returns a canonical Solana transaction signature only when Base58 decodes
/// to the exact 64-byte Ed25519 signature carried by JSON-RPC responses.
String? parseCanonicalSolanaSignature(Object? value) {
  if (value is! String || value.length > 96) return null;
  try {
    final decoded = base58Decode(value);
    if (decoded.length != 64 || base58Encode(decoded) != value) return null;
    return value;
  } on Base58Error {
    return null;
  }
}

/// Returns TRON block zero's canonical lowercase 32-byte hex identity.
String? parseCanonicalTronGenesisBlockId(Object? value) =>
    value is String && _canonicalTronGenesis.hasMatch(value) ? value : null;

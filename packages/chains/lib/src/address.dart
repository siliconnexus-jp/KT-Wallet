import 'dart:typed_data';

import 'base58.dart';
import 'keccak.dart';
import 'sha256.dart';

/// Supported chains for address validation (matches core_crypto Coin).
enum Chain { ethereum, polygon, base, arbitrum, avalanche, bnb, tron, solana }

/// Validates and normalizes destination addresses per chain, so a wrong-network
/// paste (e.g. a TRON address in an EVM transfer) is caught before building a
/// transaction (detailed-design.md §6.5, ui-m.md §10.3).
class AddressValidation {
  const AddressValidation._(this.isValid, {this.normalized, this.reason});
  final bool isValid;
  final String? normalized;
  final String? reason;

  static AddressValidation ok(String normalized) =>
      AddressValidation._(true, normalized: normalized);
  static AddressValidation bad(String reason) =>
      AddressValidation._(false, reason: reason);
}

abstract final class Addresses {
  /// Compares account identities using the chain's actual address rules.
  ///
  /// EVM hex addresses are case-insensitive; mixed case is only their EIP-55
  /// checksum presentation. TRON and Solana use case-sensitive Base58, so
  /// lowercasing either side would make the comparison incorrect.
  static bool equal(Chain chain, String left, String right) {
    final a = left.trim();
    final b = right.trim();
    return switch (chain) {
      Chain.ethereum ||
      Chain.polygon ||
      Chain.base ||
      Chain.arbitrum ||
      Chain.avalanche ||
      Chain.bnb => a.toLowerCase() == b.toLowerCase(),
      Chain.tron || Chain.solana => a == b,
    };
  }

  static AddressValidation validate(Chain chain, String address) {
    final a = address.trim();
    if (a.isEmpty) return AddressValidation.bad('empty address');
    return switch (chain) {
      Chain.ethereum ||
      Chain.polygon ||
      Chain.base ||
      Chain.arbitrum ||
      Chain.avalanche ||
      Chain.bnb => _validateEvm(a),
      Chain.tron => _validateTron(a),
      Chain.solana => _validateSolana(a),
    };
  }

  // ---- EVM (EIP-55) --------------------------------------------------------

  static final _evmRe = RegExp(r'^0x[0-9a-fA-F]{40}$');

  static AddressValidation _validateEvm(String a) {
    if (!_evmRe.hasMatch(a)) {
      return AddressValidation.bad('not a 20-byte hex address');
    }
    final hexPart = a.substring(2);
    final lower = hexPart.toLowerCase();
    final upper = hexPart.toUpperCase();
    // All-lower or all-upper: no checksum to verify, accept and normalize.
    if (hexPart == lower || hexPart == upper) {
      return AddressValidation.ok(toChecksumAddress(a));
    }
    // Mixed case: must match EIP-55 checksum.
    final checksummed = toChecksumAddress(a);
    if (checksummed == a) {
      return AddressValidation.ok(checksummed);
    }
    return AddressValidation.bad('EIP-55 checksum mismatch');
  }

  /// Applies the EIP-55 mixed-case checksum to a hex address.
  static String toChecksumAddress(String address) {
    final hexPart = address.substring(2).toLowerCase();
    final hash = keccak256(hexPart.codeUnits);
    final out = StringBuffer('0x');
    for (var i = 0; i < hexPart.length; i++) {
      final ch = hexPart[i];
      if (RegExp(r'[0-9]').hasMatch(ch)) {
        out.write(ch);
      } else {
        // Uppercase when the corresponding hash nibble >= 8.
        final nibble = (hash[i ~/ 2] >> (i.isEven ? 4 : 0)) & 0xF;
        out.write(nibble >= 8 ? ch.toUpperCase() : ch);
      }
    }
    return out.toString();
  }

  // ---- TRON (Base58Check, 0x41 prefix) ------------------------------------

  static AddressValidation _validateTron(String a) {
    if (!a.startsWith('T')) {
      return AddressValidation.bad('TRON address starts with T');
    }
    Uint8List decoded;
    try {
      decoded = base58Decode(a);
    } on Base58Error {
      return AddressValidation.bad('invalid base58');
    }
    if (decoded.length != 25) {
      return AddressValidation.bad('wrong length');
    }
    final payload = decoded.sublist(0, 21);
    if (payload[0] != 0x41) {
      return AddressValidation.bad('bad TRON prefix');
    }
    final checksum = decoded.sublist(21);
    final expected = sha256(sha256(payload)).sublist(0, 4);
    if (!_bytesEqual(checksum, expected)) {
      return AddressValidation.bad('checksum mismatch');
    }
    return AddressValidation.ok(a);
  }

  // ---- Solana (base58 of 32-byte ed25519 pubkey) --------------------------

  static AddressValidation _validateSolana(String a) {
    Uint8List decoded;
    try {
      decoded = base58Decode(a);
    } on Base58Error {
      return AddressValidation.bad('invalid base58');
    }
    if (decoded.length != 32) {
      return AddressValidation.bad('not a 32-byte key');
    }
    return AddressValidation.ok(a);
  }

  static bool _bytesEqual(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

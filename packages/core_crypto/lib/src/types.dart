import 'dart:typed_data';

/// Supported chains (SLIP-44 mapping happens on the native side).
enum Coin { eth, polygon, tron, solana }

/// Public addresses derived for one wallet. ETH and Polygon share an address.
class ChainAddresses {
  const ChainAddresses({
    required this.eth,
    required this.polygon,
    required this.tron,
    required this.solana,
  });

  final String eth;
  final String polygon;
  final String tron;
  final String solana;

  String forCoin(Coin coin) => switch (coin) {
        Coin.eth => eth,
        Coin.polygon => polygon,
        Coin.tron => tron,
        Coin.solana => solana,
      };

  Map<String, String> toMap() =>
      {'eth': eth, 'polygon': polygon, 'tron': tron, 'solana': solana};

  static ChainAddresses fromMap(Map<Object?, Object?> map) => ChainAddresses(
        eth: map['eth']! as String,
        polygon: map['polygon']! as String,
        tron: map['tron']! as String,
        solana: map['solana']! as String,
      );
}

/// Result of a native signing operation. Contains only public data.
class SignedTransaction {
  const SignedTransaction({required this.signedTx, required this.txHash});

  /// Fully signed transaction bytes, ready to broadcast.
  final Uint8List signedTx;

  /// Transaction hash (hex, chain-specific format).
  final String txHash;
}

/// Native auth gate state (drives lockout countdown UI).
class AuthState {
  const AuthState({
    required this.locked,
    required this.failCount,
    required this.cooldownSec,
  });

  final bool locked;
  final int failCount;
  final int cooldownSec;

  static AuthState fromMap(Map<Object?, Object?> map) => AuthState(
        locked: map['locked']! as bool,
        failCount: map['failCount']! as int,
        cooldownSec: map['cooldownSec']! as int,
      );
}

/// Mnemonic strengths allowed by ui-m.md (12 / 18 / 24 words).
const allowedMnemonicStrengths = {128, 192, 256};

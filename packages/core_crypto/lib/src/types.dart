import 'dart:typed_data';

/// Supported chains (SLIP-44 mapping happens on the native side).
enum Coin { eth, polygon, base, arbitrum, avalanche, tron, solana }

/// Public addresses derived for one wallet. ETH and Polygon share an address.
class ChainAddresses {
  const ChainAddresses({
    required this.eth,
    required this.polygon,
    String? base,
    String? arbitrum,
    String? avalanche,
    required this.tron,
    required this.solana,
  }) : hasExpandedEvm = base != null || arbitrum != null || avalanche != null,
       base = base ?? eth,
       arbitrum = arbitrum ?? eth,
       avalanche = avalanche ?? eth;

  final String eth;
  final String polygon;
  final String base;
  final String arbitrum;
  final String avalanche;
  final String tron;
  final String solana;
  final bool hasExpandedEvm;

  Iterable<Coin> get enabledCoins => hasExpandedEvm
      ? Coin.values
      : const [Coin.eth, Coin.polygon, Coin.tron, Coin.solana];

  String forCoin(Coin coin) => switch (coin) {
    Coin.eth => eth,
    Coin.polygon => polygon,
    Coin.base => base,
    Coin.arbitrum => arbitrum,
    Coin.avalanche => avalanche,
    Coin.tron => tron,
    Coin.solana => solana,
  };

  Map<String, String> toMap() => {
    'eth': eth,
    'polygon': polygon,
    'base': base,
    'arbitrum': arbitrum,
    'avalanche': avalanche,
    'tron': tron,
    'solana': solana,
  };

  static ChainAddresses fromMap(Map<Object?, Object?> map) => ChainAddresses(
    eth: map['eth']! as String,
    polygon: map['polygon']! as String,
    base: (map['base'] ?? map['eth'])! as String,
    arbitrum: (map['arbitrum'] ?? map['eth'])! as String,
    avalanche: (map['avalanche'] ?? map['eth'])! as String,
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

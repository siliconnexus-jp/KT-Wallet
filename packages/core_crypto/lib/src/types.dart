import 'dart:typed_data';

/// Supported chains (SLIP-44 mapping happens on the native side).
enum Coin { eth, polygon, base, arbitrum, avalanche, bnb, tron, solana }

/// How an authenticated private-key export is placed on the system clipboard.
///
/// [safe] deliberately omits the final six characters. Only that short suffix
/// is returned to Dart for the user to transcribe manually; the complete key
/// never crosses the native boundary. [full] copies the complete key only
/// after a separate UI confirmation and returns an empty suffix.
enum PrivateKeyCopyMode { safe, full }

/// Public addresses derived for one wallet. ETH and Polygon share an address.
class ChainAddresses {
  const ChainAddresses({
    required this.eth,
    required this.polygon,
    String? base,
    String? arbitrum,
    String? avalanche,
    String? bnb,
    required this.tron,
    required this.solana,
  }) : hasExpandedEvm =
           base != null || arbitrum != null || avalanche != null || bnb != null,
       base = base ?? eth,
       arbitrum = arbitrum ?? eth,
       avalanche = avalanche ?? eth,
       bnb = bnb ?? eth;

  final String eth;
  final String polygon;
  final String base;
  final String arbitrum;
  final String avalanche;
  final String bnb;
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
    Coin.bnb => bnb,
    Coin.tron => tron,
    Coin.solana => solana,
  };

  Map<String, String> toMap() => {
    'eth': eth,
    'polygon': polygon,
    'base': base,
    'arbitrum': arbitrum,
    'avalanche': avalanche,
    'bnb': bnb,
    'tron': tron,
    'solana': solana,
  };

  static ChainAddresses fromMap(Map<Object?, Object?> map) => ChainAddresses(
    eth: map['eth']! as String,
    polygon: map['polygon']! as String,
    base: (map['base'] ?? map['eth'])! as String,
    arbitrum: (map['arbitrum'] ?? map['eth'])! as String,
    avalanche: (map['avalanche'] ?? map['eth'])! as String,
    bnb: (map['bnb'] ?? map['eth'])! as String,
    tron: map['tron']! as String,
    solana: map['solana']! as String,
  );
}

class ChainPublicKeys {
  ChainPublicKeys({
    required Uint8List eth,
    required Uint8List polygon,
    Uint8List? base,
    Uint8List? arbitrum,
    Uint8List? avalanche,
    Uint8List? bnb,
    required Uint8List tron,
    required Uint8List solana,
  }) : eth = Uint8List.fromList(eth),
       polygon = Uint8List.fromList(polygon),
       base = Uint8List.fromList(base ?? eth),
       arbitrum = Uint8List.fromList(arbitrum ?? eth),
       avalanche = Uint8List.fromList(avalanche ?? eth),
       bnb = Uint8List.fromList(bnb ?? eth),
       tron = Uint8List.fromList(tron),
       solana = Uint8List.fromList(solana);

  final Uint8List eth;
  final Uint8List polygon;
  final Uint8List base;
  final Uint8List arbitrum;
  final Uint8List avalanche;
  final Uint8List bnb;
  final Uint8List tron;
  final Uint8List solana;

  Uint8List forCoin(Coin coin) => switch (coin) {
    Coin.eth => eth,
    Coin.polygon => polygon,
    Coin.base => base,
    Coin.arbitrum => arbitrum,
    Coin.avalanche => avalanche,
    Coin.bnb => bnb,
    Coin.tron => tron,
    Coin.solana => solana,
  };

  Map<String, Uint8List> toMap() => {
    'eth': eth,
    'polygon': polygon,
    'base': base,
    'arbitrum': arbitrum,
    'avalanche': avalanche,
    'bnb': bnb,
    'tron': tron,
    'solana': solana,
  };

  static ChainPublicKeys fromMap(Map<Object?, Object?> map) => ChainPublicKeys(
    eth: map['eth']! as Uint8List,
    polygon: map['polygon']! as Uint8List,
    base: (map['base'] ?? map['eth'])! as Uint8List,
    arbitrum: (map['arbitrum'] ?? map['eth'])! as Uint8List,
    avalanche: (map['avalanche'] ?? map['eth'])! as Uint8List,
    bnb: (map['bnb'] ?? map['eth'])! as Uint8List,
    tron: map['tron']! as Uint8List,
    solana: map['solana']! as Uint8List,
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

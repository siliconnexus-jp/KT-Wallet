import 'dart:typed_data';

import 'package:core_crypto/core_crypto.dart';

/// Wallet domain model with TYPE-LEVEL signing isolation (INV-14): only
/// [HotWallet] exposes a local-signing capability. Watch-wallet code paths
/// cannot call `signTransaction` because [WatchWallet] has no such method — it
/// is a compile-time impossibility, not a runtime check.
sealed class Wallet {
  Wallet({
    required this.id,
    required this.name,
    required this.avatarColor,
    required this.addresses,
    this.sortOrder = 0,
  });

  final String id;
  final String name;
  final int avatarColor;
  final ChainAddresses addresses;
  final int sortOrder;

  bool get canSignLocally;
}

/// Hot wallet: holds encrypted key material on-device and can sign locally.
class HotWallet extends Wallet {
  HotWallet({
    required super.id,
    required super.name,
    required super.avatarColor,
    required super.addresses,
    super.sortOrder,
    this.backedUp = false,
  });

  /// Whether the mnemonic has been backed up (drives reminders, ui-m.md §8.1).
  final bool backedUp;

  @override
  bool get canSignLocally => true;

  /// The ONLY entry point to local signing. Watch wallets have no equivalent.
  Future<SignedTransaction> sign(
    CoreCrypto crypto, {
    required Coin coin,
    required Uint8List signingInput,
  }) =>
      crypto.signTransaction(
        walletId: id,
        coin: coin,
        signingInput: signingInput,
      );

  HotWallet copyWith({String? name, int? avatarColor, bool? backedUp, int? sortOrder}) =>
      HotWallet(
        id: id,
        name: name ?? this.name,
        avatarColor: avatarColor ?? this.avatarColor,
        addresses: addresses,
        sortOrder: sortOrder ?? this.sortOrder,
        backedUp: backedUp ?? this.backedUp,
      );
}

/// Watch wallet: public addresses only, paired to a Cold Signer. No signing
/// capability exists on this type.
class WatchWallet extends Wallet {
  WatchWallet({
    required super.id,
    required super.name,
    required super.avatarColor,
    required super.addresses,
    super.sortOrder,
    required this.coldWalletId,
    required this.protocolVersion,
  });

  final String coldWalletId;
  final int protocolVersion;

  @override
  bool get canSignLocally => false;

  WatchWallet copyWith({String? name, int? avatarColor, int? sortOrder}) =>
      WatchWallet(
        id: id,
        name: name ?? this.name,
        avatarColor: avatarColor ?? this.avatarColor,
        addresses: addresses,
        sortOrder: sortOrder ?? this.sortOrder,
        coldWalletId: coldWalletId,
        protocolVersion: protocolVersion,
      );
}

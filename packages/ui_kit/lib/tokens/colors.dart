import 'dart:ui';

/// KT Wallet (light, online app) palette — mirrors Pencil `w-*` variables.
abstract final class WalletColors {
  static const bg = Color(0xFFF5F6F8);
  static const surface = Color(0xFFFFFFFF);
  static const text = Color(0xFF0C1220);
  static const text2 = Color(0xFF626B7A);
  static const text3 = Color(0xFF9AA3B2);
  static const accent = Color(0xFF2557E8);
  static const green = Color(0xFF0E9F5B);
  static const red = Color(0xFFDF3E42);
  static const amber = Color(0xFFE8930C);
  static const border = Color(0xFFE7E9EE);
}

/// Cold Signer (dark, offline app) palette — mirrors Pencil `c-*` variables.
abstract final class SignerColors {
  static const bg = Color(0xFF0A0C0F);
  static const surface = Color(0xFF14171D);
  static const surface2 = Color(0xFF1C2027);
  static const text = Color(0xFFF4F6F9);
  static const text2 = Color(0xFF8E97A5);
  static const ok = Color(0xFF34D77B);
  static const warn = Color(0xFFF5B722);
  static const danger = Color(0xFFFF5A5A);
  static const blue = Color(0xFF5B8DEF);
  static const border = Color(0xFF262B34);
}

/// Chain brand colors (network dots/badges).
abstract final class ChainColors {
  static const ethereum = Color(0xFF627EEA);
  static const polygon = Color(0xFF8247E5);
  static const base = Color(0xFF0052FF);
  static const arbitrum = Color(0xFF28A0F0);
  static const avalanche = Color(0xFFE84142);
  static const tron = Color(0xFFEB0029);
  static const solana = Color(0xFF9945FF);
}

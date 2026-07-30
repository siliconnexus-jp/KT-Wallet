import 'dart:convert';

import 'package:chains/chains.dart' show Amount;
import 'package:core_crypto/core_crypto.dart' show Coin;

import '../state/wallet_controller.dart';
import 'balance_service.dart';

/// A display-only last-good market snapshot.
///
/// Cached values make the portfolio useful immediately after launch. They
/// never authorize a transfer: send flows continue to fetch fresh balances,
/// fees and nonces before constructing a transaction.
class MarketSnapshot {
  const MarketSnapshot({
    required this.scope,
    required this.savedAt,
    required this.native,
    required this.tokens,
    required this.nativePrices,
    required this.tokenPrices,
    required this.nativeChanges,
    required this.tokenChanges,
  });

  final String scope;
  final DateTime savedAt;
  final Map<Coin, BalanceResult> native;
  final Map<String, BalanceResult> tokens;
  final Map<Coin, double> nativePrices;
  final Map<String, double> tokenPrices;
  final Map<Coin, double> nativeChanges;
  final Map<String, double> tokenChanges;
}

abstract interface class MarketSnapshotStore {
  Future<MarketSnapshot?> load(String walletId, String scope);
  Future<void> save(String walletId, MarketSnapshot snapshot);
}

/// Stores one network-scoped portfolio snapshot in the wallet's existing
/// versioned settings table. Keeping the scope inside the value prevents a
/// mainnet snapshot from ever appearing while a testnet/custom network is
/// active.
class WalletMarketSnapshotStore implements MarketSnapshotStore {
  WalletMarketSnapshotStore(this._wallets);

  static const _key = 'market.snapshot.v1';
  final WalletController _wallets;

  @override
  Future<MarketSnapshot?> load(String walletId, String scope) async {
    try {
      final encoded = await _wallets.walletSetting(walletId, _key);
      if (encoded == null || encoded.isEmpty) return null;
      final body = jsonDecode(encoded);
      if (body is! Map || body['v'] != 1 || body['scope'] != scope) return null;
      final savedAtMs = body['savedAtMs'];
      if (savedAtMs is! int) return null;
      return MarketSnapshot(
        scope: scope,
        savedAt: DateTime.fromMillisecondsSinceEpoch(savedAtMs),
        native: _decodeNative(body['native']),
        tokens: _decodeTokens(body['tokens']),
        nativePrices: _decodeCoinDoubles(body['nativePrices']),
        tokenPrices: _decodeStringDoubles(body['tokenPrices']),
        nativeChanges: _decodeCoinDoubles(body['nativeChanges']),
        tokenChanges: _decodeStringDoubles(body['tokenChanges']),
      );
    } catch (_) {
      // Corrupt/older cache data or a transient local-store read failure is
      // disposable. The live refresh remains the source of truth.
      return null;
    }
  }

  @override
  Future<void> save(String walletId, MarketSnapshot snapshot) async {
    final body = <String, Object?>{
      'v': 1,
      'scope': snapshot.scope,
      'savedAtMs': snapshot.savedAt.millisecondsSinceEpoch,
      'native': {
        for (final entry in snapshot.native.entries)
          if (_amount(entry.value) case final amount?)
            entry.key.name: _encodeAmount(amount),
      },
      'tokens': {
        for (final entry in snapshot.tokens.entries)
          if (_amount(entry.value) case final amount?)
            entry.key: _encodeAmount(amount),
      },
      'nativePrices': {
        for (final entry in snapshot.nativePrices.entries)
          entry.key.name: entry.value,
      },
      'tokenPrices': snapshot.tokenPrices,
      'nativeChanges': {
        for (final entry in snapshot.nativeChanges.entries)
          entry.key.name: entry.value,
      },
      'tokenChanges': snapshot.tokenChanges,
    };
    await _wallets.putWalletSetting(walletId, _key, jsonEncode(body));
  }

  static Amount? _amount(BalanceResult result) =>
      result.status == BalanceStatus.ok ? result.amount : null;

  static Map<String, Object?> _encodeAmount(Amount amount) => {
    'raw': amount.raw.toString(),
    'decimals': amount.decimals,
    'symbol': amount.symbol,
  };

  static BalanceResult? _decodeAmount(Object? value) {
    if (value is! Map) return null;
    final raw = value['raw'];
    final decimals = value['decimals'];
    final symbol = value['symbol'];
    if (raw is! String || decimals is! int || symbol is! String) return null;
    final parsed = BigInt.tryParse(raw);
    if (parsed == null) return null;
    try {
      return BalanceResult.ok(
        Amount(raw: parsed, decimals: decimals, symbol: symbol),
      );
    } catch (_) {
      return null;
    }
  }

  static Map<Coin, BalanceResult> _decodeNative(Object? value) {
    if (value is! Map) return const {};
    final out = <Coin, BalanceResult>{};
    for (final entry in value.entries) {
      final name = entry.key;
      if (name is! String) continue;
      final coin = Coin.values.where((coin) => coin.name == name).firstOrNull;
      final result = _decodeAmount(entry.value);
      if (coin != null && result != null) out[coin] = result;
    }
    return out;
  }

  static Map<String, BalanceResult> _decodeTokens(Object? value) {
    if (value is! Map) return const {};
    final out = <String, BalanceResult>{};
    for (final entry in value.entries) {
      final id = entry.key;
      final result = _decodeAmount(entry.value);
      if (id is String && result != null) out[id] = result;
    }
    return out;
  }

  static Map<Coin, double> _decodeCoinDoubles(Object? value) {
    if (value is! Map) return const {};
    final out = <Coin, double>{};
    for (final entry in value.entries) {
      final name = entry.key;
      final number = entry.value;
      if (name is! String || number is! num) continue;
      final coin = Coin.values.where((coin) => coin.name == name).firstOrNull;
      if (coin != null) out[coin] = number.toDouble();
    }
    return out;
  }

  static Map<String, double> _decodeStringDoubles(Object? value) {
    if (value is! Map) return const {};
    return {
      for (final entry in value.entries)
        if (entry.key is String && entry.value is num)
          entry.key as String: (entry.value as num).toDouble(),
    };
  }
}

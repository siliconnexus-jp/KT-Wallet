import 'dart:convert';

import 'package:chains/chains.dart' show Amount;
import 'package:core_crypto/core_crypto.dart' show Coin;

import '../state/wallet_controller.dart';
import '../rpc/json_rpc_envelope.dart';
import 'balance_service.dart';
import 'fiat_math.dart';
import 'snapshot_boundary.dart';

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
    this.fiatPerUsd = const {'USD': 1},
  });

  final String scope;
  final DateTime savedAt;
  final Map<Coin, BalanceResult> native;
  final Map<String, BalanceResult> tokens;
  final Map<Coin, double> nativePrices;
  final Map<String, double> tokenPrices;
  final Map<Coin, double> nativeChanges;
  final Map<String, double> tokenChanges;
  final Map<String, double> fiatPerUsd;
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
  static const maxSnapshotChars = 262144;
  static const _maxTokens = 512;
  static const _topV1 = {
    'v',
    'scope',
    'savedAtMs',
    'native',
    'tokens',
    'nativePrices',
    'tokenPrices',
    'nativeChanges',
    'tokenChanges',
  };
  static const _topV2 = {..._topV1, 'fiatPerUsd'};
  static const _amountMembers = {'raw', 'decimals', 'symbol'};
  static const _fiatSymbols = {'USD', 'CNY', 'JPY'};
  final WalletController _wallets;

  @override
  Future<MarketSnapshot?> load(String walletId, String scope) async {
    try {
      final encoded = await _wallets.walletSetting(walletId, _key);
      if (encoded == null || encoded.isEmpty) return null;
      final decoded = decodeJsonWithoutDuplicateKeys(
        encoded,
        maxChars: maxSnapshotChars,
      );
      if (decoded is! Map) return null;
      final rawVersion = decoded['v'];
      if (rawVersion != 1 && rawVersion != 2) return null;
      final body = requireExactSnapshotObject(
        decoded,
        members: rawVersion == 1 ? _topV1 : _topV2,
      );
      if (requireBoundedSnapshotText(body['scope'], maxChars: 4096) != scope) {
        return null;
      }
      final version = body['v'];
      final savedAtMs = requireSnapshotEpochMillis(body['savedAtMs']);
      return MarketSnapshot(
        scope: scope,
        savedAt: DateTime.fromMillisecondsSinceEpoch(savedAtMs),
        native: _decodeNative(body['native']),
        tokens: _decodeTokens(body['tokens']),
        nativePrices: _decodeCoinDoubles(body['nativePrices'], positive: true),
        tokenPrices: _decodeStringDoubles(body['tokenPrices'], positive: true),
        nativeChanges: _decodeCoinDoubles(body['nativeChanges']),
        tokenChanges: _decodeStringDoubles(body['tokenChanges']),
        fiatPerUsd: version == 1
            ? const {'USD': 1}
            : _decodeFiat(body['fiatPerUsd']),
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
      'v': 2,
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
      'fiatPerUsd': snapshot.fiatPerUsd,
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

  static BalanceResult _decodeAmount(Object? value) {
    final amount = requireExactSnapshotObject(value, members: _amountMembers);
    final raw = amount['raw'];
    final decimals = amount['decimals'];
    final symbol = requireBoundedSnapshotText(
      amount['symbol'],
      maxChars: 128,
      allowEmpty: true,
    );
    if (raw is! String ||
        raw.isEmpty ||
        raw.length > 78 ||
        !RegExp(r'^\d+$').hasMatch(raw) ||
        decimals is! int) {
      throw const FormatException('snapshot amount is invalid');
    }
    final parsed = BigInt.tryParse(raw);
    if (parsed == null) throw const FormatException('invalid amount integer');
    return BalanceResult.ok(
      Amount(raw: parsed, decimals: decimals, symbol: symbol),
    );
  }

  static Map<Coin, BalanceResult> _decodeNative(Object? value) {
    if (value is! Map || value.length > Coin.values.length) {
      throw const FormatException('native snapshot map is invalid');
    }
    final out = <Coin, BalanceResult>{};
    for (final entry in value.entries) {
      final name = entry.key;
      if (name is! String) {
        throw const FormatException('native snapshot key is invalid');
      }
      final coin = Coin.values.where((coin) => coin.name == name).firstOrNull;
      final result = _decodeAmount(entry.value);
      if (coin == null) throw const FormatException('unknown snapshot coin');
      out[coin] = result;
    }
    return Map.unmodifiable(out);
  }

  static Map<String, BalanceResult> _decodeTokens(Object? value) {
    if (value is! Map || value.length > _maxTokens) {
      throw const FormatException('token snapshot map is invalid');
    }
    final out = <String, BalanceResult>{};
    for (final entry in value.entries) {
      final id = requireBoundedSnapshotText(entry.key, maxChars: 256);
      final result = _decodeAmount(entry.value);
      out[id] = result;
    }
    return Map.unmodifiable(out);
  }

  static Map<Coin, double> _decodeCoinDoubles(
    Object? value, {
    bool positive = false,
  }) {
    if (value is! Map || value.length > Coin.values.length) {
      throw const FormatException('coin market map is invalid');
    }
    final out = <Coin, double>{};
    for (final entry in value.entries) {
      final name = entry.key;
      if (name is! String) {
        throw const FormatException('coin market key is invalid');
      }
      final coin = Coin.values.where((coin) => coin.name == name).firstOrNull;
      if (coin == null) throw const FormatException('unknown market coin');
      final number = positive
          ? positiveFiniteMarketNumber(entry.value)
          : finiteMarketNumber(entry.value);
      if (number == null || (!positive && number.abs() > 1e9)) {
        throw const FormatException('market number is invalid');
      }
      out[coin] = number;
    }
    return Map.unmodifiable(out);
  }

  static Map<String, double> _decodeStringDoubles(
    Object? value, {
    bool positive = false,
    Set<String>? allowedKeys,
  }) {
    if (value is! Map || value.length > _maxTokens) {
      throw const FormatException('token market map is invalid');
    }
    final out = <String, double>{};
    for (final entry in value.entries) {
      final key = requireBoundedSnapshotText(entry.key, maxChars: 256);
      if (allowedKeys != null && !allowedKeys.contains(key)) {
        throw const FormatException('unknown market key');
      }
      final number = positive
          ? positiveFiniteMarketNumber(entry.value)
          : finiteMarketNumber(entry.value);
      if (number == null || (!positive && number.abs() > 1e9)) {
        throw const FormatException('market number is invalid');
      }
      out[key] = number;
    }
    return Map.unmodifiable(out);
  }

  static Map<String, double> _decodeFiat(Object? value) {
    final rates = _decodeStringDoubles(
      value,
      positive: true,
      allowedKeys: _fiatSymbols,
    );
    if (rates['USD'] != 1) {
      throw const FormatException('USD snapshot rate must equal one');
    }
    return rates;
  }
}

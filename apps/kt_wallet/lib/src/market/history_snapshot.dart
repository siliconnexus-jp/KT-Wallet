import 'dart:convert';

import 'package:core_crypto/core_crypto.dart' show Coin;

import '../state/wallet_controller.dart';
import 'history_service.dart';

/// Network-scoped, display-only snapshot of remote chain history.
///
/// The local transaction table remains authoritative for transactions created
/// by this app. This snapshot only avoids an empty history surface during a
/// cold start or a temporary explorer outage.
class HistorySnapshot {
  const HistorySnapshot({
    required this.scope,
    required this.savedAt,
    required this.results,
  });

  final String scope;
  final DateTime savedAt;
  final Map<Coin, HistoryResult> results;
}

abstract interface class HistorySnapshotStore {
  Future<HistorySnapshot?> load(String walletId, String scope);
  Future<void> save(String walletId, HistorySnapshot snapshot);
}

class WalletHistorySnapshotStore implements HistorySnapshotStore {
  WalletHistorySnapshotStore(this._wallets);

  static const _key = 'history.snapshot.v1';
  final WalletController _wallets;

  @override
  Future<HistorySnapshot?> load(String walletId, String scope) async {
    try {
      final encoded = await _wallets.walletSetting(walletId, _key);
      if (encoded == null || encoded.isEmpty) return null;
      final body = jsonDecode(encoded);
      if (body is! Map || body['scope'] != scope) return null;
      final version = body['v'];
      if (version != 1 && version != 2 && version != 3) return null;
      final savedAtMs = body['savedAtMs'];
      final rows = body['results'];
      if (savedAtMs is! int || rows is! Map) return null;
      final results = <Coin, HistoryResult>{};
      for (final entry in rows.entries) {
        final name = entry.key;
        if (name is! String || entry.value is! List) continue;
        final coin = Coin.values.where((coin) => coin.name == name).firstOrNull;
        if (coin == null) continue;
        final records = <ChainTxRecord>[];
        for (final value in entry.value as List) {
          final record = _decodeRecord(coin, value);
          if (record != null) records.add(record);
        }
        results[coin] = HistoryResult.ok(List.unmodifiable(records));
      }
      if (results.isEmpty) return null;
      return HistorySnapshot(
        scope: scope,
        savedAt: DateTime.fromMillisecondsSinceEpoch(savedAtMs),
        results: Map.unmodifiable(results),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(String walletId, HistorySnapshot snapshot) async {
    final body = <String, Object?>{
      'v': 3,
      'scope': snapshot.scope,
      'savedAtMs': snapshot.savedAt.millisecondsSinceEpoch,
      'results': {
        for (final entry in snapshot.results.entries)
          if (entry.value.status == HistoryStatus.ok)
            entry.key.name: [
              for (final record in entry.value.records) _encodeRecord(record),
            ],
      },
    };
    await _wallets.putWalletSetting(walletId, _key, jsonEncode(body));
  }

  static Map<String, Object?> _encodeRecord(ChainTxRecord record) => {
    'id': record.id,
    'networkId': record.networkId,
    'hash': record.hash,
    'outgoing': record.outgoing,
    'from': record.fromAddress,
    'to': record.toAddress,
    'amount': record.amountText,
    'contract': record.assetContract,
    'symbol': record.assetSymbol,
    'verified': record.assetVerified,
    'timestampMs': record.timestamp.millisecondsSinceEpoch,
    'status': record.status.name,
  };

  static ChainTxRecord? _decodeRecord(Coin coin, Object? value) {
    if (value is! Map) return null;
    final hash = value['hash'];
    final outgoing = value['outgoing'];
    final timestampMs = value['timestampMs'];
    final rawStatus = value['status'];
    final legacyConfirmed = value['confirmed'];
    if (hash is! String ||
        hash.isEmpty ||
        outgoing is! bool ||
        timestampMs is! int) {
      return null;
    }
    final status = rawStatus is String
        ? ChainTxStatus.values
              .where((item) => item.name == rawStatus)
              .firstOrNull
        : legacyConfirmed is bool
        ? (legacyConfirmed ? ChainTxStatus.confirmed : ChainTxStatus.failed)
        : null;
    if (status == null) return null;
    return ChainTxRecord(
      coin: coin,
      networkId:
          value['networkId'] is String &&
              (value['networkId'] as String).isNotEmpty
          ? value['networkId'] as String
          : null,
      id: value['id'] is String ? value['id'] as String : null,
      hash: hash,
      outgoing: outgoing,
      fromAddress: value['from'] is String ? value['from'] as String : null,
      toAddress: value['to'] is String ? value['to'] as String : null,
      amountText: value['amount'] is String ? value['amount'] as String : null,
      assetContract: value['contract'] is String
          ? value['contract'] as String
          : null,
      assetSymbol: value['symbol'] is String ? value['symbol'] as String : null,
      assetVerified: value['verified'] is bool
          ? value['verified'] as bool
          : true,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      status: status,
    );
  }
}

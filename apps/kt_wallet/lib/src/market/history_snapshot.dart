import 'dart:convert';

import 'package:core_crypto/core_crypto.dart' show Coin;

import '../state/wallet_controller.dart';
import '../rpc/json_rpc_envelope.dart';
import 'history_service.dart';
import 'snapshot_boundary.dart';

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
  static const maxSnapshotChars = 1048576;
  static const _maxRecordsPerCoin = 100;
  static const _topMembers = {'v', 'scope', 'savedAtMs', 'results'};
  static const _recordV1 = {
    'id',
    'hash',
    'outgoing',
    'from',
    'to',
    'amount',
    'contract',
    'symbol',
    'verified',
    'timestampMs',
    'confirmed',
  };
  static const _recordV2 = {
    'id',
    'hash',
    'outgoing',
    'from',
    'to',
    'amount',
    'contract',
    'symbol',
    'verified',
    'timestampMs',
    'status',
  };
  static const _recordV3 = {..._recordV2, 'networkId'};
  final WalletController _wallets;

  @override
  Future<HistorySnapshot?> load(String walletId, String scope) async {
    try {
      final encoded = await _wallets.walletSetting(walletId, _key);
      if (encoded == null || encoded.isEmpty) return null;
      final decoded = decodeJsonWithoutDuplicateKeys(
        encoded,
        maxChars: maxSnapshotChars,
      );
      final body = requireExactSnapshotObject(decoded, members: _topMembers);
      if (requireBoundedSnapshotText(body['scope'], maxChars: 4096) != scope) {
        return null;
      }
      final rawVersion = body['v'];
      if (rawVersion != 1 && rawVersion != 2 && rawVersion != 3) return null;
      final version = rawVersion as int;
      final savedAtMs = requireSnapshotEpochMillis(body['savedAtMs']);
      final rows = body['results'];
      if (rows is! Map || rows.isEmpty || rows.length > Coin.values.length) {
        return null;
      }
      final results = <Coin, HistoryResult>{};
      for (final entry in rows.entries) {
        final name = entry.key;
        if (name is! String || entry.value is! List) {
          throw const FormatException('history result map is invalid');
        }
        final coin = Coin.values.where((coin) => coin.name == name).firstOrNull;
        if (coin == null) throw const FormatException('unknown history coin');
        final values = entry.value as List;
        if (values.length > _maxRecordsPerCoin) {
          throw const FormatException('history record limit exceeded');
        }
        final records = <ChainTxRecord>[];
        for (final value in values) {
          records.add(_decodeRecord(coin, value, version));
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

  static ChainTxRecord _decodeRecord(Coin coin, Object? value, int version) {
    final record = requireExactSnapshotObject(
      value,
      members: switch (version) {
        1 => _recordV1,
        2 => _recordV2,
        _ => _recordV3,
      },
    );
    final hash = requireBoundedSnapshotText(record['hash'], maxChars: 256);
    final outgoing = record['outgoing'];
    final timestampMs = requireSnapshotEpochMillis(record['timestampMs']);
    final verified = record['verified'];
    if (outgoing is! bool || verified is! bool) {
      throw const FormatException('history booleans are invalid');
    }
    final status = version == 1
        ? switch (record['confirmed']) {
            true => ChainTxStatus.confirmed,
            false => ChainTxStatus.failed,
            _ => throw const FormatException('legacy status is invalid'),
          }
        : ChainTxStatus.values
              .where((item) => item.name == record['status'])
              .firstOrNull;
    if (status == null) throw const FormatException('status is invalid');
    return ChainTxRecord(
      coin: coin,
      networkId: version == 3
          ? requireNullableSnapshotText(record['networkId'], maxChars: 256)
          : null,
      id: requireNullableSnapshotText(record['id'], maxChars: 512),
      hash: hash,
      outgoing: outgoing,
      fromAddress: requireNullableSnapshotText(record['from'], maxChars: 256),
      toAddress: requireNullableSnapshotText(record['to'], maxChars: 256),
      amountText: requireNullableSnapshotText(record['amount'], maxChars: 256),
      assetContract: requireNullableSnapshotText(
        record['contract'],
        maxChars: 256,
      ),
      assetSymbol: requireNullableSnapshotText(record['symbol'], maxChars: 128),
      assetVerified: verified,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs),
      status: status,
    );
  }
}

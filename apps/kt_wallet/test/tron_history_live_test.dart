import 'dart:io';

import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/market/history_service.dart';

void main() {
  final live = Platform.environment['KT_LIVE_TRON_HISTORY'] == '1';

  test(
    'TronGrid public account direct history matches the strict schema',
    () async {
      // Public account from TronGrid's reviewed history fixtures. The test
      // performs three read-only GETs and never loads a key or broadcasts.
      const owner = 'TJmmqjb1DK9TTZbQXzRQ2AuA94z4gKAPFh';
      final service = HistoryService(timeout: const Duration(seconds: 20));
      addTearDown(service.close);

      final history = await service.fetch(Coin.tron, owner, limit: 3);
      expect(history.status, HistoryStatus.ok);
      expect(history.records, isNotEmpty);
      for (final record in history.records) {
        expect(record.hash, matches(RegExp(r'^[0-9a-fA-F]{64}$')));
        expect(record.amountText, isNotNull);
        expect(
          record.fromAddress == owner || record.toAddress == owner,
          isTrue,
        );
      }
    },
    skip: live ? false : 'set KT_LIVE_TRON_HISTORY=1',
    timeout: const Timeout(Duration(seconds: 60)),
  );
}

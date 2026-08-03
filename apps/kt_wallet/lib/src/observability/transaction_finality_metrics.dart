import 'package:wallet_data/wallet_data.dart' as db;

import 'experience_metrics.dart';

/// Records one privacy-minimal finality sample after a terminal state has
/// been durably applied to the local transaction store.
///
/// Callers must win the repository's live-row compare-and-set before invoking
/// this helper. That rule makes concurrent history and detail pollers converge
/// on one metric instead of double-counting the same terminal transition.
void recordTerminalTransactionFinality(
  db.Transaction transaction,
  db.TxStatus status,
  int settledAt,
) {
  final success = switch (status) {
    db.TxStatus.confirmed => true,
    db.TxStatus.failed || db.TxStatus.replaced || db.TxStatus.expired => false,
    _ => null,
  };
  if (success == null) return;
  final startedAt = transaction.broadcastAt ?? transaction.createdAt;
  final elapsedMs = settledAt - startedAt;
  if (elapsedMs < 0) return;
  ExperienceMetrics.instance.record(
    ExperienceMetricNames.transactionFinality,
    Duration(milliseconds: elapsedMs),
    success: success,
  );
}

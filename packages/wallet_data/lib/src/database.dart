import 'package:drift/drift.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Wallets,
    Accounts,
    Tokens,
    Balances,
    Transactions,
    FinalityMetrics,
    AddressBook,
    SignRequests,
    Settings,
    WalletSettings,
    Contacts,
    CustomTokens,
  ],
)
class WalletDatabase extends _$WalletDatabase {
  WalletDatabase(super.e);

  /// v1: initial schema.
  /// v2: global `contacts` (address book) + `custom_tokens` tables.
  /// v3: EVM nonce/fee metadata and transaction-replacement lineage.
  /// v4: per-transaction network id (mainnet/testnet/custom instance).
  /// v5: TRON TAPOS/expiration and Solana last-valid-block-height metadata.
  /// v6: persisted timestamp of the latest hash-specific status lookup.
  /// v7: persisted pending/unknown outcome of that lookup.
  /// v8: explicit transfer / ERC-20 approval-revoke transaction operation.
  /// v9: crash-safe, privacy-minimal transaction-finality metric ring.
  /// v10: invalidate legacy hot-wallet backup flags. Before v10 mnemonic
  /// imports were incorrectly persisted as backed up without an explicit
  /// backup confirmation, so the old boolean cannot be trusted.
  /// v11: exact network identity for user-added custom tokens. Legacy rows
  /// remain null rather than guessing across EVM networks.
  @override
  int get schemaVersion => 11;

  /// Backfill map for [Transactions.networkId]: the chain family's MAINNET
  /// network id, keyed by the `coin` column. Kept as literals because
  /// wallet_data must not depend on the app's network registry.
  static const _mainnetNetworkIdByCoin = {
    'eth': 'eth-mainnet',
    'polygon': 'polygon-mainnet',
    'base': 'base-mainnet',
    'arbitrum': 'arbitrum-mainnet',
    'avalanche': 'avalanche-mainnet',
    'bnb': 'bnb-mainnet',
    'tron': 'tron-mainnet',
    'solana': 'sol-mainnet',
  };

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) => m.createAll(),
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await m.createTable(contacts);
        await m.createTable(customTokens);
      }
      if (from < 3) {
        await m.addColumn(transactions, transactions.nonce);
        await m.addColumn(transactions, transactions.maxPriorityFeeRaw);
        await m.addColumn(transactions, transactions.maxFeeRaw);
        await m.addColumn(transactions, transactions.gasLimitRaw);
        await m.addColumn(transactions, transactions.replacesId);
        await m.addColumn(transactions, transactions.replacedById);
        await m.addColumn(transactions, transactions.replacementKind);
      }
      if (from < 4) {
        await m.addColumn(transactions, transactions.networkId);
        // BACKFILL: rows written before v4 carry no network dimension, so the
        // instance they were actually broadcast on is not recoverable. They
        // are attributed to their chain's MAINNET id — the app's default
        // environment, and the safe direction: a testnet row mislabelled as
        // mainnet is merely refused for speed-up/cancel while mainnet is
        // active, whereas guessing a testnet would let a mainnet row be
        // replaced on a testnet. Rows whose coin is unknown stay NULL and are
        // likewise treated as "unknown network" (no replacement).
        for (final entry in _mainnetNetworkIdByCoin.entries) {
          await customStatement(
            'UPDATE transactions SET network_id = ? '
            'WHERE network_id IS NULL AND coin = ?',
            [entry.value, entry.key],
          );
        }
      }
      if (from < 5) {
        await m.addColumn(transactions, transactions.referenceBlockHeight);
        await m.addColumn(transactions, transactions.expiresAt);
        await m.addColumn(transactions, transactions.lastValidBlockHeight);
      }
      if (from < 6) {
        await m.addColumn(transactions, transactions.lastCheckedAt);
      }
      if (from < 7) {
        await m.addColumn(transactions, transactions.lastCheckOutcome);
      }
      if (from < 8) {
        await m.addColumn(transactions, transactions.operation);
      }
      if (from < 9) {
        await m.createTable(finalityMetrics);
      }
      if (from < 10) {
        // WalletType.hot is intEnum value 0. Reset once, fail-safe: genuinely
        // backed-up users only need to reconfirm, while an unbacked wallet can
        // no longer silently lose its reminder.
        await customStatement(
          'UPDATE wallets SET backed_up = 0 WHERE type = 0',
        );
      }
      // A v1 upgrade creates `custom_tokens` above from the current table
      // definition, which already contains this column. Existing v2-v10
      // databases need the additive migration.
      if (from >= 2 && from < 11) {
        await m.addColumn(customTokens, customTokens.networkId);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

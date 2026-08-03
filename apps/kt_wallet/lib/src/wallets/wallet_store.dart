import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:drift/drift.dart';
import 'package:wallet_data/wallet_data.dart' as db;

import 'wallet_manager.dart';
import 'wallet_model.dart';

/// Bridges the persistent wallet_data layer (drift) and the in-memory
/// [WalletManager] domain model: loads domain wallets from the database and
/// persists domain wallets back. A wallet's addresses live in the accounts
/// table (detailed-design.md §5.1), so a domain [Wallet] is assembled from its
/// wallet row + its four account rows.
class WalletStore {
  WalletStore(this._db)
    : _wallets = db.WalletsRepository(_db),
      _contacts = db.ContactsRepository(_db),
      _tokens = db.TokensRepository(_db);
  final db.WalletDatabase _db;
  final db.WalletsRepository _wallets;
  final db.ContactsRepository _contacts;
  final db.TokensRepository _tokens;

  static const _coins = ['eth', 'polygon', 'tron', 'solana'];
  static const deletionPendingKey = 'wallet.delete.pending.v1';
  static const _deletionPendingValue = '1';

  /// Loads all wallets into a fresh [WalletManager].
  Future<WalletManager> load() async {
    final rows = await _wallets.listAll();
    final domain = <Wallet>[];
    for (final row in rows) {
      // A durable delete intent is written before native key removal. Never
      // expose that wallet again while startup finishes the idempotent cleanup;
      // this also closes the crash window after Keychain/Keystore deletion but
      // before the Drift cascade commits.
      if (await _wallets.scoped(row.id).setting(deletionPendingKey) ==
          _deletionPendingValue) {
        continue;
      }
      final accounts = await _wallets.scoped(row.id).accounts();
      domain.add(_toDomain(row, accounts));
    }
    return WalletManager(initial: domain);
  }

  /// Persists a domain wallet: the wallet row + its four account rows, in one
  /// transaction.
  Future<void> save(Wallet wallet) => _db.transaction(() async {
    await _wallets.insert(_walletCompanion(wallet));
    final scoped = _wallets.scoped(wallet.id);
    for (final coin in _coins) {
      await scoped.upsertAccount(_accountCompanion(wallet, coin));
    }
  });

  /// Applies domain-level metadata changes back to the wallet row.
  Future<void> updateMetadata(Wallet wallet) =>
      _db.into(_db.wallets).insertOnConflictUpdate(_walletCompanion(wallet));

  /// Commits a complete reorder as one transaction. A process or disk failure
  /// cannot leave half the wallets with new sortOrder values and half old.
  Future<void> updateMetadataBatch(Iterable<Wallet> wallets) =>
      _db.transaction(() async {
        for (final wallet in wallets) {
          await _db
              .into(_db.wallets)
              .insertOnConflictUpdate(_walletCompanion(wallet));
        }
      });

  /// Durably records user-authorized deletion before touching native key
  /// material. [load] hides marked wallets and bootstrap retries the cleanup.
  Future<void> markDeletionPending(String walletId) => _wallets
      .scoped(walletId)
      .putSetting(deletionPendingKey, _deletionPendingValue);

  Future<List<String>> pendingDeletionIds() async {
    final rows = await _wallets.listAll();
    final result = <String>[];
    for (final row in rows) {
      if (await _wallets.scoped(row.id).setting(deletionPendingKey) ==
          _deletionPendingValue) {
        result.add(row.id);
      }
    }
    return result;
  }

  Future<void> delete(String walletId) => _wallets.deleteWallet(walletId);

  // ---- locally submitted transactions -----------------------------------

  /// [networkIds] restricts the result to the ACTIVE network instances (see
  /// `WalletRepository.transactions`); null keeps every network.
  Future<List<db.Transaction>> transactions(
    String walletId, {
    Set<String>? networkIds,
  }) => _wallets.scoped(walletId).transactions(networkIds: networkIds);

  /// Pending rows are always loaded across every network. The UI may filter
  /// its visible history, but finality tracking follows each persisted row.
  Future<List<db.Transaction>> pendingTransactions(String walletId) =>
      _wallets.scoped(walletId).pendingTransactions();

  Future<db.Transaction?> transactionById(String walletId, String id) =>
      _wallets.scoped(walletId).transactionById(id);

  Future<List<db.FinalityMetric>> finalityMetrics() =>
      db.FinalityMetricsRepository(_db).recent();

  Future<String?> setting(String walletId, String key) =>
      _wallets.scoped(walletId).setting(key);

  Future<void> putSetting(String walletId, String key, String value) =>
      _wallets.scoped(walletId).putSetting(key, value);

  /// Backfills incoming rows for transfers made between wallets managed by
  /// this installation. This also repairs transfers created by older app
  /// versions before immediate recipient mirroring existed.
  Future<void> mirrorIncomingTransactions({
    required String targetWalletId,
    required Map<String, String> addressesByCoin,
    Set<String>? networkIds,
  }) => _db.transaction(() async {
    final outgoing =
        await (_db.select(_db.transactions)..where(
              (tx) =>
                  tx.walletId.equals(targetWalletId).not() &
                  tx.direction.equals(db.TxDirection.outgoing.index),
            ))
            .get();
    for (final source in outgoing) {
      final hash = source.hash;
      final target = addressesByCoin[source.coin];
      if (hash == null ||
          target == null ||
          source.networkId == null ||
          source.operation == db.TxOperationKind.approvalRevoke ||
          (networkIds != null && !networkIds.contains(source.networkId)) ||
          source.status == db.TxStatus.failed ||
          source.status == db.TxStatus.expired ||
          source.status == db.TxStatus.dropped ||
          source.status == db.TxStatus.replaced) {
        continue;
      }
      final evm =
          source.coin == Coin.eth.name ||
          source.coin == Coin.polygon.name ||
          source.coin == Coin.base.name ||
          source.coin == Coin.arbitrum.name ||
          source.coin == Coin.avalanche.name ||
          source.coin == Coin.bnb.name;
      final matches = evm
          ? source.toAddr.toLowerCase() == target.toLowerCase()
          : source.toAddr == target;
      if (!matches) continue;
      await upsertIncomingTransaction(
        id: 'incoming_${targetWalletId}_${hash}_${source.contract ?? 'native'}',
        walletId: targetWalletId,
        coin: Coin.values.firstWhere((coin) => coin.name == source.coin),
        networkId: source.networkId!,
        contract: source.contract,
        from: source.fromAddr,
        to: source.toAddr,
        amountRaw: source.amountRaw,
        hash: hash,
        status: source.status,
        createdAt: source.createdAt,
        broadcastAt: source.broadcastAt,
        lastCheckedAt: source.lastCheckedAt,
        referenceBlockHeight: source.referenceBlockHeight,
        expiresAt: source.expiresAt,
        lastValidBlockHeight: source.lastValidBlockHeight,
      );
    }
  });

  Future<void> upsertTransaction({
    required String id,
    required String walletId,
    String? reqId,
    required Coin coin,
    required String networkId,
    String? contract,
    db.TxOperationKind operation = db.TxOperationKind.transfer,
    required String from,
    required String to,
    required String amountRaw,
    String? feeRaw,
    String? hash,
    required db.TxStatus status,
    required db.SignMode signMode,
    required int createdAt,
    int? broadcastAt,
    int? lastCheckedAt,
    int? referenceBlockHeight,
    int? expiresAt,
    int? lastValidBlockHeight,
    String? nonce,
    String? maxPriorityFeeRaw,
    String? maxFeeRaw,
    String? gasLimitRaw,
    String? replacesId,
    String? replacedById,
    db.TxReplacementKind? replacementKind,
  }) => _wallets
      .scoped(walletId)
      .upsertTransaction(
        db.TransactionsCompanion.insert(
          id: id,
          walletId: walletId,
          reqId: Value(reqId),
          coin: coin.name,
          networkId: Value(networkId),
          contract: Value(contract),
          operation: Value(operation),
          direction: db.TxDirection.outgoing,
          fromAddr: from,
          toAddr: to,
          amountRaw: amountRaw,
          feeRaw: Value(feeRaw),
          hash: Value(hash),
          status: status,
          signMode: signMode,
          createdAt: createdAt,
          broadcastAt: Value(broadcastAt),
          lastCheckedAt: Value(lastCheckedAt),
          referenceBlockHeight: Value(referenceBlockHeight),
          expiresAt: Value(expiresAt),
          lastValidBlockHeight: Value(lastValidBlockHeight),
          nonce: Value(nonce),
          maxPriorityFeeRaw: Value(maxPriorityFeeRaw),
          maxFeeRaw: Value(maxFeeRaw),
          gasLimitRaw: Value(gasLimitRaw),
          replacesId: Value(replacesId),
          replacedById: Value(replacedById),
          replacementKind: Value(replacementKind),
        ),
      );

  Future<void> upsertIncomingTransaction({
    required String id,
    required String walletId,
    required Coin coin,
    required String networkId,
    String? contract,
    required String from,
    required String to,
    required String amountRaw,
    required String hash,
    required db.TxStatus status,
    required int createdAt,
    int? broadcastAt,
    int? lastCheckedAt,
    int? referenceBlockHeight,
    int? expiresAt,
    int? lastValidBlockHeight,
  }) => _wallets
      .scoped(walletId)
      .upsertTransaction(
        db.TransactionsCompanion.insert(
          id: id,
          walletId: walletId,
          coin: coin.name,
          networkId: Value(networkId),
          contract: Value(contract),
          operation: const Value(db.TxOperationKind.transfer),
          direction: db.TxDirection.incoming,
          fromAddr: from,
          toAddr: to,
          amountRaw: amountRaw,
          hash: Value(hash),
          status: status,
          signMode: db.SignMode.local,
          createdAt: createdAt,
          broadcastAt: Value(broadcastAt),
          lastCheckedAt: Value(lastCheckedAt),
          referenceBlockHeight: Value(referenceBlockHeight),
          expiresAt: Value(expiresAt),
          lastValidBlockHeight: Value(lastValidBlockHeight),
        ),
      );

  Future<void> reserveEvmTransaction({
    required String id,
    required String walletId,
    required Coin coin,
    required String networkId,
    String? contract,
    db.TxOperationKind operation = db.TxOperationKind.transfer,
    required String from,
    required String to,
    required String amountRaw,
    required String feeRaw,
    required db.SignMode signMode,
    required int createdAt,
    required String nonce,
    required String maxPriorityFeeRaw,
    required String maxFeeRaw,
    required String gasLimitRaw,
    String? replacesId,
    db.TxReplacementKind? replacementKind,
  }) => _wallets
      .scoped(walletId)
      .reserveEvmTransaction(
        db.TransactionsCompanion.insert(
          id: id,
          walletId: walletId,
          coin: coin.name,
          networkId: Value(networkId),
          contract: Value(contract),
          operation: Value(operation),
          direction: db.TxDirection.outgoing,
          fromAddr: from,
          toAddr: to,
          amountRaw: amountRaw,
          feeRaw: Value(feeRaw),
          status: db.TxStatus.submitted,
          signMode: signMode,
          createdAt: createdAt,
          nonce: Value(nonce),
          maxPriorityFeeRaw: Value(maxPriorityFeeRaw),
          maxFeeRaw: Value(maxFeeRaw),
          gasLimitRaw: Value(gasLimitRaw),
          replacesId: Value(replacesId),
          replacementKind: Value(replacementKind),
        ),
        coin: coin.name,
        networkId: networkId,
        from: from,
        nonce: nonce,
        replacesId: replacesId,
      );

  Future<bool> updateTransactionStatus(
    String walletId,
    String id,
    db.TxStatus status, {
    String? hash,
    int? broadcastAt,
    int? lastCheckedAt,
    db.TxCheckOutcome? lastCheckOutcome,
    bool clearLastCheckOutcome = false,
    bool onlyIfLive = false,
    int? finalityMetricAt,
  }) => _wallets
      .scoped(walletId)
      .updateTransactionStatus(
        id,
        status,
        hash: hash,
        broadcastAt: broadcastAt,
        lastCheckedAt: lastCheckedAt,
        lastCheckOutcome: lastCheckOutcome,
        clearLastCheckOutcome: clearLastCheckOutcome,
        onlyIfLive: onlyIfLive,
        finalityMetricAt: finalityMetricAt,
      );

  Future<bool> setTransactionNonceIfAbsent(
    String walletId,
    String id,
    String nonce,
  ) => _wallets.scoped(walletId).setTransactionNonceIfAbsent(id, nonce);

  Future<bool> recordEvmReplacementBroadcast({
    required String walletId,
    required String originalId,
    required String replacementId,
    required String hash,
    required int broadcastAt,
  }) => _wallets
      .scoped(walletId)
      .recordEvmReplacementBroadcast(
        originalId: originalId,
        replacementId: replacementId,
        hash: hash,
        broadcastAt: broadcastAt,
      );

  Future<db.EvmSettlementResult> settleEvmTransaction({
    required String walletId,
    required String id,
    required db.TxStatus status,
    String? hash,
    int? lastCheckedAt,
  }) => _wallets
      .scoped(walletId)
      .settleEvmTransaction(
        id: id,
        status: status,
        hash: hash,
        lastCheckedAt: lastCheckedAt,
      );

  // ---- global address book (Settings → 地址管理) --------------------------

  Future<List<db.Contact>> listContacts() => _contacts.list();

  Future<void> addContact(db.Contact contact) =>
      _contacts.insert(contact.toCompanion(false));

  Future<void> updateContact(
    String id, {
    required String name,
    required String address,
    required String chain,
  }) => _contacts.update(id, name: name, address: address, chain: chain);

  Future<void> deleteContact(String id) => _contacts.delete(id);

  // ---- global custom-token list (Settings → Token 管理) -------------------

  Future<List<db.CustomToken>> listTokens() => _tokens.list();

  Future<void> addToken(db.CustomToken token) =>
      _tokens.insert(token.toCompanion(false));

  Future<void> setTokenEnabled(String id, bool enabled) =>
      _tokens.setEnabled(id, enabled);

  Future<void> deleteToken(String id) => _tokens.delete(id);

  /// Closes the underlying database. Call when the store is retired (e.g.
  /// leaving wallet mode in the combined installer); the store must not be
  /// used afterwards.
  Future<void> close() => _db.close();

  // ---- mapping -----------------------------------------------------------

  Wallet _toDomain(db.Wallet row, List<db.Account> accounts) {
    String addr(String coin) =>
        accounts.firstWhere((a) => a.coin == coin).address;
    final addresses = ChainAddresses(
      eth: addr('eth'),
      polygon: addr('polygon'),
      base: addr('eth'),
      arbitrum: addr('eth'),
      avalanche: addr('eth'),
      tron: addr('tron'),
      solana: addr('solana'),
    );
    return switch (row.type) {
      db.WalletType.hot => HotWallet(
        id: row.id,
        name: row.name,
        avatarColor: row.avatarColor,
        addresses: addresses,
        sortOrder: row.sortOrder,
        backedUp: row.backedUp,
      ),
      db.WalletType.watch => WatchWallet(
        id: row.id,
        name: row.name,
        avatarColor: row.avatarColor,
        addresses: addresses,
        sortOrder: row.sortOrder,
        coldWalletId: row.coldWalletId ?? '',
        protocolVersion: row.protocolVer ?? 1,
      ),
    };
  }

  db.WalletsCompanion _walletCompanion(Wallet w) => switch (w) {
    HotWallet() => db.WalletsCompanion.insert(
      id: w.id,
      name: w.name,
      type: db.WalletType.hot,
      avatarColor: w.avatarColor,
      sortOrder: Value(w.sortOrder),
      backedUp: Value(w.backedUp),
      createdAt: 0,
    ),
    WatchWallet() => db.WalletsCompanion.insert(
      id: w.id,
      name: w.name,
      type: db.WalletType.watch,
      avatarColor: w.avatarColor,
      sortOrder: Value(w.sortOrder),
      coldWalletId: Value(w.coldWalletId),
      protocolVer: Value(w.protocolVersion),
      createdAt: 0,
    ),
  };

  db.AccountsCompanion _accountCompanion(Wallet w, String coin) =>
      db.AccountsCompanion.insert(
        walletId: w.id,
        coin: coin,
        address: w.addresses.forCoin(_coinEnum(coin)),
        derivationPath: _pathFor(coin),
        accountIndex: 0,
      );

  static Coin _coinEnum(String coin) => switch (coin) {
    'eth' => Coin.eth,
    'polygon' => Coin.polygon,
    'tron' => Coin.tron,
    'solana' => Coin.solana,
    _ => throw ArgumentError('unknown coin $coin'),
  };

  static String _pathFor(String coin) => switch (coin) {
    'eth' || 'polygon' => evmDefaultDerivationPath,
    'tron' => tronDefaultDerivationPath,
    'solana' => solanaDefaultDerivationPath,
    _ => throw ArgumentError('unknown coin $coin'),
  };
}

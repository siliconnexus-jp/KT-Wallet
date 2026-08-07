import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:wallet_data/wallet_data.dart'
    show
        Contact,
        CustomToken,
        EvmSettlementResult,
        FinalityMetric,
        SignMode,
        Transaction,
        TxCheckOutcome,
        TxOperationKind,
        TxReplacementKind,
        TxStatus;

import '../wallets/wallet_manager.dart';
import '../observability/experience_metrics.dart';
import '../wallets/wallet_model.dart';
import '../wallets/wallet_store.dart';

/// App-wide wallet state. Wraps the tested [WalletManager] as a [ChangeNotifier]
/// so screens rebuild when the current wallet changes (switch/add/rename/etc.).
///
/// Key operations go through [CoreCrypto]. The default is always the native
/// implementation; deterministic test doubles must be injected explicitly by
/// tests and can never be enabled through a shipped runtime flag. Production
/// wires a [WalletStore] for drift persistence; tests can omit it.
class WalletController extends ChangeNotifier {
  WalletController(
    this._manager, {
    CoreCrypto? crypto,
    WalletStore? store,
    bool allowTestBypass = false,
    Random? secureRandom,
  }) : _crypto = crypto ?? MethodChannelCoreCrypto(),
       _random = secureRandom ?? Random.secure(),
       // ignore: prefer_initializing_formals
       _allowTestBypass = allowTestBypass,
       // ignore: prefer_initializing_formals
       _store = store;

  final WalletManager _manager;
  final CoreCrypto _crypto;
  final Random _random;
  final bool _allowTestBypass;
  final WalletStore? _store;
  Future<void> _metadataWrites = Future<void>.value();
  Future<void> _finalityMetricRefreshes = Future<void>.value();

  /// Releases the backing store's database connection (no-op for in-memory
  /// controllers). Call when the controller is retired, e.g. when leaving
  /// wallet mode in the combined installer; the controller must not be used
  /// afterwards.
  Future<void> close() async {
    // A screen can be removed immediately after initiating a rename/reorder.
    // Drain the serialized metadata queue before closing Drift, otherwise the
    // last user-visible change can race a closed database and be lost.
    await _metadataWrites;
    await _finalityMetricRefreshes;
    await _store?.close();
  }

  /// Mnemonic generated during create-onboarding, held only between the
  /// "create new wallet" tap and the backup-verify confirmation, then dropped.
  String? _pendingMnemonic;
  String? get pendingMnemonic => _pendingMnemonic;

  static const _palette = [
    0xFF0EA5E9,
    0xFF10B981,
    0xFFEF4444,
    0xFFF59E0B,
    0xFF8B5CF6,
    0xFFEC4899,
  ];

  List<Wallet> get wallets => _manager.wallets;
  Wallet? get current => _manager.current;
  CoreCrypto get crypto => _crypto;
  bool get allowsTestBypass => _allowTestBypass;
  int get count => _manager.count;
  bool get canAddMore => _manager.canAddMore;

  /// Checks that every persisted hot wallet still has a native secure-storage
  /// record, without opening its secret or showing an authentication prompt.
  /// A missing record fails startup closed; it is never removed or rewritten.
  Future<void> validateNativeWalletPresence() async {
    for (final wallet in _manager.wallets.whereType<HotWallet>()) {
      if (!await _crypto.walletExists(wallet.id)) {
        throw WalletNotFoundException(wallet.id);
      }
    }
  }

  /// Proves that persisted public addresses belong to the native key material.
  /// This opens each wallet secret and can therefore require system
  /// authentication. Keep it out of automatic startup; call it only from an
  /// explicit authenticated integrity-check flow.
  Future<void> validateNativeWallets() async {
    for (final wallet in _manager.wallets.whereType<HotWallet>()) {
      final derived = await _crypto.deriveAddresses(wallet.id);
      for (final coin in Coin.values) {
        final expected = wallet.addresses.forCoin(coin);
        final actual = derived.forCoin(coin);
        final matches = switch (coin) {
          Coin.eth ||
          Coin.polygon ||
          Coin.base ||
          Coin.arbitrum ||
          Coin.avalanche ||
          Coin.bnb => expected.toLowerCase() == actual.toLowerCase(),
          Coin.tron || Coin.solana => expected == actual,
        };
        if (!matches) {
          throw StateError(
            'persisted wallet address does not match native key: '
            '${wallet.id}/${coin.name}',
          );
        }
      }
    }
  }

  /// Completes user-authorized hot-wallet deletions that were interrupted
  /// between the native vault operation and the Drift cascade. Pending rows
  /// are already hidden by [WalletStore.load], so a missing key is the
  /// expected idempotent state, not a reason to resurrect a broken wallet.
  Future<void> recoverPendingDeletions() async {
    final store = _store;
    if (store == null) return;
    for (final walletId in await store.pendingDeletionIds()) {
      try {
        await _crypto.deleteWallet(walletId);
      } on WalletNotFoundException {
        // The process may have died after native deletion already succeeded.
      }
      await store.delete(walletId);
    }
  }

  /// Locally recorded transactions for the current wallet. [networkIds] keeps
  /// only rows recorded on those network instances (callers pass the ACTIVE
  /// ids so a testnet row never shows up in a mainnet list); null keeps all.
  Future<List<Transaction>> localTransactions({Set<String>? networkIds}) async {
    final wallet = current;
    final store = _store;
    if (wallet == null || store == null) return const [];
    await store.mirrorIncomingTransactions(
      targetWalletId: wallet.id,
      addressesByCoin: {
        for (final coin in Coin.values)
          coin.name: wallet.addresses.forCoin(coin),
      },
      networkIds: networkIds,
    );
    return store.transactions(wallet.id, networkIds: networkIds);
  }

  /// Locally submitted rows that still need finality reconciliation, across
  /// all networks for the current wallet. This intentionally bypasses the
  /// active-network display filter; every row is queried using its own
  /// persisted network identity by [TransactionStatusService].
  Future<List<Transaction>> localPendingTransactions() async {
    final wallet = current;
    final store = _store;
    if (wallet == null || store == null) return const [];
    return store.pendingTransactions(wallet.id);
  }

  Future<Transaction?> localTransactionById(String id) async {
    final walletId = current?.id;
    if (walletId == null || _store == null) return null;
    return _store.transactionById(walletId, id);
  }

  /// Small wallet-scoped values used by display caches. Callers must pass an
  /// id owned by this controller; the repository remains scoped to that id.
  Future<String?> walletSetting(String walletId, String key) async {
    if (_store == null || !_manager.wallets.any((w) => w.id == walletId)) {
      return null;
    }
    return _store.setting(walletId, key);
  }

  Future<void> putWalletSetting(
    String walletId,
    String key,
    String value,
  ) async {
    if (_store == null || !_manager.wallets.any((w) => w.id == walletId)) {
      return;
    }
    await _store.putSetting(walletId, key, value);
  }

  Future<void> saveOutgoingTransaction({
    required String id,
    String? reqId,
    required Coin coin,

    /// Active network instance the transaction belongs to (`Network.id`).
    required String networkId,
    String? contract,
    TxOperationKind operation = TxOperationKind.transfer,
    required String from,
    required String to,
    required String amountRaw,
    String? feeRaw,
    String? hash,
    required TxStatus status,
    required SignMode signMode,
    required int createdAt,
    int? broadcastAt,
    int? referenceBlockHeight,
    int? expiresAt,
    int? lastValidBlockHeight,
    String? nonce,
    String? maxPriorityFeeRaw,
    String? maxFeeRaw,
    String? gasLimitRaw,
    String? replacesId,
    String? replacedById,
    TxReplacementKind? replacementKind,
  }) async {
    final walletId = current?.id;
    if (walletId == null || _store == null) {
      if (_allowTestBypass) return;
      throw StateError('No persistent wallet selected');
    }
    await _store.upsertTransaction(
      id: id,
      walletId: walletId,
      reqId: reqId,
      coin: coin,
      networkId: networkId,
      contract: contract,
      operation: operation,
      from: from,
      to: to,
      amountRaw: amountRaw,
      feeRaw: feeRaw,
      hash: hash,
      status: status,
      signMode: signMode,
      createdAt: createdAt,
      broadcastAt: broadcastAt,
      referenceBlockHeight: referenceBlockHeight,
      expiresAt: expiresAt,
      lastValidBlockHeight: lastValidBlockHeight,
      nonce: nonce,
      maxPriorityFeeRaw: maxPriorityFeeRaw,
      maxFeeRaw: maxFeeRaw,
      gasLimitRaw: gasLimitRaw,
      replacesId: replacesId,
      replacedById: replacedById,
      replacementKind: replacementKind,
    );
    notifyListeners();
  }

  /// Mirrors a transfer into every other locally managed wallet whose address
  /// matches [to]. This gives the receiving wallet an immediate pending row
  /// while the external account-history indexer catches up. The row is later
  /// reconciled by the same hash-based chain status/history refresh as any
  /// other local transaction.
  Future<void> saveIncomingForLocalWallets({
    required Coin coin,
    required String networkId,
    String? contract,
    required String from,
    required String to,
    required String amountRaw,
    required String hash,
    required int createdAt,
    int? broadcastAt,
    int? referenceBlockHeight,
    int? expiresAt,
    int? lastValidBlockHeight,
  }) async {
    final store = _store;
    final senderWalletId = current?.id;
    if (store == null || senderWalletId == null) return;
    final evm = switch (coin) {
      Coin.eth ||
      Coin.polygon ||
      Coin.base ||
      Coin.arbitrum ||
      Coin.avalanche ||
      Coin.bnb => true,
      Coin.tron || Coin.solana => false,
    };
    var saved = false;
    for (final wallet in wallets) {
      if (wallet.id == senderWalletId) continue;
      final local = wallet.addresses.forCoin(coin);
      final matches = evm
          ? local.toLowerCase() == to.toLowerCase()
          : local == to;
      if (!matches) continue;
      await store.upsertIncomingTransaction(
        id: 'incoming_${wallet.id}_${hash}_${contract ?? 'native'}',
        walletId: wallet.id,
        coin: coin,
        networkId: networkId,
        contract: contract,
        from: from,
        to: to,
        amountRaw: amountRaw,
        hash: hash,
        status: TxStatus.pending,
        createdAt: createdAt,
        broadcastAt: broadcastAt,
        referenceBlockHeight: referenceBlockHeight,
        expiresAt: expiresAt,
        lastValidBlockHeight: lastValidBlockHeight,
      );
      saved = true;
    }
    if (saved) notifyListeners();
  }

  Future<void> reserveOutgoingEvmTransaction({
    required String id,
    required Coin coin,

    /// Active network instance the transaction belongs to (`Network.id`); part
    /// of the nonce-reservation key, so networks cannot block one another.
    required String networkId,
    String? contract,
    TxOperationKind operation = TxOperationKind.transfer,
    required String from,
    required String to,
    required String amountRaw,
    required String feeRaw,
    required SignMode signMode,
    required int createdAt,
    required String nonce,
    required String maxPriorityFeeRaw,
    required String maxFeeRaw,
    required String gasLimitRaw,
    String? replacesId,
    TxReplacementKind? replacementKind,
  }) async {
    final walletId = current?.id;
    if (walletId == null || _store == null) {
      throw StateError('No persistent wallet selected');
    }
    await _store.reserveEvmTransaction(
      id: id,
      walletId: walletId,
      coin: coin,
      networkId: networkId,
      contract: contract,
      operation: operation,
      from: from,
      to: to,
      amountRaw: amountRaw,
      feeRaw: feeRaw,
      signMode: signMode,
      createdAt: createdAt,
      nonce: nonce,
      maxPriorityFeeRaw: maxPriorityFeeRaw,
      maxFeeRaw: maxFeeRaw,
      gasLimitRaw: gasLimitRaw,
      replacesId: replacesId,
      replacementKind: replacementKind,
    );
    notifyListeners();
  }

  Future<void> updateTransactionStatus(
    String id,
    TxStatus status, {
    String? hash,
    int? broadcastAt,
    int? lastCheckedAt,
    TxCheckOutcome? lastCheckOutcome,
    bool clearLastCheckOutcome = false,
    int? finalityMetricAt,
  }) async {
    final walletId = current?.id;
    if (walletId == null || _store == null) {
      if (_allowTestBypass) return;
      throw StateError('No persistent wallet selected');
    }
    await updateTransactionStatusForWallet(
      walletId,
      id,
      status,
      hash: hash,
      broadcastAt: broadcastAt,
      lastCheckedAt: lastCheckedAt,
      lastCheckOutcome: lastCheckOutcome,
      clearLastCheckOutcome: clearLastCheckOutcome,
      finalityMetricAt: finalityMetricAt,
    );
  }

  /// Persists an asynchronous status result in the wallet scope captured by
  /// the transaction row. Background finality queries must never re-read the
  /// currently selected wallet after awaiting the network.
  Future<bool> updateTransactionStatusForWallet(
    String walletId,
    String id,
    TxStatus status, {
    String? hash,
    int? broadcastAt,
    int? lastCheckedAt,
    TxCheckOutcome? lastCheckOutcome,
    bool clearLastCheckOutcome = false,
    bool onlyIfLive = false,
    int? finalityMetricAt,
  }) async {
    final store = _store;
    if (store == null) {
      if (_allowTestBypass) return false;
      throw StateError('Wallet storage unavailable');
    }
    final applied = await store.updateTransactionStatus(
      walletId,
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
    if (applied) {
      if (finalityMetricAt != null) await restoreDurableFinalityMetrics();
      notifyListeners();
    }
    return applied;
  }

  Future<bool> setTransactionNonceIfAbsent(String id, String nonce) async {
    final walletId = current?.id;
    if (walletId == null || _store == null) return false;
    return setTransactionNonceIfAbsentForWallet(walletId, id, nonce);
  }

  Future<bool> setTransactionNonceIfAbsentForWallet(
    String walletId,
    String id,
    String nonce,
  ) async {
    final store = _store;
    if (store == null) return false;
    return store.setTransactionNonceIfAbsent(walletId, id, nonce);
  }

  Future<bool> recordEvmReplacementBroadcast({
    required String originalId,
    required String replacementId,
    required String hash,
    required int broadcastAt,
  }) async {
    final walletId = current?.id;
    if (walletId == null || _store == null) return false;
    final accepted = await _store.recordEvmReplacementBroadcast(
      walletId: walletId,
      originalId: originalId,
      replacementId: replacementId,
      hash: hash,
      broadcastAt: broadcastAt,
    );
    notifyListeners();
    return accepted;
  }

  /// Persists a receipt-backed EVM terminal result and resolves replacement
  /// lineage atomically. Do not use this for local auth or broadcast errors.
  Future<EvmSettlementResult> settleEvmTransaction({
    required String id,
    required TxStatus status,
    String? hash,
    int? lastCheckedAt,
  }) async {
    final walletId = current?.id;
    if (walletId == null || _store == null) {
      return EvmSettlementResult.notApplied;
    }
    return settleEvmTransactionForWallet(
      walletId: walletId,
      id: id,
      status: status,
      hash: hash,
      lastCheckedAt: lastCheckedAt,
    );
  }

  /// Wallet-scoped counterpart used after an awaited chain lookup.
  Future<EvmSettlementResult> settleEvmTransactionForWallet({
    required String walletId,
    required String id,
    required TxStatus status,
    String? hash,
    int? lastCheckedAt,
  }) async {
    final store = _store;
    if (store == null) return EvmSettlementResult.notApplied;
    final result = await store.settleEvmTransaction(
      walletId: walletId,
      id: id,
      status: status,
      hash: hash,
      lastCheckedAt: lastCheckedAt,
    );
    if (result.applied) {
      await restoreDurableFinalityMetrics();
      notifyListeners();
    }
    return result;
  }

  /// Loads SQLite's privacy-minimal finality ring into the local diagnostics
  /// view. SQLite remains the sole persistent owner of these samples.
  Future<void> restoreDurableFinalityMetrics() {
    final store = _store;
    if (store == null) return Future<void>.value();
    final refresh = _finalityMetricRefreshes.then((_) async {
      try {
        final List<FinalityMetric> rows = await store.finalityMetrics();
        ExperienceMetrics.instance.replaceDurableTransactionFinality(
          rows.map(
            (row) => DurableTransactionFinalityMetric(
              duration: Duration(milliseconds: row.durationMs),
              success: row.success,
            ),
          ),
        );
      } on Object {
        // A transaction status is already durable before this diagnostic read.
        // Observability must never fail startup, confirmation or UI refresh.
      }
    });
    _finalityMetricRefreshes = refresh;
    return refresh;
  }

  int _nextColor() => _palette[_manager.count % _palette.length];

  /// Allocates a new opaque local wallet identifier from 144 bits of secure
  /// randomness. Wallet IDs bind native key aliases, database rows and AIRGAP
  /// sessions, so timestamps are both unnecessarily predictable and easier to
  /// collide under concurrent imports.
  ///
  /// Existing timestamp/demo IDs remain readable. New IDs are URL/file-name
  /// safe for the native vaults. A broken/injected RNG that repeatedly returns
  /// an existing ID fails closed instead of selecting or overwriting it.
  String allocateWalletId() {
    for (var attempt = 0; attempt < 8; attempt++) {
      final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
      final encoded = base64UrlEncode(bytes).replaceAll('=', '');
      final id = 'w_$encoded';
      if (_manager.byId(id) == null) return id;
    }
    throw WalletError('unable to allocate a unique wallet id');
  }

  void select(String id) {
    if (_manager.currentId == id) return;
    _manager.select(id);
    notifyListeners();
  }

  /// Adds an already-built wallet (watch-wallet pairing / seeding) and
  /// persists it. A persistence failure rolls the in-memory publication back,
  /// so the UI never reports a wallet that will disappear after restart.
  Future<void> add(Wallet wallet) async {
    final previousCurrentId = _manager.currentId;
    _manager.add(wallet);
    try {
      await _store?.save(wallet);
    } catch (error, stackTrace) {
      _manager.remove(wallet.id);
      if (previousCurrentId != null &&
          _manager.byId(previousCurrentId) != null) {
        _manager.select(previousCurrentId);
      }
      notifyListeners();
      Error.throwWithStackTrace(error, stackTrace);
    }
    notifyListeners();
  }

  // ---- onboarding: create ------------------------------------------------

  /// Generates a fresh mnemonic and holds it for the backup show/verify flow.
  Future<void> beginCreate() async {
    _pendingMnemonic = await _crypto.generateMnemonic();
    notifyListeners();
  }

  /// Commits the pending mnemonic after the creation flow has displayed it
  /// and the user has passed the backup challenge. [name] is the localized
  /// default name built by the caller (which has an l10n context).
  Future<HotWallet> finalizeCreate({required String name}) async {
    final mnemonic = _pendingMnemonic;
    if (mnemonic == null) throw StateError('no pending mnemonic to finalize');
    final wallet = await _materialize(name, mnemonic, backedUp: true);
    // A failed materialization has already compensated every native/database
    // write. Keep the still-uncommitted phrase in memory so transient native
    // authentication or storage failures remain retryable on the verification
    // screen; discard it only after the durable wallet commit succeeds.
    _pendingMnemonic = null;
    return wallet;
  }

  // ---- onboarding: import ------------------------------------------------

  /// Imports an existing mnemonic as a hot wallet. Possessing a phrase is not
  /// proof that the user still has a durable backup after this import, so the
  /// wallet remains unbacked-up until the authenticated "I wrote it down"
  /// action records that fact explicitly.
  /// [name] is the localized default name built by the caller.
  Future<HotWallet> importWallet(String mnemonic, {required String name}) =>
      _materialize(name, mnemonic.trim(), backedUp: false);

  /// Stores the key in CoreCrypto, derives public addresses, builds the domain
  /// wallet, persists it, then publishes it to the manager and selects it.
  Future<HotWallet> _materialize(
    String name,
    String mnemonic, {
    required bool backedUp,
  }) async {
    if (!_manager.canAddMore) {
      throw WalletError('wallet limit reached (${WalletManager.maxWallets})');
    }
    final id = allocateWalletId();
    var nativeWalletStored = false;
    var managerPublished = false;
    final previousCurrentId = _manager.currentId;
    try {
      await _crypto.storeWallet(walletId: id, mnemonic: mnemonic);
      nativeWalletStored = true;
      final addresses = await _crypto.deriveAddresses(id);
      final duplicate = _manager.wallets.whereType<HotWallet>().any(
        (existing) => Coin.values.every((coin) {
          final left = existing.addresses.forCoin(coin);
          final right = addresses.forCoin(coin);
          return switch (coin) {
            Coin.eth ||
            Coin.polygon ||
            Coin.base ||
            Coin.arbitrum ||
            Coin.avalanche ||
            Coin.bnb => left.toLowerCase() == right.toLowerCase(),
            Coin.tron || Coin.solana => left == right,
          };
        }),
      );
      if (duplicate) throw DuplicateWalletError();
      final wallet = HotWallet(
        id: id,
        name: name,
        avatarColor: _nextColor(),
        addresses: addresses,
        sortOrder: _manager.count,
        backedUp: backedUp,
      );

      // Drift's wallet + account write is transactional. Do not expose this
      // wallet to listeners until that durable commit has succeeded.
      await _store?.save(wallet);
      _manager.add(wallet);
      managerPublished = true;
      _manager.select(id);
      notifyListeners();
      return wallet;
    } catch (error, stackTrace) {
      Object? cleanupError;
      StackTrace? cleanupStackTrace;
      if (nativeWalletStored) {
        try {
          await _crypto.deleteWallet(id);
        } catch (cleanup, cleanupStack) {
          cleanupError = cleanup;
          cleanupStackTrace = cleanupStack;
        }
      }
      try {
        await _store?.delete(id);
      } catch (cleanup, cleanupStack) {
        cleanupError ??= cleanup;
        cleanupStackTrace ??= cleanupStack;
      }
      if (managerPublished && _manager.byId(id) != null) {
        _manager.remove(id);
        if (previousCurrentId != null &&
            _manager.byId(previousCurrentId) != null) {
          _manager.select(previousCurrentId);
        }
        notifyListeners();
      }
      if (cleanupError != null) {
        Error.throwWithStackTrace(cleanupError, cleanupStackTrace!);
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  // ---- mutations ---------------------------------------------------------

  Future<void> rename(String id, String name) => _queueMetadataWrite(() async {
    final current = _manager.byId(id);
    if (current == null) throw WalletError('unknown wallet id: $id');
    final proposed = switch (current) {
      HotWallet() => current.copyWith(name: name),
      WatchWallet() => current.copyWith(name: name),
    };
    await _store?.updateMetadata(proposed);
    _manager.rename(id, name);
    notifyListeners();
  });

  Future<void> setColor(String id, int color) => _queueMetadataWrite(() async {
    final current = _manager.byId(id);
    if (current == null) throw WalletError('unknown wallet id: $id');
    final proposed = switch (current) {
      HotWallet() => current.copyWith(avatarColor: color),
      WatchWallet() => current.copyWith(avatarColor: color),
    };
    await _store?.updateMetadata(proposed);
    _manager.setColor(id, color);
    notifyListeners();
  });

  /// Exposes the stored mnemonic for backup/inspection flows. Requires the
  /// wallet's key material to exist in [CoreCrypto] (throws
  /// [CoreCryptoException] otherwise, e.g. for demo-seeded wallets).
  Future<String> exportMnemonic(String id) => _crypto.exportMnemonic(id);

  Future<void> markBackedUp(String id) => _queueMetadataWrite(() async {
    final current = _manager.byId(id);
    if (current is! HotWallet) {
      throw WalletError('watch wallets have no backup state');
    }
    final proposed = current.copyWith(backedUp: true);
    await _store?.updateMetadata(proposed);
    _manager.markBackedUp(id);
    notifyListeners();
  });

  Future<void> remove(String id) async {
    final wallet = _manager.byId(id);
    // Key deletion is a property of the wallet type, not of whether a Drift
    // store happens to be attached. Keeping the old `_store != null` gate
    // could remove an in-memory hot wallet while silently leaving its native
    // Keychain/Keystore secret behind.
    if (wallet is HotWallet) {
      final store = _store;
      // This durable intent closes the otherwise unrecoverable window where
      // the native key is gone but Drift still presents the wallet on restart.
      if (store != null) await store.markDeletionPending(id);
      try {
        await _crypto.deleteWallet(id);
      } on WalletNotFoundException {
        // Explicit deletion is idempotent. A previously interrupted attempt
        // may already have removed the key while leaving the durable intent.
        if (store == null && !_allowTestBypass) rethrow;
      }
      _manager.remove(id);
      notifyListeners();
      if (store != null) {
        try {
          await store.delete(id);
        } catch (_) {
          // The wallet is already cryptographically deleted and its durable
          // tombstone prevents resurrection. Bootstrap will retry the cascade.
        }
      }
      return;
    }
    // Watch wallets have no native secret: commit the Drift deletion before
    // publishing the in-memory removal, so a storage failure changes nothing.
    await _store?.delete(id);
    _manager.remove(id);
    notifyListeners();
  }

  /// Moves the wallet at [oldIndex] (position in the sorted [wallets] list) to
  /// [newIndex], then persists every wallet's new sortOrder — a drag rewrites
  /// the whole permutation, so all rows are "affected".
  Future<void> reorder(int oldIndex, int newIndex) =>
      _queueMetadataWrite(() async {
        final current = _manager.wallets;
        final ids = current.map((wallet) => wallet.id).toList();
        final id = ids.removeAt(oldIndex);
        ids.insert(newIndex, id);
        final byId = {for (final wallet in current) wallet.id: wallet};
        final proposed = <Wallet>[
          for (final (index, walletId) in ids.indexed)
            switch (byId[walletId]!) {
              final HotWallet wallet => wallet.copyWith(sortOrder: index),
              final WatchWallet wallet => wallet.copyWith(sortOrder: index),
            },
        ];
        await _store?.updateMetadataBatch(proposed);
        _manager.reorder(ids);
        notifyListeners();
      });

  Future<T> _queueMetadataWrite<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _metadataWrites = _metadataWrites.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  // ---- global address book & custom-token list ---------------------------
  //
  // Persisted through the store when present; a plain in-memory list when
  // `_store == null` (gallery/goldens/widget tests), so the screens have a
  // single code path either way.

  final List<Contact> _contacts = [];
  final List<CustomToken> _tokens = [];
  int _rowSeq = 0;

  /// Whether contacts/tokens survive a restart (drift store wired).
  bool get hasStore => _store != null;

  List<Contact> get contacts => List.unmodifiable(_contacts);
  List<CustomToken> get tokens => List.unmodifiable(_tokens);

  String _rowId(String prefix) =>
      '$prefix${DateTime.now().microsecondsSinceEpoch}-${_rowSeq++}';

  /// Refreshes [contacts] from the store (no-op refresh without one).
  Future<List<Contact>> loadContacts() async {
    final store = _store;
    if (store != null) {
      _contacts
        ..clear()
        ..addAll(await store.listContacts());
    }
    return contacts;
  }

  Future<Contact> addContact({
    required String name,
    required String address,
    required String chain,
  }) async {
    final contact = Contact(
      id: _rowId('c'),
      name: name,
      address: address,
      chain: chain,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _store?.addContact(contact);
    _contacts.add(contact);
    notifyListeners();
    return contact;
  }

  /// Edits an existing contact. Keeps its `createdAt`, so a rename does not
  /// reshuffle the address book.
  Future<void> updateContact(
    String id, {
    required String name,
    required String address,
    required String chain,
  }) async {
    final index = _contacts.indexWhere((c) => c.id == id);
    if (index < 0) return;
    await _store?.updateContact(id, name: name, address: address, chain: chain);
    _contacts[index] = _contacts[index].copyWith(
      name: name,
      address: address,
      chain: chain,
    );
    notifyListeners();
  }

  Future<void> removeContact(String id) async {
    await _store?.deleteContact(id);
    _contacts.removeWhere((c) => c.id == id);
    notifyListeners();
  }

  /// Refreshes [tokens] from the store (no-op refresh without one).
  Future<List<CustomToken>> loadTokens() async {
    final store = _store;
    if (store != null) {
      _tokens
        ..clear()
        ..addAll(await store.listTokens());
    }
    return tokens;
  }

  Future<CustomToken> addToken({
    required String symbol,
    required String name,
    String? contract,
    required String network,
    bool enabled = true,
  }) async {
    final token = CustomToken(
      id: _rowId('t'),
      symbol: symbol,
      name: name,
      contract: contract,
      network: network,
      enabled: enabled,
      sortOrder: _tokens.length,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );
    await _store?.addToken(token);
    _tokens.add(token);
    notifyListeners();
    return token;
  }

  Future<void> setTokenEnabled(String id, bool enabled) async {
    await _store?.setTokenEnabled(id, enabled);
    final i = _tokens.indexWhere((t) => t.id == id);
    if (i >= 0) _tokens[i] = _tokens[i].copyWith(enabled: enabled);
    notifyListeners();
  }
}

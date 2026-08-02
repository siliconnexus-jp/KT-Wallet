import 'dart:math';

import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:wallet_data/wallet_data.dart' as db;

class _TrackingDeriveFailureCrypto extends MockCoreCrypto {
  int deleteCalls = 0;

  @override
  Future<ChainAddresses> deriveAddresses(String walletId) =>
      Future<ChainAddresses>.error(StateError('native derive unavailable'));

  @override
  Future<void> deleteWallet(String walletId) async {
    deleteCalls += 1;
    await super.deleteWallet(walletId);
  }
}

class _TrackingCrypto extends MockCoreCrypto {
  int deleteCalls = 0;

  @override
  Future<void> deleteWallet(String walletId) async {
    deleteCalls += 1;
    await super.deleteWallet(walletId);
  }
}

class _SaveFailureStore extends WalletStore {
  _SaveFailureStore(super.database);

  int deleteCalls = 0;

  @override
  Future<void> save(Wallet wallet) =>
      Future<void>.error(StateError('wallet database unavailable'));

  @override
  Future<void> delete(String walletId) async {
    deleteCalls += 1;
    await super.delete(walletId);
  }
}

class _MetadataFailureStore extends WalletStore {
  _MetadataFailureStore(super.database);

  @override
  Future<void> updateMetadata(Wallet wallet) =>
      Future<void>.error(StateError('metadata database unavailable'));
}

class _ZeroRandom implements Random {
  @override
  bool nextBool() => false;

  @override
  double nextDouble() => 0;

  @override
  int nextInt(int max) => 0;
}

ChainAddresses _addresses(String seed) => ChainAddresses(
  eth: '0x${seed}000000000000000000000000000000000000',
  polygon: '0x${seed}000000000000000000000000000000000000',
  base: '0x${seed}000000000000000000000000000000000000',
  arbitrum: '0x${seed}000000000000000000000000000000000000',
  avalanche: '0x${seed}000000000000000000000000000000000000',
  bnb: '0x${seed}000000000000000000000000000000000000',
  tron: 'T${seed}tron',
  solana: '${seed}solana',
);

void main() {
  late db.WalletDatabase database;

  setUp(() {
    database = db.WalletDatabase(NativeDatabase.memory());
  });

  tearDown(() => database.close());

  test('new wallet ids are opaque URL-safe 144-bit values', () {
    final controller = WalletController(
      WalletManager(),
      secureRandom: Random(20260803),
    );

    final ids = List<String>.generate(
      128,
      (_) => controller.allocateWalletId(),
    );

    expect(ids.toSet(), hasLength(ids.length));
    for (final id in ids) {
      expect(id, matches(RegExp(r'^w_[A-Za-z0-9_-]{24}$')));
    }
  });

  test('wallet id generation fails closed after repeated collisions', () {
    const collidingId = 'w_AAAAAAAAAAAAAAAAAAAAAAAA';
    final existing = WatchWallet(
      id: collidingId,
      name: 'Existing',
      avatarColor: 1,
      addresses: _addresses('1'),
      coldWalletId: 'cold-existing',
      protocolVersion: 1,
    );
    final controller = WalletController(
      WalletManager(initial: <Wallet>[existing]),
      secureRandom: _ZeroRandom(),
    );

    expect(controller.allocateWalletId, throwsA(isA<WalletError>()));
    expect(controller.wallets, contains(same(existing)));
  });

  test('derive failure compensates the newly stored native key', () async {
    final crypto = _TrackingDeriveFailureCrypto();
    final controller = WalletController(WalletManager(), crypto: crypto);
    final mnemonic = await crypto.generateMnemonic();

    await expectLater(
      controller.importWallet(mnemonic, name: 'Never published'),
      throwsStateError,
    );

    expect(crypto.deleteCalls, 1);
    expect(crypto.storedWalletCount, 0);
    expect(controller.wallets, isEmpty);
  });

  test(
    'database failure never publishes a hot wallet and cleans its key',
    () async {
      final crypto = _TrackingCrypto();
      final store = _SaveFailureStore(database);
      final controller = WalletController(
        WalletManager(),
        crypto: crypto,
        store: store,
      );
      final mnemonic = await crypto.generateMnemonic();

      await expectLater(
        controller.importWallet(mnemonic, name: 'Never published'),
        throwsStateError,
      );

      expect(controller.wallets, isEmpty);
      expect(crypto.deleteCalls, 1);
      expect(crypto.storedWalletCount, 0);
      expect(store.deleteCalls, 1);
      expect((await store.load()).wallets, isEmpty);
    },
  );

  test('failed create keeps its pending phrase for a safe retry', () async {
    final crypto = _TrackingDeriveFailureCrypto();
    final controller = WalletController(WalletManager(), crypto: crypto);
    await controller.beginCreate();
    expect(controller.pendingMnemonic, isNotNull);

    await expectLater(
      controller.finalizeCreate(name: 'Never published'),
      throwsStateError,
    );

    expect(controller.pendingMnemonic, isNotNull);
    expect(controller.wallets, isEmpty);
    expect(crypto.storedWalletCount, 0);
  });

  test(
    'duplicate mnemonic import is rejected and its extra key is deleted',
    () async {
      final crypto = _TrackingCrypto();
      final controller = WalletController(WalletManager(), crypto: crypto);
      final mnemonic = await crypto.generateMnemonic();
      final first = await controller.importWallet(mnemonic, name: 'First');

      await expectLater(
        controller.importWallet(mnemonic, name: 'Duplicate'),
        throwsA(isA<DuplicateWalletError>()),
      );

      expect(controller.wallets, hasLength(1));
      expect(controller.wallets.single.id, first.id);
      expect(crypto.storedWalletCount, 1);
      expect(crypto.deleteCalls, 1);
    },
  );

  test(
    'watch-wallet persistence failure rolls back the in-memory add',
    () async {
      final existing = WatchWallet(
        id: 'existing',
        name: 'Existing',
        avatarColor: 1,
        addresses: _addresses('1'),
        coldWalletId: 'cold-existing',
        protocolVersion: 1,
      );
      final manager = WalletManager(initial: <Wallet>[existing]);
      final controller = WalletController(
        manager,
        crypto: MockCoreCrypto(),
        store: _SaveFailureStore(database),
      );
      final candidate = WatchWallet(
        id: 'candidate',
        name: 'Candidate',
        avatarColor: 2,
        addresses: _addresses('2'),
        coldWalletId: 'cold-candidate',
        protocolVersion: 1,
      );

      await expectLater(controller.add(candidate), throwsStateError);

      expect(controller.wallets.map((wallet) => wallet.id), <String>[
        'existing',
      ]);
      expect(controller.current?.id, 'existing');
    },
  );

  test(
    'startup native validation blocks missing or mismatched hot keys',
    () async {
      final missing = HotWallet(
        id: 'missing-key',
        name: 'Missing',
        avatarColor: 1,
        addresses: _addresses('3'),
        backedUp: true,
      );
      final missingController = WalletController(
        WalletManager(initial: <Wallet>[missing]),
        crypto: MockCoreCrypto(),
      );
      await expectLater(
        missingController.validateNativeWallets(),
        throwsA(isA<WalletNotFoundException>()),
      );
      expect(missingController.wallets.single.id, 'missing-key');

      final crypto = MockCoreCrypto();
      final mnemonic = await crypto.generateMnemonic();
      await crypto.storeWallet(walletId: 'wrong-address', mnemonic: mnemonic);
      final mismatched = HotWallet(
        id: 'wrong-address',
        name: 'Mismatched',
        avatarColor: 1,
        addresses: _addresses('4'),
        backedUp: true,
      );
      final mismatchController = WalletController(
        WalletManager(initial: <Wallet>[mismatched]),
        crypto: crypto,
      );
      await expectLater(
        mismatchController.validateNativeWallets(),
        throwsStateError,
      );
      expect(mismatchController.wallets.single.id, 'wrong-address');
    },
  );

  test(
    'metadata failures never publish rename, color, or backup state',
    () async {
      final wallet = HotWallet(
        id: 'metadata-guard',
        name: 'Committed name',
        avatarColor: 1,
        addresses: _addresses('5'),
        backedUp: false,
      );
      final store = _MetadataFailureStore(database);
      await store.save(wallet);
      final controller = WalletController(
        WalletManager(initial: <Wallet>[wallet]),
        crypto: MockCoreCrypto(),
        store: store,
      );

      await expectLater(
        controller.rename(wallet.id, 'Lost name'),
        throwsStateError,
      );
      await expectLater(controller.setColor(wallet.id, 99), throwsStateError);
      await expectLater(controller.markBackedUp(wallet.id), throwsStateError);

      final current = controller.current! as HotWallet;
      expect(current.name, 'Committed name');
      expect(current.avatarColor, 1);
      expect(current.backedUp, isFalse);
    },
  );
}

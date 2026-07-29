import 'package:core_crypto/core_crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:wallet_data/wallet_data.dart';

ChainAddresses _addr(String seed) => ChainAddresses(
  eth: '0x${seed}eth',
  polygon: '0x${seed}eth', // eth == polygon
  tron: 'T${seed}tron',
  solana: '${seed}sol',
);

HotWallet _hot(String id) => HotWallet(
  id: id,
  name: 'hot-$id',
  avatarColor: 0xF59E0B,
  addresses: _addr(id),
  backedUp: true,
);

WatchWallet _watch(String id) => WatchWallet(
  id: id,
  name: 'watch-$id',
  avatarColor: 0x0C1220,
  addresses: _addr(id),
  coldWalletId: 'COLD-$id',
  protocolVersion: 1,
);

void main() {
  late WalletDatabase db;
  late WalletStore store;

  setUp(() {
    db = WalletDatabase(NativeDatabase.memory());
    store = WalletStore(db);
  });
  tearDown(() => db.close());

  test(
    'save then load round-trips a hot wallet with all four addresses',
    () async {
      await store.save(_hot('A'));
      final manager = await store.load();
      final w = manager.current!;
      expect(w, isA<HotWallet>());
      expect(w.id, 'A');
      expect((w as HotWallet).backedUp, isTrue);
      expect(w.addresses.eth, '0xAeth');
      expect(w.addresses.polygon, w.addresses.eth);
      expect(w.addresses.tron, 'TAtron');
      expect(w.addresses.solana, 'Asol');
    },
  );

  test('watch wallet round-trips with cold pairing info', () async {
    await store.save(_watch('B'));
    final manager = await store.load();
    final w = manager.current! as WatchWallet;
    expect(w.coldWalletId, 'COLD-B');
    expect(w.protocolVersion, 1);
    expect(w.canSignLocally, isFalse);
  });

  test('mixed wallets load together', () async {
    await store.save(_hot('A'));
    await store.save(_watch('B'));
    final manager = await store.load();
    expect(manager.count, 2);
    expect(manager.wallets.map((w) => w.id).toSet(), {'A', 'B'});
  });

  test('delete removes the wallet and its accounts', () async {
    await store.save(_hot('A'));
    await store.delete('A');
    final manager = await store.load();
    expect(manager.count, 0);
    // Accounts are gone too (cascade via deleteWallet).
    final accounts = await WalletsRepository(db).scoped('A').accounts();
    expect(accounts, isEmpty);
  });

  test('updateMetadata persists a rename + backup flag', () async {
    await store.save(_hot('A'));
    final renamed = _hot('A').copyWith(name: 'Daily', backedUp: false);
    await store.updateMetadata(renamed);
    final w = (await store.load()).current! as HotWallet;
    expect(w.name, 'Daily');
    expect(w.backedUp, isFalse);
  });

  test('four account rows are written per wallet', () async {
    await store.save(_hot('A'));
    final accounts = await WalletsRepository(db).scoped('A').accounts();
    expect(accounts.map((a) => a.coin).toSet(), {
      'eth',
      'polygon',
      'tron',
      'solana',
    });
    final tron = accounts.firstWhere((a) => a.coin == 'tron');
    expect(tron.derivationPath, "m/44'/195'/0'/0/0");
  });

  test(
    'a transfer to another local wallet creates an incoming history row',
    () async {
      final sender = _hot('A');
      final recipient = _hot('B');
      await store.save(sender);
      await store.save(recipient);
      final controller = WalletController(
        WalletManager(initial: [sender, recipient]),
        store: store,
      );

      await controller.saveIncomingForLocalWallets(
        coin: Coin.eth,
        networkId: 'eth-mainnet',
        from: sender.addresses.eth,
        to: recipient.addresses.eth,
        amountRaw: '1200000000000000',
        hash: '0xhash',
        createdAt: 1000,
        broadcastAt: 1001,
      );

      final rows = await store.transactions('B');
      expect(rows, hasLength(1));
      expect(rows.single.direction, TxDirection.incoming);
      expect(rows.single.hash, '0xhash');
      expect(rows.single.status, TxStatus.pending);
      expect(rows.single.fromAddr, sender.addresses.eth);
      expect(rows.single.toAddr, recipient.addresses.eth);
    },
  );

  test(
    'older local transfers are backfilled into the recipient history',
    () async {
      final sender = _hot('A');
      final recipient = _hot('B');
      await store.save(sender);
      await store.save(recipient);
      await store.upsertTransaction(
        id: 'old-outgoing',
        walletId: sender.id,
        coin: Coin.bnb,
        networkId: 'bnb-mainnet',
        from: sender.addresses.eth,
        to: recipient.addresses.eth,
        amountRaw: '5000000000000000',
        hash: '0xoldhash',
        status: TxStatus.confirmed,
        signMode: SignMode.local,
        createdAt: 900,
        broadcastAt: 901,
      );
      final controller = WalletController(
        WalletManager(initial: [sender, recipient]),
        store: store,
      )..select(recipient.id);

      final rows = await controller.localTransactions(
        networkIds: {'bnb-mainnet'},
      );

      expect(rows, hasLength(1));
      expect(rows.single.direction, TxDirection.incoming);
      expect(rows.single.coin, Coin.bnb.name);
      expect(rows.single.status, TxStatus.confirmed);
      expect(rows.single.hash, '0xoldhash');
    },
  );

  group('transactions carry their network', () {
    Future<void> reserve(
      String id, {
      required String networkId,
      String nonce = '7',
    }) => store.reserveEvmTransaction(
      id: id,
      walletId: 'A',
      coin: Coin.eth,
      networkId: networkId,
      from: '0xfrom',
      to: '0xto',
      amountRaw: '1000',
      feeRaw: '4200',
      signMode: SignMode.local,
      createdAt: 1000,
      nonce: nonce,
      maxPriorityFeeRaw: '10',
      maxFeeRaw: '20',
      gasLimitRaw: '21000',
    );

    setUp(() => store.save(_hot('A')));

    test('the recorded network id survives the round-trip', () async {
      await reserve('sepolia-tx', networkId: 'eth-sepolia');
      final row = (await store.transactions('A')).single;
      expect(row.networkId, 'eth-sepolia');
      expect(row.coin, 'eth'); // the chain family alone is not enough
    });

    test('history reads are filtered to the active networks', () async {
      await reserve('sepolia-tx', networkId: 'eth-sepolia');
      await reserve('mainnet-tx', networkId: 'eth-mainnet', nonce: '9');

      expect(await store.transactions('A'), hasLength(2));
      expect(
        (await store.transactions('A', networkIds: {'eth-mainnet'})).single.id,
        'mainnet-tx',
      );
      expect(
        (await store.transactions('A', networkIds: {'eth-sepolia'})).single.id,
        'sepolia-tx',
      );
    });

    test('a testnet nonce never blocks the same nonce on mainnet', () async {
      await reserve('sepolia-tx', networkId: 'eth-sepolia');
      // Same wallet/sender/chain family/nonce, different network instance.
      await reserve('mainnet-tx', networkId: 'eth-mainnet');
      expect(await store.transactions('A'), hasLength(2));

      // Within one network the reservation still conflicts.
      await expectLater(
        reserve('mainnet-racing', networkId: 'eth-mainnet'),
        throwsA(isA<EvmNonceConflict>()),
      );
    });
  });
}

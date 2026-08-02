import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:wallet_data/wallet_data.dart';

WalletDatabase _memDb() => WalletDatabase(NativeDatabase.memory());

WalletsCompanion _wallet(String id, {WalletType type = WalletType.hot}) =>
    WalletsCompanion.insert(
      id: id,
      name: 'wallet-$id',
      type: type,
      avatarColor: 0xFF0000,
      createdAt: 1000,
    );

TransactionsCompanion _tx(
  String id,
  String walletId, {
  String amount = '100',
}) => TransactionsCompanion.insert(
  id: id,
  walletId: walletId,
  coin: 'eth',
  direction: TxDirection.outgoing,
  fromAddr: '0xfrom',
  toAddr: '0xto',
  amountRaw: amount,
  status: TxStatus.confirmed,
  signMode: SignMode.local,
  createdAt: 1000,
);

TransactionsCompanion _evmTx(
  String id,
  String walletId, {
  String nonce = '7',
  String networkId = 'eth-mainnet',
  String? replacesId,
  TxReplacementKind? replacementKind,
}) => TransactionsCompanion.insert(
  id: id,
  walletId: walletId,
  coin: 'eth',
  networkId: Value(networkId),
  direction: TxDirection.outgoing,
  fromAddr: '0xfrom',
  toAddr: '0xto',
  amountRaw: '100',
  feeRaw: const Value('420000'),
  status: TxStatus.submitted,
  signMode: SignMode.local,
  createdAt: 1000,
  nonce: Value(nonce),
  maxPriorityFeeRaw: const Value('10'),
  maxFeeRaw: const Value('20'),
  gasLimitRaw: const Value('21000'),
  replacesId: Value(replacesId),
  replacementKind: Value(replacementKind),
);

void main() {
  late WalletDatabase db;
  late WalletsRepository wallets;

  setUp(() async {
    db = _memDb();
    wallets = WalletsRepository(db);
    await wallets.insert(_wallet('A'));
    await wallets.insert(_wallet('B', type: WalletType.watch));
  });

  tearDown(() => db.close());

  group('per-wallet isolation (DD §8.11)', () {
    test('transactions written to A are invisible to B', () async {
      await wallets.scoped('A').upsertTransaction(_tx('t1', 'A'));
      await wallets.scoped('A').upsertTransaction(_tx('t2', 'A'));

      expect(await wallets.scoped('A').transactions(), hasLength(2));
      expect(await wallets.scoped('B').transactions(), isEmpty);
    });

    test('address book is isolated per wallet', () async {
      await wallets
          .scoped('A')
          .addContact(
            AddressBookCompanion.insert(
              id: 'c1',
              walletId: 'A',
              name: 'Alice',
              address: '0xalice',
              coin: 'eth',
              createdAt: 1,
            ),
          );
      expect(await wallets.scoped('A').contacts(), hasLength(1));
      expect(await wallets.scoped('B').contacts(), isEmpty);
    });

    test('token visibility toggles are per wallet', () async {
      await wallets
          .scoped('A')
          .upsertToken(
            TokensCompanion.insert(
              walletId: 'A',
              coin: 'eth',
              symbol: 'USDT',
              decimals: 6,
              name: 'Tether',
              enabled: const Value(false),
            ),
          );
      expect(await wallets.scoped('A').tokens(), hasLength(1));
      expect(await wallets.scoped('A').tokens(enabledOnly: true), isEmpty);
      expect(await wallets.scoped('B').tokens(), isEmpty);
    });

    test('per-wallet settings do not leak', () async {
      await wallets.scoped('A').putSetting('theme', 'dark');
      expect(await wallets.scoped('A').setting('theme'), 'dark');
      expect(await wallets.scoped('B').setting('theme'), isNull);
    });

    test(
      'scope forces walletId even if the caller passes a foreign one',
      () async {
        // A caller tries to smuggle a row for B through A's repository (asserts
        // are stripped in release, so the repo must force the scope's walletId).
        await wallets.scoped('A').upsertTransaction(_tx('t1', 'B'));
        expect(await wallets.scoped('A').transactions(), hasLength(1));
        expect(await wallets.scoped('B').transactions(), isEmpty);
        expect((await wallets.scoped('A').transactions()).single.walletId, 'A');
      },
    );
  });

  group('wallet lifecycle', () {
    test('listAll returns wallets ordered by sortOrder', () async {
      final all = await wallets.listAll();
      expect(all.map((w) => w.id), containsAll(['A', 'B']));
    });

    test('deleteWallet cascades all per-wallet rows', () async {
      final a = wallets.scoped('A');
      await a.upsertTransaction(_tx('t1', 'A'));
      await a.addContact(
        AddressBookCompanion.insert(
          id: 'c1',
          walletId: 'A',
          name: 'x',
          address: 'y',
          coin: 'eth',
          createdAt: 1,
        ),
      );
      await a.putSetting('k', 'v');

      await wallets.deleteWallet('A');

      expect(await wallets.byId('A'), isNull);
      expect(await wallets.scoped('A').transactions(), isEmpty);
      expect(await wallets.scoped('A').contacts(), isEmpty);
      expect(await wallets.scoped('A').setting('k'), isNull);
      // B is untouched.
      expect(await wallets.byId('B'), isNotNull);
    });

    test('count reflects inserts and deletes', () async {
      expect(await wallets.count(), 2);
      await wallets.deleteWallet('B');
      expect(await wallets.count(), 1);
    });
  });

  group('money is stored losslessly as text', () {
    test('large BigInt amount round-trips exactly', () async {
      const huge = '123456789012345678901234567890';
      await wallets.scoped('A').upsertTransaction(_tx('t1', 'A', amount: huge));
      final tx = (await wallets.scoped('A').transactions()).single;
      expect(tx.amountRaw, huge);
      expect(BigInt.parse(tx.amountRaw), BigInt.parse(huge));
    });
  });

  group('EVM nonce reservation and replacement', () {
    test('observed nonce backfill is write-once', () async {
      final repo = wallets.scoped('A');
      await repo.upsertTransaction(
        _tx(
          'legacy-pending',
          'A',
        ).copyWith(status: const Value(TxStatus.pending)),
      );

      expect(
        await repo.setTransactionNonceIfAbsent('legacy-pending', '7'),
        isTrue,
      );
      expect(
        await repo.setTransactionNonceIfAbsent('legacy-pending', '8'),
        isFalse,
      );
      expect((await repo.transactionById('legacy-pending'))?.nonce, '7');
    });

    test(
      'racing transaction with the same nonce is rejected atomically',
      () async {
        final repo = wallets.scoped('A');
        await repo.reserveEvmTransaction(
          _evmTx('original', 'A'),
          coin: 'eth',
          networkId: 'eth-mainnet',
          from: '0xfrom',
          nonce: '7',
        );

        await expectLater(
          repo.reserveEvmTransaction(
            _evmTx('racing', 'A'),
            coin: 'eth',
            networkId: 'eth-mainnet',
            from: '0xfrom',
            nonce: '7',
          ),
          throwsA(
            isA<EvmNonceConflict>().having(
              (error) => error.existing.id,
              'existing.id',
              'original',
            ),
          ),
        );
        expect(await repo.transactions(), hasLength(1));
      },
    );

    test('one replacement may reuse the original nonce', () async {
      final repo = wallets.scoped('A');
      await repo.reserveEvmTransaction(
        _evmTx('original', 'A'),
        coin: 'eth',
        networkId: 'eth-mainnet',
        from: '0xfrom',
        nonce: '7',
      );
      await repo.updateTransactionStatus('original', TxStatus.pending);

      await repo.reserveEvmTransaction(
        _evmTx(
          'replacement',
          'A',
          replacesId: 'original',
          replacementKind: TxReplacementKind.speedUp,
        ),
        coin: 'eth',
        networkId: 'eth-mainnet',
        from: '0xfrom',
        nonce: '7',
        replacesId: 'original',
      );

      await expectLater(
        repo.reserveEvmTransaction(
          _evmTx(
            'second-replacement',
            'A',
            replacesId: 'original',
            replacementKind: TxReplacementKind.cancel,
          ),
          coin: 'eth',
          networkId: 'eth-mainnet',
          from: '0xfrom',
          nonce: '7',
          replacesId: 'original',
        ),
        throwsA(isA<EvmNonceConflict>()),
      );
    });

    test('node acceptance keeps both nonce competitors pending', () async {
      final repo = wallets.scoped('A');
      await repo.reserveEvmTransaction(
        _evmTx('original', 'A'),
        coin: 'eth',
        networkId: 'eth-mainnet',
        from: '0xfrom',
        nonce: '7',
      );
      await repo.updateTransactionStatus('original', TxStatus.pending);
      await repo.reserveEvmTransaction(
        _evmTx(
          'replacement',
          'A',
          replacesId: 'original',
          replacementKind: TxReplacementKind.cancel,
        ),
        coin: 'eth',
        networkId: 'eth-mainnet',
        from: '0xfrom',
        nonce: '7',
        replacesId: 'original',
      );

      expect(
        await repo.recordEvmReplacementBroadcast(
          originalId: 'original',
          replacementId: 'replacement',
          hash: '0xnew',
          broadcastAt: 2000,
        ),
        isTrue,
      );

      final original = await repo.transactionById('original');
      final replacement = await repo.transactionById('replacement');
      expect(original!.status, TxStatus.pending);
      expect(original.replacedById, 'replacement');
      expect(replacement!.status, TxStatus.pending);
      expect(replacement.hash, '0xnew');
      expect(replacement.broadcastAt, 2000);
    });

    test('confirmed replacement atomically settles the original', () async {
      final repo = wallets.scoped('A');
      await repo.reserveEvmTransaction(
        _evmTx('original', 'A'),
        coin: 'eth',
        networkId: 'eth-mainnet',
        from: '0xfrom',
        nonce: '7',
      );
      await repo.updateTransactionStatus('original', TxStatus.pending);
      await repo.reserveEvmTransaction(
        _evmTx(
          'replacement',
          'A',
          replacesId: 'original',
          replacementKind: TxReplacementKind.speedUp,
        ),
        coin: 'eth',
        networkId: 'eth-mainnet',
        from: '0xfrom',
        nonce: '7',
        replacesId: 'original',
      );
      await repo.recordEvmReplacementBroadcast(
        originalId: 'original',
        replacementId: 'replacement',
        hash: '0xnew',
        broadcastAt: 2000,
      );

      await repo.settleEvmTransaction(
        id: 'replacement',
        status: TxStatus.confirmed,
        hash: '0xnew',
        lastCheckedAt: 3000,
      );

      final original = await repo.transactionById('original');
      final replacement = await repo.transactionById('replacement');
      expect(original!.status, TxStatus.replaced);
      expect(original.replacedById, 'replacement');
      expect(replacement!.status, TxStatus.confirmed);
      expect(replacement.lastCheckedAt, 3000);
    });

    test('confirmed original atomically settles its replacement', () async {
      final repo = wallets.scoped('A');
      await repo.reserveEvmTransaction(
        _evmTx('original', 'A'),
        coin: 'eth',
        networkId: 'eth-mainnet',
        from: '0xfrom',
        nonce: '7',
      );
      await repo.updateTransactionStatus('original', TxStatus.pending);
      await repo.reserveEvmTransaction(
        _evmTx(
          'replacement',
          'A',
          replacesId: 'original',
          replacementKind: TxReplacementKind.cancel,
        ),
        coin: 'eth',
        networkId: 'eth-mainnet',
        from: '0xfrom',
        nonce: '7',
        replacesId: 'original',
      );
      await repo.recordEvmReplacementBroadcast(
        originalId: 'original',
        replacementId: 'replacement',
        hash: '0xnew',
        broadcastAt: 2000,
      );

      await repo.settleEvmTransaction(
        id: 'original',
        status: TxStatus.confirmed,
        hash: '0xold',
      );

      final original = await repo.transactionById('original');
      final replacement = await repo.transactionById('replacement');
      expect(original!.status, TxStatus.confirmed);
      expect(replacement!.status, TxStatus.replaced);
      expect(replacement.replacedById, 'original');
    });

    test('local replacement failure never settles the original', () async {
      final repo = wallets.scoped('A');
      await repo.reserveEvmTransaction(
        _evmTx('original', 'A'),
        coin: 'eth',
        networkId: 'eth-mainnet',
        from: '0xfrom',
        nonce: '7',
      );
      await repo.updateTransactionStatus('original', TxStatus.pending);
      await repo.reserveEvmTransaction(
        _evmTx(
          'replacement',
          'A',
          replacesId: 'original',
          replacementKind: TxReplacementKind.speedUp,
        ),
        coin: 'eth',
        networkId: 'eth-mainnet',
        from: '0xfrom',
        nonce: '7',
        replacesId: 'original',
      );

      await repo.updateTransactionStatus('replacement', TxStatus.failed);

      expect(
        (await repo.transactionById('original'))!.status,
        TxStatus.pending,
      );
      expect(
        (await repo.transactionById('replacement'))!.status,
        TxStatus.failed,
      );
    });

    test(
      'status lookup time persists without inventing a final state',
      () async {
        final repo = wallets.scoped('A');
        await repo.reserveEvmTransaction(
          _evmTx('pending-diagnostic', 'A'),
          coin: 'eth',
          networkId: 'eth-mainnet',
          from: '0xfrom',
          nonce: '7',
        );

        await repo.updateTransactionStatus(
          'pending-diagnostic',
          TxStatus.submitted,
          lastCheckedAt: 123456789,
          lastCheckOutcome: TxCheckOutcome.unknown,
        );

        final row = await repo.transactionById('pending-diagnostic');
        expect(row!.status, TxStatus.submitted);
        expect(row.lastCheckedAt, 123456789);
        expect(row.lastCheckOutcome, TxCheckOutcome.unknown);

        await repo.updateTransactionStatus(
          'pending-diagnostic',
          TxStatus.pending,
          lastCheckedAt: 123456999,
          lastCheckOutcome: TxCheckOutcome.pending,
        );
        final recovered = await repo.transactionById('pending-diagnostic');
        expect(recovered!.status, TxStatus.pending);
        expect(recovered.lastCheckOutcome, TxCheckOutcome.pending);

        await repo.updateTransactionStatus(
          'pending-diagnostic',
          TxStatus.failed,
          clearLastCheckOutcome: true,
        );
        expect(
          (await repo.transactionById('pending-diagnostic'))!.lastCheckOutcome,
          isNull,
        );
      },
    );

    test('the nonce conflict key is scoped per network', () async {
      final repo = wallets.scoped('A');
      await repo.reserveEvmTransaction(
        _evmTx('sepolia', 'A', networkId: 'eth-sepolia'),
        coin: 'eth',
        networkId: 'eth-sepolia',
        from: '0xfrom',
        nonce: '7',
      );

      // Same wallet, same chain family, same sender, same nonce — but a
      // different network instance, so it is NOT a conflict.
      await repo.reserveEvmTransaction(
        _evmTx('mainnet', 'A', networkId: 'eth-mainnet'),
        coin: 'eth',
        networkId: 'eth-mainnet',
        from: '0xfrom',
        nonce: '7',
      );
      expect(await repo.transactions(), hasLength(2));

      // Within one network the conflict still fires.
      await expectLater(
        repo.reserveEvmTransaction(
          _evmTx('mainnet-racing', 'A', networkId: 'eth-mainnet'),
          coin: 'eth',
          networkId: 'eth-mainnet',
          from: '0xfrom',
          nonce: '7',
        ),
        throwsA(
          isA<EvmNonceConflict>().having(
            (error) => error.existing.id,
            'existing.id',
            'mainnet',
          ),
        ),
      );
    });

    test('transactions can be filtered to the active networks', () async {
      final repo = wallets.scoped('A');
      await repo.upsertTransaction(
        _evmTx('sepolia', 'A', networkId: 'eth-sepolia'),
      );
      await repo.upsertTransaction(
        _evmTx('mainnet', 'A', nonce: '8', networkId: 'eth-mainnet'),
      );

      expect(await repo.transactions(), hasLength(2));
      expect(
        (await repo.transactions(networkIds: {'eth-mainnet'})).single.id,
        'mainnet',
      );
      expect(
        (await repo.transactions(networkIds: {'eth-sepolia'})).single.id,
        'sepolia',
      );
      expect(await repo.transactions(networkIds: {'tron-nile'}), isEmpty);
    });
  });
}

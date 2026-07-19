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

TransactionsCompanion _tx(String id, String walletId, {String amount = '100'}) =>
    TransactionsCompanion.insert(
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
      await wallets.scoped('A').addContact(AddressBookCompanion.insert(
            id: 'c1',
            walletId: 'A',
            name: 'Alice',
            address: '0xalice',
            coin: 'eth',
            createdAt: 1,
          ));
      expect(await wallets.scoped('A').contacts(), hasLength(1));
      expect(await wallets.scoped('B').contacts(), isEmpty);
    });

    test('token visibility toggles are per wallet', () async {
      await wallets.scoped('A').upsertToken(TokensCompanion.insert(
            walletId: 'A',
            coin: 'eth',
            symbol: 'USDT',
            decimals: 6,
            name: 'Tether',
            enabled: const Value(false),
          ));
      expect(await wallets.scoped('A').tokens(), hasLength(1));
      expect(await wallets.scoped('A').tokens(enabledOnly: true), isEmpty);
      expect(await wallets.scoped('B').tokens(), isEmpty);
    });

    test('per-wallet settings do not leak', () async {
      await wallets.scoped('A').putSetting('theme', 'dark');
      expect(await wallets.scoped('A').setting('theme'), 'dark');
      expect(await wallets.scoped('B').setting('theme'), isNull);
    });

    test('scope forces walletId even if the caller passes a foreign one', () async {
      // A caller tries to smuggle a row for B through A's repository (asserts
      // are stripped in release, so the repo must force the scope's walletId).
      await wallets.scoped('A').upsertTransaction(_tx('t1', 'B'));
      expect(await wallets.scoped('A').transactions(), hasLength(1));
      expect(await wallets.scoped('B').transactions(), isEmpty);
      expect((await wallets.scoped('A').transactions()).single.walletId, 'A');
    });
  });

  group('wallet lifecycle', () {
    test('listAll returns wallets ordered by sortOrder', () async {
      final all = await wallets.listAll();
      expect(all.map((w) => w.id), containsAll(['A', 'B']));
    });

    test('deleteWallet cascades all per-wallet rows', () async {
      final a = wallets.scoped('A');
      await a.upsertTransaction(_tx('t1', 'A'));
      await a.addContact(AddressBookCompanion.insert(
        id: 'c1', walletId: 'A', name: 'x', address: 'y', coin: 'eth', createdAt: 1,
      ));
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
}

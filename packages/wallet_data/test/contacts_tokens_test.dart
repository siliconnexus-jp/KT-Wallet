import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:test/test.dart';
import 'package:wallet_data/wallet_data.dart';

ContactsCompanion _contact(
  String id, {
  String chain = 'ethereum',
  int createdAt = 0,
}) => ContactsCompanion.insert(
  id: id,
  name: 'name-$id',
  address: 'addr-$id',
  chain: chain,
  createdAt: createdAt,
);

CustomTokensCompanion _token(
  String id, {
  String symbol = 'USDT',
  String? contract,
  String? networkId,
  bool enabled = true,
  int sortOrder = 0,
  int createdAt = 0,
}) => CustomTokensCompanion.insert(
  id: id,
  symbol: symbol,
  name: 'token-$id',
  contract: Value(contract),
  network: 'Ethereum · ERC-20',
  networkId: Value(networkId),
  enabled: Value(enabled),
  sortOrder: Value(sortOrder),
  createdAt: createdAt,
);

void main() {
  late WalletDatabase db;

  setUp(() => db = WalletDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('ContactsRepository', () {
    test('insert then list round-trips all fields', () async {
      final repo = ContactsRepository(db);
      await repo.insert(
        ContactsCompanion.insert(
          id: 'c1',
          name: 'Alice',
          address: '0x71c8B2…9F3dA24',
          chain: 'ethereum',
          createdAt: 42,
        ),
      );
      final row = (await repo.list()).single;
      expect(row.id, 'c1');
      expect(row.name, 'Alice');
      expect(row.address, '0x71c8B2…9F3dA24');
      expect(row.chain, 'ethereum');
      expect(row.createdAt, 42);
    });

    test('list is ordered by createdAt', () async {
      final repo = ContactsRepository(db);
      await repo.insert(_contact('late', createdAt: 300));
      await repo.insert(_contact('early', createdAt: 100));
      await repo.insert(_contact('mid', createdAt: 200));
      expect((await repo.list()).map((c) => c.id).toList(), [
        'early',
        'mid',
        'late',
      ]);
    });

    test('delete removes exactly the targeted contact', () async {
      final repo = ContactsRepository(db);
      await repo.insert(_contact('c1'));
      await repo.insert(_contact('c2'));
      await repo.delete('c1');
      expect((await repo.list()).map((c) => c.id).toList(), ['c2']);
    });
  });

  group('TokensRepository', () {
    test(
      'insert then list round-trips all fields (nullable contract)',
      () async {
        final repo = TokensRepository(db);
        await repo.insert(
          CustomTokensCompanion.insert(
            id: 't1',
            symbol: 'LINK',
            name: 'Chainlink',
            contract: const Value('0x514910771AF9Ca656af840dff83E8264EcF986CA'),
            network: 'Chainlink · 0x514910…F986CA',
            networkId: const Value('eth-mainnet'),
            createdAt: 7,
          ),
        );
        await repo.insert(
          _token('t2', symbol: 'USDT', sortOrder: 1, createdAt: 8),
        );

        final rows = await repo.list();
        expect(rows, hasLength(2));
        final link = rows.first;
        expect(link.symbol, 'LINK');
        expect(link.contract, '0x514910771AF9Ca656af840dff83E8264EcF986CA');
        expect(link.networkId, 'eth-mainnet');
        expect(link.enabled, isTrue); // default
        expect(rows.last.contract, isNull);
      },
    );

    test('list is ordered by sortOrder', () async {
      final repo = TokensRepository(db);
      await repo.insert(_token('b', sortOrder: 1));
      await repo.insert(_token('c', sortOrder: 2));
      await repo.insert(_token('a', sortOrder: 0));
      expect((await repo.list()).map((t) => t.id).toList(), ['a', 'b', 'c']);
    });

    test('setEnabled flips and persists the flag', () async {
      final repo = TokensRepository(db);
      await repo.insert(_token('t1', enabled: true));
      await repo.setEnabled('t1', false);
      expect((await repo.list()).single.enabled, isFalse);
      await repo.setEnabled('t1', true);
      expect((await repo.list()).single.enabled, isTrue);
    });

    test('delete removes exactly the targeted token', () async {
      final repo = TokensRepository(db);
      await repo.insert(_token('t1'));
      await repo.insert(_token('t2', sortOrder: 1));
      await repo.delete('t2');
      expect((await repo.list()).map((t) => t.id).toList(), ['t1']);
    });
  });
}

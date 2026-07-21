import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:wallet_data/wallet_data.dart';

/// The address book and custom-token list must survive an app restart: a new
/// [WalletController] built over the same drift database (simulated restart)
/// has to see everything a previous controller persisted.
void main() {
  late WalletDatabase db;

  setUp(() => db = WalletDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  /// A fresh controller over the same database — the restart simulation.
  WalletController restart() =>
      WalletController(WalletManager(), store: WalletStore(db));

  test('added contact is still there after a restart', () async {
    final before = restart();
    await before.loadContacts();
    await before.addContact(
      name: 'Carol',
      address: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      chain: 'tron',
    );

    final after = restart();
    final contacts = await after.loadContacts();
    expect(contacts, hasLength(1));
    expect(contacts.single.name, 'Carol');
    expect(contacts.single.address, 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t');
    expect(contacts.single.chain, 'tron');
  });

  test('removed contact stays gone after a restart', () async {
    final before = restart();
    final keep = await before.addContact(name: 'Keep', address: '0xkeep', chain: 'ethereum');
    final drop = await before.addContact(name: 'Drop', address: '0xdrop', chain: 'ethereum');
    await before.removeContact(drop.id);
    expect(before.contacts.map((c) => c.id), [keep.id]);

    final after = restart();
    final contacts = await after.loadContacts();
    expect(contacts.map((c) => c.id), [keep.id]);
  });

  test('custom token and its enabled toggle persist across a restart', () async {
    final before = restart();
    await before.loadTokens();
    final link = await before.addToken(
      symbol: 'LINK',
      name: 'Chainlink',
      contract: '0x514910771AF9Ca656af840dff83E8264EcF986CA',
      network: 'Chainlink · 0x514910…F986CA',
    );
    await before.addToken(symbol: 'ARB', name: 'Arbitrum', network: 'Arbitrum');
    await before.setTokenEnabled(link.id, false);

    final after = restart();
    final tokens = await after.loadTokens();
    expect(tokens, hasLength(2));
    final restored = tokens.firstWhere((t) => t.id == link.id);
    expect(restored.symbol, 'LINK');
    expect(restored.contract, '0x514910771AF9Ca656af840dff83E8264EcF986CA');
    expect(restored.enabled, isFalse);
    expect(tokens.firstWhere((t) => t.symbol == 'ARB').enabled, isTrue);
  });

  test('re-enabling a token persists too', () async {
    final before = restart();
    final t = await before.addToken(symbol: 'UNI', name: 'Uniswap', network: 'Ethereum · ERC-20', enabled: false);
    await before.setTokenEnabled(t.id, true);

    final after = restart();
    expect((await after.loadTokens()).single.enabled, isTrue);
  });

  test('without a store the controller keeps a working in-memory list', () async {
    final memory = WalletController(WalletManager());
    expect(memory.hasStore, isFalse);

    await memory.addContact(name: 'Ghost', address: '0xghost', chain: 'ethereum');
    final token = await memory.addToken(symbol: 'GHO', name: 'Ghost', network: 'Ethereum');
    await memory.setTokenEnabled(token.id, false);
    expect((await memory.loadContacts()).single.name, 'Ghost');
    expect((await memory.loadTokens()).single.enabled, isFalse);
    await memory.removeContact(memory.contacts.single.id);
    expect(memory.contacts, isEmpty);

    // Nothing leaked into the database: a store-backed controller sees none of it.
    final persisted = restart();
    expect(await persisted.loadContacts(), isEmpty);
    expect(await persisted.loadTokens(), isEmpty);
  });
}

import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

ChainAddresses _addr(String seed) => ChainAddresses(
      eth: '0x$seed',
      polygon: '0x$seed',
      tron: 'T$seed',
      solana: seed,
    );

HotWallet _hot(String id, {int sort = 0, bool backedUp = false}) => HotWallet(
      id: id,
      name: 'hot-$id',
      avatarColor: 0xF59E0B,
      addresses: _addr(id),
      sortOrder: sort,
      backedUp: backedUp,
    );

WatchWallet _watch(String id, {int sort = 0}) => WatchWallet(
      id: id,
      name: 'watch-$id',
      avatarColor: 0x0C1220,
      addresses: _addr(id),
      sortOrder: sort,
      coldWalletId: 'COLD-$id',
      protocolVersion: 1,
    );

void main() {
  group('WalletManager', () {
    test('add sets first wallet as current and tracks count', () {
      final m = WalletManager();
      expect(m.current, isNull);
      m.add(_hot('A'));
      expect(m.current?.id, 'A');
      expect(m.count, 1);
      m.add(_watch('B'));
      expect(m.count, 2);
      expect(m.current?.id, 'A'); // adding doesn't switch
    });

    test('rejects duplicate ids', () {
      final m = WalletManager()..add(_hot('A'));
      expect(() => m.add(_hot('A')), throwsA(isA<WalletError>()));
    });

    test('enforces the 20-wallet cap', () {
      final m = WalletManager();
      for (var i = 0; i < WalletManager.maxWallets; i++) {
        m.add(_hot('w$i'));
      }
      expect(m.canAddMore, isFalse);
      expect(() => m.add(_hot('over')), throwsA(isA<WalletError>()));
    });

    test('select switches the current wallet (global switch)', () {
      final m = WalletManager()
        ..add(_hot('A'))
        ..add(_watch('B'));
      m.select('B');
      expect(m.current?.id, 'B');
      expect(() => m.select('missing'), throwsA(isA<WalletError>()));
    });

    test('mixed hot + watch coexist and sort by sortOrder', () {
      final m = WalletManager()
        ..add(_hot('A', sort: 2))
        ..add(_watch('B', sort: 0))
        ..add(_hot('C', sort: 1));
      expect(m.wallets.map((w) => w.id), ['B', 'C', 'A']);
    });

    test('rename / setColor / markBackedUp mutate in place', () {
      final m = WalletManager()..add(_hot('A'));
      m.rename('A', 'Daily');
      m.setColor('A', 0x123456);
      m.markBackedUp('A');
      final w = m.current! as HotWallet;
      expect(w.name, 'Daily');
      expect(w.avatarColor, 0x123456);
      expect(w.backedUp, isTrue);
    });

    test('markBackedUp is meaningless for watch wallets', () {
      final m = WalletManager()..add(_watch('B'));
      expect(() => m.markBackedUp('B'), throwsA(isA<WalletError>()));
    });

    test('remove falls back current to first remaining, or null', () {
      final m = WalletManager()
        ..add(_hot('A', sort: 0))
        ..add(_hot('B', sort: 1));
      m.select('A');
      m.remove('A');
      expect(m.current?.id, 'B');
      m.remove('B');
      expect(m.current, isNull);
    });

    test('reorder rewrites sortOrder', () {
      final m = WalletManager()
        ..add(_hot('A', sort: 0))
        ..add(_hot('B', sort: 1))
        ..add(_hot('C', sort: 2));
      m.reorder(['C', 'A', 'B']);
      expect(m.wallets.map((w) => w.id), ['C', 'A', 'B']);
    });

    test('reorder must be a full permutation (no partial mutation)', () {
      final m = WalletManager()
        ..add(_hot('A', sort: 0))
        ..add(_hot('B', sort: 1))
        ..add(_hot('C', sort: 2));
      // A subset is rejected up front; order stays unchanged.
      expect(() => m.reorder(['C', 'A']), throwsA(isA<WalletError>()));
      expect(m.wallets.map((w) => w.id), ['A', 'B', 'C']);
      // An unknown id is rejected before any wallet is mutated.
      expect(() => m.reorder(['C', 'A', 'X']), throwsA(isA<WalletError>()));
      expect(m.wallets.map((w) => w.id), ['A', 'B', 'C']);
    });
  });

  group('type-level signing isolation (INV-14)', () {
    test('watch wallet cannot sign locally; hot wallet can', () {
      expect(_hot('A').canSignLocally, isTrue);
      expect(_watch('B').canSignLocally, isFalse);
    });

    test('only HotWallet exposes a sign() method (compile-time isolation)', () {
      // This is enforced by the type system: `WatchWallet` has no `sign`.
      // The test documents the guarantee; the real proof is that referencing
      // (_watch('B') as dynamic).sign(...) would fail at runtime and a static
      // `watchWallet.sign` would not compile.
      final Wallet w = _watch('B');
      expect(w is HotWallet, isFalse);
      expect(w is WatchWallet, isTrue);
    });
  });
}

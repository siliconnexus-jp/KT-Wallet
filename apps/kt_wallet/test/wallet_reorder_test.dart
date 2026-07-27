import 'package:core_crypto/core_crypto.dart' show ChainAddresses;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/wallet_screens.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/wallets/wallet_store.dart';
import 'package:wallet_data/wallet_data.dart';

/// Wallet drag-to-reorder: the controller must persist the new sortOrder so
/// the order survives a restart, and the manage screen's reorder mode must
/// actually move rows.
const _addresses = ChainAddresses(
  eth: '0xa',
  polygon: '0xa',
  tron: 'Ta',
  solana: 'a',
);

HotWallet _wallet(String id, String name, int sortOrder) => HotWallet(
  id: id,
  name: name,
  avatarColor: 0xFFF59E0B,
  addresses: _addresses,
  sortOrder: sortOrder,
  backedUp: true,
);

void main() {
  group('WalletController.reorder', () {
    late WalletDatabase db;

    setUp(() => db = WalletDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test(
      'reorders the list and persists sortOrder across a store reload',
      () async {
        final controller =
            WalletController(WalletManager(), store: WalletStore(db))
              ..add(_wallet('w1', 'A', 0))
              ..add(_wallet('w2', 'B', 1))
              ..add(_wallet('w3', 'C', 2));

        controller.reorder(0, 2); // drag A below C

        expect(controller.wallets.map((w) => w.id), ['w2', 'w3', 'w1']);
        expect(controller.wallets.map((w) => w.sortOrder), [0, 1, 2]);

        // Simulated restart: a fresh manager loaded from the same database.
        final reloaded = await WalletStore(db).load();
        expect(reloaded.wallets.map((w) => w.id), ['w2', 'w3', 'w1']);
        expect(reloaded.wallets.map((w) => w.sortOrder), [0, 1, 2]);
        // And the first (lowest sortOrder) wallet is the initial selection.
        expect(reloaded.current?.id, 'w2');
      },
    );

    test('moving a wallet up persists too', () async {
      final controller =
          WalletController(WalletManager(), store: WalletStore(db))
            ..add(_wallet('w1', 'A', 0))
            ..add(_wallet('w2', 'B', 1))
            ..add(_wallet('w3', 'C', 2));

      controller.reorder(2, 0); // drag C to the top
      expect(controller.wallets.map((w) => w.id), ['w3', 'w1', 'w2']);

      final reloaded = await WalletStore(db).load();
      expect(reloaded.wallets.map((w) => w.id), ['w3', 'w1', 'w2']);
    });

    test('works without a store (in-memory only)', () {
      final controller = WalletController(WalletManager())
        ..add(_wallet('w1', 'A', 0))
        ..add(_wallet('w2', 'B', 1));
      controller.reorder(1, 0);
      expect(controller.wallets.map((w) => w.id), ['w2', 'w1']);
    });
  });

  group('WalletManageScreen reorder mode', () {
    Widget app(WalletController controller) => MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: WalletScope(
        controller: controller,
        child: const WalletManageScreen(),
      ),
    );

    testWidgets(
      '排序 toggles reorder mode; dragging row 0 below row 1 reorders and persists',
      (tester) async {
        final db = WalletDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final controller =
            WalletController(WalletManager(), store: WalletStore(db))
              ..add(_wallet('w1', 'Alpha', 0))
              ..add(_wallet('w2', 'Beta', 1));

        await tester.pumpWidget(app(controller));
        await tester.pumpAndSettle();

        // Normal mode: delete buttons visible, no drag handles.
        expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
        expect(find.byIcon(Icons.drag_handle), findsNothing);

        await tester.tap(find.text('排序'));
        await tester.pumpAndSettle();

        // Reorder mode: 完成 replaces 排序, handles replace delete buttons.
        expect(find.text('完成'), findsOneWidget);
        expect(find.text('排序'), findsNothing);
        expect(find.byIcon(Icons.drag_handle), findsNWidgets(2));
        expect(find.byIcon(Icons.delete_outline), findsNothing);

        // Drag the first row's handle below the second row (explicit gesture:
        // the reorderable list needs frames between lift, move and drop).
        final handle = tester.getCenter(find.byIcon(Icons.drag_handle).first);
        final gesture = await tester.startGesture(handle);
        await tester.pump(const Duration(milliseconds: 100));
        await gesture.moveBy(const Offset(0, 60));
        await tester.pump(const Duration(milliseconds: 100));
        await gesture.moveBy(const Offset(0, 60));
        await tester.pump(const Duration(milliseconds: 100));
        await gesture.up();
        await tester.pumpAndSettle();

        expect(controller.wallets.map((w) => w.id), ['w2', 'w1']);
        expect(controller.wallets.map((w) => w.sortOrder), [0, 1]);

        // Persisted: a fresh store over the same database sees the new order.
        final reloaded = await WalletStore(db).load();
        expect(reloaded.wallets.map((w) => w.id), ['w2', 'w1']);

        // 完成 exits reorder mode and restores the normal list.
        await tester.tap(find.text('完成'));
        await tester.pumpAndSettle();
        expect(find.text('排序'), findsOneWidget);
        expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
        expect(find.byIcon(Icons.drag_handle), findsNothing);
      },
    );
  });
}

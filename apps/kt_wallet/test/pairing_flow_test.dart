import 'package:flutter/material.dart';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/screens/wallet_screens.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/pairing_airgap.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

/// The cold-wallet pairing loop: the signer's AccountExport travels the real
/// protocol path (fragment → wire bytes → aggregate → decode) and the created
/// watch wallet carries the decoded name/id/addresses — not hardcoded demos.
void main() {
  test(
    'AccountExport round-trip: fragment → aggregate → decode equals source',
    () {
      final frames = demoAccountExportFrames();
      expect(
        frames.length,
        greaterThan(1),
        reason: 'demo chunk size must exercise aggregation',
      );

      final agg = FrameAggregator();
      for (final frame in frames) {
        agg.addFrame(AirgapFrame.decode(frame.encode()));
      }
      final payload = agg.payload;
      expect(payload, isNotNull);

      final decoded = AirgapPayload.decode(payload!) as AccountExport;
      expect(decoded.walletId, demoAccountExport.walletId);
      expect(decoded.walletName, demoAccountExport.walletName);
      expect(decoded.accounts.length, 4);
      for (var i = 0; i < 4; i++) {
        expect(decoded.accounts[i].coin, demoAccountExport.accounts[i].coin);
        expect(
          decoded.accounts[i].address,
          demoAccountExport.accounts[i].address,
        );
        expect(decoded.accounts[i].path, demoAccountExport.accounts[i].path);
      }
    },
  );

  testWidgets(
    'scan → import-confirm shows decoded export → creates the paired watch wallet',
    (tester) async {
      tester.platformDispatcher.localesTestValue = <Locale>[const Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);

      final controller = WalletController(
        WalletManager(
          initial: [
            HotWallet(
              id: 'daily',
              name: '日常钱包',
              avatarColor: 0xFFF59E0B,
              addresses: const ChainAddressesFixture().addresses,
              backedUp: true,
            ),
          ],
        ),
      );
      await tester.pumpWidget(
        KtWalletApp(controller: controller, initialLocation: '/connect-cold'),
      );
      await tester.pumpAndSettle();

      // W11 → W12: start scanning.
      await tester.tap(find.text('扫描账户二维码').last);
      await tester.pumpAndSettle();

      // Feed every frame through the simulated camera; progress appears.
      final frames = demoAccountExportFrames();
      for (var i = 0; i < frames.length; i++) {
        await tester.tap(find.byIcon(Icons.qr_code_2));
        await tester.pumpAndSettle();
      }

      // W13 renders the DECODED export, not the legacy demo snapshot.
      expect(find.text('主钱包'), findsOneWidget);
      expect(find.textContaining('WLT-3E8A91'), findsOneWidget);
      expect(find.textContaining('TR7NHqje'), findsOneWidget);

      // Create the watch wallet from the payload.
      await tester.tap(find.text('创建观察钱包'));
      await tester.pumpAndSettle();

      final created = controller.wallets.whereType<WatchWallet>().single;
      expect(created.id, matches(RegExp(r'^w_[A-Za-z0-9_-]{24}$')));
      expect(created.name, '主钱包');
      expect(created.coldWalletId, 'WLT-3E8A91');
      expect(created.addresses.tron, 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t');
      expect(
        created.addresses.eth,
        '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      );
      expect(controller.current, created);
    },
  );

  testWidgets('invalid offline export uses the active English locale', (
    tester,
  ) async {
    final controller = WalletController(WalletManager());
    final invalid = AccountExport(
      walletId: 'WLT-invalid',
      walletName: 'Offline wallet',
      accounts: [
        AccountRecord(
          coin: 60,
          address: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
          path: "m/44'/60'/0'/0/0",
          index: 0,
        ),
      ],
    );
    await tester.pumpWidget(
      _localizedApp(
        controller: controller,
        locale: const Locale('en'),
        home: ImportConfirmScreen(export: invalid),
      ),
    );
    await tester.tap(find.text('Create watch wallet'));
    await tester.pumpAndSettle();

    expect(find.text('Invalid offline wallet export'), findsOneWidget);
    expect(find.text('离线钱包导出数据无效'), findsNothing);
    expect(controller.wallets, isEmpty);
  });

  testWidgets('missing AccountExport never exposes or creates fixture wallet', (
    tester,
  ) async {
    final controller = WalletController(WalletManager());
    await tester.pumpWidget(
      _localizedApp(
        controller: controller,
        locale: const Locale('en'),
        home: const ImportConfirmScreen(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Invalid offline wallet export'), findsOneWidget);
    expect(find.text('Create watch wallet'), findsNothing);
    expect(find.textContaining('WLT-3E8A91'), findsNothing);
    expect(controller.wallets, isEmpty);
  });

  testWidgets('duplicate pairing uses Japanese and keeps the existing wallet', (
    tester,
  ) async {
    final existing = WatchWallet(
      id: 'existing',
      name: '既存ウォレット',
      avatarColor: 0xFF0C1220,
      addresses: const ChainAddressesFixture().addresses,
      coldWalletId: demoAccountExport.walletId,
      protocolVersion: 1,
    );
    final controller = WalletController(WalletManager(initial: [existing]));
    await tester.pumpWidget(
      _localizedApp(
        controller: controller,
        locale: const Locale('ja'),
        home: ImportConfirmScreen(export: demoAccountExport),
      ),
    );
    await tester.tap(find.text('監視ウォレットを作成'));
    await tester.pumpAndSettle();

    expect(find.text('このオフラインウォレットはすでにペアリングされています'), findsOneWidget);
    expect(find.text('This offline wallet is already paired'), findsNothing);
    expect(controller.wallets, hasLength(1));
    expect(controller.wallets.single, same(existing));
  });

  testWidgets('wallet identifiers use Japanese labels', (tester) async {
    final wallet = WatchWallet(
      id: 'watch-1',
      name: '監視ウォレット',
      avatarColor: 0xFF0C1220,
      addresses: const ChainAddressesFixture().addresses,
      coldWalletId: 'WLT-COLD-1',
      protocolVersion: 1,
    );
    final controller = WalletController(WalletManager(initial: [wallet]));
    await tester.pumpWidget(
      _localizedApp(
        controller: controller,
        locale: const Locale('ja'),
        home: const WalletDetailScreen(walletId: 'watch-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ウォレット ID'), findsOneWidget);
    expect(find.text('KT Cold Signer ウォレット ID'), findsOneWidget);
    expect(find.text('Wallet ID'), findsNothing);
  });
}

Widget _localizedApp({
  required WalletController controller,
  required Locale locale,
  required Widget home,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: WalletScope(controller: controller, child: home),
);

/// Matches main.dart's `_addr('a')` demo shape without importing private API.
class ChainAddressesFixture {
  const ChainAddressesFixture();
  ChainAddresses get addresses => ChainAddresses(
    eth: '0xa71c8B29b3d4b79E19bE1',
    polygon: '0xa71c8B29b3d4b79E19bE1',
    tron: 'TaPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
    solana: 'ayKpXwMWd4qmDqVr2W',
  );
}

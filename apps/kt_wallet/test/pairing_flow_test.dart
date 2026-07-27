import 'dart:ui';

import 'package:flutter/material.dart' show Icons;

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
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
      expect(
        find.text('TcPa2Wc8…7L3kFa'),
        findsNothing,
      ); // sanity: truncation format checked below
      expect(find.textContaining('TcPa2Wc8'), findsOneWidget);

      // Create the watch wallet from the payload.
      await tester.tap(find.text('创建观察钱包'));
      await tester.pumpAndSettle();

      final created = controller.wallets.whereType<WatchWallet>().single;
      expect(created.name, '主钱包');
      expect(created.coldWalletId, 'WLT-3E8A91');
      expect(created.addresses.tron, 'TcPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa');
      expect(created.addresses.eth, '0xc71c8B29b3d4b79E19bE1');
      expect(controller.current, created);
    },
  );
}

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

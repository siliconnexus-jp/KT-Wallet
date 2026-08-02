import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/wallet_screens.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/wallets/pairing_airgap.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:ui_kit/ui_kit.dart';

const _addresses = ChainAddresses(
  eth: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
  polygon: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
  tron: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  solana: 'So11111111111111111111111111111111111111112',
);

Widget _app({
  required WalletController controller,
  required Locale locale,
  required Widget home,
}) => MaterialApp(
  locale: locale,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: KtDeviceChrome(
    mockStatusBar: false,
    child: WalletScope(controller: controller, child: home),
  ),
);

Future<void> _evidencePause(WidgetTester tester, String marker) async {
  // ignore: avoid_print
  print('LOCALIZATION_COPY_CAPTURE READY=$marker');
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(seconds: 20)),
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Japanese wallet identifiers remain localized',
    (tester) async {
      final watch = WatchWallet(
        id: 'watch-1',
        name: '監視ウォレット',
        avatarColor: 0xFF0C1220,
        addresses: _addresses,
        coldWalletId: 'WLT-COLD-1',
        protocolVersion: 1,
      );
      await tester.pumpWidget(
        _app(
          controller: WalletController(WalletManager(initial: [watch])),
          locale: const Locale('ja'),
          home: const WalletDetailScreen(walletId: 'watch-1'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ウォレット ID'), findsOneWidget);
      expect(find.text('KT Cold Signer ウォレット ID'), findsOneWidget);
      expect(find.text('Wallet ID'), findsNothing);
      await _evidencePause(tester, 'wallet-identifiers-ja');
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  testWidgets(
    'invalid export error follows the English locale',
    (tester) async {
      final invalidController = WalletController(WalletManager());
      final invalid = AccountExport(
        walletId: 'WLT-invalid',
        walletName: 'Offline wallet',
        accounts: [
          AccountRecord(
            coin: 60,
            address: _addresses.eth,
            path: evmDefaultDerivationPath,
            index: 0,
            publicKey: Uint8List(33),
          ),
        ],
      );
      await tester.pumpWidget(
        _app(
          controller: invalidController,
          locale: const Locale('en'),
          home: ImportConfirmScreen(export: invalid),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create watch wallet'));
      await tester.pumpAndSettle();
      expect(find.text('Invalid offline wallet export'), findsOneWidget);
      expect(find.text('离线钱包导出数据无效'), findsNothing);
      expect(invalidController.wallets, isEmpty);
      await _evidencePause(tester, 'invalid-export-en');
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );

  testWidgets(
    'duplicate export error follows the Japanese locale',
    (tester) async {
      final existing = WatchWallet(
        id: 'existing',
        name: '既存ウォレット',
        avatarColor: 0xFF0C1220,
        addresses: _addresses,
        coldWalletId: demoAccountExport.walletId,
        protocolVersion: 1,
      );
      final duplicateController = WalletController(
        WalletManager(initial: [existing]),
      );
      await tester.pumpWidget(
        _app(
          controller: duplicateController,
          locale: const Locale('ja'),
          home: ImportConfirmScreen(export: demoAccountExport),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('監視ウォレットを作成'));
      await tester.pumpAndSettle();
      expect(find.text('このオフラインウォレットはすでにペアリングされています'), findsOneWidget);
      expect(find.text('This offline wallet is already paired'), findsNothing);
      expect(duplicateController.wallets, hasLength(1));
      await _evidencePause(tester, 'duplicate-export-ja');
    },
    timeout: const Timeout(Duration(minutes: 1)),
  );
}

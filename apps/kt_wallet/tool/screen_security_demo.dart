import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/state/locale_controller.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:ui_kit/ui_kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const locale = Locale('en');
  final localeController = LocaleController(initial: locale);
  final controller = WalletController(
    WalletManager(),
    crypto: MockCoreCrypto(),
  );
  await controller.beginCreate();
  runApp(
    ScreenSecurityGuard(
      locale: localeController.locale,
      child: KtWalletApp(
        controller: controller,
        localeController: localeController,
        initialLocation: '/mnemonic-show',
      ),
    ),
  );
}

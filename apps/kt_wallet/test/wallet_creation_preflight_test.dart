import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/main.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';

class _DeviceCrypto extends MockCoreCrypto {
  bool ready = false;
  int generated = 0;
  @override
  Future<void> checkWalletCreationReady() async {
    if (!ready) throw const AuthUnavailableException();
  }

  @override
  Future<String> generateMnemonic({int strength = 128}) {
    generated++;
    return super.generateMnemonic(strength: strength);
  }
}

void main() {
  testWidgets(
    'unavailable device is explained before generating secrets and can retry',
    (tester) async {
      tester.platformDispatcher.localesTestValue = [const Locale('zh')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      final crypto = _DeviceCrypto();
      final controller = WalletController(WalletManager(), crypto: crypto);
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        KtWalletApp(controller: controller, initialLocation: '/add-wallet'),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('创建新钱包'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('wallet-create-preflight-error')),
        findsOneWidget,
      );
      expect(find.textContaining('锁屏 PIN 或密码'), findsOneWidget);
      expect(crypto.generated, 0);
      expect(controller.pendingMnemonic, isNull);
      expect(controller.count, 0);
      crypto.ready = true;
      await tester.tap(find.text('创建新钱包'));
      await tester.tap(find.text('创建新钱包'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('显示助记词'), findsOneWidget);
      expect(crypto.generated, 1);
      expect(controller.count, 0);
    },
  );
}

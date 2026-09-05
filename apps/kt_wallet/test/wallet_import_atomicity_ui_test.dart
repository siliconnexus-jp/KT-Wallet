import 'package:core_crypto/testing.dart';
import 'package:core_crypto/core_crypto.dart';
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
import 'package:wallet_data/wallet_data.dart' as db;

class _SaveFailureStore extends WalletStore {
  _SaveFailureStore(super.database);

  @override
  Future<void> save(Wallet wallet) =>
      Future<void>.error(StateError('wallet database unavailable'));
}

class _UnavailableAuthCrypto extends MockCoreCrypto {
  @override
  Future<void> storeWallet({
    required String walletId,
    required String mnemonic,
    bool requireAuth = true,
    String? kdfPassword,
  }) async {
    throw const AuthUnavailableException();
  }
}

Future<void> _pumpImport(
  WidgetTester tester,
  WalletController controller,
) async {
  await tester.pumpWidget(
    WalletScope(
      controller: controller,
      child: const MaterialApp(
        locale: Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MnemonicImportScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _enterPhrase(WidgetTester tester, String mnemonic) async {
  final words = mnemonic.split(' ');
  final fields = find.byType(TextField);
  expect(fields, findsNWidgets(12));
  for (var i = 0; i < words.length; i++) {
    await tester.enterText(fields.at(i), words[i]);
  }
  await tester.pump();
}

void main() {
  testWidgets('unavailable authentication explains device setup on import', (
    tester,
  ) async {
    final crypto = _UnavailableAuthCrypto();
    final controller = WalletController(WalletManager(), crypto: crypto);
    await _pumpImport(tester, controller);
    await _enterPhrase(tester, await crypto.generateMnemonic());
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    expect(find.textContaining('锁屏 PIN 或密码'), findsOneWidget);
    expect(controller.wallets, isEmpty);
    expect(find.byType(MnemonicImportScreen), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      isNotEmpty,
    );
  });

  testWidgets('duplicate import stays on screen and explains the rejection', (
    tester,
  ) async {
    final crypto = MockCoreCrypto();
    final controller = WalletController(WalletManager(), crypto: crypto);
    final mnemonic = await crypto.generateMnemonic();
    await controller.importWallet(mnemonic, name: 'Existing');
    await _pumpImport(tester, controller);
    await _enterPhrase(tester, mnemonic);

    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    expect(find.text('该钱包已存在于本机。'), findsOneWidget);
    expect(controller.wallets, hasLength(1));
    expect(find.byType(MnemonicImportScreen), findsOneWidget);
  });

  testWidgets('database failure never reports import success', (tester) async {
    final database = db.WalletDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final crypto = MockCoreCrypto();
    final controller = WalletController(
      WalletManager(),
      crypto: crypto,
      store: _SaveFailureStore(database),
    );
    final mnemonic = await crypto.generateMnemonic();
    await _pumpImport(tester, controller);
    await _enterPhrase(tester, mnemonic);

    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    expect(find.text('无法安全保存钱包，本次未添加任何钱包。请重试。'), findsOneWidget);
    expect(find.text('助记词已导入'), findsNothing);
    expect(controller.wallets, isEmpty);
    expect(crypto.storedWalletCount, 0);
    expect(find.byType(MnemonicImportScreen), findsOneWidget);
  });
}

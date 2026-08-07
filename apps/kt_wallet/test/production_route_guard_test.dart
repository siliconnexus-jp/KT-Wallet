import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;
import 'package:core_crypto/testing.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/app_router.dart';
import 'package:kt_wallet/src/market/asset_ref.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

TransferDraft _draft() => TransferDraft(
  symbol: 'ETH',
  networkLabel: 'Sepolia',
  chain: Chain.ethereum,
  recipient: '0x0000000000000000000000000000000000000001',
  amount: Amount(raw: BigInt.one, decimals: 18, symbol: 'ETH'),
  feeTier: 1,
);

SignRequest _request() => SignRequest(
  reqId: Uint8List.fromList(const [1, 2, 3, 4, 5, 6, 7, 8]),
  walletId: 'wallet-1',
  coin: 60,
  rawTx: Uint8List.fromList(const [1]),
  createdAt: 100,
  expiresAt: 200,
);

SignResult _result() => SignResult(
  reqId: Uint8List.fromList(const [1, 2, 3, 4, 5, 6, 7, 8]),
  walletId: 'wallet-1',
  coin: 60,
  signedTx: Uint8List.fromList(const [2]),
  signer: '0x0000000000000000000000000000000000000002',
  txHash: '0x01',
);

String? _redirect(
  String path, {
  Object? extra,
  TransferSession? session,
  bool gallery = false,
  WalletController? wallets,
}) => productionRouteRedirect(
  galleryMode: gallery,
  uri: Uri.parse(path),
  extra: extra,
  walletController: wallets ?? _walletController(),
  transferSession: session,
);

WalletController _walletController({bool withWallet = true}) =>
    WalletController(
      WalletManager(
        initial: withWallet
            ? [
                HotWallet(
                  id: 'wallet-1',
                  name: 'Wallet',
                  avatarColor: 0xFF2557E8,
                  addresses: const ChainAddresses(
                    eth: '0x0000000000000000000000000000000000000001',
                    polygon: '0x0000000000000000000000000000000000000001',
                    tron: 'TQm9xPa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
                    solana: '11111111111111111111111111111111',
                  ),
                  backedUp: true,
                ),
              ]
            : const [],
      ),
      crypto: MockCoreCrypto(),
    );

void main() {
  test('gallery routes retain explicit visual fixtures', () {
    expect(_redirect('/import-confirm', gallery: true), isNull);
    expect(_redirect('/confirm-hot', gallery: true), isNull);
    expect(_redirect('/broadcast-result', gallery: true), isNull);
  });

  test('production fixture and wallet-dependent routes fail closed', () {
    expect(_redirect('/splash'), '/home');
    final empty = _walletController(withWallet: false);
    for (final path in const [
      '/receive',
      '/transfer',
      '/assets',
      '/records',
      '/wallet-detail',
      '/wallet-addresses',
      '/backup',
    ]) {
      expect(_redirect(path, wallets: empty), '/add-wallet');
    }
    expect(_redirect('/wallet-detail?id=missing'), '/wallet-manage');
    expect(_redirect('/wallet-detail?id=wallet-1'), isNull);
    expect(_redirect('/wallet-addresses?id=missing'), '/wallet-manage');
    expect(_redirect('/wallet-addresses?id=wallet-1'), isNull);
  });

  test('production creation pages require the live pending mnemonic', () async {
    final wallets = _walletController(withWallet: false);
    for (final path in const [
      '/create-warn',
      '/mnemonic-show',
      '/mnemonic-verify',
    ]) {
      expect(_redirect(path, wallets: wallets), '/add-wallet');
    }
    await wallets.beginCreate();
    for (final path in const [
      '/create-warn',
      '/mnemonic-show',
      '/mnemonic-verify',
    ]) {
      expect(_redirect(path, wallets: wallets), isNull);
    }
  });

  test('production pairing and data-detail routes require real payloads', () {
    expect(_redirect('/import-confirm'), '/connect-cold');
    expect(
      _redirect(
        '/import-confirm',
        extra: AccountExport(
          walletId: 'wallet-1',
          walletName: 'Wallet',
          accounts: [
            AccountRecord(
              coin: 60,
              address: '0x01',
              path: "m/44'/60'/0'/0/0",
              index: 0,
            ),
          ],
        ),
      ),
      isNull,
    );
    expect(_redirect('/tx-detail'), '/records');
    expect(_redirect('/tx-detail?id=local-1'), isNull);
    expect(_redirect('/token'), '/assets');
    expect(
      _redirect(
        '/token',
        extra: AssetRef.native(coin: Coin.eth, symbol: 'ETH', name: 'Ethereum'),
      ),
      isNull,
    );
  });

  test(
    'production transfer routes advance only with matching session state',
    () {
      final session = TransferSession();
      for (final path in const [
        '/confirm-hot',
        '/confirm-watch',
        '/sign-qr',
        '/transfer-auth',
      ]) {
        expect(_redirect(path, session: session), '/invalid-transfer');
      }
      expect(_redirect('/fee', session: session), '/transfer');
      expect(_redirect('/scan-result', session: session), '/invalid-transfer');
      expect(
        _redirect('/broadcast-confirm', session: session),
        '/invalid-transfer',
      );
      expect(
        _redirect('/broadcast-result', session: session),
        '/invalid-transfer',
      );

      session.begin(_draft());
      expect(_redirect('/confirm-hot', session: session), isNull);
      expect(_redirect('/confirm-watch', session: session), isNull);
      expect(_redirect('/sign-qr', session: session), isNull);
      expect(_redirect('/transfer-auth', session: session), isNull);
      expect(_redirect('/scan-result', session: session), '/invalid-transfer');

      session.request = _request();
      expect(_redirect('/scan-result', session: session), isNull);
      expect(
        _redirect('/broadcast-confirm', session: session),
        '/invalid-transfer',
      );

      session.result = _result();
      expect(_redirect('/broadcast-confirm', session: session), isNull);
      expect(
        _redirect('/broadcast-result', session: session),
        '/invalid-transfer',
      );
      session
        ..localTransactionId = 'local-1'
        ..broadcastTxHash = '0x01';
      expect(_redirect('/broadcast-result', session: session), isNull);
    },
  );

  testWidgets('stateful transfer screens also fail closed when embedded', (
    tester,
  ) async {
    for (final screen in const <Widget>[
      TransferConfirmScreen(isHot: true),
      SignRequestQrScreen(),
      ScanResultScreen(),
      FeeSelectScreen(),
    ]) {
      await tester.pumpWidget(_productionHarness(screen));
      await tester.pump();
      expect(
        find.text(
          'The on-chain transaction parameters could not be verified. '
          'Signing is disabled.',
        ),
        findsOneWidget,
      );
      expect(find.text('-120.00 USDT'), findsNothing);
    }
  });
}

Widget _productionHarness(Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: WalletScope(
    controller: WalletController(WalletManager()),
    child: TransferSessionScope(session: TransferSession(), child: child),
  ),
);

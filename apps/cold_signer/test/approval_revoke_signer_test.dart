import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:cold_signer/l10n/app_localizations.dart';
import 'package:cold_signer/src/screens/signer_signing_screens.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ui_kit/ui_kit.dart';

const _spender = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
const _token = '0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48';

SignRequest _request() {
  final raw = Eip1559Tx.forTransfer(
    TransferIntent(
      chain: Chain.ethereum,
      operation: TxOperation.approvalRevoke,
      from: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
      to: _spender,
      amount: Amount(raw: BigInt.zero, decimals: 6, symbol: 'USDC'),
      tokenContract: _token,
    ),
    chainId: BigInt.one,
    nonce: BigInt.from(7),
    maxPriorityFeePerGas: BigInt.from(2),
    maxFeePerGas: BigInt.from(30),
    gasLimit: BigInt.from(50000),
  ).encodeUnsigned();
  return SignRequest(
    reqId: Uint8List.fromList(const [1, 2, 3, 4, 5, 6, 7, 8]),
    walletId: 'wallet-1',
    coin: 60,
    chainId: 1,
    rawTx: raw,
    createdAt: 1900000000,
    expiresAt: 1900000600,
  );
}

void main() {
  testWidgets('offline signer labels exact zero-allowance revoke honestly', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      KtDeviceChrome(
        mockStatusBar: false,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SignerParseScreen(request: _request()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ethereum · Revoke token approval'), findsOneWidget);
    expect(find.text('Set allowance to zero'), findsOneWidget);
    expect(find.textContaining('approve(spender, 0)'), findsOneWidget);
    expect(find.text('Authorized spender'), findsOneWidget);
    expect(find.text(_spender.toLowerCase()), findsOneWidget);
    expect(find.text('Token contract'), findsOneWidget);
    expect(find.text(_token), findsOneWidget);
    expect(find.text('Confirm signing'), findsOneWidget);
  });
}

import 'dart:async';
import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart' show ChainAddresses;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/screens/transfer_screens.dart';
import 'package:kt_wallet/src/state/wallet_controller.dart';
import 'package:kt_wallet/src/state/wallet_scope.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_manager.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';
import 'package:kt_wallet/src/widgets/scan_viewfinder.dart';

void main() {
  for (final failFirstSave in [false, true]) {
    testWidgets(
      'real signature scan is single-flight; save failure=$failFirstSave',
      (tester) async {
        // Public deterministic test-only key, never a user wallet.
        final algorithm = Ed25519();
        final key = await algorithm.newKeyPairFromSeed(List<int>.filled(32, 7));
        final pubkey = await key.extractPublicKey();
        final signer = base58Encode(Uint8List.fromList(pubkey.bytes));
        final raw = SolanaMessage.systemTransfer(
          from: signer,
          to: solanaSystemProgram,
          lamports: BigInt.one,
          recentBlockhash: solanaSystemProgram,
        ).serialize();
        final signature = await algorithm.sign(raw, keyPair: key);
        final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final request = SignRequest(
          reqId: Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]),
          walletId: 'cold-id',
          coin: 501,
          rawTx: raw,
          createdAt: now,
          expiresAt: now + 600,
        );
        final result = SignResult(
          reqId: request.reqId,
          walletId: request.walletId,
          coin: 501,
          signer: signer,
          signedTx: Uint8List.fromList([1, ...signature.bytes, ...raw]),
          txHash: base58Encode(Uint8List.fromList(signature.bytes)),
        );
        final session = TransferSession()
          ..draft = TransferDraft(
            symbol: 'SOL',
            networkLabel: 'Solana',
            chain: Chain.solana,
            recipient: solanaSystemProgram,
            amount: Amount(raw: BigInt.one, decimals: 9),
            feeTier: 1,
          )
          ..request = request;
        final wallet = WatchWallet(
          id: 'local-id',
          coldWalletId: 'cold-id',
          protocolVersion: airgapVersion,
          name: 'Test',
          avatarColor: 0xFF123456,
          addresses: ChainAddresses(
            eth: '',
            polygon: '',
            tron: '',
            solana: signer,
          ),
        );
        final controller = WalletController(
          WalletManager(initial: [wallet]),
          allowTestBypass: true,
        );
        addTearDown(controller.dispose);
        var saves = 0;
        var pushes = 0;
        var save = Completer<void>();
        final router = GoRouter(
          initialLocation: '/scan',
          routes: [
            GoRoute(
              path: '/scan',
              builder: (_, _) => ScanResultScreen(
                availability: const FakeCameraAvailability(false),
                resultPersistence: (_, _, _) {
                  saves++;
                  return save.future;
                },
              ),
            ),
            GoRoute(
              path: '/broadcast-confirm',
              builder: (_, _) {
                pushes++;
                return const Scaffold(body: Text('Broadcast review'));
              },
            ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          WalletScope(
            controller: controller,
            child: TransferSessionScope(
              session: session,
              child: MaterialApp.router(
                routerConfig: router,
                locale: const Locale('zh'),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final frames = encodeQrFrames(result, reqId: request.reqId);
        void feed() {
          final onScanned = tester
              .widget<ScanViewfinder>(find.byType(ScanViewfinder))
              .onScanned!;
          for (final frame in frames) {
            onScanned(frame);
          }
        }

        feed();
        feed();
        feed();
        await tester.pumpAndSettle();
        expect(saves, 1);
        expect(
          session.result,
          isNull,
          reason: 'No result published before durable save',
        );
        if (failFirstSave) {
          save.completeError(StateError('database unavailable'));
          await tester.pumpAndSettle();
          expect(pushes, 0);
          expect(session.result, isNull);
          expect(find.textContaining('无法安全保存签名结果'), findsOneWidget);
          save = Completer<void>();
          feed();
          feed();
          await tester.pumpAndSettle();
          expect(saves, 2);
        }
        save.complete();
        await tester.pumpAndSettle();
        expect(pushes, 1);
        expect(session.result?.txHash, result.txHash);
        router.pop();
        await tester.pumpAndSettle();
        save = Completer<void>();
        feed();
        feed();
        await tester.pumpAndSettle();
        expect(saves, failFirstSave ? 3 : 2);
        save.complete();
        await tester.pumpAndSettle();
        expect(pushes, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

import 'dart:typed_data';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:cold_signer/src/signer_router.dart';
import 'package:cold_signer/src/security/secure_vault.dart';
import 'package:cold_signer/src/signing/mnemonic_review.dart';
import 'package:cold_signer/src/state/signer_wallet_controller.dart';
import 'package:flutter_test/flutter_test.dart';

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
  signer: '0x0000000000000000000000000000000000000001',
  txHash: '0x01',
);

String? _redirect(
  String path, {
  Object? extra,
  bool gallery = false,
  bool hasWallet = false,
  bool hasPendingMnemonic = false,
  SignerOnboardingStage onboardingStage = SignerOnboardingStage.idle,
  String? currentWalletId,
}) => signerProductionRouteRedirect(
  galleryMode: gallery,
  uri: Uri.parse(path),
  extra: extra,
  hasWallet: hasWallet,
  hasPendingMnemonic: hasPendingMnemonic,
  onboardingStage: onboardingStage,
  currentWalletId: currentWalletId,
);

void main() {
  test('debug gallery retains explicit signing previews', () {
    expect(_redirect('/parse', gallery: true), isNull);
    expect(_redirect('/auth', gallery: true), isNull);
    expect(_redirect('/result-qr', gallery: true), isNull);
  });

  test('production signing stages require in-memory protocol evidence', () {
    expect(_redirect('/parse'), '/welcome');
    expect(_redirect('/auth'), '/welcome');
    expect(_redirect('/result-qr'), '/welcome');

    final request = _request();
    expect(_redirect('/parse', extra: request, hasWallet: true), isNull);
    expect(_redirect('/auth', extra: request, hasWallet: true), isNull);
    expect(_redirect('/result-qr', extra: request, hasWallet: true), '/scan');
    expect(_redirect('/result-qr', extra: _result(), hasWallet: true), isNull);
  });

  test('production phrase routes require ephemeral in-memory phrase state', () {
    expect(_redirect('/mnemonic-show'), '/welcome');
    expect(_redirect('/mnemonic-verify'), '/welcome');
    expect(
      signerProductionRouteRedirect(
        galleryMode: false,
        uri: Uri.parse('/mnemonic-show'),
        hasWallet: true,
      ),
      '/home',
    );
    expect(
      signerProductionRouteRedirect(
        galleryMode: false,
        uri: Uri.parse('/mnemonic-show'),
        hasPendingMnemonic: true,
        onboardingStage: SignerOnboardingStage.mnemonicReview,
      ),
      isNull,
    );

    final flow = MnemonicReviewFlow(
      purpose: MnemonicReviewPurpose.backup,
      words: List<String>.filled(12, 'abandon'),
    );
    expect(_redirect('/mnemonic-show', extra: flow, hasWallet: true), isNull);
    expect(_redirect('/mnemonic-verify', extra: flow, hasWallet: true), isNull);
  });

  test('wallet management requires a loaded wallet in production', () {
    expect(_redirect('/wallet'), '/welcome');
    expect(
      signerProductionRouteRedirect(
        galleryMode: false,
        uri: Uri.parse('/wallet'),
        hasWallet: true,
      ),
      isNull,
    );
  });

  test('wallet-dependent routes reject a no-wallet deep link', () {
    for (final path in const [
      '/home',
      '/scan',
      '/parse',
      '/risk',
      '/auth',
      '/result-qr',
      '/export',
      '/records',
      '/wallet',
      '/security',
      '/delete',
      '/created',
    ]) {
      expect(_redirect(path), '/welcome', reason: path);
    }
  });

  test('onboarding routes require the exact volatile stage', () {
    expect(_redirect('/set-password'), '/welcome');
    expect(_redirect('/biometric'), '/welcome');
    expect(
      _redirect(
        '/set-password',
        hasPendingMnemonic: true,
        onboardingStage: SignerOnboardingStage.pinSetup,
      ),
      isNull,
    );
    expect(
      _redirect(
        '/biometric',
        hasPendingMnemonic: true,
        onboardingStage: SignerOnboardingStage.biometricSetup,
      ),
      isNull,
    );
    expect(
      _redirect(
        '/biometric',
        hasPendingMnemonic: true,
        onboardingStage: SignerOnboardingStage.pinSetup,
      ),
      '/set-password',
    );
    expect(
      _redirect(
        '/mnemonic-import',
        hasPendingMnemonic: true,
        onboardingStage: SignerOnboardingStage.mnemonicReview,
      ),
      '/mnemonic-show',
    );
  });

  test('an existing wallet cannot re-enter onboarding or fake success', () {
    const walletId = 'wallet-existing';
    for (final path in const [
      '/welcome',
      '/mnemonic-warn',
      '/mnemonic-import',
      '/biometric',
      '/created',
    ]) {
      expect(
        _redirect(path, hasWallet: true, currentWalletId: walletId),
        '/home',
        reason: path,
      );
    }
    const metadata = WalletMetadata(
      walletId: walletId,
      name: 'Existing',
      createdAt: 1,
    );
    expect(
      _redirect(
        '/created',
        extra: metadata,
        hasWallet: true,
        onboardingStage: SignerOnboardingStage.completed,
        currentWalletId: walletId,
      ),
      isNull,
    );
  });

  test('ordinary pre-wallet routes remain available', () {
    for (final path in const [
      '/welcome',
      '/mnemonic-warn',
      '/mnemonic-import',
      '/security-check',
    ]) {
      expect(_redirect(path), isNull, reason: path);
    }
  });
}

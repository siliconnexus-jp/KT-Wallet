import 'support/e2e_credential_batch.dart';
import 'support/e2e_wallet_cleanup.dart';

import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';

void main() {
  requireFreshE2eCredentialBatchIfConfigured();
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Wallet Core signs Sepolia native and ERC-20 type-2 envelopes', (
    tester,
  ) async {
    final crypto = MethodChannelCoreCrypto();
    const walletId = 'sepolia-signing-e2e-v2';
    const mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');
    expect(
      mnemonic,
      isNotEmpty,
      reason:
          'pass integration_test/.sepolia-e2e.json via '
          '--dart-define-from-file',
    );
    await crypto.storeWallet(
      walletId: walletId,
      mnemonic: mnemonic,
      requireAuth: false,
    );
    registerE2eWalletCleanup(crypto, walletId);
    final addresses = await crypto.deriveAddresses(walletId);
    // Public address only. The generated mnemonic never leaves native
    // Keystore-backed storage and is never written to the repository.
    // ignore: avoid_print
    print('SEPOLIA_E2E_ADDRESS=${addresses.eth}');

    final drafts = [
      TransferDraft(
        symbol: 'ETH',
        networkLabel: 'Sepolia',
        chain: Chain.ethereum,
        recipient: addresses.eth,
        amount: Amount.parse('0.000001', 18, symbol: 'ETH'),
        feeTier: 1,
      ),
      TransferDraft(
        symbol: 'USDT',
        networkLabel: 'Sepolia · ERC-20',
        chain: Chain.ethereum,
        recipient: addresses.eth,
        amount: Amount.parse('1', 6, symbol: 'USDT'),
        feeTier: 1,
        tokenContract: '0xc4DCC311c028e341fd8602D8eB89c5de94625927',
      ),
    ];

    for (final draft in drafts) {
      final unsigned = rawTxFor(
        draft,
        from: addresses.eth,
        nonce: BigInt.zero,
        maxPriorityFeePerGas: BigInt.from(1000000000),
        maxFeePerGas: BigInt.from(2000000000),
        evmChainId: 11155111,
      );
      final signed = await crypto.signTransaction(
        walletId: walletId,
        coin: Coin.eth,
        signingInput: Uint8List.fromList(unsigned),
      );
      expect(signed.signedTx, isNotEmpty);
      expect(signed.signedTx.first, 0x02);
      expect(signed.txHash, matches(RegExp(r'^0x[0-9a-f]{64}$')));
    }
  });
}

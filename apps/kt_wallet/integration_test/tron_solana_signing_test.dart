import 'support/e2e_credential_batch.dart';
import 'support/e2e_wallet_cleanup.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _mnemonic = String.fromEnvironment('SEPOLIA_E2E_MNEMONIC');

void main() {
  requireFreshE2eCredentialBatchIfConfigured();
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test('Wallet Core signs TRON raw_data and Solana legacy messages', () async {
    expect(_mnemonic, isNotEmpty);
    final crypto = MethodChannelCoreCrypto();
    const walletId = 'multi-chain-signing';
    await crypto.storeWallet(
      walletId: walletId,
      mnemonic: _mnemonic,
      requireAuth: false,
    );
    registerE2eWalletCleanup(crypto, walletId);
    final addresses = await crypto.deriveAddresses(walletId);

    final tronIntent = TransferIntent(
      chain: Chain.tron,
      operation: TxOperation.nativeTransfer,
      from: addresses.tron,
      to: addresses.tron,
      amount: Amount.parse('0.000001', 6, symbol: 'TRX'),
    );
    final tronRaw = TronRawTx.forTransfer(
      tronIntent,
      refBlockBytes: Uint8List.fromList(const [0x12, 0x34]),
      refBlockHash: Uint8List.fromList(const [1, 2, 3, 4, 5, 6, 7, 8]),
      expiration: 1900000060000,
      timestamp: 1900000000000,
    ).encodeRawData();
    final tronSigned = await crypto.signTransaction(
      walletId: walletId,
      coin: Coin.tron,
      signingInput: tronRaw,
    );
    final tronJson = jsonDecode(utf8.decode(tronSigned.signedTx)) as Map;
    expect(tronJson['transaction'], isA<String>());
    expect((tronJson['transaction'] as String).length, greaterThan(200));
    expect(tronJson['txID'], tronSigned.txHash);

    final solanaMessage = SolanaMessage.systemTransfer(
      from: addresses.solana,
      to: addresses.solana,
      lamports: BigInt.one,
      recentBlockhash: solanaSystemProgram,
    ).serialize();
    final solanaSigned = await crypto.signTransaction(
      walletId: walletId,
      coin: Coin.solana,
      signingInput: solanaMessage,
    );
    expect(solanaSigned.signedTx.first, 1);
    expect(
      Uint8List.sublistView(solanaSigned.signedTx, 65),
      orderedEquals(solanaMessage),
    );
    expect(solanaSigned.txHash, isNotEmpty);
  });
}

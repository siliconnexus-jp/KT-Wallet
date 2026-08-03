import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/e2e_wallet_cleanup.dart';

/// Device-level regression for the broadcast verification boundary.
///
/// The mnemonic is generated inside the native Wallet Core bridge, is never
/// logged, and the temporary vault entry is registered for authenticated test
/// teardown. No RPC or funded account is involved.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native Wallet Core emits canonical EVM, TRON and Solana signatures',
    () async {
      const walletId = 'kt-e2e-native-canonicality';
      final crypto = MethodChannelCoreCrypto();
      final mnemonic = await crypto.generateMnemonic();
      expect(await crypto.validateMnemonic(mnemonic), isTrue);
      await storeE2eWallet(
        crypto,
        walletId: walletId,
        mnemonic: mnemonic,
        requireAuth: false,
      );
      final addresses = await crypto.deriveAddresses(walletId);

      final evm = Eip1559Tx(
        chainId: BigInt.from(11155111),
        nonce: BigInt.zero,
        maxPriorityFeePerGas: BigInt.from(1000000000),
        maxFeePerGas: BigInt.from(2000000000),
        gasLimit: BigInt.from(21000),
        to: Eip1559Tx.addressBytes(
          '0x000000000000000000000000000000000000dEaD',
        ),
        value: BigInt.one,
        data: Uint8List(0),
      );
      final evmSigned = await crypto.signTransaction(
        walletId: walletId,
        coin: Coin.eth,
        signingInput: evm.encodeUnsigned(),
      );
      final evmVerified = await verifySignedTransaction(
        chain: Chain.ethereum,
        unsignedTx: evm.encodeUnsigned(),
        signedTx: evmSigned.signedTx,
        claimedSigner: addresses.eth,
      );
      expect(evmVerified.txHash, evmSigned.txHash);

      final tronIntent = TransferIntent(
        chain: Chain.tron,
        operation: TxOperation.nativeTransfer,
        from: addresses.tron,
        to: 'TBSd3Ju3T5URPH3q5C2HqhPG5qewNDuCtR',
        amount: Amount(raw: BigInt.one, decimals: 6, symbol: 'TRX'),
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
      final tronVerified = await verifySignedTransaction(
        chain: Chain.tron,
        unsignedTx: tronRaw,
        signedTx: tronSigned.signedTx,
        claimedSigner: addresses.tron,
      );
      expect(tronVerified.txHash, tronSigned.txHash);

      final solanaMessage = SolanaMessage.systemTransfer(
        from: addresses.solana,
        to: '11111111111111111111111111111111',
        lamports: BigInt.one,
        recentBlockhash: '11111111111111111111111111111111',
      ).serialize();
      final solanaSigned = await crypto.signTransaction(
        walletId: walletId,
        coin: Coin.solana,
        signingInput: solanaMessage,
      );
      final solanaVerified = await verifySignedTransaction(
        chain: Chain.solana,
        unsignedTx: solanaMessage,
        signedTx: solanaSigned.signedTx,
        claimedSigner: addresses.solana,
      );
      expect(solanaVerified.txHash, solanaSigned.txHash);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

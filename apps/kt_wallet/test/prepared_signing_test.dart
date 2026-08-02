import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';
import 'package:kt_wallet/src/wallets/wallet_model.dart';

const _walletEvm = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
const _walletTron = 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G';
const _walletSolana = '2KW2XRd9kwqet15Aha2oK3tYvd3nWbTFH1MBiRAv1BE1';

HotWallet _wallet() => HotWallet(
  id: 'wallet-1',
  name: 'Test',
  avatarColor: 0,
  addresses: ChainAddresses(
    eth: _walletEvm,
    polygon: _walletEvm,
    tron: _walletTron,
    solana: _walletSolana,
  ),
);

void main() {
  final service = LocalTransferService();
  final crypto = MockCoreCrypto();

  test('EVM signing rejects a quote prepared for another sender', () {
    final prepared = PreparedEvmTransfer(
      chain: Chain.ethereum,
      evmChainId: 1,
      coin: Coin.eth,
      operation: TxOperation.nativeTransfer,
      from: '0x000000000000000000000000000000000000dEaD',
      recipient: '0x0000000000000000000000000000000000000001',
      amountRaw: BigInt.one,
      tokenContract: null,
      nonce: BigInt.zero,
      maxPriorityFeePerGas: BigInt.one,
      maxFeePerGas: BigInt.one,
      gasLimit: BigInt.from(21000),
      unsignedTx: Uint8List.fromList(const [1]),
    );

    expect(
      () => service.signAndBroadcastEvm(
        wallet: _wallet(),
        crypto: crypto,
        prepared: prepared,
      ),
      throwsA(isA<LocalTransferException>()),
    );
  });

  test('TRON signing rejects a quote prepared for another sender', () {
    final prepared = PreparedTronTransfer(
      from: 'TUu9UMDUmaTjv9ctwC9SPZzRURQ5DJJp9W',
      recipient: _walletTron,
      amountRaw: BigInt.one,
      tokenContract: null,
      maximumFeeSun: BigInt.one,
      referenceBlockHeight: 1,
      expiresAt: 2,
      rawTx: Uint8List.fromList(const [1]),
    );

    expect(
      () => service.signAndBroadcastTron(
        wallet: _wallet(),
        crypto: crypto,
        prepared: prepared,
        expectedNetworkIdentity: null,
      ),
      throwsA(isA<LocalTransferException>()),
    );
  });

  test('Solana signing rejects a quote prepared for another sender', () {
    final prepared = PreparedSolanaTransfer(
      from: '11111111111111111111111111111111',
      recipient: _walletSolana,
      amountRaw: BigInt.one,
      tokenMint: null,
      tokenProgram: null,
      networkFeeLamports: BigInt.one,
      rentDepositLamports: BigInt.zero,
      lastValidBlockHeight: 1,
      message: Uint8List.fromList(const [1]),
    );

    expect(
      () => service.signAndBroadcastSolana(
        wallet: _wallet(),
        crypto: crypto,
        prepared: prepared,
        expectedNetworkIdentity: null,
      ),
      throwsA(isA<LocalTransferException>()),
    );
  });
}

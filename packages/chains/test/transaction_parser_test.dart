import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:test/test.dart';

void main() {
  test('parses EIP-1559 ERC-20 fields from raw bytes', () {
    final intent = TransferIntent(
      chain: Chain.polygon,
      operation: TxOperation.tokenTransfer,
      from: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
      to: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      amount: Amount.parse('100', 6, symbol: 'USDT'),
      tokenContract: '0xc2132D05D31c914a87C6611C10748AEb04B58e8F',
      tokenSymbol: 'USDT',
    );
    final raw = Eip1559Tx.forTransfer(
      intent,
      chainId: BigInt.from(137),
      nonce: BigInt.one,
      maxPriorityFeePerGas: BigInt.from(30),
      maxFeePerGas: BigInt.from(40),
      gasLimit: BigInt.from(65000),
    ).encodeUnsigned();

    final parsed = parseUnsignedTransfer(Chain.polygon, raw);

    expect(parsed.operation, TxOperation.tokenTransfer);
    expect(parsed.networkId, BigInt.from(137));
    expect(parsed.to, '0x5aaeb6053f3e94c9b9a09f33669435e7ef1beaed');
    expect(parsed.tokenContract, '0xc2132d05d31c914a87c6611c10748aeb04b58e8f');
    expect(parsed.amountRaw, BigInt.from(100000000));
    expect(parsed.maxFeeRaw, BigInt.from(2600000));
    expect(parsed.nonce, BigInt.one);
    expect(parsed.maxPriorityFeePerGas, BigInt.from(30));
    expect(parsed.maxFeePerGas, BigInt.from(40));
    expect(parsed.gasLimit, BigInt.from(65000));
  });

  test('parses protobuf TRC-20 fields and fee limit', () {
    final intent = TransferIntent(
      chain: Chain.tron,
      operation: TxOperation.tokenTransfer,
      from: 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G',
      to: 'TBSd3Ju3T5URPH3q5C2HqhPG5qewNDuCtR',
      amount: Amount.parse('12', 6, symbol: 'USDT'),
      tokenContract: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
      tokenSymbol: 'USDT',
    );
    final raw = TronRawTx.forTransfer(
      intent,
      refBlockBytes: Uint8List.fromList([0x12, 0x34]),
      refBlockHash: Uint8List.fromList(List<int>.generate(8, (i) => i)),
      timestamp: 1700000000000,
      expiration: 1700000600000,
      feeLimit: 50000000,
    ).encodeRawData();

    final parsed = parseUnsignedTransfer(Chain.tron, raw);

    expect(parsed.operation, TxOperation.tokenTransfer);
    expect(parsed.from, intent.from);
    expect(parsed.to, intent.to);
    expect(parsed.tokenContract, intent.tokenContract);
    expect(parsed.amountRaw, BigInt.from(12000000));
    expect(parsed.maxFeeRaw, BigInt.from(50000000));
  });

  test('parses Solana native message without consulting summary data', () {
    final raw = SolanaMessage.systemTransfer(
      from: '4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T',
      to: 'FDQB1yWWkVeMTHXCVAK7UAGMDX6WUduBmVZLTmiHssbg',
      lamports: BigInt.from(123456),
      recentBlockhash: 'DzfXchZJoLMG3cNftcf2sw7qatkkuwQf4xH15N5wkKAb',
    ).serialize();

    final parsed = parseUnsignedTransfer(Chain.solana, raw);

    expect(parsed.operation, TxOperation.nativeTransfer);
    expect(parsed.from, '4Nd1mBQtrMJVYVfKf2PJy9NZUZdTAsp7D4xWLs4gDB4T');
    expect(parsed.to, 'FDQB1yWWkVeMTHXCVAK7UAGMDX6WUduBmVZLTmiHssbg');
    expect(parsed.amountRaw, BigInt.from(123456));
  });

  test('parses Token-2022 checked transfer with idempotent ATA create', () {
    const recipient = 'GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB';
    const mint = '2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo';
    final raw = SolanaMessage.splTransferChecked(
      source: 'Bi9EDynRhtGiiG9wDCzhc5w2yGz8TSaamm9AUJhjZ2u5',
      destination: SolanaMessage.associatedTokenAddress(
        owner: recipient,
        mint: mint,
        tokenProgram: solanaToken2022Program,
      ),
      owner: '2KW2XRd9kwqet15Aha2oK3tYvd3nWbTFH1MBiRAv1BE1',
      recipientOwner: recipient,
      mint: mint,
      amount: BigInt.from(1250000),
      decimals: 6,
      recentBlockhash: 'DzfXchZJoLMG3cNftcf2sw7qatkkuwQf4xH15N5wkKAb',
      tokenProgram: solanaToken2022Program,
      createDestination: true,
    ).serialize();

    final parsed = parseUnsignedTransfer(Chain.solana, raw);

    expect(parsed.operation, TxOperation.tokenTransfer);
    expect(parsed.to, recipient);
    expect(parsed.tokenContract, mint);
    expect(parsed.amountRaw, BigInt.from(1250000));
  });

  test('rejects an ATA create that does not bind the transfer destination', () {
    const recipient = 'GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB';
    const mint = '2b1kV6DkPAnxd5ixfnxCpjxmKwqjjaYmCZfHsFu24GXo';
    final valid = SolanaMessage.splTransferChecked(
      source: 'Bi9EDynRhtGiiG9wDCzhc5w2yGz8TSaamm9AUJhjZ2u5',
      destination: SolanaMessage.associatedTokenAddress(
        owner: recipient,
        mint: mint,
        tokenProgram: solanaToken2022Program,
      ),
      owner: '2KW2XRd9kwqet15Aha2oK3tYvd3nWbTFH1MBiRAv1BE1',
      recipientOwner: recipient,
      mint: mint,
      amount: BigInt.from(1250000),
      decimals: 6,
      recentBlockhash: 'DzfXchZJoLMG3cNftcf2sw7qatkkuwQf4xH15N5wkKAb',
      tokenProgram: solanaToken2022Program,
      createDestination: true,
    );
    final forged = SolanaMessage(
      numRequiredSignatures: valid.numRequiredSignatures,
      numReadonlySignedAccounts: valid.numReadonlySignedAccounts,
      numReadonlyUnsignedAccounts: valid.numReadonlyUnsignedAccounts,
      accountKeys: valid.accountKeys,
      recentBlockhash: valid.recentBlockhash,
      instructions: [
        SolanaInstruction(
          programIdIndex: valid.instructions.first.programIdIndex,
          // Claims the source account is the ATA being created while the
          // transfer still sends to the real destination.
          accountIndices: const [0, 1, 3, 4, 5, 6],
          data: valid.instructions.first.data,
        ),
        valid.instructions.last,
      ],
    );

    expect(
      () => parseUnsignedTransfer(Chain.solana, forged.serialize()),
      throwsFormatException,
    );
  });

  test('parses BNB EIP-1559 chain domain', () {
    final intent = TransferIntent(
      chain: Chain.bnb,
      operation: TxOperation.nativeTransfer,
      from: '0x70997970C51812dc3A010C7d01b50e0d17dc79C8',
      to: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
      amount: Amount.parse('0.1', 18, symbol: 'BNB'),
    );
    final raw = Eip1559Tx.forTransfer(
      intent,
      chainId: BigInt.from(56),
      nonce: BigInt.zero,
      maxPriorityFeePerGas: BigInt.from(1000000000),
      maxFeePerGas: BigInt.from(3000000000),
      gasLimit: BigInt.from(21000),
    ).encodeUnsigned();

    final parsed = parseUnsignedTransfer(Chain.bnb, raw);
    expect(parsed.chain, Chain.bnb);
    expect(parsed.networkId, BigInt.from(56));
    expect(parsed.amountRaw, BigInt.parse('100000000000000000'));
  });
}

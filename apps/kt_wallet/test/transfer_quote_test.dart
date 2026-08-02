import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/transfer/airgap_codec.dart' show rawTxFor;
import 'package:kt_wallet/src/transfer/transfer_draft.dart';

const _from = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
const _to = '0x925fEA1c0dbf3B011391bbed682E32861BE73213';
const _tronFrom = 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G';
const _tronTo = 'TUu9UMDUmaTjv9ctwC9SPZzRURQ5DJJp9W';
const _solFrom = '2KW2XRd9kwqet15Aha2oK3tYvd3nWbTFH1MBiRAv1BE1';
const _solTo = 'GmaDrppBC7P5ARKV8g3djiwP89vz1jLK23V2GBjuAEGB';
const _solMint = 'JUPyiwrYJFskUPiHa7hkeR8VUtAeFoSYbKedZNsDvCN';

TransferDraft _draft({String recipient = _to, String amount = '0.5'}) =>
    TransferDraft(
      symbol: 'ETH',
      networkLabel: 'Ethereum',
      chain: Chain.ethereum,
      recipient: recipient,
      amount: Amount.parse(amount, 18, symbol: 'ETH'),
      feeTier: 1,
    );

TransferDraft _tokenDraft() => TransferDraft(
  symbol: 'USDT',
  networkLabel: 'Ethereum · ERC-20',
  chain: Chain.ethereum,
  recipient: _to,
  amount: Amount.parse('2.5', 6, symbol: 'USDT'),
  feeTier: 1,
  tokenContract: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
);

TransferDraft _approvalRevokeDraft() => TransferDraft(
  symbol: 'USDT',
  networkLabel: 'Ethereum · ERC-20',
  chain: Chain.ethereum,
  recipient: _to,
  amount: Amount(raw: BigInt.zero, decimals: 6, symbol: 'USDT'),
  feeTier: 1,
  tokenContract: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
  operation: TxOperation.approvalRevoke,
);

PreparedEvmTransfer _prepared(TransferDraft draft) => PreparedEvmTransfer(
  chain: draft.chain,
  evmChainId: 1,
  coin: Coin.eth,
  operation: draft.operation,
  from: _from,
  recipient: draft.recipient,
  amountRaw: draft.amount.raw,
  tokenContract: draft.tokenContract,
  nonce: BigInt.from(7),
  maxPriorityFeePerGas: BigInt.from(2),
  maxFeePerGas: BigInt.from(30),
  gasLimit: BigInt.from(21000),
  unsignedTx: rawTxFor(
    draft,
    from: _from,
    nonce: BigInt.from(7),
    maxPriorityFeePerGas: BigInt.from(2),
    maxFeePerGas: BigInt.from(30),
    gasLimit: BigInt.from(21000),
    evmChainId: 1,
  ),
);

TransferDraft _tronDraft({
  String recipient = _tronTo,
  String amount = '1',
  String? tokenContract,
}) => TransferDraft(
  symbol: tokenContract == null ? 'TRX' : 'USDT',
  networkLabel: 'TRON',
  chain: Chain.tron,
  recipient: recipient,
  amount: Amount.parse(
    amount,
    6,
    symbol: tokenContract == null ? 'TRX' : 'USDT',
  ),
  feeTier: 1,
  tokenContract: tokenContract,
);

PreparedTronTransfer _preparedTron(TransferDraft draft) => PreparedTronTransfer(
  from: _tronFrom,
  recipient: draft.recipient,
  amountRaw: draft.amount.raw,
  tokenContract: draft.tokenContract,
  maximumFeeSun: BigInt.from(1200000),
  referenceBlockHeight: 42,
  expiresAt: 90000,
  rawTx: Uint8List.fromList(const [10, 11, 12]),
);

TransferDraft _solDraft({
  String recipient = _solTo,
  String amount = '1',
  String? tokenContract = _solMint,
  String? tokenProgram = solanaTokenProgram,
}) => TransferDraft(
  symbol: tokenContract == null ? 'SOL' : 'JUP',
  networkLabel: 'Solana',
  chain: Chain.solana,
  recipient: recipient,
  amount: Amount.parse(amount, tokenContract == null ? 9 : 6),
  feeTier: 1,
  tokenContract: tokenContract,
  tokenProgram: tokenProgram,
);

PreparedSolanaTransfer _preparedSolana(TransferDraft draft) =>
    PreparedSolanaTransfer(
      from: _solFrom,
      recipient: draft.recipient,
      amountRaw: draft.amount.raw,
      tokenMint: draft.tokenContract,
      tokenProgram: draft.tokenProgram,
      networkFeeLamports: BigInt.from(5000),
      rentDepositLamports: BigInt.from(2039280),
      lastValidBlockHeight: 777,
      message: Uint8List.fromList(const [20, 21, 22]),
    );

void main() {
  test('native EVM asset changes are decoded from the signed envelope', () {
    final draft = _draft();
    final changes = decodeEvmAssetChanges(
      prepared: _prepared(draft),
      draft: draft,
      nativeDecimals: 18,
      nativeSymbol: 'ETH',
    );

    expect(changes.outgoing.toString(), '0.5 ETH');
    expect(changes.maximumNetworkFee.raw, BigInt.from(630000));
    expect(changes.maximumNetworkFee.toString(), '0.00000000000063 ETH');
    expect(changes.recipient, _to.toLowerCase());
    expect(changes.tokenContract, isNull);
  });

  test('ERC-20 changes separate token outflow from native maximum fee', () {
    final draft = _tokenDraft();
    final changes = decodeEvmAssetChanges(
      prepared: _prepared(draft),
      draft: draft,
      nativeDecimals: 18,
      nativeSymbol: 'ETH',
    );

    expect(changes.outgoing.toString(), '2.5 USDT');
    expect(changes.maximumNetworkFee.symbol, 'ETH');
    expect(changes.tokenContract, draft.tokenContract!.toLowerCase());
  });

  test('wire bytes that disagree with the approved draft fail closed', () {
    final tokenDraft = _tokenDraft();
    final nativeEnvelope = _prepared(_draft());
    final mismatched = PreparedEvmTransfer(
      chain: tokenDraft.chain,
      evmChainId: nativeEnvelope.evmChainId,
      coin: nativeEnvelope.coin,
      operation: tokenDraft.operation,
      from: nativeEnvelope.from,
      recipient: tokenDraft.recipient,
      amountRaw: tokenDraft.amount.raw,
      tokenContract: tokenDraft.tokenContract,
      nonce: nativeEnvelope.nonce,
      maxPriorityFeePerGas: nativeEnvelope.maxPriorityFeePerGas,
      maxFeePerGas: nativeEnvelope.maxFeePerGas,
      gasLimit: nativeEnvelope.gasLimit,
      unsignedTx: nativeEnvelope.unsignedTx,
    );

    expect(
      () => decodeEvmAssetChanges(
        prepared: mismatched,
        draft: tokenDraft,
        nativeDecimals: 18,
        nativeSymbol: 'ETH',
      ),
      throwsFormatException,
    );
  });

  test('fresh exact EVM quote is reusable by auth/sign', () {
    final draft = _draft();
    final prepared = _prepared(draft);
    final session = TransferSession()
      ..draft = draft
      ..preparedEvm = prepared
      ..preparedNetworkId = 'eth-mainnet'
      ..preparedAtMs = 1000;

    expect(
      session.validEvmQuote(
        forDraft: draft,
        networkId: 'eth-mainnet',
        evmChainId: 1,
        from: _from.toLowerCase(),
        nowMs: 1000 + TransferSession.quoteValidity.inMilliseconds,
      ),
      same(prepared),
    );
  });

  test(
    'expired, future-dated or wrong-network identity quote fails closed',
    () {
      final draft = _draft();
      final session = TransferSession()
        ..draft = draft
        ..preparedEvm = _prepared(draft)
        ..preparedNetworkId = 'eth-mainnet'
        ..preparedAtMs = 1000;

      expect(
        session.validEvmQuote(
          forDraft: draft,
          networkId: 'eth-mainnet',
          evmChainId: 1,
          from: _from,
          nowMs: 1001 + TransferSession.quoteValidity.inMilliseconds,
        ),
        isNull,
      );
      expect(
        session.validEvmQuote(
          forDraft: draft,
          networkId: 'eth-mainnet',
          evmChainId: 1,
          from: _from,
          nowMs: 999,
        ),
        isNull,
      );
      expect(
        session.validEvmQuote(
          forDraft: draft,
          networkId: 'eth-sepolia',
          evmChainId: 1,
          from: _from,
          nowMs: 1001,
        ),
        isNull,
      );
      expect(
        session.validEvmQuote(
          forDraft: draft,
          networkId: 'eth-mainnet',
          evmChainId: 11155111,
          from: _from,
          nowMs: 1001,
        ),
        isNull,
      );
    },
  );

  test('recipient or amount drift invalidates the approved quote', () {
    final draft = _draft();
    final session = TransferSession()
      ..draft = draft
      ..preparedEvm = _prepared(draft)
      ..preparedNetworkId = 'eth-mainnet'
      ..preparedAtMs = 1000;

    expect(
      session.validEvmQuote(
        forDraft: _draft(
          recipient: '0x52908400098527886E0F7030069857D2E4169EE7',
        ),
        networkId: 'eth-mainnet',
        evmChainId: 1,
        from: _from,
        nowMs: 1001,
      ),
      isNull,
    );
    expect(
      session.validEvmQuote(
        forDraft: _draft(amount: '0.6'),
        networkId: 'eth-mainnet',
        evmChainId: 1,
        from: _from,
        nowMs: 1001,
      ),
      isNull,
    );
  });

  test('operation drift cannot turn a revoke into a zero token transfer', () {
    final revoke = _approvalRevokeDraft();
    final zeroTransfer = TransferDraft(
      symbol: revoke.symbol,
      networkLabel: revoke.networkLabel,
      chain: revoke.chain,
      recipient: revoke.recipient,
      amount: revoke.amount,
      feeTier: revoke.feeTier,
      tokenContract: revoke.tokenContract,
      operation: TxOperation.tokenTransfer,
    );
    final session = TransferSession()
      ..draft = revoke
      ..preparedEvm = _prepared(zeroTransfer)
      ..preparedNetworkId = 'eth-mainnet'
      ..preparedAtMs = 1000;

    expect(
      session.validEvmQuote(
        forDraft: revoke,
        networkId: 'eth-mainnet',
        evmChainId: 1,
        from: _from,
        nowMs: 1001,
      ),
      isNull,
    );
  });

  test('starting a new transfer destroys the previous quote', () {
    final first = _draft();
    final session = TransferSession()
      ..draft = first
      ..preparedEvm = _prepared(first)
      ..preparedNetworkId = 'eth-mainnet'
      ..preparedAtMs = 1000;

    session.begin(_draft(amount: '0.1'));
    expect(session.preparedEvm, isNull);
    expect(session.preparedNetworkId, isNull);
    expect(session.preparedAtMs, isNull);
  });

  test('TRON quote is exact, fresh and bound to network and draft', () {
    final draft = _tronDraft(tokenContract: 'TToken');
    final prepared = _preparedTron(draft);
    final session = TransferSession()
      ..draft = draft
      ..preparedTron = prepared
      ..preparedNetworkId = 'tron-nile'
      ..preparedAtMs = 1000;

    expect(
      session.validTronQuote(
        forDraft: draft,
        networkId: 'tron-nile',
        from: _tronFrom,
        nowMs: 1000 + TransferSession.quoteValidity.inMilliseconds,
      ),
      same(prepared),
    );
    expect(
      session.validTronQuote(
        forDraft: _tronDraft(amount: '2', tokenContract: 'TToken'),
        networkId: 'tron-nile',
        from: _tronFrom,
        nowMs: 1001,
      ),
      isNull,
    );
    expect(
      session.validTronQuote(
        forDraft: draft,
        networkId: 'tron-mainnet',
        from: _tronFrom,
        nowMs: 1001,
      ),
      isNull,
    );
    expect(
      session.validTronQuote(
        forDraft: draft,
        networkId: 'tron-nile',
        from: _tronFrom,
        nowMs: 1001 + TransferSession.quoteValidity.inMilliseconds,
      ),
      isNull,
    );
  });

  test('Solana quote rejects recipient, mint, program and sender drift', () {
    final draft = _solDraft();
    final prepared = _preparedSolana(draft);
    final session = TransferSession()
      ..draft = draft
      ..preparedSolana = prepared
      ..preparedNetworkId = 'solana-devnet'
      ..preparedAtMs = 1000;

    expect(
      session.validSolanaQuote(
        forDraft: draft,
        networkId: 'solana-devnet',
        from: _solFrom,
        nowMs: 1001,
      ),
      same(prepared),
    );
    expect(
      session.validSolanaQuote(
        forDraft: _solDraft(recipient: _solFrom),
        networkId: 'solana-devnet',
        from: _solFrom,
        nowMs: 1001,
      ),
      isNull,
    );
    expect(
      session.validSolanaQuote(
        forDraft: _solDraft(tokenContract: null, tokenProgram: null),
        networkId: 'solana-devnet',
        from: _solFrom,
        nowMs: 1001,
      ),
      isNull,
    );
    expect(
      session.validSolanaQuote(
        forDraft: _solDraft(tokenProgram: solanaToken2022Program),
        networkId: 'solana-devnet',
        from: _solFrom,
        nowMs: 1001,
      ),
      isNull,
    );
    expect(
      session.validSolanaQuote(
        forDraft: draft,
        networkId: 'solana-devnet',
        from: _solTo,
        nowMs: 1001,
      ),
      isNull,
    );
  });

  test('new transfer clears non-EVM quotes and validity boundaries', () {
    final tron = _tronDraft();
    final solana = _solDraft();
    final session = TransferSession()
      ..draft = tron
      ..preparedTron = _preparedTron(tron)
      ..preparedSolana = _preparedSolana(solana)
      ..preparedNetworkId = 'mixed-test'
      ..preparedAtMs = 1000
      ..referenceBlockHeight = 42
      ..expiresAt = 90000
      ..lastValidBlockHeight = 777;

    session.begin(_draft());
    expect(session.preparedTron, isNull);
    expect(session.preparedSolana, isNull);
    expect(session.referenceBlockHeight, isNull);
    expect(session.expiresAt, isNull);
    expect(session.lastValidBlockHeight, isNull);
  });

  test(
    'prepared transaction bytes cannot be mutated through shared buffers',
    () {
      final evmInput = Uint8List.fromList(const [1, 2, 3]);
      final tronInput = Uint8List.fromList(const [4, 5, 6]);
      final solanaInput = Uint8List.fromList(const [7, 8, 9]);
      final draft = _draft();
      final tronDraft = _tronDraft();
      final solanaDraft = _solDraft();
      final evm = PreparedEvmTransfer(
        chain: draft.chain,
        evmChainId: 1,
        coin: Coin.eth,
        operation: draft.operation,
        from: _from,
        recipient: draft.recipient,
        amountRaw: draft.amount.raw,
        tokenContract: null,
        nonce: BigInt.zero,
        maxPriorityFeePerGas: BigInt.one,
        maxFeePerGas: BigInt.one,
        gasLimit: BigInt.one,
        unsignedTx: evmInput,
      );
      final tron = PreparedTronTransfer(
        from: _tronFrom,
        recipient: tronDraft.recipient,
        amountRaw: tronDraft.amount.raw,
        tokenContract: null,
        maximumFeeSun: BigInt.one,
        referenceBlockHeight: 1,
        expiresAt: 2,
        rawTx: tronInput,
      );
      final solana = PreparedSolanaTransfer(
        from: _solFrom,
        recipient: solanaDraft.recipient,
        amountRaw: solanaDraft.amount.raw,
        tokenMint: solanaDraft.tokenContract,
        tokenProgram: solanaDraft.tokenProgram,
        networkFeeLamports: BigInt.one,
        rentDepositLamports: BigInt.zero,
        lastValidBlockHeight: 1,
        message: solanaInput,
      );

      evmInput[0] = 99;
      tronInput[0] = 99;
      solanaInput[0] = 99;
      evm.unsignedTx[1] = 99;
      tron.rawTx[1] = 99;
      solana.message[1] = 99;

      expect(evm.unsignedTx, [1, 2, 3]);
      expect(tron.rawTx, [4, 5, 6]);
      expect(solana.message, [7, 8, 9]);
    },
  );
}

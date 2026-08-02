import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/transfer/chain_params_service.dart';
import 'package:kt_wallet/src/transfer/local_transfer_service.dart';

final class _ReplacementParams extends ChainParamsService {
  _ReplacementParams({
    required this.confirmed,
    required this.pending,
    required this.fastPriority,
    required this.fastMaxFee,
    this.estimatedGas = 21000,
    this.nativePending,
    this.nativeLatest,
    this.pendingAvailable = true,
  });

  final int confirmed;
  final int pending;
  final BigInt fastPriority;
  final BigInt fastMaxFee;
  final int estimatedGas;
  final BigInt? nativePending;
  final BigInt? nativeLatest;
  final bool pendingAvailable;
  String? simulatedBlockTag;

  @override
  Future<EvmNonceState> fetchEvmNonceState(
    Chain chain,
    String fromAddress,
  ) async => EvmNonceState(confirmed: confirmed, pending: pending);

  @override
  Future<EvmChainParams> fetchEvmParams(Chain chain, String fromAddress) async {
    final tier = GasFeeEstimateTier(
      maxPriorityFeePerGas: fastPriority,
      maxFeePerGas: fastMaxFee,
    );
    return EvmChainParams(
      nonce: pending,
      fees: GasFeeEstimate(slow: tier, standard: tier, fast: tier),
    );
  }

  @override
  Future<BigInt> estimateEvmGas(
    Chain chain, {
    required String from,
    required String to,
    required BigInt value,
    required String data,
  }) async => BigInt.from(estimatedGas);

  @override
  Future<void> simulateEvmTransfer(
    Chain chain, {
    required String from,
    required String to,
    required BigInt value,
    required String data,
    required bool tokenTransfer,
    String blockTag = 'pending',
  }) async {
    simulatedBlockTag = blockTag;
  }

  @override
  Future<EvmSpendableBalances> fetchEvmSpendableBalances(
    Chain chain, {
    required String address,
    String? tokenContract,
  }) async => EvmSpendableBalances(
    native: nativePending ?? BigInt.from(10).pow(30),
    nativeLatest: nativeLatest ?? BigInt.from(10).pow(30),
    pendingAvailable: pendingAvailable,
  );
}

const _from = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
const _to = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
const _token = '0xc2132D05D31c914a87C6611C10748AEb04B58e8F';

void main() {
  group('LocalTransferService EVM replacement', () {
    test(
      'speed-up preserves native transfer and bumps both fees by 12.5%',
      () async {
        final params = _ReplacementParams(
          confirmed: 4,
          pending: 6,
          fastPriority: BigInt.from(10),
          fastMaxFee: BigInt.from(20),
        );
        final service = LocalTransferService(params: params);

        final prepared = await service.prepareEvmReplacement(
          chain: Chain.polygon,
          evmChainId: 80002,
          from: _from,
          recipient: _to,
          amountRaw: BigInt.from(123456),
          tokenContract: null,
          nonce: BigInt.from(5),
          previousMaxPriorityFeePerGas: BigInt.from(100),
          previousMaxFeePerGas: BigInt.from(200),
          previousGasLimit: BigInt.from(21000),
          cancel: false,
        );
        final parsed = parseUnsignedTransfer(
          Chain.polygon,
          prepared.unsignedTx,
        );

        expect(parsed.networkId, BigInt.from(80002));
        expect(parsed.nonce, BigInt.from(5));
        expect(parsed.to, _to.toLowerCase());
        expect(parsed.amountRaw, BigInt.from(123456));
        expect(parsed.operation, TxOperation.nativeTransfer);
        expect(parsed.maxPriorityFeePerGas, BigInt.from(113));
        expect(parsed.maxFeePerGas, BigInt.from(225));
        expect(parsed.gasLimit, BigInt.from(21000));
        expect(params.simulatedBlockTag, 'latest');
      },
    );

    test('speed-up preserves ERC-20 contract, recipient and amount', () async {
      final service = LocalTransferService(
        params: _ReplacementParams(
          confirmed: 8,
          pending: 10,
          fastPriority: BigInt.from(30),
          fastMaxFee: BigInt.from(50),
        ),
      );

      final prepared = await service.prepareEvmReplacement(
        chain: Chain.ethereum,
        evmChainId: 11155111,
        from: _from,
        recipient: _to,
        amountRaw: BigInt.from(2500000),
        tokenContract: _token,
        nonce: BigInt.from(9),
        previousMaxPriorityFeePerGas: BigInt.from(20),
        previousMaxFeePerGas: BigInt.from(40),
        previousGasLimit: BigInt.from(65000),
        cancel: false,
      );
      final parsed = parseUnsignedTransfer(Chain.ethereum, prepared.unsignedTx);

      expect(parsed.operation, TxOperation.tokenTransfer);
      expect(parsed.nonce, BigInt.from(9));
      expect(parsed.tokenContract, _token.toLowerCase());
      expect(parsed.to, _to.toLowerCase());
      expect(parsed.amountRaw, BigInt.from(2500000));
      expect(parsed.maxPriorityFeePerGas, BigInt.from(30));
      expect(parsed.maxFeePerGas, BigInt.from(50));
      expect(parsed.gasLimit, BigInt.from(65000));
    });

    test('speed-up preserves exact approve(spender, 0) revocation', () async {
      final service = LocalTransferService(
        params: _ReplacementParams(
          confirmed: 8,
          pending: 10,
          fastPriority: BigInt.from(30),
          fastMaxFee: BigInt.from(50),
        ),
      );

      final prepared = await service.prepareEvmReplacement(
        chain: Chain.ethereum,
        evmChainId: 11155111,
        from: _from,
        recipient: _to,
        amountRaw: BigInt.zero,
        tokenContract: _token,
        operation: TxOperation.approvalRevoke,
        nonce: BigInt.from(9),
        previousMaxPriorityFeePerGas: BigInt.from(20),
        previousMaxFeePerGas: BigInt.from(40),
        previousGasLimit: BigInt.from(50000),
        cancel: false,
      );
      final parsed = parseUnsignedTransfer(Chain.ethereum, prepared.unsignedTx);

      expect(prepared.operation, TxOperation.approvalRevoke);
      expect(parsed.operation, TxOperation.approvalRevoke);
      expect(parsed.tokenContract, _token.toLowerCase());
      expect(parsed.to, _to.toLowerCase());
      expect(parsed.amountRaw, BigInt.zero);
      expect(parsed.nonce, BigInt.from(9));
    });

    test('cancel replaces a revoke with a zero native self-transfer', () async {
      final service = LocalTransferService(
        params: _ReplacementParams(
          confirmed: 8,
          pending: 10,
          fastPriority: BigInt.from(30),
          fastMaxFee: BigInt.from(50),
          estimatedGas: 21000,
        ),
      );

      final prepared = await service.prepareEvmReplacement(
        chain: Chain.ethereum,
        evmChainId: 11155111,
        from: _from,
        recipient: _to,
        amountRaw: BigInt.zero,
        tokenContract: _token,
        operation: TxOperation.approvalRevoke,
        nonce: BigInt.from(9),
        previousMaxPriorityFeePerGas: BigInt.from(20),
        previousMaxFeePerGas: BigInt.from(40),
        previousGasLimit: BigInt.from(50000),
        cancel: true,
      );
      final parsed = parseUnsignedTransfer(Chain.ethereum, prepared.unsignedTx);

      expect(prepared.operation, TxOperation.nativeTransfer);
      expect(prepared.tokenContract, isNull);
      expect(parsed.operation, TxOperation.nativeTransfer);
      expect(parsed.to, _from.toLowerCase());
      expect(parsed.amountRaw, BigInt.zero);
    });

    test(
      'cancel sends zero native value back to sender with estimated gas',
      () async {
        final params = _ReplacementParams(
          confirmed: 2,
          pending: 4,
          fastPriority: BigInt.from(50),
          fastMaxFee: BigInt.from(90),
          estimatedGas: 23000,
        );
        final service = LocalTransferService(params: params);

        final prepared = await service.prepareEvmReplacement(
          chain: Chain.base,
          evmChainId: 84532,
          from: _from,
          recipient: _to,
          amountRaw: BigInt.from(999),
          tokenContract: _token,
          nonce: BigInt.from(3),
          previousMaxPriorityFeePerGas: BigInt.from(100),
          previousMaxFeePerGas: BigInt.from(200),
          previousGasLimit: BigInt.from(65000),
          cancel: true,
        );
        final parsed = parseUnsignedTransfer(Chain.base, prepared.unsignedTx);

        expect(prepared.tokenContract, isNull);
        expect(parsed.operation, TxOperation.nativeTransfer);
        expect(parsed.to, _from.toLowerCase());
        expect(parsed.amountRaw, BigInt.zero);
        expect(parsed.nonce, BigInt.from(3));
        expect(parsed.gasLimit, BigInt.from(23000));
        expect(params.simulatedBlockTag, 'latest');
      },
    );

    test('rejects replacement after the nonce is mined', () {
      final service = LocalTransferService(
        params: _ReplacementParams(
          confirmed: 6,
          pending: 6,
          fastPriority: BigInt.one,
          fastMaxFee: BigInt.two,
        ),
      );

      expect(
        () => service.prepareEvmReplacement(
          chain: Chain.avalanche,
          evmChainId: 43113,
          from: _from,
          recipient: _to,
          amountRaw: BigInt.one,
          tokenContract: null,
          nonce: BigInt.from(5),
          previousMaxPriorityFeePerGas: BigInt.one,
          previousMaxFeePerGas: BigInt.two,
          previousGasLimit: BigInt.from(21000),
          cancel: false,
        ),
        throwsA(
          isA<EvmNonceAlreadyConsumed>()
              .having((error) => error.nonce, 'nonce', 5)
              .having((error) => error.confirmedNonce, 'confirmedNonce', 6),
        ),
      );
    });

    test(
      'latest fallback is allowed only at the current confirmed nonce',
      () async {
        final currentParams = _ReplacementParams(
          confirmed: 5,
          pending: 5,
          fastPriority: BigInt.from(10),
          fastMaxFee: BigInt.from(20),
          pendingAvailable: false,
        );
        final current = LocalTransferService(params: currentParams);
        final prepared = await current.prepareEvmReplacement(
          chain: Chain.avalanche,
          evmChainId: 43113,
          from: _from,
          recipient: _to,
          amountRaw: BigInt.one,
          tokenContract: null,
          nonce: BigInt.from(5),
          previousMaxPriorityFeePerGas: BigInt.from(10),
          previousMaxFeePerGas: BigInt.from(20),
          previousGasLimit: BigInt.from(21000),
          cancel: false,
        );
        expect(prepared.nonce, BigInt.from(5));

        final queued = LocalTransferService(
          params: _ReplacementParams(
            confirmed: 4,
            pending: 4,
            fastPriority: BigInt.from(10),
            fastMaxFee: BigInt.from(20),
            pendingAvailable: false,
          ),
        );
        await expectLater(
          queued.prepareEvmReplacement(
            chain: Chain.avalanche,
            evmChainId: 43113,
            from: _from,
            recipient: _to,
            amountRaw: BigInt.one,
            tokenContract: null,
            nonce: BigInt.from(5),
            previousMaxPriorityFeePerGas: BigInt.from(10),
            previousMaxFeePerGas: BigInt.from(20),
            previousGasLimit: BigInt.from(21000),
            cancel: false,
          ),
          throwsA(isA<EvmPreflightFailed>()),
        );
      },
    );

    test('rejects replacement when latest cannot fund the winning tx', () {
      final service = LocalTransferService(
        params: _ReplacementParams(
          confirmed: 0,
          pending: 1,
          fastPriority: BigInt.one,
          fastMaxFee: BigInt.two,
          nativeLatest: BigInt.from(63999),
        ),
      );

      expect(
        () => service.prepareEvmReplacement(
          chain: Chain.ethereum,
          evmChainId: 11155111,
          from: _from,
          recipient: _to,
          amountRaw: BigInt.from(1000),
          tokenContract: null,
          nonce: BigInt.zero,
          previousMaxPriorityFeePerGas: BigInt.one,
          previousMaxFeePerGas: BigInt.two,
          previousGasLimit: BigInt.from(21000),
          cancel: false,
        ),
        throwsA(isA<EvmInsufficientFunds>()),
      );
    });

    test('rejects fee bump when pending cannot fund the extra liability', () {
      final service = LocalTransferService(
        params: _ReplacementParams(
          confirmed: 0,
          pending: 1,
          fastPriority: BigInt.one,
          fastMaxFee: BigInt.two,
          nativePending: BigInt.from(20999),
          nativeLatest: BigInt.from(100000),
        ),
      );

      expect(
        () => service.prepareEvmReplacement(
          chain: Chain.ethereum,
          evmChainId: 11155111,
          from: _from,
          recipient: _to,
          amountRaw: BigInt.from(1000),
          tokenContract: null,
          nonce: BigInt.zero,
          previousMaxPriorityFeePerGas: BigInt.one,
          previousMaxFeePerGas: BigInt.two,
          previousGasLimit: BigInt.from(21000),
          cancel: false,
        ),
        throwsA(isA<EvmInsufficientFunds>()),
      );
    });
  });
}

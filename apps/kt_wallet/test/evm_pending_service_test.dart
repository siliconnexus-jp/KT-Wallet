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
  });

  final int confirmed;
  final int pending;
  final BigInt fastPriority;
  final BigInt fastMaxFee;
  final int estimatedGas;

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
}

const _from = '0x70997970C51812dc3A010C7d01b50e0d17dc79C8';
const _to = '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed';
const _token = '0xc2132D05D31c914a87C6611C10748AEb04B58e8F';

void main() {
  group('LocalTransferService EVM replacement', () {
    test(
      'speed-up preserves native transfer and bumps both fees by 12.5%',
      () async {
        final service = LocalTransferService(
          params: _ReplacementParams(
            confirmed: 4,
            pending: 6,
            fastPriority: BigInt.from(10),
            fastMaxFee: BigInt.from(20),
          ),
        );

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

    test(
      'cancel sends zero native value back to sender with estimated gas',
      () async {
        final service = LocalTransferService(
          params: _ReplacementParams(
            confirmed: 2,
            pending: 4,
            fastPriority: BigInt.from(50),
            fastMaxFee: BigInt.from(90),
            estimatedGas: 23000,
          ),
        );

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
  });
}

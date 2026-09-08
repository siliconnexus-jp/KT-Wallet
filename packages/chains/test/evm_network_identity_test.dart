import 'dart:typed_data';
import 'package:chains/chains.dart';
import 'package:test/test.dart';

void main() {
  test('all known EVM mainnets and testnets reject every other family', () {
    final families = evmSigningNetworks.values.toSet();
    for (final entry in evmSigningNetworks.entries) {
      for (final family in families) {
        final raw = Eip1559Tx(
          chainId: BigInt.from(entry.key),
          nonce: BigInt.zero,
          maxPriorityFeePerGas: BigInt.one,
          maxFeePerGas: BigInt.two,
          gasLimit: BigInt.from(21000),
          to: Uint8List(20),
          value: BigInt.one,
          data: Uint8List(0),
        ).encodeUnsigned();
        if (family == entry.value) {
          expect(
            parseUnsignedTransfer(family, raw).networkId,
            BigInt.from(entry.key),
          );
        } else {
          expect(
            () => parseUnsignedTransfer(family, raw),
            throwsFormatException,
          );
        }
      }
    }
  });
  test(
    'offline unknown networks fail closed; online custom RPC stays available',
    () {
      expect(
        () =>
            validateEvmNetworkIdentity(Chain.ethereum, BigInt.from(123456789)),
        throwsFormatException,
      );
      validateEvmNetworkIdentity(
        Chain.ethereum,
        BigInt.from(123456789),
        allowUnknown: true,
      );
      expect(
        () => validateEvmNetworkIdentity(
          Chain.ethereum,
          BigInt.zero,
          allowUnknown: true,
        ),
        throwsFormatException,
      );
    },
  );
}

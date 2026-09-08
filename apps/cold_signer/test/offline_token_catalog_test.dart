import 'package:chains/chains.dart';
import 'package:cold_signer/src/signing/offline_token_catalog.dart';
import 'package:flutter_test/flutter_test.dart';

ParsedUnsignedTransfer transfer(
  OfflineToken token, {
  String? contract,
  BigInt? networkId,
  Chain? chain,
}) => ParsedUnsignedTransfer(
  chain: chain ?? token.chain,
  operation: TxOperation.tokenTransfer,
  to: 'unused',
  amountRaw: BigInt.from(2000000),
  tokenContract: contract ?? token.contract,
  networkId:
      networkId ?? (token.chainId == null ? null : BigInt.from(token.chainId!)),
);

void main() {
  test('every built-in identity is unique, valid and has an exact scale', () {
    final identities = <String>{};
    for (final token in offlineTokens) {
      expect(
        identities.add(
          '${token.chain.name}:${token.chainId}:${token.contract}',
        ),
        isTrue,
      );
      expect(token.decimals, inInclusiveRange(0, 18));
      expect(offlineTokenFor(transfer(token)), same(token));
      if (token.chainId != null) {
        expect(RegExp(r'^0x[0-9a-f]{40}$').hasMatch(token.contract), isTrue);
        expect(
          offlineTokenFor(
            transfer(token, contract: token.contract.toUpperCase()),
          ),
          same(token),
        );
        expect(
          offlineTokenFor(transfer(token, networkId: BigInt.from(999999))),
          isNull,
        );
      } else {
        expect(
          base58Decode(token.contract),
          hasLength(token.chain == Chain.solana ? 32 : 25),
        );
        expect(
          offlineTokenFor(
            transfer(token, contract: token.contract.toLowerCase()),
          ),
          isNull,
        );
      }
      final raw = BigInt.from(2) * BigInt.from(10).pow(token.decimals);
      expect(Amount(raw: raw, decimals: token.decimals).format(), '2');
    }
  });

  test(
    'missing network identity, wrong chain and unknown contract stay unknown',
    () {
      final token = offlineTokens.first;
      expect(
        offlineTokenFor(
          ParsedUnsignedTransfer(
            chain: token.chain,
            operation: TxOperation.tokenTransfer,
            to: 'unused',
            amountRaw: BigInt.one,
            tokenContract: token.contract,
          ),
        ),
        isNull,
      );
      expect(offlineTokenFor(transfer(token, chain: Chain.arbitrum)), isNull);
      expect(
        offlineTokenFor(
          transfer(
            token,
            contract: '0x0000000000000000000000000000000000000001',
          ),
        ),
        isNull,
      );
    },
  );
}

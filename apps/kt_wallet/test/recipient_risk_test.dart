import 'package:chains/chains.dart' show Chain;
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/transfer/recipient_risk.dart';

void main() {
  const known = KnownRecipientAddress(
    address: '0x1234561111111111111111111111111111abcdef',
    label: 'Alice',
  );

  test('same visible EVM edges with a different middle is suspicious', () {
    final risk = detectRecipientLookalike(
      chain: Chain.ethereum,
      candidate: '0x1234562222222222222222222222222222abcdef',
      knownAddresses: const [known],
    );

    expect(risk?.known.label, 'Alice');
  });

  test('an exact known recipient is not suspicious', () {
    expect(
      detectRecipientLookalike(
        chain: Chain.arbitrum,
        candidate: known.address.toUpperCase().replaceFirst('0X', '0x'),
        knownAddresses: const [known],
      ),
      isNull,
    );
  });

  test('one matching edge is insufficient', () {
    expect(
      detectRecipientLookalike(
        chain: Chain.ethereum,
        candidate: '0x1234562222222222222222222222222222fedcba',
        knownAddresses: const [known],
      ),
      isNull,
    );
  });

  test(
    'invalid candidate is ignored instead of receiving a safety verdict',
    () {
      expect(
        detectRecipientLookalike(
          chain: Chain.ethereum,
          candidate: '0x123456abcdef',
          knownAddresses: const [known],
        ),
        isNull,
      );
    },
  );
}

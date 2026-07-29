import 'package:chains/chains.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/transfer/transfer_draft.dart';

TransferDraft _draft(String recipient) => TransferDraft(
  symbol: 'ETH',
  networkLabel: 'Sepolia',
  chain: Chain.ethereum,
  recipient: recipient,
  amount: Amount(raw: BigInt.one, decimals: 18, symbol: 'ETH'),
  feeTier: 1,
);

void main() {
  test('a new transfer cannot reuse the previous local transaction id', () {
    final session = TransferSession()
      ..begin(_draft('0x1111111111111111111111111111111111111111'))
      ..localTransactionId = 'local-first'
      ..broadcastTxHash = '0xfirst';

    session.begin(_draft('0x2222222222222222222222222222222222222222'));

    expect(session.localTransactionId, isNull);
    expect(session.broadcastTxHash, isNull);
    expect(
      session.draft?.recipient,
      '0x2222222222222222222222222222222222222222',
    );
  });
}

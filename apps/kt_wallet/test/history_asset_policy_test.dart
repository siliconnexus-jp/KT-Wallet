import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/market/history_asset_policy.dart';
import 'package:kt_wallet/src/market/history_service.dart';
import 'package:wallet_data/wallet_data.dart' show CustomToken;

const _contract = '0x1111111111111111111111111111111111111111';

ChainTxRecord _record({
  String? networkId = 'base-mainnet',
  String? contract = _contract,
  String symbol = 'CUSTOM',
  bool verified = false,
}) => ChainTxRecord(
  coin: Coin.base,
  networkId: networkId,
  hash: '0xhash',
  outgoing: false,
  amountText: '1 $symbol',
  assetContract: contract,
  assetSymbol: symbol,
  assetVerified: verified,
  timestamp: DateTime.utc(2026, 8, 8),
  confirmed: true,
);

CustomToken _custom({
  String? networkId = 'base-mainnet',
  String? contract = _contract,
  bool enabled = true,
}) => CustomToken(
  id: 'custom',
  symbol: 'CUSTOM',
  name: 'Custom Token',
  contract: contract,
  network: 'Base · ERC-20',
  networkId: networkId,
  enabled: enabled,
  sortOrder: 0,
  createdAt: 0,
);

void main() {
  test('native and registry-verified assets stay in primary history', () {
    expect(
      classifyHistoryAsset(_record(contract: null), const []),
      HistoryAssetKind.official,
    );
    expect(
      classifyHistoryAsset(_record(verified: true), const []),
      HistoryAssetKind.official,
    );
  });

  test('enabled user token requires exact network and contract identity', () {
    expect(
      classifyHistoryAsset(_record(contract: _contract.toUpperCase()), [
        _custom(),
      ]),
      HistoryAssetKind.userAdded,
    );
    expect(
      classifyHistoryAsset(_record(networkId: 'eth-mainnet'), [_custom()]),
      HistoryAssetKind.unverified,
    );
    expect(
      classifyHistoryAsset(_record(), [_custom(enabled: false)]),
      HistoryAssetKind.unverified,
    );
  });

  test('legacy custom rows without a network id never bypass filtering', () {
    expect(
      classifyHistoryAsset(_record(), [_custom(networkId: null)]),
      HistoryAssetKind.unverified,
    );
  });

  test('protected-symbol impersonation and promotional links are risky', () {
    expect(
      classifyHistoryAsset(_record(symbol: 'USDT'), const []),
      HistoryAssetKind.risky,
    );
    expect(
      classifyHistoryAsset(_record(symbol: 'ARB | t.me/s/arb_pool'), const []),
      HistoryAssetKind.risky,
    );
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/market/token_balance_service.dart';

import '../tool/e2e_funding_preflight_model.dart';

const _addresses = E2eFundingAddressesFixture(
  evm: '0x1111111111111111111111111111111111111111',
  tron: 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf',
  solana: '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
);

class E2eFundingAddressesFixture {
  const E2eFundingAddressesFixture({
    required this.evm,
    required this.tron,
    required this.solana,
  });
  final String evm;
  final String tron;
  final String solana;

  E2eFundingAddresses build() =>
      E2eFundingAddresses(evm: evm, tron: tron, solana: solana);
}

void main() {
  test('all eight exact funding targets are ready', () {
    final report = evaluateE2eFunding(
      addresses: _addresses.build(),
      portfolio: _portfolio(),
    );

    expect(report.readiness, FundingReadiness.ready);
    expect(report.networks, hasLength(8));
    expect(report.networks.every((row) => row.native.sufficient), isTrue);
    expect(report.networks.every((row) => row.token.sufficient), isTrue);
  });

  test('host preflight token identities match the production registry', () {
    final production = {
      FundingCoin.eth: usdtSepoliaToken,
      FundingCoin.polygon: usdcPolygonAmoyToken,
      FundingCoin.base: usdcBaseSepoliaToken,
      FundingCoin.arbitrum: usdcArbitrumSepoliaToken,
      FundingCoin.avalanche: usdcAvalancheFujiToken,
      FundingCoin.bnb: busdBnbTestnetToken,
      FundingCoin.tron: usdtTronNileToken,
      FundingCoin.solana: usdcSolanaDevnetToken,
    };

    for (final requirement in e2eFundingRequirements) {
      final token = production[requirement.coin]!;
      expect(requirement.token.contract, token.contract);
      expect(requirement.token.symbol, token.symbol);
      expect(requirement.token.decimals, token.decimals);
    }
  });

  test('one deficient native balance fails with an exact raw deficit', () {
    final requirement = e2eFundingRequirements.singleWhere(
      (row) => row.coin == FundingCoin.polygon,
    );
    final actual = requirement.nativeTargetRaw - BigInt.one;
    final report = evaluateE2eFunding(
      addresses: _addresses.build(),
      portfolio: _portfolio(nativeOverrides: {FundingCoin.polygon: actual}),
    );

    expect(report.readiness, FundingReadiness.insufficient);
    final row = report.networks.singleWhere(
      (item) => item.requirement.coin == FundingCoin.polygon,
    );
    expect(row.readiness, FundingReadiness.insufficient);
    expect(row.native.actualRaw, actual);
    expect(row.native.deficitRaw, BigInt.one);
    expect(row.token.sufficient, isTrue);
  });

  test('failed chain is unavailable instead of reporting zero', () {
    final portfolio = _portfolio(failed: {FundingCoin.solana});
    final report = evaluateE2eFunding(
      addresses: _addresses.build(),
      portfolio: portfolio,
    );

    expect(report.readiness, FundingReadiness.unavailable);
    final row = report.networks.singleWhere(
      (item) => item.requirement.coin == FundingCoin.solana,
    );
    expect(row.readiness, FundingReadiness.unavailable);
    expect(row.reason, 'balance_query_unavailable');
    expect(row.native.actualRaw, isNull);
    expect(row.token.actualRaw, isNull);
  });

  test('wrong or duplicate token identity is unavailable', () {
    final requirement = e2eFundingRequirements.singleWhere(
      (row) => row.coin == FundingCoin.tron,
    );
    final balances = _balances(requirement);
    final duplicate = ObservedBalances(
      native: balances.native,
      tokens: [...balances.tokens, ...balances.tokens],
    );
    final report = evaluateE2eFunding(
      addresses: _addresses.build(),
      portfolio: _portfolio(balanceOverrides: {FundingCoin.tron: duplicate}),
    );

    final row = report.networks.singleWhere(
      (item) => item.requirement.coin == FundingCoin.tron,
    );
    expect(row.readiness, FundingReadiness.unavailable);
    expect(row.reason, 'token_balance_unavailable');
  });

  test('token error is unavailable and never treated as zero', () {
    final requirement = e2eFundingRequirements.singleWhere(
      (row) => row.coin == FundingCoin.eth,
    );
    final report = evaluateE2eFunding(
      addresses: _addresses.build(),
      portfolio: _portfolio(
        balanceOverrides: {
          FundingCoin.eth: ObservedBalances(
            native: ObservedNativeBalance(
              raw: requirement.nativeTargetRaw,
              decimals: 18,
              symbol: requirement.nativeSymbol,
            ),
            tokens: [
              ObservedTokenBalance(
                contract: requirement.token.contract,
                raw: null,
                decimals: requirement.token.decimals,
                symbol: requirement.token.symbol,
                error: 'upstream_error',
              ),
            ],
          ),
        },
      ),
    );

    final row = report.networks.first;
    expect(row.readiness, FundingReadiness.unavailable);
    expect(row.token.actualRaw, isNull);
    expect(row.token.toJson()['sufficient'], isFalse);
  });

  test('public address validation rejects malformed chain identities', () {
    expect(
      () => E2eFundingAddresses(
        evm: '0x1',
        tron: _addresses.tron,
        solana: _addresses.solana,
      ),
      throwsFormatException,
    );
    expect(
      () => E2eFundingAddresses(
        evm: _addresses.evm,
        tron: '0x1111111111111111111111111111111111111111',
        solana: _addresses.solana,
      ),
      throwsFormatException,
    );
    expect(
      () => E2eFundingAddresses(
        evm: _addresses.evm,
        tron: _addresses.tron,
        solana: 'not-a-solana-address',
      ),
      throwsFormatException,
    );
  });

  test('JSON output carries only public readiness evidence', () {
    final report = evaluateE2eFunding(
      addresses: _addresses.build(),
      portfolio: _portfolio(),
    );
    final json = report.toJson();

    expect(json['status'], 'ready');
    expect(json.toString(), isNot(contains('mnemonic')));
    expect(json.toString(), isNot(contains('privateKey')));
    expect(json.toString(), isNot(contains('signedTx')));
  });

  test('closed Gateway parser accepts the exact eight-chain response', () {
    final decoded = _gatewayResponse();
    final portfolio = parseGatewayFundingResponse(
      decoded,
      expectedId: 7,
      expectedAddresses: _addresses.build(),
    );

    expect(portfolio.failedChains, isEmpty);
    expect(portfolio.balances, hasLength(8));
    expect(
      portfolio.balances[FundingCoin.solana]!.native.raw,
      e2eFundingRequirements.last.nativeTargetRaw,
    );
  });

  test('closed Gateway parser rejects wrong id and unknown fields', () {
    final wrongId = _gatewayResponse()..['id'] = 8;
    expect(
      () => parseGatewayFundingResponse(
        wrongId,
        expectedId: 7,
        expectedAddresses: _addresses.build(),
      ),
      throwsFormatException,
    );

    final unknown = _gatewayResponse();
    unknown['result'] = <String, Object?>{
      ...unknown['result']! as Map<String, Object?>,
      'unexpected': true,
    };
    expect(
      () => parseGatewayFundingResponse(
        unknown,
        expectedId: 7,
        expectedAddresses: _addresses.build(),
      ),
      throwsFormatException,
    );
  });

  test('closed Gateway parser rejects cross-network and Token metadata', () {
    final wrongNetwork = _gatewayResponse();
    final accounts =
        (wrongNetwork['result']! as Map<String, Object?>)['accounts']! as List;
    (accounts.first as Map<String, Object?>)['network'] = 'eth-mainnet';
    expect(
      () => parseGatewayFundingResponse(
        wrongNetwork,
        expectedId: 7,
        expectedAddresses: _addresses.build(),
      ),
      throwsFormatException,
    );

    final wrongToken = _gatewayResponse();
    final tokenAccounts =
        (wrongToken['result']! as Map<String, Object?>)['accounts']! as List;
    final firstResult =
        (tokenAccounts.first as Map<String, Object?>)['result']!
            as Map<String, Object?>;
    final tokens = firstResult['tokens']! as List;
    (tokens.single as Map<String, Object?>)['decimals'] = 18;
    expect(
      () => parseGatewayFundingResponse(
        wrongToken,
        expectedId: 7,
        expectedAddresses: _addresses.build(),
      ),
      throwsFormatException,
    );
  });

  test('closed Gateway parser rejects outer and nested account mismatch', () {
    final wrongOuter = _gatewayResponse();
    final outerAccounts =
        (wrongOuter['result']! as Map<String, Object?>)['accounts']! as List;
    (outerAccounts.first as Map<String, Object?>)['address'] =
        '0x2222222222222222222222222222222222222222';
    expect(
      () => parseGatewayFundingResponse(
        wrongOuter,
        expectedId: 7,
        expectedAddresses: _addresses.build(),
      ),
      throwsFormatException,
    );

    final wrongNested = _gatewayResponse();
    final nestedAccounts =
        (wrongNested['result']! as Map<String, Object?>)['accounts']! as List;
    final nestedResult =
        (nestedAccounts.first as Map<String, Object?>)['result']!
            as Map<String, Object?>;
    nestedResult['network'] = 'eth-mainnet';
    expect(
      () => parseGatewayFundingResponse(
        wrongNested,
        expectedId: 7,
        expectedAddresses: _addresses.build(),
      ),
      throwsFormatException,
    );
  });

  test('host Gateway decoder rejects literal and escaped duplicate keys', () {
    expect(
      () => decodeGatewayFundingJson(
        '{"jsonrpc":"2.0","id":1,"id":2,"result":{}}',
      ),
      throwsFormatException,
    );
    expect(
      () => decodeGatewayFundingJson(
        '{"jsonrpc":"2.0","id":1,"result":{},"re\\u0073ult":{}}',
      ),
      throwsFormatException,
    );
  });
}

FundingPortfolio _portfolio({
  Set<FundingCoin> failed = const {},
  Map<FundingCoin, BigInt> nativeOverrides = const {},
  Map<FundingCoin, ObservedBalances> balanceOverrides = const {},
}) {
  final balances = <FundingCoin, ObservedBalances>{};
  for (final requirement in e2eFundingRequirements) {
    if (!failed.contains(requirement.coin)) {
      balances[requirement.coin] =
          balanceOverrides[requirement.coin] ??
          _balances(
            requirement,
            nativeRaw:
                nativeOverrides[requirement.coin] ??
                requirement.nativeTargetRaw,
          );
    }
  }
  return FundingPortfolio(balances: balances, failedChains: failed);
}

ObservedBalances _balances(
  FundingRequirement requirement, {
  BigInt? nativeRaw,
}) => ObservedBalances(
  native: ObservedNativeBalance(
    raw: nativeRaw ?? requirement.nativeTargetRaw,
    decimals: requirement.nativeDecimals,
    symbol: requirement.nativeSymbol,
  ),
  tokens: [
    ObservedTokenBalance(
      contract: requirement.token.contract,
      raw: requirement.tokenTargetRaw,
      decimals: requirement.token.decimals,
      symbol: requirement.token.symbol,
    ),
  ],
);

Map<String, Object?> _gatewayResponse() => {
  'jsonrpc': '2.0',
  'id': 7,
  'result': {
    'accounts': [
      for (final requirement in e2eFundingRequirements)
        {
          'chain': requirement.coin.name,
          'network': requirement.networkId,
          'address': _addresses.build().forCoin(requirement.coin),
          'result': {
            'chain': requirement.coin.name,
            'network': requirement.networkId,
            'address': _addresses.build().forCoin(requirement.coin),
            'native': {
              'raw': requirement.nativeTargetRaw.toString(),
              'decimals': requirement.nativeDecimals,
              'symbol': requirement.nativeSymbol,
            },
            'tokens': [
              {
                'contract': requirement.token.contract,
                'raw': requirement.tokenTargetRaw.toString(),
                'decimals': requirement.token.decimals,
                'symbol': requirement.token.symbol,
              },
            ],
          },
        },
    ],
  },
};

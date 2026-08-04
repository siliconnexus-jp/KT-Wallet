import 'package:crypto/crypto.dart' show sha256;

enum FundingReadiness { ready, insufficient, unavailable }

enum FundingCoin { eth, polygon, base, arbitrum, avalanche, bnb, tron, solana }

class E2eFundingAddresses {
  E2eFundingAddresses({
    required this.evm,
    required this.tron,
    required this.solana,
  }) {
    if (!_evmPattern.hasMatch(evm)) {
      throw const FormatException('invalid EVM address');
    }
    if (!_isTronAddress(tron)) {
      throw const FormatException('invalid TRON address');
    }
    if (_decodeBase58(solana)?.length != 32) {
      throw const FormatException('invalid Solana address');
    }
  }

  final String evm;
  final String tron;
  final String solana;

  String forCoin(FundingCoin coin) => switch (coin) {
    FundingCoin.eth ||
    FundingCoin.polygon ||
    FundingCoin.base ||
    FundingCoin.arbitrum ||
    FundingCoin.avalanche ||
    FundingCoin.bnb => evm,
    FundingCoin.tron => tron,
    FundingCoin.solana => solana,
  };

  Map<String, String> toJson() => {'evm': evm, 'tron': tron, 'solana': solana};
}

class FundingToken {
  const FundingToken({
    required this.symbol,
    required this.contract,
    required this.decimals,
  });

  final String symbol;
  final String contract;
  final int decimals;
}

class FundingRequirement {
  const FundingRequirement({
    required this.coin,
    required this.networkId,
    required this.networkLabel,
    required this.nativeSymbol,
    required this.nativeDecimals,
    required this.nativeTargetRaw,
    required this.token,
  });

  final FundingCoin coin;
  final String networkId;
  final String networkLabel;
  final String nativeSymbol;
  final int nativeDecimals;

  /// Conservative faucet target for the complete native + Token E2E pair.
  /// The transfer flow still performs live simulation and exact maximum-fee
  /// validation immediately before signing; this target is not a fee quote.
  final BigInt nativeTargetRaw;
  final FundingToken token;

  BigInt get tokenTargetRaw => BigInt.from(10).pow(token.decimals);

  Map<String, Object?> accountQuery(String address) => {
    'chain': coin.name,
    'network': networkId,
    'address': address,
    'tokens': [
      {
        'contract': token.contract,
        'decimals': token.decimals,
        'symbol': token.symbol,
      },
    ],
  };
}

final List<FundingRequirement> e2eFundingRequirements = List.unmodifiable([
  FundingRequirement(
    coin: FundingCoin.eth,
    networkId: 'eth-sepolia',
    networkLabel: 'Ethereum Sepolia',
    nativeSymbol: 'ETH',
    nativeDecimals: 18,
    nativeTargetRaw: BigInt.parse('1000000000000000'), // 0.001 ETH
    token: FundingToken(
      symbol: 'USDT',
      contract: '0xc4DCC311c028e341fd8602D8eB89c5de94625927',
      decimals: 6,
    ),
  ),
  FundingRequirement(
    coin: FundingCoin.polygon,
    networkId: 'polygon-amoy',
    networkLabel: 'Polygon Amoy',
    nativeSymbol: 'POL',
    nativeDecimals: 18,
    nativeTargetRaw: BigInt.parse('5000000000000000'), // 0.005 POL
    token: FundingToken(
      symbol: 'USDC',
      contract: '0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582',
      decimals: 6,
    ),
  ),
  FundingRequirement(
    coin: FundingCoin.base,
    networkId: 'base-sepolia',
    networkLabel: 'Base Sepolia',
    nativeSymbol: 'ETH',
    nativeDecimals: 18,
    nativeTargetRaw: BigInt.parse('1000000000000000'), // 0.001 ETH
    token: FundingToken(
      symbol: 'USDC',
      contract: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
      decimals: 6,
    ),
  ),
  FundingRequirement(
    coin: FundingCoin.arbitrum,
    networkId: 'arbitrum-sepolia',
    networkLabel: 'Arbitrum Sepolia',
    nativeSymbol: 'ETH',
    nativeDecimals: 18,
    nativeTargetRaw: BigInt.parse('1000000000000000'), // 0.001 ETH
    token: FundingToken(
      symbol: 'USDC',
      contract: '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d',
      decimals: 6,
    ),
  ),
  FundingRequirement(
    coin: FundingCoin.avalanche,
    networkId: 'avalanche-fuji',
    networkLabel: 'Avalanche Fuji',
    nativeSymbol: 'AVAX',
    nativeDecimals: 18,
    nativeTargetRaw: BigInt.parse('10000000000000000'), // 0.01 AVAX
    token: FundingToken(
      symbol: 'USDC',
      contract: '0x5425890298aed601595a70AB815c96711a31Bc65',
      decimals: 6,
    ),
  ),
  FundingRequirement(
    coin: FundingCoin.bnb,
    networkId: 'bnb-testnet',
    networkLabel: 'BNB Smart Chain Testnet',
    nativeSymbol: 'BNB',
    nativeDecimals: 18,
    nativeTargetRaw: BigInt.parse('5000000000000000'), // 0.005 BNB
    token: FundingToken(
      symbol: 'BUSD',
      contract: '0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee',
      decimals: 18,
    ),
  ),
  FundingRequirement(
    coin: FundingCoin.tron,
    networkId: 'tron-nile',
    networkLabel: 'TRON Nile',
    nativeSymbol: 'TRX',
    nativeDecimals: 6,
    nativeTargetRaw: BigInt.from(50000000), // 50 TRX
    token: FundingToken(
      symbol: 'USDT',
      contract: 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf',
      decimals: 6,
    ),
  ),
  FundingRequirement(
    coin: FundingCoin.solana,
    networkId: 'sol-devnet',
    networkLabel: 'Solana Devnet',
    nativeSymbol: 'SOL',
    nativeDecimals: 9,
    nativeTargetRaw: BigInt.from(10000000), // 0.01 SOL
    token: FundingToken(
      symbol: 'USDC',
      contract: '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
      decimals: 6,
    ),
  ),
]);

class ObservedNativeBalance {
  const ObservedNativeBalance({
    required this.raw,
    required this.decimals,
    required this.symbol,
  });
  final BigInt raw;
  final int decimals;
  final String symbol;
}

class ObservedTokenBalance {
  const ObservedTokenBalance({
    required this.contract,
    required this.raw,
    required this.decimals,
    required this.symbol,
    this.error,
  });
  final String contract;
  final BigInt? raw;
  final int decimals;
  final String symbol;
  final String? error;
}

class ObservedBalances {
  const ObservedBalances({required this.native, required this.tokens});
  final ObservedNativeBalance native;
  final List<ObservedTokenBalance> tokens;
}

class FundingPortfolio {
  const FundingPortfolio({required this.balances, required this.failedChains});
  final Map<FundingCoin, ObservedBalances> balances;
  final Set<FundingCoin> failedChains;
}

FundingPortfolio parseGatewayFundingResponse(
  Object? decoded, {
  required int expectedId,
  List<FundingRequirement>? requirements,
}) {
  final expected = requirements ?? e2eFundingRequirements;
  final root = _map(decoded, 'response');
  _exactKeys(root, {'jsonrpc', 'id', 'result'}, 'response');
  if (root['jsonrpc'] != '2.0' || root['id'] != expectedId) {
    throw const FormatException('unbound Gateway response');
  }
  final result = _map(root['result'], 'result');
  _exactKeys(result, {'accounts'}, 'result');
  final accounts = result['accounts'];
  if (accounts is! List || accounts.length != expected.length) {
    throw const FormatException('unexpected portfolio account count');
  }
  final expectedByCoin = {for (final row in expected) row.coin.name: row};
  final balances = <FundingCoin, ObservedBalances>{};
  final failed = <FundingCoin>{};
  final seen = <FundingCoin>{};
  for (final value in accounts) {
    final row = _map(value, 'account');
    final chain = row['chain'];
    final requirement = chain is String ? expectedByCoin[chain] : null;
    if (requirement == null || !seen.add(requirement.coin)) {
      throw const FormatException('unknown or duplicate portfolio chain');
    }
    final hasResult = row.containsKey('result');
    final hasError = row.containsKey('error');
    _exactKeys(
      row,
      hasResult && !hasError
          ? {'chain', 'network', 'result'}
          : !hasResult && hasError
          ? {'chain', 'network', 'error'}
          : const {},
      'account',
    );
    if (row['network'] != requirement.networkId) {
      throw const FormatException('portfolio network mismatch');
    }
    if (hasError) {
      if (row['error'] is! String || (row['error'] as String).isEmpty) {
        throw const FormatException('malformed portfolio error');
      }
      failed.add(requirement.coin);
      continue;
    }
    balances[requirement.coin] = _parseBalances(row['result'], requirement);
  }
  if (balances.length + failed.length != expected.length) {
    throw const FormatException('incomplete portfolio response');
  }
  return FundingPortfolio(
    balances: Map.unmodifiable(balances),
    failedChains: Set.unmodifiable(failed),
  );
}

ObservedBalances _parseBalances(Object? value, FundingRequirement requirement) {
  final result = _map(value, 'balances');
  _exactKeys(result, {'native', 'tokens'}, 'balances');
  final native = _map(result['native'], 'native');
  _exactKeys(native, {'raw', 'decimals', 'symbol'}, 'native');
  final nativeRaw = _nonNegativeBigInt(native['raw'], 'native.raw');
  if (native['decimals'] != requirement.nativeDecimals ||
      native['symbol'] != requirement.nativeSymbol) {
    throw const FormatException('native metadata mismatch');
  }
  final tokens = result['tokens'];
  if (tokens is! List || tokens.length != 1) {
    throw const FormatException('unexpected token balance count');
  }
  final token = _map(tokens.single, 'token');
  final hasError = token.containsKey('error');
  _exactKeys(
    token,
    hasError
        ? {'contract', 'raw', 'decimals', 'symbol', 'error'}
        : {'contract', 'raw', 'decimals', 'symbol'},
    'token',
  );
  final contract = token['contract'];
  final contractMatches =
      contract is String &&
      (_isEvm(requirement.coin)
          ? contract.toLowerCase() == requirement.token.contract.toLowerCase()
          : contract == requirement.token.contract);
  if (!contractMatches ||
      token['decimals'] != requirement.token.decimals ||
      token['symbol'] != requirement.token.symbol) {
    throw const FormatException('token metadata mismatch');
  }
  final error = token['error'];
  if (hasError && (error is! String || error.isEmpty)) {
    throw const FormatException('malformed token error');
  }
  return ObservedBalances(
    native: ObservedNativeBalance(
      raw: nativeRaw,
      decimals: requirement.nativeDecimals,
      symbol: requirement.nativeSymbol,
    ),
    tokens: [
      ObservedTokenBalance(
        contract: contract,
        raw: hasError ? null : _nonNegativeBigInt(token['raw'], 'token.raw'),
        decimals: requirement.token.decimals,
        symbol: requirement.token.symbol,
        error: hasError ? error as String : null,
      ),
    ],
  );
}

class FundingAssetResult {
  const FundingAssetResult({
    required this.symbol,
    required this.requiredRaw,
    required this.actualRaw,
  });
  final String symbol;
  final BigInt requiredRaw;
  final BigInt? actualRaw;
  bool get sufficient => actualRaw != null && actualRaw! >= requiredRaw;
  BigInt? get deficitRaw => actualRaw == null
      ? null
      : actualRaw! >= requiredRaw
      ? BigInt.zero
      : requiredRaw - actualRaw!;

  Map<String, Object?> toJson() => {
    'symbol': symbol,
    'requiredRaw': requiredRaw.toString(),
    'actualRaw': actualRaw?.toString(),
    'deficitRaw': deficitRaw?.toString(),
    'sufficient': sufficient,
  };
}

class FundingNetworkResult {
  const FundingNetworkResult({
    required this.requirement,
    required this.address,
    required this.readiness,
    required this.native,
    required this.token,
    this.reason,
  });
  final FundingRequirement requirement;
  final String address;
  final FundingReadiness readiness;
  final FundingAssetResult native;
  final FundingAssetResult token;
  final String? reason;

  Map<String, Object?> toJson() => {
    'network': requirement.networkId,
    'label': requirement.networkLabel,
    'address': address,
    'status': readiness.name,
    'native': native.toJson(),
    'token': {
      ...token.toJson(),
      'contract': requirement.token.contract,
      'decimals': requirement.token.decimals,
    },
    if (reason != null) 'reason': reason,
  };
}

class FundingReport {
  const FundingReport(this.networks);
  final List<FundingNetworkResult> networks;
  FundingReadiness get readiness {
    if (networks.any((row) => row.readiness == FundingReadiness.unavailable)) {
      return FundingReadiness.unavailable;
    }
    if (networks.any((row) => row.readiness == FundingReadiness.insufficient)) {
      return FundingReadiness.insufficient;
    }
    return FundingReadiness.ready;
  }

  Map<String, Object?> toJson() => {
    'status': readiness.name,
    'networks': [for (final row in networks) row.toJson()],
  };
}

FundingReport evaluateE2eFunding({
  required E2eFundingAddresses addresses,
  required FundingPortfolio portfolio,
  List<FundingRequirement>? requirements,
}) {
  final rows = <FundingNetworkResult>[];
  for (final requirement in requirements ?? e2eFundingRequirements) {
    final address = addresses.forCoin(requirement.coin);
    final balances = portfolio.balances[requirement.coin];
    if (portfolio.failedChains.contains(requirement.coin) || balances == null) {
      rows.add(_unavailable(requirement, address, 'balance_query_unavailable'));
      continue;
    }
    final tokenMatches = balances.tokens
        .where((row) {
          final contractMatches = _isEvm(requirement.coin)
              ? row.contract.toLowerCase() ==
                    requirement.token.contract.toLowerCase()
              : row.contract == requirement.token.contract;
          return contractMatches &&
              row.symbol == requirement.token.symbol &&
              row.decimals == requirement.token.decimals;
        })
        .toList(growable: false);
    if (tokenMatches.length != 1 ||
        tokenMatches.single.error != null ||
        tokenMatches.single.raw == null) {
      rows.add(_unavailable(requirement, address, 'token_balance_unavailable'));
      continue;
    }
    final native = FundingAssetResult(
      symbol: requirement.nativeSymbol,
      requiredRaw: requirement.nativeTargetRaw,
      actualRaw: balances.native.raw,
    );
    final token = FundingAssetResult(
      symbol: requirement.token.symbol,
      requiredRaw: requirement.tokenTargetRaw,
      actualRaw: tokenMatches.single.raw,
    );
    rows.add(
      FundingNetworkResult(
        requirement: requirement,
        address: address,
        readiness: native.sufficient && token.sufficient
            ? FundingReadiness.ready
            : FundingReadiness.insufficient,
        native: native,
        token: token,
      ),
    );
  }
  return FundingReport(List.unmodifiable(rows));
}

FundingNetworkResult _unavailable(
  FundingRequirement requirement,
  String address,
  String reason,
) => FundingNetworkResult(
  requirement: requirement,
  address: address,
  readiness: FundingReadiness.unavailable,
  native: FundingAssetResult(
    symbol: requirement.nativeSymbol,
    requiredRaw: requirement.nativeTargetRaw,
    actualRaw: null,
  ),
  token: FundingAssetResult(
    symbol: requirement.token.symbol,
    requiredRaw: requirement.tokenTargetRaw,
    actualRaw: null,
  ),
  reason: reason,
);

Map<Object?, Object?> _map(Object? value, String label) {
  if (value is! Map) throw FormatException('$label must be an object');
  return value;
}

void _exactKeys(Map<Object?, Object?> value, Set<String> keys, String label) {
  if (value.length != keys.length ||
      value.keys.any((key) => key is! String || !keys.contains(key))) {
    throw FormatException('$label has unknown or missing fields');
  }
}

BigInt _nonNegativeBigInt(Object? value, String label) {
  if (value is! String || !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(value)) {
    throw FormatException('$label must be a canonical non-negative integer');
  }
  return BigInt.parse(value);
}

bool _isEvm(FundingCoin coin) => switch (coin) {
  FundingCoin.eth ||
  FundingCoin.polygon ||
  FundingCoin.base ||
  FundingCoin.arbitrum ||
  FundingCoin.avalanche ||
  FundingCoin.bnb => true,
  FundingCoin.tron || FundingCoin.solana => false,
};

final _evmPattern = RegExp(r'^0x[0-9a-fA-F]{40}$');
const _base58Alphabet =
    '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

List<int>? _decodeBase58(String value) {
  if (value.isEmpty) return null;
  var decoded = BigInt.zero;
  for (final unit in value.codeUnits) {
    final digit = _base58Alphabet.indexOf(String.fromCharCode(unit));
    if (digit < 0) return null;
    decoded = decoded * BigInt.from(58) + BigInt.from(digit);
  }
  final bytes = <int>[];
  while (decoded > BigInt.zero) {
    bytes.add((decoded & BigInt.from(0xff)).toInt());
    decoded >>= 8;
  }
  for (var i = 0; i < value.length && value.codeUnitAt(i) == 0x31; i++) {
    bytes.add(0);
  }
  return bytes.reversed.toList(growable: false);
}

bool _isTronAddress(String value) {
  final decoded = _decodeBase58(value);
  if (decoded == null || decoded.length != 25 || decoded.first != 0x41) {
    return false;
  }
  final payload = decoded.sublist(0, 21);
  final checksum = sha256.convert(sha256.convert(payload).bytes).bytes;
  for (var index = 0; index < 4; index++) {
    if (decoded[21 + index] != checksum[index]) return false;
  }
  return true;
}

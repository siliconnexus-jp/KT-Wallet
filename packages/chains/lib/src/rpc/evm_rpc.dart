import 'transport.dart';

/// Inclusion evidence returned by `eth_getTransactionReceipt` after every
/// field needed to bind it to the requested transaction has been validated.
class EvmReceiptEvidence {
  const EvmReceiptEvidence({
    required this.transactionHash,
    required this.blockHash,
    required this.blockNumber,
    required this.transactionIndex,
    required this.succeeded,
  });

  final String transactionHash;
  final String blockHash;
  final BigInt blockNumber;
  final BigInt transactionIndex;
  final bool succeeded;
}

final RegExp _evmHashPattern = RegExp(r'^0x[0-9a-fA-F]{64}$');
final RegExp _evmQuantityPattern = RegExp(
  r'^0x(?:0|[1-9a-fA-F][0-9a-fA-F]{0,63})$',
);

/// Validates that [receipt] is complete inclusion evidence for
/// [expectedTransactionHash].
///
/// A receipt status alone is not enough: a stale, malformed, or misrouted RPC
/// response must never confirm a different local transaction. Error messages
/// deliberately omit provider-controlled field values.
EvmReceiptEvidence parseEvmReceiptEvidence(
  Map<Object?, Object?> receipt, {
  required String expectedTransactionHash,
}) {
  if (!_evmHashPattern.hasMatch(expectedTransactionHash)) {
    throw RpcException('invalid expected EVM transaction hash');
  }
  final transactionHash = receipt['transactionHash'];
  if (transactionHash is! String ||
      !_evmHashPattern.hasMatch(transactionHash) ||
      transactionHash.toLowerCase() != expectedTransactionHash.toLowerCase()) {
    throw RpcException('malformed EVM receipt transaction hash');
  }
  final blockHash = receipt['blockHash'];
  if (blockHash is! String || !_evmHashPattern.hasMatch(blockHash)) {
    throw RpcException('malformed EVM receipt block hash');
  }
  final blockNumber = _parseEvmReceiptQuantity(
    receipt['blockNumber'],
    'block number',
  );
  final transactionIndex = _parseEvmReceiptQuantity(
    receipt['transactionIndex'],
    'transaction index',
  );
  final succeeded = switch (receipt['status']) {
    '0x1' => true,
    '0x0' => false,
    _ => throw RpcException('malformed EVM receipt status'),
  };
  return EvmReceiptEvidence(
    transactionHash: transactionHash,
    blockHash: blockHash,
    blockNumber: blockNumber,
    transactionIndex: transactionIndex,
    succeeded: succeeded,
  );
}

BigInt _parseEvmReceiptQuantity(Object? value, String field) {
  if (value is! String || !_evmQuantityPattern.hasMatch(value)) {
    throw RpcException('malformed EVM receipt $field');
  }
  return BigInt.parse(value.substring(2), radix: 16);
}

/// Slow / standard / fast EVM fee tiers (EIP-1559).
class GasFeeEstimate {
  const GasFeeEstimate({
    required this.slow,
    required this.standard,
    required this.fast,
  });
  final GasFeeEstimateTier slow;
  final GasFeeEstimateTier standard;
  final GasFeeEstimateTier fast;
}

/// Ethereum / Polygon JSON-RPC client (detailed-design.md §4.3). Query results
/// are parsed here; the concrete network transport is injected.
class EvmRpc {
  EvmRpc({required this.url, required this.transport});
  final String url;
  final JsonRpcTransport transport;

  int _id = 0;

  Future<Object?> _call(String method, List<Object?> params) async {
    final resp = await transport.post(url, {
      'jsonrpc': '2.0',
      'id': ++_id,
      'method': method,
      'params': params,
    });
    if (resp is! Map) throw RpcException('malformed response');
    if (resp['error'] != null) {
      final err = resp['error'];
      final code = err is Map && err['code'] is int ? err['code'] as int : null;
      throw RpcRejectedException(
        publicRpcRejectionMessage(err is Map ? err['message'] : err),
        code: code,
      );
    }
    return resp['result'];
  }

  static BigInt _hexToBigInt(Object? v) {
    if (v is! String || !v.startsWith('0x')) {
      throw RpcException('expected hex quantity');
    }
    return BigInt.parse(v.substring(2), radix: 16);
  }

  Future<BigInt> getBalance(
    String address, {
    String blockTag = 'latest',
  }) async {
    _requireBlockTag(blockTag);
    return _hexToBigInt(await _call('eth_getBalance', [address, blockTag]));
  }

  Future<BigInt> getBlockNumber() async =>
      _hexToBigInt(await _call('eth_blockNumber', const []));

  Future<int> getNonce(String address) async => getNonceAt(address, 'pending');

  Future<int> getConfirmedNonce(String address) async =>
      getNonceAt(address, 'latest');

  Future<int> getNonceAt(String address, String blockTag) async {
    if (blockTag != 'latest' && blockTag != 'pending') {
      throw ArgumentError.value(blockTag, 'blockTag');
    }
    return _hexToBigInt(
      await _call('eth_getTransactionCount', [address, blockTag]),
    ).toInt();
  }

  /// Returns null when the node no longer knows [hash].
  Future<Map<Object?, Object?>?> getTransactionByHash(String hash) async {
    final result = await _call('eth_getTransactionByHash', [hash]);
    if (result == null) return null;
    if (result is! Map) throw RpcException('malformed transaction response');
    return result;
  }

  /// Returns null until the transaction is mined (or when it is unknown).
  Future<Map<Object?, Object?>?> getTransactionReceipt(String hash) async {
    final result = await _call('eth_getTransactionReceipt', [hash]);
    if (result == null) return null;
    if (result is! Map) throw RpcException('malformed receipt response');
    return result;
  }

  Future<BigInt> estimateGas({
    required String from,
    required String to,
    required BigInt value,
    required String data,
  }) async => _hexToBigInt(
    await _call('eth_estimateGas', [
      {
        'from': from,
        'to': to,
        'value': '0x${value.toRadixString(16)}',
        'data': data,
      },
    ]),
  );

  /// Executes the exact transfer call against the node's pending state.
  ///
  /// A successful response may be `0x` (native transfers and non-standard
  /// ERC-20 contracts) or ABI-encoded return data. RPC execution errors are
  /// surfaced as [RpcException] and must stop signing.
  Future<String> call({
    required String from,
    required String to,
    required BigInt value,
    required String data,
    String blockTag = 'pending',
  }) async {
    if (blockTag != 'latest' && blockTag != 'pending') {
      throw ArgumentError.value(blockTag, 'blockTag');
    }
    final result = await _call('eth_call', [
      {
        'from': from,
        'to': to,
        'value': '0x${value.toRadixString(16)}',
        'data': data,
      },
      blockTag,
    ]);
    if (result is! String ||
        !result.startsWith('0x') ||
        result.length.isOdd ||
        !RegExp(r'^[0-9a-fA-F]*$').hasMatch(result.substring(2))) {
      throw RpcException('malformed eth_call result');
    }
    return result;
  }

  /// ERC-20 balanceOf via eth_call.
  Future<BigInt> erc20Balance(
    String contract,
    String owner, {
    String blockTag = 'latest',
  }) async {
    _requireBlockTag(blockTag);
    // balanceOf(address) selector 70a08231 + padded owner.
    final data = '0x70a08231${'0' * 24}${_strip0x(owner)}';
    return _hexToBigInt(
      await _call('eth_call', [
        {'to': contract, 'data': data},
        blockTag,
      ]),
    );
  }

  Future<String> sendRawTransaction(String signedHex) async {
    final result = await _call('eth_sendRawTransaction', [signedHex]);
    if (result is! String) throw RpcException('no tx hash returned');
    return result;
  }

  /// Estimates 1559 fees from feeHistory percentiles (slow/standard/fast).
  Future<GasFeeEstimate> estimateFees() async {
    final history = await _call('eth_feeHistory', [
      '0x5',
      'latest',
      [25, 50, 90],
    ]);
    if (history is! Map) throw RpcException('bad feeHistory');
    final rawBase = history['baseFeePerGas'];
    final rawRewards = history['reward'];
    if (rawBase is! List || rawBase.isEmpty || rawRewards is! List) {
      throw RpcException('malformed feeHistory');
    }
    final baseFees = rawBase.map(_hexToBigInt).toList();
    final rewards = rawRewards.map((r) {
      if (r is! List || r.length < 3) {
        throw RpcException('malformed feeHistory reward row');
      }
      return r.map(_hexToBigInt).toList();
    }).toList();
    if (rewards.isEmpty) throw RpcException('empty feeHistory reward');
    // Use the latest base fee and the mean reward per percentile.
    final baseFee = baseFees.last;
    BigInt meanReward(int idx) {
      final vals = rewards.map((r) => r[idx]).toList();
      final sum = vals.fold(BigInt.zero, (a, b) => a + b);
      return sum ~/ BigInt.from(vals.length);
    }

    GasFeeEstimateTier tier(int idx) {
      final tip = meanReward(idx);
      return GasFeeEstimateTier(
        maxPriorityFeePerGas: tip,
        maxFeePerGas: baseFee + tip,
      );
    }

    return GasFeeEstimate(slow: tier(0), standard: tier(1), fast: tier(2));
  }

  static String _strip0x(String s) => s.startsWith('0x') ? s.substring(2) : s;

  static void _requireBlockTag(String blockTag) {
    if (blockTag != 'latest' && blockTag != 'pending') {
      throw ArgumentError.value(blockTag, 'blockTag');
    }
  }
}

/// One EVM fee tier.
class GasFeeEstimateTier {
  const GasFeeEstimateTier({
    required this.maxPriorityFeePerGas,
    required this.maxFeePerGas,
  });
  final BigInt maxPriorityFeePerGas;
  final BigInt maxFeePerGas;
}

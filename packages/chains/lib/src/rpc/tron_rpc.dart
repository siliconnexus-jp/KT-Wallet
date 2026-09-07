import '../address.dart';
import '../base58.dart';
import 'transport.dart';

final RegExp _tronTransactionIdPattern = RegExp(r'^[0-9a-fA-F]{64}$');
const _tronReceiptResults = {
  'SUCCESS',
  'REVERT',
  'BAD_JUMP_DESTINATION',
  'OUT_OF_MEMORY',
  'PRECOMPILED_CONTRACT',
  'STACK_TOO_SMALL',
  'STACK_TOO_LARGE',
  'ILLEGAL_OPERATION',
  'STACK_OVERFLOW',
  'OUT_OF_ENERGY',
  'OUT_OF_TIME',
  'JVM_STACK_OVER_FLOW',
  'TRANSFER_FAILED',
  'INVALID_CODE',
};

/// Complete inclusion evidence returned by
/// `/wallet/gettransactioninfobyid`, bound to the requested transaction.
class TronTransactionEvidence {
  const TronTransactionEvidence({
    required this.transactionId,
    required this.blockNumber,
    required this.result,
    required this.feeSun,
  });

  final String transactionId;
  final int blockNumber;
  final String result;
  final BigInt? feeSun;

  bool get succeeded => result == 'SUCCESS';
}

/// Rejects stale, misrouted, or incomplete TRON transaction information.
/// Provider-controlled field values are deliberately omitted from errors.
TronTransactionEvidence parseTronTransactionEvidence(
  Map<Object?, Object?> response, {
  required String expectedTransactionId,
  Map<Object?, Object?>? transaction,
}) {
  if (!_tronTransactionIdPattern.hasMatch(expectedTransactionId)) {
    throw RpcException('invalid expected TRON transaction id');
  }
  final transactionId = response['id'];
  if (transactionId is! String ||
      !_tronTransactionIdPattern.hasMatch(transactionId) ||
      transactionId.toLowerCase() != expectedTransactionId.toLowerCase()) {
    throw RpcException('malformed TRON transaction id');
  }
  final blockNumber = response['blockNumber'];
  if (blockNumber is! int || blockNumber < 0) {
    throw RpcException('malformed TRON block number');
  }
  final receipt = response['receipt'];
  final receiptResult = receipt is Map ? receipt['result'] : null;
  final topLevelResult = response['result'];
  String normalizedResult;
  if (receiptResult is String && receiptResult.isNotEmpty) {
    normalizedResult = receiptResult.toUpperCase();
  } else if (topLevelResult is String && topLevelResult.isNotEmpty) {
    if (topLevelResult.toUpperCase() != 'FAILED') {
      throw RpcException('unknown TRON transaction result');
    }
    normalizedResult = 'FAILED';
  } else {
    normalizedResult = _parseTronContractResults(
      transaction,
      expectedTransactionId: expectedTransactionId,
    );
  }
  if (normalizedResult != 'FAILED' &&
      !_tronReceiptResults.contains(normalizedResult)) {
    throw RpcException('unknown TRON receipt result');
  }
  final rawFee = response['fee'];
  final feeSun = rawFee == null
      ? null
      : rawFee is int && rawFee >= 0
      ? BigInt.from(rawFee)
      : throw RpcException('malformed TRON transaction fee');
  return TronTransactionEvidence(
    transactionId: transactionId,
    blockNumber: blockNumber,
    result: normalizedResult,
    feeSun: feeSun,
  );
}

String _parseTronContractResults(
  Map<Object?, Object?>? transaction, {
  required String expectedTransactionId,
}) {
  if (transaction == null || transaction.isEmpty) {
    throw RpcException('missing TRON transaction result');
  }
  final transactionId = transaction['txID'];
  if (transactionId is! String ||
      !_tronTransactionIdPattern.hasMatch(transactionId) ||
      transactionId.toLowerCase() != expectedTransactionId.toLowerCase()) {
    throw RpcException('malformed TRON transaction result id');
  }
  final results = transaction['ret'];
  if (results is! List || results.isEmpty) {
    throw RpcException('missing TRON contract result');
  }
  var normalizedResult = 'SUCCESS';
  for (final row in results) {
    final raw = row is Map ? row['contractRet'] : null;
    if (raw is! String || raw.isEmpty) {
      throw RpcException('malformed TRON contract result');
    }
    final result = raw.toUpperCase();
    if (!_tronReceiptResults.contains(result)) {
      throw RpcException('unknown TRON contract result');
    }
    if (result != 'SUCCESS') normalizedResult = result;
  }
  return normalizedResult;
}

/// TRON TronGrid REST client (detailed-design.md §4.3). Broadcast is NOT
/// retried automatically (double-spend safety) — that policy is enforced by
/// the caller; this client just posts once.
class TronRpc {
  TronRpc({required this.baseUrl, required this.transport});
  final String baseUrl;
  final RestTransport transport;

  /// TRX balance in SUN.
  Future<BigInt> getTrxBalance(String address) async =>
      (await getAccountBalances(address)).trx;

  /// Uncached TRX plus an optional authoritative TRC-20 contract balance.
  /// [activated] distinguishes a real zero-balance account from an address
  /// that does not yet exist and will incur TRON's activation fee.
  Future<TronAccountBalances> getAccountBalances(
    String address, {
    String? tokenContract,
  }) async {
    final resp = await transport.getJson('$baseUrl/v1/accounts/$address');
    if (resp is! Map) throw RpcException('bad account response');
    final data = resp['data'];
    if (resp['success'] == false ||
        resp['Error'] != null ||
        resp['error'] != null ||
        data is! List) {
      throw RpcException('bad account response');
    }
    if (data.isEmpty) {
      return TronAccountBalances(
        activated: false,
        trx: BigInt.zero,
        token: tokenContract == null
            ? null
            : await getTrc20Balance(address, tokenContract),
      );
    }
    final account = data.first;
    if (account is! Map) throw RpcException('bad account entry');
    final balance = account['balance'];
    // Absent balance = 0 (valid for a fresh account); a present-but-non-int
    // value is a malformed response, not a zero balance.
    if (balance != null && balance is! int) {
      throw RpcException('non-integer balance');
    }
    // A smart contract can credit a TRC-20 mapping before the recipient has a
    // native TRON account object. `/v1/accounts/{address}` then returns an
    // empty data list even though balanceOf(address) is non-zero. The contract
    // call is therefore the authoritative token balance source.
    final token = tokenContract == null
        ? null
        : await getTrc20Balance(address, tokenContract);
    return TronAccountBalances(
      activated: true,
      trx: balance == null ? BigInt.zero : BigInt.from(balance as int),
      token: token,
    );
  }

  /// Reads one TRC-20 balance from the contract's authoritative mapping.
  ///
  /// The response is bound back to the exact holder, contract and calldata;
  /// an unrelated/stale constant-call response is never accepted as money.
  Future<BigInt> getTrc20Balance(String holder, String contract) async {
    final holderWord = _tronAddressWord(holder, 'holder');
    _tronAddressWord(contract, 'contract');
    final parameter = '${'0' * 24}$holderWord';
    final callData = '70a08231$parameter';
    final response = await transport
        .postJson('$baseUrl/wallet/triggerconstantcontract', {
          'owner_address': holder,
          'contract_address': contract,
          'function_selector': 'balanceOf(address)',
          'parameter': parameter,
          'visible': true,
        });
    return _parseBoundTrc20Balance(
      response,
      holder: holder,
      contract: contract,
      callData: callData,
    );
  }

  /// Full-node confirmation result for [txId], or null while the node does not
  /// know it. This bypasses account-history indexing.
  Future<TronTransactionEvidence?> transactionEvidence(String txId) async {
    final resp = await transport.postJson(
      '$baseUrl/wallet/gettransactioninfobyid',
      {'value': txId},
    );
    if (resp is! Map) throw RpcException('bad transaction info response');
    if (resp.isEmpty) return null;
    Map<Object?, Object?>? transaction;
    final receipt = resp['receipt'];
    final receiptResult = receipt is Map ? receipt['result'] : null;
    final topLevelResult = resp['result'];
    if ((receiptResult is! String || receiptResult.isEmpty) &&
        (topLevelResult is! String || topLevelResult.isEmpty)) {
      final tx = await transport.postJson(
        '$baseUrl/wallet/gettransactionbyid',
        {'value': txId},
      );
      if (tx is! Map) throw RpcException('bad transaction response');
      transaction = tx;
    }
    return parseTronTransactionEvidence(
      resp,
      expectedTransactionId: txId,
      transaction: transaction,
    );
  }

  /// Full-node confirmation result for [txId], or null while the node does not
  /// know it. System transfers whose receipt omits the protobuf default result
  /// are verified against the same transaction's `ret.contractRet` evidence.
  Future<bool?> transactionSucceeded(String txId) async {
    return (await transactionEvidence(txId))?.succeeded;
  }

  /// Latest block ref (refBlockBytes/refBlockHash) for transaction expiration.
  Future<TronBlockRef> getNowBlock() async {
    final resp = await transport.postJson('$baseUrl/wallet/getnowblock', {});
    if (resp is! Map) throw RpcException('bad block');
    final blockId = resp['blockID'];
    final header = resp['block_header'];
    final raw = header is Map ? header['raw_data'] : null;
    if (raw is! Map) throw RpcException('bad block header');
    final number = raw['number'];
    final timestamp = raw['timestamp'];
    if (number is! int ||
        timestamp is! int ||
        blockId is! String ||
        blockId.length != 64) {
      throw RpcException('missing block fields');
    }
    return TronBlockRef(number: number, blockId: blockId, timestamp: timestamp);
  }

  /// Reads the owner's current resource allowances and the chain-governed fee
  /// schedule once so every component of one quote uses the same snapshot.
  ///
  /// A TRC-20 quote needs this state for both Energy and Bandwidth. Fetching
  /// the two endpoints independently for each calculation doubles the burst
  /// against TronGrid and can make the second identical resource request hit
  /// the unauthenticated rate limit even though the first one succeeded.
  Future<TronFeeState> getFeeState(String owner) async {
    final responses = await Future.wait<Object?>([
      transport.postJson('$baseUrl/wallet/getaccountresource', {
        'address': owner,
        'visible': true,
      }),
      transport.postJson('$baseUrl/wallet/getchainparameters', {}),
    ]);
    final resources = responses[0];
    final parameters = responses[1];
    if (resources is! Map || parameters is! Map) {
      throw RpcException('TRON resource estimation failed');
    }

    int nonNegative(String key) {
      final value = resources[key];
      if (value == null) return 0;
      if (value is! int || value < 0) {
        throw RpcException('bad TRON resource $key');
      }
      return value;
    }

    final energyLimit = nonNegative('EnergyLimit');
    final energyAvailable = (energyLimit - nonNegative('EnergyUsed'))
        .clamp(0, energyLimit)
        .toInt();
    final netLimit = nonNegative('NetLimit');
    final stakedBandwidth = (netLimit - nonNegative('NetUsed'))
        .clamp(0, netLimit)
        .toInt();
    final freeNetLimit = nonNegative('freeNetLimit');
    final freeBandwidth = (freeNetLimit - nonNegative('freeNetUsed'))
        .clamp(0, freeNetLimit)
        .toInt();

    final chainParameters = parameters['chainParameter'];
    if (chainParameters is! List) {
      throw RpcException('TRON fee schedule unavailable');
    }
    final values = <String, int>{};
    for (final entry in chainParameters) {
      if (entry is Map && entry['key'] is String && entry['value'] is int) {
        values[entry['key'] as String] = entry['value'] as int;
      }
    }
    return TronFeeState(
      energyAvailable: energyAvailable,
      stakedBandwidthAvailable: stakedBandwidth,
      freeBandwidthAvailable: freeBandwidth,
      energyPriceSun: values['getEnergyFee'],
      bandwidthPriceSun: values['getTransactionFee'],
      activationFeeSun: values['getCreateNewAccountFeeInSystemContract'],
      activationBandwidthFeeSun: values['getCreateAccountFee'],
    );
  }

  /// Budgets the full TRC-20 execution, including 20% energy headroom.
  /// TRON applies fee_limit to staked/delegated energy as well as TRX burn;
  /// subtract available energy only when estimating the liquid TRX needed.
  Future<TronEnergyEstimate> estimateTokenEnergy({
    required String owner,
    required String contract,
    required String parameter,
    TronFeeState? feeState,
  }) async {
    final responses = await Future.wait<Object?>([
      transport.postJson('$baseUrl/wallet/triggerconstantcontract', {
        'owner_address': owner,
        'contract_address': contract,
        'function_selector': 'transfer(address,uint256)',
        'parameter': parameter,
        'visible': true,
      }),
      feeState == null ? getFeeState(owner) : Future.value(feeState),
    ]);
    final trigger = responses[0];
    final state = responses[1];
    if (trigger is! Map ||
        trigger['result'] is! Map ||
        (trigger['result'] as Map)['result'] != true ||
        trigger['energy_used'] is! int) {
      throw RpcException('TRON energy estimation failed');
    }
    if (state is! TronFeeState) {
      throw RpcException('TRON resource estimation failed');
    }
    final required = trigger['energy_used'] as int;
    if (required <= 0) throw RpcException('TRON energy estimation failed');
    final available = state.energyAvailable;
    final price = state.energyPriceSun;
    if (price == null || price <= 0) {
      throw RpcException('TRON energy price unavailable');
    }
    final requiredSun = BigInt.from(required) * BigInt.from(price);
    final maxFeeLimit = BigInt.from(15000000000);
    if (requiredSun > maxFeeLimit) {
      throw RpcException('TRON energy requirement exceeds fee limit');
    }
    final feeLimit =
        ((requiredSun * BigInt.from(12) + BigInt.from(9)) ~/ BigInt.from(10))
            .toInt()
            .clamp(1000000, 15000000000);
    return TronEnergyEstimate(
      energyRequired: required,
      energyAvailable: available,
      energyPriceSun: price,
      feeLimitSun: feeLimit,
    );
  }

  /// Computes the maximum Bandwidth burn and optional new-account activation
  /// fee for the exact serialized raw_data. The byte estimate includes one
  /// 65-byte signature, protobuf framing and transaction result headroom.
  /// All prices come from current chain parameters; no static mainnet price is
  /// reused on Nile/Shasta or after a governance update.
  Future<TronBandwidthEstimate> estimateBandwidthFee({
    required String owner,
    required int rawDataLength,
    required bool activatesRecipient,
    TronFeeState? feeState,
  }) async {
    if (rawDataLength <= 0) {
      throw ArgumentError.value(rawDataLength, 'rawDataLength');
    }
    final state = feeState ?? await getFeeState(owner);
    final staked = state.stakedBandwidthAvailable;
    final free = state.freeBandwidthAvailable;
    final unitPrice = state.bandwidthPriceSun;
    final activationFee = state.activationFeeSun;
    final activationBandwidthFee = state.activationBandwidthFeeSun;
    if (unitPrice == null || unitPrice <= 0) {
      throw RpcException('TRON bandwidth price unavailable');
    }
    if (activatesRecipient &&
        (activationFee == null ||
            activationFee <= 0 ||
            activationBandwidthFee == null ||
            activationBandwidthFee <= 0)) {
      throw RpcException('TRON activation fee unavailable');
    }

    // raw_data + protobuf field/length framing + one 65-byte signature +
    // transaction result. Apply another 20% safety margin because the result
    // protobuf is produced by the node rather than the local serializer.
    final framedBytes =
        rawDataLength + _varintLength(rawDataLength) + 1 + 67 + 32;
    final required = (framedBytes * 12 + 9) ~/ 10;
    final bandwidthFee = activatesRecipient
        ? (staked >= required ? 0 : activationBandwidthFee!)
        : (staked + free >= required ? 0 : required * unitPrice);
    return TronBandwidthEstimate(
      estimatedBandwidth: required,
      stakedBandwidthAvailable: staked,
      freeBandwidthAvailable: free,
      bandwidthFeeSun: bandwidthFee,
      activationFeeSun: activatesRecipient ? activationFee! : 0,
    );
  }

  /// Broadcasts a signed transaction. Returns the txid on success.
  ///
  /// Two payload shapes are accepted, and the endpoint follows from the shape:
  ///
  /// * `{"transaction": "<hex>"}` — the full signed `Transaction` protobuf,
  ///   what the wallet-core signers emit. Goes to `/wallet/broadcasthex`,
  ///   which is the ONLY endpoint that takes a serialized transaction. Only
  ///   the `transaction` key is forwarded; TronGrid rejects unknown fields.
  /// * anything else — a complete TronGrid transaction JSON (`raw_data` +
  ///   `raw_data_hex` + `signature`), posted verbatim to
  ///   `/wallet/broadcasttransaction`. That endpoint dereferences `raw_data`
  ///   unconditionally, so a body without it comes back as a bare
  ///   NullPointerException.
  Future<String> broadcast(Object signedTx) async {
    final hexTx = signedTx is Map ? signedTx['transaction'] : null;
    final broadcastHex = hexTx is String;
    final resp = await transport.postJson(
      '$baseUrl/wallet/${broadcastHex ? 'broadcasthex' : 'broadcasttransaction'}',
      broadcastHex ? {'transaction': hexTx} : signedTx,
    );
    if (resp is! Map) throw RpcException('bad broadcast response');
    final txid = resp['txid'] ?? (signedTx is Map ? signedTx['txID'] : null);
    if (resp['result'] == true && txid is String) {
      return txid;
    }
    // TronGrid reports node-level failures as a top-level `Error` string and
    // contract-level ones as `code` + hex-encoded `message`; without `Error`
    // in this chain the reason came back as a bare `null`, hiding the cause.
    final duplicate = resp['code'] == 'DUP_TRANSACTION_ERROR';
    final message = duplicate
        ? publicRpcRejectionMessage(RpcRejectionKind.alreadyKnown)
        : resp['message'] ?? resp['Error'] ?? resp['code'];
    throw RpcRejectedException(publicRpcRejectionMessage(message));
  }
}

class TronBlockRef {
  const TronBlockRef({
    required this.number,
    required this.blockId,
    required this.timestamp,
  });
  final int number;
  final String blockId;
  final int timestamp;
}

class TronAccountBalances {
  const TronAccountBalances({
    required this.activated,
    required this.trx,
    this.token,
  });

  final bool activated;
  final BigInt trx;
  final BigInt? token;
}

class TronEnergyEstimate {
  const TronEnergyEstimate({
    required this.energyRequired,
    required this.energyAvailable,
    required this.energyPriceSun,
    required this.feeLimitSun,
  });

  final int energyRequired;
  final int energyAvailable;
  final int energyPriceSun;
  final int feeLimitSun;

  /// Liquid TRX exposure within the budget, assuming the current resource
  /// snapshot remains available. Rented/delegated energy reduces this value,
  /// never [feeLimitSun]. A new quote must be obtained before signing.
  BigInt get maximumBurnSun {
    final burn =
        BigInt.from(feeLimitSun) -
        BigInt.from(energyAvailable) * BigInt.from(energyPriceSun);
    return burn.isNegative ? BigInt.zero : burn;
  }
}

/// One internally consistent resource and governance-fee snapshot used by a
/// single TRON transfer quote. Nullable prices remain fail-closed in the
/// estimator that actually needs them, so a native transfer does not require
/// an unrelated Energy parameter and a token transfer cannot invent one.
class TronFeeState {
  const TronFeeState({
    required this.energyAvailable,
    required this.stakedBandwidthAvailable,
    required this.freeBandwidthAvailable,
    required this.energyPriceSun,
    required this.bandwidthPriceSun,
    required this.activationFeeSun,
    required this.activationBandwidthFeeSun,
  });

  final int energyAvailable;
  final int stakedBandwidthAvailable;
  final int freeBandwidthAvailable;
  final int? energyPriceSun;
  final int? bandwidthPriceSun;
  final int? activationFeeSun;
  final int? activationBandwidthFeeSun;
}

class TronBandwidthEstimate {
  const TronBandwidthEstimate({
    required this.estimatedBandwidth,
    required this.stakedBandwidthAvailable,
    required this.freeBandwidthAvailable,
    required this.bandwidthFeeSun,
    required this.activationFeeSun,
  });

  final int estimatedBandwidth;
  final int stakedBandwidthAvailable;
  final int freeBandwidthAvailable;
  final int bandwidthFeeSun;
  final int activationFeeSun;

  BigInt get maximumFeeSun => BigInt.from(bandwidthFeeSun + activationFeeSun);
}

String _tronAddressWord(String address, String label) {
  final validated = Addresses.validate(Chain.tron, address);
  if (!validated.isValid) throw RpcException('invalid TRON $label address');
  final decoded = base58Decode(validated.normalized!);
  if (decoded.length != 25 || decoded.first != 0x41) {
    throw RpcException('invalid TRON $label address');
  }
  return decoded
      .sublist(1, 21)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();
}

BigInt _parseBoundTrc20Balance(
  Object? raw, {
  required String holder,
  required String contract,
  required String callData,
}) {
  final response = _tronExtensibleMap(raw, const {
    'transaction',
    'constant_result',
    'result',
  });
  final result = _tronExtensibleMap(response['result'], const {'result'});
  if (result['result'] != true) {
    throw RpcException('TRC-20 balance call failed');
  }

  final transaction = _tronExtensibleMap(response['transaction'], const {
    'raw_data',
    'visible',
  });
  if (transaction['visible'] != true) {
    throw RpcException('unbound TRC-20 balance response');
  }
  final rawData = _tronExtensibleMap(transaction['raw_data'], const {
    'contract',
  });
  final calls = rawData['contract'];
  if (calls is! List || calls.length != 1) {
    throw RpcException('unbound TRC-20 balance response');
  }
  final call = _tronExtensibleMap(calls.single, const {'parameter', 'type'});
  if (call['type'] != 'TriggerSmartContract') {
    throw RpcException('unbound TRC-20 balance response');
  }
  final parameter = _tronExtensibleMap(call['parameter'], const {
    'value',
    'type_url',
  });
  if (parameter['type_url'] !=
      'type.googleapis.com/protocol.TriggerSmartContract') {
    throw RpcException('unbound TRC-20 balance response');
  }
  final value = _tronExtensibleMap(parameter['value'], const {
    'owner_address',
    'contract_address',
    'data',
  });
  if (value['owner_address'] != holder ||
      value['contract_address'] != contract ||
      value['data'] != callData) {
    throw RpcException('unbound TRC-20 balance response');
  }

  final words = response['constant_result'];
  if (words is! List || words.length != 1) {
    throw RpcException('malformed TRC-20 balance result');
  }
  final word = words.single;
  if (word is! String || !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(word)) {
    throw RpcException('malformed TRC-20 balance result');
  }
  return BigInt.parse(word, radix: 16);
}

Map<Object?, Object?> _tronExtensibleMap(Object? raw, Set<String> consumed) {
  if (raw is! Map || raw.keys.any((key) => key is! String)) {
    throw RpcException('malformed TRON response');
  }
  for (final key in raw.keys.cast<String>()) {
    for (final expected in consumed) {
      if (key != expected && key.toLowerCase() == expected.toLowerCase()) {
        throw RpcException('ambiguous TRON response');
      }
    }
  }
  for (final required in consumed) {
    if (!raw.containsKey(required)) {
      throw RpcException('incomplete TRON response');
    }
  }
  return raw.cast<Object?, Object?>();
}

int _varintLength(int value) {
  var length = 1;
  var remaining = value;
  while (remaining >= 0x80) {
    remaining >>= 7;
    length++;
  }
  return length;
}

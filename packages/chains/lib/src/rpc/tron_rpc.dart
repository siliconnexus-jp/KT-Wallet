import 'transport.dart';

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

  /// Uncached TRX and optional TRC-20 balances from one account response.
  /// [activated] distinguishes a real zero-balance account from an address
  /// that does not yet exist and will incur TRON's activation fee.
  Future<TronAccountBalances> getAccountBalances(
    String address, {
    String? tokenContract,
  }) async {
    final resp = await transport.getJson('$baseUrl/v1/accounts/$address');
    if (resp is! Map) throw RpcException('bad account response');
    final data = resp['data'];
    if (data is! List || data.isEmpty) {
      return TronAccountBalances(activated: false, trx: BigInt.zero);
    }
    final account = data.first;
    if (account is! Map) throw RpcException('bad account entry');
    final balance = account['balance'];
    // Absent balance = 0 (valid for a fresh account); a present-but-non-int
    // value is a malformed response, not a zero balance.
    if (balance != null && balance is! int) {
      throw RpcException('non-integer balance');
    }
    BigInt? token;
    if (tokenContract != null) {
      token = BigInt.zero;
      final rows = account['trc20'];
      if (rows != null && rows is! List) {
        throw RpcException('bad trc20 balance list');
      }
      if (rows is List) {
        for (final row in rows) {
          if (row is! Map || !row.containsKey(tokenContract)) continue;
          final raw = row[tokenContract];
          if (raw is! String || !RegExp(r'^[0-9]+$').hasMatch(raw)) {
            throw RpcException('bad trc20 balance');
          }
          token = BigInt.parse(raw);
          break;
        }
      }
    }
    return TronAccountBalances(
      activated: true,
      trx: balance == null ? BigInt.zero : BigInt.from(balance as int),
      token: token,
    );
  }

  /// Full-node confirmation result for [txId], or null while the node does not
  /// know it. This bypasses account-history indexing.
  Future<bool?> transactionSucceeded(String txId) async {
    final resp = await transport.postJson(
      '$baseUrl/wallet/gettransactioninfobyid',
      {'value': txId},
    );
    if (resp is! Map) throw RpcException('bad transaction info response');
    if (resp.isEmpty) return null;
    final receipt = resp['receipt'];
    final result = receipt is Map ? receipt['result'] : resp['result'];
    if (result == null || '$result'.isEmpty) {
      // A non-empty info object without an error result is a successful
      // included native transaction.
      return resp['id'] is String && (resp['id'] as String).isNotEmpty;
    }
    return '$result'.toUpperCase() == 'SUCCESS';
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

  /// Estimates the TRX that may be burned by a TRC-20 contract call. The
  /// returned feeLimit includes a 20% headroom over the node's energy result
  /// after subtracting the account's currently available staked energy.
  Future<TronEnergyEstimate> estimateTokenEnergy({
    required String owner,
    required String contract,
    required String parameter,
  }) async {
    final responses = await Future.wait<Object?>([
      transport.postJson('$baseUrl/wallet/triggerconstantcontract', {
        'owner_address': owner,
        'contract_address': contract,
        'function_selector': 'transfer(address,uint256)',
        'parameter': parameter,
        'visible': true,
      }),
      transport.postJson('$baseUrl/wallet/getaccountresource', {
        'address': owner,
        'visible': true,
      }),
      transport.postJson('$baseUrl/wallet/getchainparameters', {}),
    ]);
    final trigger = responses[0];
    final resources = responses[1];
    final parameters = responses[2];
    if (trigger is! Map ||
        trigger['result'] is! Map ||
        (trigger['result'] as Map)['result'] != true ||
        trigger['energy_used'] is! int) {
      throw RpcException('TRON energy estimation failed');
    }
    if (resources is! Map || parameters is! Map) {
      throw RpcException('TRON resource estimation failed');
    }
    final required = trigger['energy_used'] as int;
    final limit = resources['EnergyLimit'] is int
        ? resources['EnergyLimit'] as int
        : 0;
    final used = resources['EnergyUsed'] is int
        ? resources['EnergyUsed'] as int
        : 0;
    final available = (limit - used).clamp(0, limit).toInt();
    final chainParameters = parameters['chainParameter'];
    if (chainParameters is! List) {
      throw RpcException('TRON energy price unavailable');
    }
    int? price;
    for (final entry in chainParameters) {
      if (entry is Map && entry['key'] == 'getEnergyFee') {
        final value = entry['value'];
        if (value is int) price = value;
      }
    }
    if (price == null || price <= 0) {
      throw RpcException('TRON energy price unavailable');
    }
    final burnEnergy = (required - available).clamp(0, required).toInt();
    // At least 1 TRX prevents nodes rejecting a zero feeLimit when the
    // account currently has enough energy but its resource state races.
    final estimatedSun = burnEnergy * price;
    final feeLimit = ((estimatedSun * 12 + 9) ~/ 10)
        .clamp(1000000, 15000000000)
        .toInt();
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
  }) async {
    if (rawDataLength <= 0) {
      throw ArgumentError.value(rawDataLength, 'rawDataLength');
    }
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
      throw RpcException('TRON bandwidth estimation failed');
    }
    int nonNegative(String key) {
      final value = resources[key];
      if (value == null) return 0;
      if (value is! int || value < 0) {
        throw RpcException('bad TRON resource $key');
      }
      return value;
    }

    final staked = (nonNegative('NetLimit') - nonNegative('NetUsed')).clamp(
      0,
      nonNegative('NetLimit'),
    );
    final free = (nonNegative('freeNetLimit') - nonNegative('freeNetUsed'))
        .clamp(0, nonNegative('freeNetLimit'));
    final chainParameters = parameters['chainParameter'];
    if (chainParameters is! List) {
      throw RpcException('TRON bandwidth price unavailable');
    }
    final values = <String, int>{};
    for (final entry in chainParameters) {
      if (entry is Map && entry['key'] is String && entry['value'] is int) {
        values[entry['key'] as String] = entry['value'] as int;
      }
    }
    final unitPrice = values['getTransactionFee'];
    final activationFee = values['getCreateNewAccountFeeInSystemContract'];
    final activationBandwidthFee = values['getCreateAccountFee'];
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
    final message = resp['message'] ?? resp['Error'] ?? resp['code'];
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

int _varintLength(int value) {
  var length = 1;
  var remaining = value;
  while (remaining >= 0x80) {
    remaining >>= 7;
    length++;
  }
  return length;
}

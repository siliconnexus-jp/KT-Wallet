import 'transport.dart';

/// TRON TronGrid REST client (detailed-design.md §4.3). Broadcast is NOT
/// retried automatically (double-spend safety) — that policy is enforced by
/// the caller; this client just posts once.
class TronRpc {
  TronRpc({required this.baseUrl, required this.transport});
  final String baseUrl;
  final RestTransport transport;

  /// TRX balance in SUN.
  Future<BigInt> getTrxBalance(String address) async {
    final resp = await transport.getJson('$baseUrl/v1/accounts/$address');
    if (resp is! Map) throw RpcException('bad account response');
    final data = resp['data'];
    if (data is! List || data.isEmpty) {
      return BigInt.zero; // unactivated account
    }
    final account = data.first;
    if (account is! Map) throw RpcException('bad account entry');
    final balance = account['balance'];
    // Absent balance = 0 (valid for a fresh account); a present-but-non-int
    // value is a malformed response, not a zero balance.
    if (balance == null) return BigInt.zero;
    if (balance is! int) throw RpcException('non-integer balance');
    return BigInt.from(balance);
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
    if (number is! int || blockId is! String || blockId.length != 64) {
      throw RpcException('missing block fields');
    }
    return TronBlockRef(number: number, blockId: blockId);
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
    final message =
        resp['message'] ?? resp['Error'] ?? resp['code'] ?? 'no reason given';
    throw RpcException('broadcast rejected: $message');
  }
}

class TronBlockRef {
  const TronBlockRef({required this.number, required this.blockId});
  final int number;
  final String blockId;
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

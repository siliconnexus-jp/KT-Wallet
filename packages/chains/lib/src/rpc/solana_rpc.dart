import 'dart:convert';
import 'dart:typed_data';

import '../base58.dart';
import '../solana_tx.dart' show solanaToken2022Program, solanaTokenProgram;
import 'transport.dart';

/// Solana JSON-RPC client (detailed-design.md §4.3).
class SolanaRpc {
  SolanaRpc({required this.url, required this.transport});
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

  /// Lamport balance.
  Future<BigInt> getBalance(String address) async {
    _solanaPublicKey(address, 'balance account');
    final result = await _call('getBalance', [
      address,
      {'commitment': 'confirmed'},
    ]);
    final envelope = _solanaValueEnvelope(result, 'balance');
    return BigInt.from(_u64(envelope['value'], 'balance'));
  }

  /// Sum of all SPL token accounts owned by [owner] for [mint].
  Future<BigInt> getTokenBalance(
    String owner,
    String mint, {
    int? expectedDecimals,
  }) async {
    final accounts = await getTokenAccounts(
      owner,
      mint,
      expectedDecimals: expectedDecimals,
    );
    var total = BigInt.zero;
    for (final account in accounts) {
      total += account.amount;
    }
    return total;
  }

  /// Parsed SPL token accounts owned by [owner] for [mint].
  Future<List<SolanaTokenAccount>> getTokenAccounts(
    String owner,
    String mint, {
    int? expectedDecimals,
  }) async {
    _solanaPublicKey(owner, 'token owner');
    _solanaPublicKey(mint, 'token mint');
    if (expectedDecimals != null &&
        (expectedDecimals < 0 || expectedDecimals > 255)) {
      throw RpcException('bad expected token decimals');
    }
    final result = await _call('getTokenAccountsByOwner', [
      owner,
      {'mint': mint},
      {'encoding': 'jsonParsed', 'commitment': 'confirmed'},
    ]);
    final envelope = _solanaValueEnvelope(result, 'token accounts');
    final value = envelope['value'];
    if (value is! List || value.length > 10000) {
      throw RpcException('bad token account response');
    }
    final accounts = <SolanaTokenAccount>[];
    final seen = <String>{};
    var total = BigInt.zero;
    for (final entry in value) {
      final row = _exactMap(
        entry,
        allowed: const {'account', 'pubkey'},
        required: const {'account', 'pubkey'},
        label: 'token account row',
      );
      final pubkey = _solanaPublicKey(row['pubkey'], 'token account identity');
      if (!seen.add(pubkey)) {
        throw RpcException('duplicate token account identity');
      }
      final account = _parseTokenAccount(
        row['account'],
        requestedOwner: owner,
        requestedMint: mint,
        expectedDecimals: expectedDecimals,
      );
      total += account.amount;
      if (total > _maximumU64) {
        throw RpcException('token account balance overflow');
      }
      accounts.add(account.withAddress(pubkey));
    }
    return List.unmodifiable(accounts);
  }

  /// Latest blockhash together with the last block height at which it remains
  /// valid. Callers that persist a submitted transaction must keep both:
  /// a missing signature is only provably expired after the canonical chain
  /// advances beyond [SolanaLatestBlockhash.lastValidBlockHeight].
  Future<SolanaLatestBlockhash> getLatestBlockhashInfo() async {
    final result = await _call('getLatestBlockhash', [
      {'commitment': 'finalized'},
    ]);
    final envelope = _solanaValueEnvelope(result, 'blockhash');
    final value = _exactMap(
      envelope['value'],
      allowed: const {'blockhash', 'lastValidBlockHeight'},
      required: const {'blockhash', 'lastValidBlockHeight'},
      label: 'blockhash value',
    );
    final blockhash = _solanaPublicKey(value['blockhash'], 'blockhash');
    final lastValidBlockHeight = _u64(
      value['lastValidBlockHeight'],
      'last valid block height',
    );
    return SolanaLatestBlockhash(
      blockhash: blockhash,
      lastValidBlockHeight: lastValidBlockHeight,
    );
  }

  /// Compatibility helper for callers that do not submit/persist a
  /// transaction. Production transfer construction uses
  /// [getLatestBlockhashInfo] so the validity boundary is never discarded.
  Future<String> getLatestBlockhash() async =>
      (await getLatestBlockhashInfo()).blockhash;

  /// Current canonical block height at the requested finalized commitment.
  Future<int> getBlockHeight() async {
    final result = await _call('getBlockHeight', [
      {'commitment': 'finalized'},
    ]);
    return _u64(result, 'block height');
  }

  /// Fee in lamports for the exact serialized message.
  Future<BigInt> getFeeForMessage(Uint8List message) async {
    final result = await _call('getFeeForMessage', [
      base64Encode(message),
      {'commitment': 'confirmed'},
    ]);
    final envelope = _solanaValueEnvelope(result, 'fee');
    final value = envelope['value'];
    if (value == null) throw RpcException('fee unavailable for message');
    return BigInt.from(_u64(value, 'fee'));
  }

  /// Simulates the exact single-signer legacy transaction with a zeroed
  /// signature. Signature verification is disabled, but every instruction,
  /// account, balance and recent blockhash is checked by the node.
  Future<SolanaSimulationResult> simulateMessage(
    Uint8List message, {
    List<String> accountAddresses = const [],
  }) async {
    final transaction = Uint8List.fromList([
      1,
      ...List<int>.filled(64, 0),
      ...message,
    ]);
    final result = await _call('simulateTransaction', [
      base64Encode(transaction),
      {
        'encoding': 'base64',
        'sigVerify': false,
        'replaceRecentBlockhash': false,
        'commitment': 'processed',
        if (accountAddresses.isNotEmpty)
          'accounts': {'encoding': 'base64', 'addresses': accountAddresses},
      },
    ]);
    final envelope = _solanaValueEnvelope(result, 'simulation');
    final value = _exactMap(
      envelope['value'],
      allowed: const {
        'accounts',
        'err',
        'fee',
        'innerInstructions',
        'loadedAccountsDataSize',
        'loadedAddresses',
        'logs',
        'postBalances',
        'postTokenBalances',
        'preBalances',
        'preTokenBalances',
        'replacementBlockhash',
        'returnData',
        'unitsConsumed',
      },
      required: const {'err'},
      label: 'simulation value',
    );
    if (value['err'] != null) {
      throw RpcException('transaction simulation failed');
    }
    if (value['innerInstructions'] != null) {
      throw RpcException('unexpected simulation inner instructions');
    }
    if (value['replacementBlockhash'] != null) {
      throw RpcException('unexpected simulation replacement blockhash');
    }
    _validateSimulationLogs(value['logs']);
    _validateSimulationReturnData(value['returnData']);
    final fee = value['fee'];
    final feeLamports = fee == null
        ? null
        : BigInt.from(_u64(fee, 'simulation fee'));
    _validateLoadedAddresses(value['loadedAddresses']);
    final preBalances = _validateSimulationBalances(
      value['preBalances'],
      'pre balances',
    );
    final postBalances = _validateSimulationBalances(
      value['postBalances'],
      'post balances',
    );
    if ((preBalances == null) != (postBalances == null) ||
        (preBalances != null && preBalances.length != postBalances!.length)) {
      throw RpcException('inconsistent simulation balances');
    }
    _validateTokenBalances(value['preTokenBalances'], 'pre token balances');
    _validateTokenBalances(value['postTokenBalances'], 'post token balances');
    if (value['loadedAccountsDataSize'] case final loadedSize?) {
      final parsed = _u64(loadedSize, 'loaded accounts data size');
      if (parsed > 0xffffffff) {
        throw RpcException('bad loaded accounts data size');
      }
    }
    final lamports = <String, BigInt>{};
    if (accountAddresses.isNotEmpty) {
      final accounts = value['accounts'];
      if (accounts is! List || accounts.length != accountAddresses.length) {
        throw RpcException('simulation account state unavailable');
      }
      for (var i = 0; i < accounts.length; i++) {
        final account = _simulationAccount(accounts[i]);
        lamports[accountAddresses[i]] = BigInt.from(
          _u64(account['lamports'], 'simulation account balance'),
        );
      }
    } else if (value['accounts'] != null) {
      throw RpcException('unexpected simulation account state');
    }
    final units = value['unitsConsumed'];
    return SolanaSimulationResult(
      accountLamports: Map.unmodifiable(lamports),
      feeLamports: feeLamports,
      unitsConsumed: units == null ? null : _u64(units, 'compute units'),
    );
  }

  Future<String> sendTransaction(String base64Tx) async {
    final result = await _call('sendTransaction', [
      base64Tx,
      {'encoding': 'base64'},
    ]);
    if (result is! String) throw RpcException('no signature returned');
    return result;
  }

  /// Confirmation status for a signature, or null if unknown.
  Future<String?> signatureStatus(String signature) async {
    return (await signatureResult(signature))?.confirmationStatus;
  }

  /// Full confirmation result for a signature. [failed] is sourced from the
  /// RPC's `err` field, so callers never mistake an included failed
  /// transaction for a successful confirmation.
  Future<SolanaSignatureStatus?> signatureResult(String signature) async {
    final result = await _call('getSignatureStatuses', [
      [signature],
      {'searchTransactionHistory': true},
    ]);
    final value = result is Map ? result['value'] : null;
    if (value is! List || value.isEmpty) return null;
    final entry = value.first;
    if (entry is! Map) return null;
    final status = entry['confirmationStatus'];
    if (status == null) return null;
    if (status is! String) throw RpcException('bad confirmationStatus');
    return SolanaSignatureStatus(
      confirmationStatus: status,
      failed: entry['err'] != null,
    );
  }
}

class SolanaLatestBlockhash {
  const SolanaLatestBlockhash({
    required this.blockhash,
    required this.lastValidBlockHeight,
  });

  final String blockhash;
  final int lastValidBlockHeight;
}

class SolanaSignatureStatus {
  const SolanaSignatureStatus({
    required this.confirmationStatus,
    required this.failed,
  });

  final String confirmationStatus;
  final bool failed;
}

class SolanaSimulationResult {
  const SolanaSimulationResult({
    required this.accountLamports,
    this.feeLamports,
    this.unitsConsumed,
  });

  final Map<String, BigInt> accountLamports;
  final BigInt? feeLamports;
  final int? unitsConsumed;
}

class SolanaTokenAccount {
  const SolanaTokenAccount({
    required this.address,
    required this.amount,
    required this.decimals,
    required this.state,
  });

  final String address;
  final BigInt amount;
  final int decimals;
  final SolanaTokenAccountState state;

  SolanaTokenAccount withAddress(String value) => SolanaTokenAccount(
    address: value,
    amount: amount,
    decimals: decimals,
    state: state,
  );
}

enum SolanaTokenAccountState { initialized, frozen }

final BigInt _maximumU64 = (BigInt.one << 64) - BigInt.one;

Map<Object?, Object?> _solanaValueEnvelope(Object? raw, String label) {
  final envelope = _exactMap(
    raw,
    allowed: const {'context', 'value'},
    required: const {'context', 'value'},
    label: '$label response',
  );
  final context = _exactMap(
    envelope['context'],
    allowed: const {'apiVersion', 'slot'},
    required: const {'slot'},
    label: '$label context',
  );
  _u64(context['slot'], '$label context slot');
  if (context['apiVersion'] case final Object? version?) {
    if (version is! String ||
        version.isEmpty ||
        version.length > 64 ||
        version.codeUnits.any((code) => code < 0x20 || code == 0x7f)) {
      throw RpcException('bad $label context version');
    }
  }
  return envelope;
}

Map<Object?, Object?> _exactMap(
  Object? raw, {
  required Set<String> allowed,
  required Set<String> required,
  required String label,
}) {
  if (raw is! Map ||
      raw.keys.any((key) => key is! String || !allowed.contains(key)) ||
      required.any((key) => !raw.containsKey(key))) {
    throw RpcException('bad $label');
  }
  return raw;
}

int _u64(Object? raw, String label) {
  if (raw is! int || raw < 0 || BigInt.from(raw) > _maximumU64) {
    throw RpcException('bad $label');
  }
  return raw;
}

SolanaTokenAccount _parseTokenAccount(
  Object? raw, {
  required String requestedOwner,
  required String requestedMint,
  required int? expectedDecimals,
}) {
  final account = _exactMap(
    raw,
    allowed: const {
      'data',
      'executable',
      'lamports',
      'owner',
      'rentEpoch',
      'space',
    },
    required: const {'data', 'executable', 'lamports', 'owner', 'rentEpoch'},
    label: 'token account',
  );
  if (account['executable'] != false) {
    throw RpcException('bad executable token account');
  }
  _u64(account['lamports'], 'token account lamports');
  _unsignedJsonNumber(account['rentEpoch'], 'token account rent epoch');
  final accountSpace = account['space'] == null
      ? null
      : _u64(account['space'], 'token account space');
  final tokenProgram = _solanaPublicKey(
    account['owner'],
    'token program owner',
  );
  if (tokenProgram != solanaTokenProgram &&
      tokenProgram != solanaToken2022Program) {
    throw RpcException('unexpected token program owner');
  }

  final data = _exactMap(
    account['data'],
    allowed: const {'parsed', 'program', 'space'},
    required: const {'parsed', 'program'},
    label: 'parsed token account data',
  );
  final parsedProgram = data['program'];
  if (parsedProgram is! String ||
      (parsedProgram != 'spl-token' && parsedProgram != 'spl-token-2022') ||
      (tokenProgram == solanaTokenProgram && parsedProgram != 'spl-token')) {
    throw RpcException('token program identity mismatch');
  }
  final dataSpace = data['space'] == null
      ? null
      : _u64(data['space'], 'parsed token account space');
  if (accountSpace != null && dataSpace != null && accountSpace != dataSpace) {
    throw RpcException('token account space mismatch');
  }
  final parsed = _exactMap(
    data['parsed'],
    allowed: const {'info', 'type'},
    required: const {'info', 'type'},
    label: 'parsed token account',
  );
  if (parsed['type'] != 'account') {
    throw RpcException('unexpected parsed token account type');
  }
  final info = _tokenInfoMap(parsed['info']);
  if (info['isNative'] is! bool) {
    throw RpcException('bad native token flag');
  }
  if (_solanaPublicKey(info['mint'], 'token account mint') != requestedMint) {
    throw RpcException('token mint identity mismatch');
  }
  if (_solanaPublicKey(info['owner'], 'token account owner') !=
      requestedOwner) {
    throw RpcException('token owner identity mismatch');
  }
  final state = switch (info['state']) {
    'initialized' => SolanaTokenAccountState.initialized,
    'frozen' => SolanaTokenAccountState.frozen,
    _ => throw RpcException('bad token account state'),
  };
  final amount = _parseTokenAmount(
    info['tokenAmount'],
    expectedDecimals: expectedDecimals,
  );
  return SolanaTokenAccount(
    address: '',
    amount: amount.$1,
    decimals: amount.$2,
    state: state,
  );
}

Map<Object?, Object?> _tokenInfoMap(Object? raw) {
  if (raw is! Map || raw.length > 64 || raw.keys.any((key) => key is! String)) {
    throw RpcException('bad token account info');
  }
  const consumed = {'isNative', 'mint', 'owner', 'state', 'tokenAmount'};
  for (final key in raw.keys.cast<String>()) {
    for (final canonical in consumed) {
      if (key.toLowerCase() == canonical.toLowerCase() && key != canonical) {
        throw RpcException('ambiguous token account info');
      }
    }
  }
  if (consumed.any((key) => !raw.containsKey(key))) {
    throw RpcException('incomplete token account info');
  }
  return raw;
}

(BigInt, int) _parseTokenAmount(Object? raw, {required int? expectedDecimals}) {
  final value = _exactMap(
    raw,
    allowed: const {'amount', 'decimals', 'uiAmount', 'uiAmountString'},
    required: const {'amount', 'decimals', 'uiAmount', 'uiAmountString'},
    label: 'token amount',
  );
  final amountRaw = value['amount'];
  if (amountRaw is! String ||
      amountRaw.isEmpty ||
      amountRaw.length > 20 ||
      !RegExp(r'^(0|[1-9][0-9]*)$').hasMatch(amountRaw)) {
    throw RpcException('bad token amount');
  }
  final amount = BigInt.parse(amountRaw);
  if (amount > _maximumU64) throw RpcException('bad token amount');
  final decimals = value['decimals'];
  if (decimals is! int || decimals < 0 || decimals > 255) {
    throw RpcException('bad token decimals');
  }
  if (expectedDecimals != null && decimals != expectedDecimals) {
    throw RpcException('token decimals mismatch');
  }
  final uiAmount = value['uiAmount'];
  if (uiAmount != null &&
      (uiAmount is! num || !uiAmount.isFinite || uiAmount < 0)) {
    throw RpcException('bad UI token amount');
  }
  final uiAmountString = value['uiAmountString'];
  if (uiAmountString is! String ||
      uiAmountString != _canonicalTokenAmount(amount, decimals)) {
    throw RpcException('inconsistent UI token amount');
  }
  return (amount, decimals);
}

String _canonicalTokenAmount(BigInt amount, int decimals) {
  var digits = amount.toString();
  if (decimals == 0) return digits;
  if (digits.length <= decimals) {
    digits = '${'0' * (decimals - digits.length + 1)}$digits';
  }
  final point = digits.length - decimals;
  final whole = digits.substring(0, point);
  final fraction = digits.substring(point).replaceFirst(RegExp(r'0+$'), '');
  return fraction.isEmpty ? whole : '$whole.$fraction';
}

String _solanaPublicKey(Object? raw, String label) {
  if (raw is! String || raw.length > 64) throw RpcException('bad $label');
  try {
    final decoded = base58Decode(raw);
    if (decoded.length != 32 || base58Encode(decoded) != raw) {
      throw RpcException('bad $label');
    }
  } on Base58Error {
    throw RpcException('bad $label');
  }
  return raw;
}

Map<Object?, Object?> _simulationAccount(Object? raw) {
  final account = _exactMap(
    raw,
    allowed: const {
      'data',
      'executable',
      'lamports',
      'owner',
      'rentEpoch',
      'space',
    },
    required: const {'data', 'executable', 'lamports', 'owner', 'rentEpoch'},
    label: 'simulation account',
  );
  _validateBase64Tuple(account['data'], 'simulation account data');
  if (account['executable'] is! bool) {
    throw RpcException('bad simulation account executable');
  }
  _u64(account['lamports'], 'simulation account lamports');
  _solanaPublicKey(account['owner'], 'simulation account owner');
  _unsignedJsonNumber(account['rentEpoch'], 'simulation account rent epoch');
  if (account['space'] case final Object? space?) {
    _u64(space, 'simulation account space');
  }
  return account;
}

void _validateBase64Tuple(Object? raw, String label) {
  if (raw is! List ||
      raw.length != 2 ||
      raw[0] is! String ||
      raw[1] != 'base64') {
    throw RpcException('bad $label');
  }
  final encoded = raw[0]! as String;
  if (encoded.length > 2 * 1024 * 1024 ||
      encoded.length % 4 != 0 ||
      !RegExp(r'^[A-Za-z0-9+/]*={0,2}$').hasMatch(encoded)) {
    throw RpcException('bad $label');
  }
  try {
    base64Decode(encoded);
  } on FormatException {
    throw RpcException('bad $label');
  }
}

void _validateSimulationLogs(Object? raw) {
  if (raw == null) return;
  if (raw is! List || raw.length > 10000) {
    throw RpcException('bad simulation logs');
  }
  for (final line in raw) {
    if (line is! String || line.length > 4096) {
      throw RpcException('bad simulation logs');
    }
  }
}

void _validateSimulationReturnData(Object? raw) {
  if (raw == null) return;
  final value = _exactMap(
    raw,
    allowed: const {'data', 'programId'},
    required: const {'data', 'programId'},
    label: 'simulation return data',
  );
  _solanaPublicKey(value['programId'], 'simulation return program');
  _validateBase64Tuple(value['data'], 'simulation return data');
}

void _validateLoadedAddresses(Object? raw) {
  if (raw == null) return;
  final value = _exactMap(
    raw,
    allowed: const {'readonly', 'writable'},
    required: const {'readonly', 'writable'},
    label: 'simulation loaded addresses',
  );
  for (final key in const ['readonly', 'writable']) {
    final addresses = value[key];
    if (addresses is! List || addresses.length > 256) {
      throw RpcException('bad simulation loaded addresses');
    }
    // KT Wallet currently constructs legacy messages, so address lookup table
    // entries would contradict the exact bytes sent for simulation.
    if (addresses.isNotEmpty) {
      throw RpcException('unexpected simulation loaded address');
    }
  }
}

List<BigInt>? _validateSimulationBalances(Object? raw, String label) {
  if (raw == null) return null;
  if (raw is! List || raw.length > 256) {
    throw RpcException('bad simulation $label');
  }
  return List<BigInt>.unmodifiable(
    raw.map((value) => BigInt.from(_u64(value, 'simulation $label'))),
  );
}

void _validateTokenBalances(Object? raw, String label) {
  if (raw == null) return;
  if (raw is! List || raw.length > 512) {
    throw RpcException('bad simulation $label');
  }
  for (final entry in raw) {
    final value = _exactMap(
      entry,
      allowed: const {
        'accountIndex',
        'mint',
        'owner',
        'programId',
        'uiTokenAmount',
      },
      required: const {'accountIndex', 'mint', 'uiTokenAmount'},
      label: 'simulation token balance',
    );
    final accountIndex = _u64(
      value['accountIndex'],
      'simulation token account index',
    );
    if (accountIndex > 255) {
      throw RpcException('bad simulation token account index');
    }
    _solanaPublicKey(value['mint'], 'simulation token mint');
    if (value['owner'] case final Object? owner?) {
      _solanaPublicKey(owner, 'simulation token owner');
    }
    if (value['programId'] case final Object? program?) {
      _solanaPublicKey(program, 'simulation token program');
    }
    final amount = _exactMap(
      value['uiTokenAmount'],
      allowed: const {'amount', 'decimals', 'uiAmount', 'uiAmountString'},
      required: const {'amount', 'decimals', 'uiAmount', 'uiAmountString'},
      label: 'simulation UI token amount',
    );
    final rawAmount = amount['amount'];
    if (rawAmount is! String ||
        rawAmount.isEmpty ||
        rawAmount.length > 78 ||
        !RegExp(r'^[0-9]+$').hasMatch(rawAmount)) {
      throw RpcException('bad simulation token amount');
    }
    final decimals = _u64(amount['decimals'], 'simulation token decimals');
    if (decimals > 255) throw RpcException('bad simulation token decimals');
    final uiAmount = amount['uiAmount'];
    if (uiAmount != null &&
        (uiAmount is! num || !uiAmount.isFinite || uiAmount < 0)) {
      throw RpcException('bad simulation UI token amount');
    }
    final uiAmountString = amount['uiAmountString'];
    if (uiAmountString is! String ||
        uiAmountString.isEmpty ||
        uiAmountString.length > 128 ||
        !RegExp(r'^[0-9]+(?:\.[0-9]+)?$').hasMatch(uiAmountString)) {
      throw RpcException('bad simulation UI token amount');
    }
  }
}

void _unsignedJsonNumber(Object? raw, String label) {
  if (raw is int) {
    _u64(raw, label);
    return;
  }
  if (raw is! double ||
      !raw.isFinite ||
      raw < 0 ||
      // JSON may decode u64::MAX rentEpoch as the nearest double (2^64).
      // This metadata is not used in a signing decision; lamports, slots,
      // heights, fees and compute units still require exact Dart ints.
      raw > 1.8446744073709552e19 ||
      raw != raw.truncateToDouble()) {
    throw RpcException('bad $label');
  }
}

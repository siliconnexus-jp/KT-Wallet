import 'dart:io';

/// Closed review boundary for data controlled by Gateway/RPC operators.
///
/// The wallet intentionally has no remotely downloaded policy or feature-flag
/// plane. Gateway data may provide chain state, metadata and additive risk
/// signals, but it must never be able to disable authentication, signature
/// verification or exact-transaction binding. This audit freezes the current
/// response vocabulary and the network-free cryptographic modules so a future
/// remote field or SDK cannot silently acquire security authority.
const _reviewedGatewayResponseKeys = <String>{
  'accounts',
  'amount',
  'amountRaw',
  'approvals',
  'approvedAt',
  'address',
  'balance',
  'blockTag',
  'cachedAtMs',
  'category',
  'chain',
  'change24h',
  'code',
  'contract',
  'data',
  'decimals',
  'direction',
  'error',
  'fees',
  'fiatPerUsd',
  'from',
  'gas',
  'hash',
  'id',
  'identity',
  'maxFeePerGas',
  'maxPriorityFeePerGas',
  'message',
  'name',
  'native',
  'nativeLatest',
  'nativePending',
  'network',
  'networks',
  'nonce',
  'ok',
  'pendingAvailable',
  'popular',
  'prices',
  'raw',
  'records',
  'result',
  'returnData',
  'risk',
  'source',
  'spender',
  'spenderName',
  'spenderTag',
  'spenderTrusted',
  'status',
  'symbol',
  'timestampMs',
  'to',
  'token',
  'tokenAddress',
  'tokenContract',
  'tokenName',
  'tokenSymbol',
  'tokens',
  'transaction',
  'txHash',
  'unlimited',
  'upstream',
  'upstreams',
  'USD',
  'usd',
  'value',
  'verified',
  'version',
};

const _remotePolicySdkTokens = <String>{
  'firebase_remote_config',
  'remote_config',
  'configcat',
  'launchdarkly',
  'unleash',
  'growthbook',
  'feature_flag',
};

const _networkFreeSecurityFiles = <String>{
  'apps/kt_wallet/lib/src/transfer/airgap_codec.dart',
  'apps/kt_wallet/lib/src/security/transaction_auth.dart',
  'apps/kt_wallet/lib/src/security/wallet_pin.dart',
  'apps/cold_signer/lib/src/state/signer_wallet_controller.dart',
  'packages/chains/lib/src/signature_verifier.dart',
};

void main() {
  final selfTestFailures = _selfTestFailures();
  if (selfTestFailures.isNotEmpty) {
    for (final failure in selfTestFailures) {
      stderr.writeln('Remote security boundary self-test failed: $failure');
    }
    exitCode = 70;
    return;
  }

  if (!File('pubspec.yaml').existsSync()) {
    stderr.writeln('Run this audit from the KT-Wallet repository root.');
    exitCode = 64;
    return;
  }

  final failures = <String>[];
  _auditRemoteSdkDependencies(failures);
  _auditGatewayVocabulary(failures);
  _auditNetworkFreeSecurityModules(failures);
  _auditHotSigningBoundary(failures);
  _auditGatewayFirstNetworkIdentity(failures);
  _auditGatewayIrreversibleRequestSchema(failures);
  _auditGatewayPublicRequestSchemas(failures);
  _auditGatewayRPCEnvelope(failures);
  _auditGatewayUpstreamRPCEnvelope(failures);
  _auditGatewayHeliusResponseSchema(failures);
  _auditGatewayAlchemyResponseSchema(failures);
  _auditGatewayExplorerResponseSchema(failures);
  _auditGatewayTronHistoryResponseSchema(failures);
  _auditGatewayCoinGeckoResponseSchema(failures);
  _auditGatewayGoPlusResponseSchema(failures);
  _auditRiskSignalDirection(failures);

  if (failures.isNotEmpty) {
    for (final failure in failures) {
      stderr.writeln('Remote security boundary FAIL: $failure');
    }
    exitCode = 1;
    return;
  }
  stdout.writeln(
    'Remote security boundary audit passed: '
    '${_reviewedGatewayResponseKeys.length} reviewed Gateway fields, '
    '${_networkFreeSecurityFiles.length} network-free security modules, '
    '3 hot-signing families independently verified, '
    'hot and air-gapped broadcasts hash-bound before success metrics and '
    'answered Gateway errors kept single-shot, '
    'all parameterized public Gateway requests, inbound JSON-RPC envelopes, '
    'upstream node responses, Helius, Alchemy, Etherscan/Blockscout, '
    'TronGrid history, CoinGecko market responses, and all three GoPlus '
    'security responses plus fallback block timestamps exact-schema '
    'decoded.',
  );
}

void _auditRemoteSdkDependencies(List<String> failures) {
  for (final path in const [
    'apps/kt_wallet/pubspec.yaml',
    'apps/cold_signer/pubspec.yaml',
  ]) {
    final source = File(path).readAsStringSync().toLowerCase();
    for (final token in _remotePolicySdkTokens) {
      if (source.contains(token)) {
        failures.add('$path introduces remote policy dependency: $token');
      }
    }
  }

  for (final root in const [
    'apps/kt_wallet/lib',
    'apps/cold_signer/lib',
    'packages/core_crypto/lib',
    'packages/airgap_protocol/lib',
    'packages/chains/lib',
  ]) {
    for (final entity in Directory(root).listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final imports = _imports(entity.readAsStringSync());
      for (final import in imports) {
        final normalized = import.toLowerCase();
        for (final token in _remotePolicySdkTokens) {
          if (normalized.contains(token)) {
            failures.add('${entity.path} imports remote policy SDK: $import');
          }
        }
      }
    }
  }
}

void _auditGatewayVocabulary(List<String> failures) {
  const path = 'apps/kt_wallet/lib/src/market/gateway_client.dart';
  final source = File(path).readAsStringSync();
  final actual = _mapLookupKeys(source);
  final added = actual.difference(_reviewedGatewayResponseKeys).toList()
    ..sort();
  final stale = _reviewedGatewayResponseKeys.difference(actual).toList()
    ..sort();
  if (added.isNotEmpty) {
    failures.add('$path has unreviewed remote fields: ${added.join(', ')}');
  }
  if (stale.isNotEmpty) {
    failures.add(
      '$path removed reviewed fields; shrink allowlist: ${stale.join(', ')}',
    );
  }
}

void _auditNetworkFreeSecurityModules(List<String> failures) {
  for (final path in _networkFreeSecurityFiles) {
    final file = File(path);
    if (!file.existsSync()) {
      failures.add('$path is missing');
      continue;
    }
    for (final import in _imports(file.readAsStringSync())) {
      final normalized = import.toLowerCase();
      if (normalized == 'dart:io' ||
          normalized == 'package:http/http.dart' ||
          normalized.contains('gateway_client.dart') ||
          _remotePolicySdkTokens.any(normalized.contains)) {
        failures.add(
          '$path lets network/remote policy into crypto/auth: $import',
        );
      }
    }
  }
}

void _auditHotSigningBoundary(List<String> failures) {
  const path = 'apps/kt_wallet/lib/src/transfer/local_transfer_service.dart';
  final source = File(path).readAsStringSync();
  final expectations = <String, List<String>>{
    'signPreparedEvm': [
      '_verifyNativeSignedResult(',
      'unsignedTx: prepared.unsignedTx',
      'claimedSigner: prepared.from',
    ],
    'signPreparedTron': [
      '_verifyNativeSignedResult(',
      'unsignedTx: prepared.rawTx',
      'claimedSigner: prepared.from',
    ],
    'signPreparedSolana': [
      '_verifyNativeSignedResult(',
      'unsignedTx: prepared.message',
      'claimedSigner: prepared.from',
    ],
  };
  for (final entry in expectations.entries) {
    final section = _futureMethodSection(source, entry.key);
    if (section == null) {
      failures.add('$path is missing ${entry.key}');
      continue;
    }
    for (final marker in entry.value) {
      if (!section.contains(marker)) {
        failures.add(
          '$path ${entry.key} bypasses post-sign verification: $marker',
        );
      }
    }
  }

  final verifier = _futureMethodSection(source, '_verifyNativeSignedResult');
  for (final marker in const [
    'Uint8List.fromList(signed.signedTx)',
    'verifySignedTransaction(',
    'claimedSigner: claimedSigner',
    'if (verified.txHash != signed.txHash)',
    "'native transaction hash mismatch'",
  ]) {
    if (verifier == null || !verifier.contains(marker)) {
      failures.add('$path post-sign verifier lost invariant: $marker');
    }
  }
  if ('wallet.sign('.allMatches(source).length != 3) {
    failures.add(
      '$path changed native signing ownership; review every sign site',
    );
  }

  final broadcaster = _futureMethodSection(source, 'broadcastSigned');
  for (final marker in const [
    'required String expectedTxHash',
    'expectedTxHash: expectedTxHash',
  ]) {
    if (broadcaster == null || !broadcaster.contains(marker)) {
      failures.add('$path broadcast boundary lost local-hash binding: $marker');
    }
  }
  final irreversibleBoundary = _futureMethodSection(source, '_broadcast');
  for (final marker in const [
    "'missing locally verified transaction hash'",
    'transactionHashesMatch(chain, expectedTxHash, txHash)',
    "'The node returned an inconsistent transaction hash'",
    'return expectedTxHash',
  ]) {
    if (irreversibleBoundary == null ||
        !irreversibleBoundary.contains(marker)) {
      failures.add('$path broadcast result lost local-hash binding: $marker');
    }
  }
  for (final method in const [
    'signAndBroadcastEvm',
    'signAndBroadcastTron',
    'signAndBroadcastSolana',
  ]) {
    final section = _futureMethodSection(source, method);
    if (section == null || !section.contains('expectedTxHash: signed.txHash')) {
      failures.add('$path $method does not bind node response to signed hash');
    }
  }

  const airgapPath = 'apps/kt_wallet/lib/src/screens/transfer_screens.dart';
  final airgap = File(airgapPath).readAsStringSync();
  final airgapBroadcast = _futureMethodSection(airgap, '_broadcast');
  for (final marker in const [
    'transactionHashesMatch(',
    'chainForCoin(result.coin)',
    'result.txHash,',
    'expectedTxHash: result.txHash',
    '..broadcastTxHash = result.txHash',
    '..broadcastOutcomeUnknown = true',
  ]) {
    if (airgapBroadcast == null || !airgapBroadcast.contains(marker)) {
      failures.add(
        '$airgapPath lost air-gapped broadcast hash binding: $marker',
      );
    }
  }

  const broadcastPath =
      'apps/kt_wallet/lib/src/transfer/broadcast_service.dart';
  final broadcast = File(broadcastPath).readAsStringSync();
  for (final marker in const [
    'bool transactionHashesMatch(',
    'Chain.solana => expected == actual',
    'expected.toLowerCase() == actual.toLowerCase()',
  ]) {
    if (!broadcast.contains(marker)) {
      failures.add('$broadcastPath lost chain-aware hash comparison: $marker');
    }
  }

  final measuredBroadcast = _futureMethodSection(broadcast, 'broadcast');
  for (final marker in const [
    'required String expectedTxHash',
    'ExperienceMetrics.instance.measure(',
    '() => _broadcastBound(',
    'isSuccess: (outcome) => outcome.status == BroadcastStatus.ok',
  ]) {
    if (measuredBroadcast == null || !measuredBroadcast.contains(marker)) {
      failures.add(
        '$broadcastPath measures an unbound broadcast result: $marker',
      );
    }
  }
  final boundBroadcast = _futureMethodSection(broadcast, '_broadcastBound');
  for (final marker in const [
    'if (expectedTxHash.trim().isEmpty)',
    'final outcome = await _broadcast(chain, signedTx)',
    '!transactionHashesMatch(chain, expectedTxHash, nodeHash)',
    'BroadcastOutcome.unknown(',
    'return BroadcastOutcome.ok(expectedTxHash)',
  ]) {
    if (boundBroadcast == null || !boundBroadcast.contains(marker)) {
      failures.add(
        '$broadcastPath lost pre-metric local-hash binding: $marker',
      );
    }
  }

  final irreversibleBroadcast = _futureMethodSection(broadcast, '_broadcast');
  const answeredErrorStart = '} on GatewayException {';
  const localPreflightStart = '} on GatewayNetworkUnsupported {';
  final answeredStart =
      irreversibleBroadcast?.indexOf(answeredErrorStart) ?? -1;
  final localStart = answeredStart < 0
      ? -1
      : irreversibleBroadcast!.indexOf(
          localPreflightStart,
          answeredStart + answeredErrorStart.length,
        );
  if (answeredStart < 0 || localStart < 0) {
    failures.add(
      '$broadcastPath lost answered-error versus local-preflight boundary',
    );
  } else {
    final answeredError = irreversibleBroadcast!.substring(
      answeredStart + answeredErrorStart.length,
      localStart,
    );
    if (_answeredGatewayErrorCanSetTerminalFailure(answeredError)) {
      failures.add(
        '$broadcastPath lets an answered Gateway error control terminal state or re-post signed bytes',
      );
    }
    if (!_answeredGatewayErrorTerminatesUnknown(answeredError)) {
      failures.add(
        '$broadcastPath answered Gateway error does not terminate as unknown',
      );
    }
  }
}

void _auditGatewayFirstNetworkIdentity(List<String> failures) {
  const verifierPath = 'apps/kt_wallet/lib/src/transfer/network_identity.dart';
  final verifier = File(verifierPath).readAsStringSync();
  for (final marker in const [
    "import '../market/gateway_client.dart';",
    'return await gateway.getNetworkIdentity(chain: coin);',
    'on GatewayNetworkUnsupported',
    'on GatewayTransportException',
    'if (error.code == -32601) return null;',
    'rethrow;',
    '_requireMatch(chain, expected, gatewayIdentity);',
    '_requireMatch(Chain.tron, expectedGenesisBlockId, gatewayIdentity);',
    '_requireMatch(Chain.solana, expectedGenesisHash, gatewayIdentity);',
  ]) {
    if (!verifier.contains(marker)) {
      failures.add(
        '$verifierPath can bypass Gateway-first network identity: $marker',
      );
    }
  }
  if ('final gatewayIdentity = await _gatewayIdentity('
          .allMatches(verifier)
          .length !=
      3) {
    failures.add(
      '$verifierPath does not Gateway-check all three signing families',
    );
  }

  const transferPath =
      'apps/kt_wallet/lib/src/transfer/local_transfer_service.dart';
  final transfer = File(transferPath).readAsStringSync();
  if (!transfer.contains('RpcNetworkIdentityVerifier(') ||
      !transfer.contains('gateway: gateway,')) {
    failures.add(
      '$transferPath does not pass the production Gateway into pre-sign identity verification',
    );
  }
}

void _auditGatewayIrreversibleRequestSchema(List<String> failures) {
  const path = 'backend/gateway/internal/handlers/broadcast.go';
  final source = File(path).readAsStringSync();
  const strictDecode = 'decodeStrictJSON(params, &p)';
  if (!source.contains(strictDecode)) {
    failures.add('$path lost exact-schema broadcast decoding: $strictDecode');
  }
  const permissiveDecode = 'json.Unmarshal(params, &p)';
  if (source.contains(permissiveDecode)) {
    failures.add(
      '$path restored permissive irreversible-request decoding: '
      '$permissiveDecode',
    );
  }
  const tronDuplicateGuard = 'rejectDuplicateJSONKeys([]byte(trimmed))';
  if (!source.contains(tronDuplicateGuard)) {
    failures.add(
      '$path lost nested TRON payload duplicate-key rejection: '
      '$tronDuplicateGuard',
    );
  }
}

void _auditGatewayPublicRequestSchemas(List<String> failures) {
  const expectedRegistrations = <String, String>{
    'kt_health': 'Health',
    'kt_getBalances': 'GetBalances',
    'kt_getPortfolio': 'GetPortfolio',
    'kt_getPrices': 'GetPrices',
    'kt_getChainParams': 'GetChainParams',
    'kt_simulateEvmTransfer': 'SimulateEVMTransfer',
    'kt_estimateEvmGas': 'EstimateEVMGas',
    'kt_getEvmSpendableBalances': 'GetEVMSpendableBalances',
    'kt_getHistory': 'GetHistory',
    'kt_getTransactionStatus': 'GetTransactionStatus',
    'kt_getNetworkIdentity': 'GetNetworkIdentity',
    'kt_searchTokens': 'SearchOfficialTokens',
    'kt_checkTokenRisk': 'CheckTokenRisk',
    'kt_getEvmTokenApprovals': 'GetEVMTokenApprovals',
    'kt_reportDiagnostics': 'ReportAppDiagnostics',
    'kt_broadcast': 'Broadcast',
  };
  const gatewayPath = 'backend/gateway/internal/handlers/gateway.go';
  final gateway = File(gatewayPath).readAsStringSync();
  final registrationPattern = RegExp(
    r's\.Register\("([^"]+)",\s*g\.([A-Za-z0-9_]+)\)',
  );
  final actualRegistrations = <String, String>{};
  for (final match in registrationPattern.allMatches(gateway)) {
    final method = match.group(1)!;
    final handler = match.group(2)!;
    if (actualRegistrations.containsKey(method)) {
      failures.add('$gatewayPath duplicates public method $method');
    }
    actualRegistrations[method] = handler;
  }
  if (!_sameStringMap(actualRegistrations, expectedRegistrations)) {
    failures.add(
      '$gatewayPath public method registry changed; review every new or '
      'rebound method request schema',
    );
  }

  const expectedStrictParamDecodes = <String, int>{
    'backend/gateway/internal/handlers/balances.go': 2,
    'backend/gateway/internal/handlers/prices.go': 1,
    'backend/gateway/internal/handlers/chainparams.go': 1,
    // Simulation and estimation share validatedEVMCall; spendable balances
    // has its own request object.
    'backend/gateway/internal/handlers/evm_preflight.go': 2,
    'backend/gateway/internal/handlers/history.go': 1,
    'backend/gateway/internal/handlers/transaction_status.go': 1,
    'backend/gateway/internal/handlers/network_identity.go': 1,
    'backend/gateway/internal/handlers/official_tokens.go': 1,
    'backend/gateway/internal/handlers/token_risk.go': 1,
    'backend/gateway/internal/handlers/token_approvals.go': 1,
    'backend/gateway/internal/handlers/broadcast.go': 1,
  };
  const strictMarker = 'decodeStrictJSON(params, &p)';
  for (final entry in expectedStrictParamDecodes.entries) {
    final source = File(entry.key).readAsStringSync();
    final actual = strictMarker.allMatches(source).length;
    if (actual != entry.value) {
      failures.add(
        '${entry.key} has $actual exact-schema parameter decodes; '
        'expected ${entry.value}',
      );
    }
  }

  const diagnosticsPath =
      'backend/gateway/internal/handlers/app_diagnostics.go';
  final diagnostics = File(diagnosticsPath).readAsStringSync();
  if (!diagnostics.contains('decodeStrictJSON(params, &report)')) {
    failures.add('$diagnosticsPath lost exact-schema diagnostics decoding');
  }

  final handlers = Directory('backend/gateway/internal/handlers');
  final permissive = RegExp(r'json\.Unmarshal\s*\(\s*params\b');
  for (final entity in handlers.listSync()) {
    if (entity is! File ||
        !entity.path.endsWith('.go') ||
        entity.path.endsWith('_test.go')) {
      continue;
    }
    if (permissive.hasMatch(entity.readAsStringSync())) {
      failures.add(
        '${entity.path} restored permissive public parameter decoding',
      );
    }
  }
}

bool _sameStringMap(Map<String, String> left, Map<String, String> right) {
  if (left.length != right.length) return false;
  for (final entry in right.entries) {
    if (left[entry.key] != entry.value) return false;
  }
  return true;
}

void _auditGatewayRPCEnvelope(List<String> failures) {
  const path = 'backend/gateway/internal/rpc/rpc.go';
  final source = File(path).readAsStringSync();
  for (final marker in const [
    'func decodeRequestEnvelope(',
    'req, envelopeErr := decodeRequestEnvelope(body)',
    'if _, duplicate := seen[key]; duplicate',
    'case "jsonrpc":',
    'case "method":',
    'case "params":',
    'case "id":',
    'if !isValidParamsValue(raw)',
    'if !isValidRequestID(raw)',
    's.writeError(w, nil, envelopeErr)',
  ]) {
    if (!source.contains(marker)) {
      failures.add('$path lost exact JSON-RPC envelope invariant: $marker');
    }
  }
  if (source.contains('json.Unmarshal(body, &req)')) {
    failures.add('$path restored permissive JSON-RPC envelope decoding');
  }
}

void _auditGatewayUpstreamRPCEnvelope(List<String> failures) {
  const poolPath = 'backend/gateway/internal/upstream/pool.go';
  final pool = File(poolPath).readAsStringSync();
  for (final marker in const [
    'decodeExactJSONObject(data, "jsonrpc", "id", "result", "error")',
    'decodeExactJSONObject(rpcErrorRaw, "code", "message", "data")',
    'hasResult == hasError',
    'bytes.Equal(bytes.TrimSpace(fields["id"]), []byte("1"))',
    'code == nil || message == nil',
  ]) {
    if (!pool.contains(marker)) {
      failures.add(
        '$poolPath lost exact upstream JSON-RPC response invariant: $marker',
      );
    }
  }
  for (final permissive in const [
    'json.Unmarshal(data, &out)',
    'json.Unmarshal(out.Error, &rpcError)',
  ]) {
    if (pool.contains(permissive)) {
      failures.add(
        '$poolPath restored permissive upstream JSON-RPC decoding: '
        '$permissive',
      );
    }
  }

  const decoderPath = 'backend/gateway/internal/upstream/strict_json.go';
  final decoder = File(decoderPath).readAsStringSync();
  for (final marker in const [
    'if _, known := allowed[key]; !known',
    'if _, duplicate := values[key]; duplicate',
    'expected JSON object',
  ]) {
    if (!decoder.contains(marker)) {
      failures.add(
        '$decoderPath lost exact-object response invariant: $marker',
      );
    }
  }
}

void _auditGatewayHeliusResponseSchema(List<String> failures) {
  const path = 'backend/gateway/internal/upstream/history.go';
  final source = File(path).readAsStringSync();
  for (final marker in const [
    'func decodeHeliusTransfers(',
    'decodeExactJSONObject(data, "jsonrpc", "id", "result", "error")',
    'version != "2.0" || id != "kt-wallet" || hasResult == hasError',
    'decodeExactJSONObject(errorRaw, "code", "message", "data")',
    'decodeExactJSONObject(resultRaw, "data", "paginationToken")',
    'func decodeHeliusTransfer(',
    'validUnsignedProviderInteger(*wire.Amount)',
    'hasFeeAmount != hasFeeUIAmount',
    'transfers, rejected, err := decodeHeliusTransfers(data)',
  ]) {
    if (!source.contains(marker)) {
      failures.add('$path lost exact Helius response invariant: $marker');
    }
  }
  if (source.contains('Data []HeliusTransfer `json:"data"`')) {
    failures.add('$path restored permissive Helius history decoding');
  }
}

void _auditGatewayAlchemyResponseSchema(List<String> failures) {
  const path = 'backend/gateway/internal/upstream/alchemy.go';
  final source = File(path).readAsStringSync();
  for (final marker in const [
    'func decodeAlchemyTransfers(',
    'decodeExactJSONObject(data, "jsonrpc", "id", "result", "error")',
    'decodeExactJSONObject(resultRaw, "transfers", "pageKey")',
    'func decodeAlchemyTransfer(',
    'decodeExactJSONObject(fields["rawContract"], "value", "address", "decimal")',
    'validOptionalJSONNumber(fields["value"])',
    'missingOrJSONNull(fields["erc721TokenId"])',
    'missingOrJSONNull(fields["erc1155Metadata"])',
    'missingOrJSONNull(fields["tokenId"])',
    'validAlchemyQuantity(*rawWire.Value)',
    'rawAmount.Sign() <= 0',
    'rawDecimals.Uint64() > 255',
    'transfers, rejected, err := decodeAlchemyTransfers(data)',
    'func decodeAlchemyBlockTimestamps(',
    'blockFields, err := decodeUniqueJSONObject(resultRaw)',
    'strings.EqualFold(key, "timestamp") && key != "timestamp"',
    'timestamps, rejected, err := decodeAlchemyBlockTimestamps(data, blocks)',
  ]) {
    if (!source.contains(marker)) {
      failures.add('$path lost exact Alchemy response invariant: $marker');
    }
  }
  for (final permissive in const [
    'Transfers []AlchemyTransfer `json:"transfers"`',
    'json.Unmarshal(data, &out)',
  ]) {
    if (source.contains(permissive)) {
      failures.add(
        '$path restored permissive Alchemy response decoding: $permissive',
      );
    }
  }
}

void _auditGatewayExplorerResponseSchema(List<String> failures) {
  const path = 'backend/gateway/internal/upstream/history.go';
  final source = File(path).readAsStringSync();
  for (final marker in const [
    'func decodeExplorerAccountEnvelope(',
    'decodeExactJSONObject(data, "status", "message", "result")',
    '*status == "1" && *message == "OK"',
    '*status == "0" && *message == "No transactions found"',
    'func decodeEtherscanTx(',
    'func decodeEtherscanTokenTx(',
    'func decodeEtherscanInternalTx(',
    'validEVMUnsignedDecimal(',
    'hasHash == hasTransactionHash',
    'hasTraceID == hasIndex',
    'rows, rejected, err := decodeExplorerAccountEnvelope(data)',
  ]) {
    if (!source.contains(marker)) {
      failures.add('$path lost exact explorer response invariant: $marker');
    }
  }
  for (final permissive in const [
    'json.Unmarshal(data, &out)',
    'Result  json.RawMessage `json:"result"`',
  ]) {
    if (source.contains(permissive)) {
      failures.add(
        '$path restored permissive explorer response decoding: $permissive',
      );
    }
  }
}

void _auditGatewayTronHistoryResponseSchema(List<String> failures) {
  const decoderPath = 'backend/gateway/internal/upstream/tron_history.go';
  final decoder = File(decoderPath).readAsStringSync();
  for (final marker in const [
    'func decodeTronHistoryEnvelope(',
    'decodeExactJSONObject(data, "data", "success", "meta")',
    'func decodeTronTRC20History(',
    'func decodeTronTRC20Transfer(',
    'typeName != "Transfer"',
    'validTronUnsignedDecimal(value, 256)',
    'func decodeTronNativeHistory(',
    'func decodeTronNativeTransaction(',
    'ContractIndex: index',
    'func decodeTronInternalHistory(',
    'func decodeTronInternalTransaction(',
    'transfer.AssetIndex = 1',
    'func validTronAddress(',
  ]) {
    if (!decoder.contains(marker)) {
      failures.add(
        '$decoderPath lost exact TronGrid history invariant: $marker',
      );
    }
  }

  const clientPath = 'backend/gateway/internal/upstream/tron.go';
  final client = File(clientPath).readAsStringSync();
  for (final marker in const [
    'transfers, err := decodeTronTRC20History(data)',
    'transfers, err := decodeTronNativeHistory(data)',
    'transfers, err := decodeTronInternalHistory(data)',
    'only_confirmed=true&order_by=block_timestamp,desc',
  ]) {
    if (!client.contains(marker)) {
      failures.add('$clientPath lost strict TronGrid history binding: $marker');
    }
  }

  const handlerPath = 'backend/gateway/internal/handlers/history.go';
  final handler = File(handlerPath).readAsStringSync();
  for (final marker in const [
    'ID:          tronTRC20EventID(t)',
    'func tronTRC20EventID(',
    'digest := sha256.Sum256([]byte(semantic))',
    'if from != selfHex && to != selfHex',
    'id += fmt.Sprintf(":contract:%d", t.ContractIndex)',
    'id += ":trc10:" + t.TokenID',
  ]) {
    if (!handler.contains(marker)) {
      failures.add(
        '$handlerPath lost TronGrid event-identity invariant: $marker',
      );
    }
  }
  if (handler.contains('tokenHashes[t.TransactionID]')) {
    failures.add('$handlerPath restored hash-wide TRC-20/native suppression');
  }
}

void _auditGatewayCoinGeckoResponseSchema(List<String> failures) {
  const clientPath = 'backend/gateway/internal/upstream/prices.go';
  final client = File(clientPath).readAsStringSync();
  for (final marker in const [
    'validateCoinGeckoIDs(ids)',
    'q.Set("include_last_updated_at", "true")',
    'q.Set("precision", "full")',
    'decodeCoinGeckoQuotes(data, expectedIDs, time.Now())',
    'func decodeCoinGeckoQuotes(',
    'objects, err := decodeUniqueJSONObject(data)',
    'len(objects) != len(expectedIDs)',
    'if _, requested := expectedIDs[id]; !requested',
    'func decodeCoinGeckoQuote(',
    '"usd", "usd_24h_change",',
    '"cny", "cny_24h_change",',
    '"jpy", "jpy_24h_change",',
    '"last_updated_at",',
    'parsePositiveFiniteJSONNumber(',
    'parseNullableCoinGeckoChange(',
    'parseCoinGeckoTimestamp(',
    'validateCoinGeckoFXConsistency(out)',
  ]) {
    if (!client.contains(marker)) {
      failures.add(
        '$clientPath lost exact CoinGecko response invariant: $marker',
      );
    }
  }
  if (client.contains('json.Unmarshal(data, &out)')) {
    failures.add('$clientPath restored permissive CoinGecko decoding');
  }

  const handlerPath = 'backend/gateway/internal/handlers/prices.go';
  final handler = File(handlerPath).readAsStringSync();
  for (final marker in const [
    'cnyRates = append(cnyRates, quote.CNY/quote.USD)',
    'jpyRates = append(jpyRates, quote.JPY/quote.USD)',
    'fiatPerUSD["CNY"] = medianRate(cnyRates)',
    'fiatPerUSD["JPY"] = medianRate(jpyRates)',
    'func medianRate(',
  ]) {
    if (!handler.contains(marker)) {
      failures.add(
        '$handlerPath lost deterministic CoinGecko FX invariant: $marker',
      );
    }
  }
}

void _auditGatewayGoPlusResponseSchema(List<String> failures) {
  const commonPath = 'backend/gateway/internal/upstream/goplus_response.go';
  final common = File(commonPath).readAsStringSync();
  for (final marker in const [
    'decodeExactJSONObject(data, "code", "message", "result")',
    'func decodeBoundGoPlusRecord(',
    'if len(result) != 1',
    'func parseBinaryFlag(',
    'func decodeMaliciousBehaviors(',
    'func validateGoPlusTokenIdentity(',
    'func validateGoPlusApprovalIdentity(',
    'func validateSolanaMint(',
  ]) {
    if (!common.contains(marker)) {
      failures.add('$commonPath lost strict GoPlus invariant: $marker');
    }
  }

  const evmPath = 'backend/gateway/internal/upstream/goplus.go';
  final evm = File(evmPath).readAsStringSync();
  for (final marker in const [
    'validateGoPlusTokenIdentity(chainID, contract)',
    'decodeGoPlusEnvelope(data)',
    'decodeBoundGoPlusRecord(',
    'explicitTokenThreatCategory(recordRaw)',
    'parseGoPlusFakeToken(',
    'decodeExactJSONObject(raw, "true_token_address", "value")',
    'return "", honeypotPresent, nil',
  ]) {
    if (!evm.contains(marker)) {
      failures.add('$evmPath lost strict GoPlus EVM invariant: $marker');
    }
  }
  for (final banned in const [
    'json.Unmarshal(data, &envelope)',
    'var record map[string]any',
    'func flagIsOne(',
  ]) {
    if (evm.contains(banned)) {
      failures.add('$evmPath restored permissive GoPlus EVM parsing: $banned');
    }
  }

  const solanaPath = 'backend/gateway/internal/upstream/goplus_solana.go';
  final solana = File(solanaPath).readAsStringSync();
  for (final marker in const [
    'validateSolanaMint(mint)',
    'decodeGoPlusEnvelope(data)',
    'decodeBoundGoPlusRecord(envelope.Result, mint, false)',
    '{name: "creators", array: true}',
    'func parseSolanaCapability(',
    'decodeExactJSONObject(raw, "status", authorityKey)',
    'func parseSolanaAuthorityArray(',
    'decodeExactJSONObject(row, "address", "malicious_address")',
  ]) {
    if (!solana.contains(marker)) {
      failures.add('$solanaPath lost strict GoPlus Solana invariant: $marker');
    }
  }
  if (solana.contains('json.Unmarshal(data, &envelope)') ||
      solana.contains('"creator",')) {
    failures.add('$solanaPath restored permissive or singular creator parsing');
  }

  const approvalsPath = 'backend/gateway/internal/upstream/goplus_approvals.go';
  final approvals = File(approvalsPath).readAsStringSync();
  for (final marker in const [
    'validateGoPlusApprovalIdentity(chainID, address)',
    'decodeGoPlusEnvelope(data)',
    'parseApprovalToken(token, chainID, maxEvidenceTime)',
    'chainID != expectedChainID',
    'func parseApprovalContract(',
    'func parseApprovalAddressInfo(',
    'decodeExactJSONObject(',
    'duplicate approval token',
    'duplicate approval record',
  ]) {
    if (!approvals.contains(marker)) {
      failures.add(
        '$approvalsPath lost strict GoPlus approval invariant: $marker',
      );
    }
  }
  for (final banned in const [
    'json.Unmarshal(data, &envelope)',
    'func rawFlagIsOne(',
    'type approvalEnvelope struct',
  ]) {
    if (approvals.contains(banned)) {
      failures.add(
        '$approvalsPath restored permissive GoPlus approval parsing: $banned',
      );
    }
  }

  const handlerPath = 'backend/gateway/internal/handlers/token_risk.go';
  final handler = File(handlerPath).readAsStringSync();
  if (!handler.contains('if official && threat.Found')) {
    failures.add(
      '$handlerPath can mark an official identity provider-checked without a bound record',
    );
  }
}

void _auditRiskSignalDirection(List<String> failures) {
  const transferPath = 'apps/kt_wallet/lib/src/screens/transfer_screens.dart';
  final transfer = File(transferPath).readAsStringSync();
  for (final marker in const [
    '_tokenRisk == _TokenRiskUiState.checking ||',
    '_tokenRisk == _TokenRiskUiState.unsafe',
    'GatewayTokenRiskStatus.unknown => _TokenRiskUiState.unknown',
    '_TokenRiskUiState.unavailable',
  ]) {
    if (!transfer.contains(marker)) {
      failures.add(
        '$transferPath lost additive/fail-visible risk rule: $marker',
      );
    }
  }

  const gatewayPath = 'apps/kt_wallet/lib/src/market/gateway_client.dart';
  final gateway = File(gatewayPath).readAsStringSync();
  for (final marker in const [
    "(risk != 'unsafe' && risk != 'unknown')",
    'enum GatewayTokenApprovalRisk { unsafe, unknown }',
    'responseNetwork != expectedNetwork',
    '_tokenIdentityMatches(chain, contract, responseContract)',
    'source == \'official_catalog+goplus\'',
    '_tokenRiskUnsafeResultKeys',
    '_officialTokenResultKeys',
    '_officialTokenPopularRowKeys',
    'requestedNetworks.contains(network)',
    '_officialTokenMatchesQuery(',
    '_tokenIdentityMatches(chain, contract, contract)',
    "FormatException('duplicate official token identity')",
  ]) {
    if (!gateway.contains(marker)) {
      failures.add(
        '$gatewayPath lost fail-closed remote risk binding: $marker',
      );
    }
  }

  const gatewayHandlerPath = 'backend/gateway/internal/handlers/gateway.go';
  final gatewayHandler = File(gatewayHandlerPath).readAsStringSync();
  for (final marker in const [
    'tokenRiskRegistryOK  bool',
    'tokenRiskRegistryOK := err == nil',
    'tokenRiskRegistryOK: tokenRiskRegistryOK',
  ]) {
    if (!gatewayHandler.contains(marker)) {
      failures.add(
        '$gatewayHandlerPath lost invalid-registry fail-closed state: $marker',
      );
    }
  }

  const tokenRiskPath = 'backend/gateway/internal/handlers/token_risk.go';
  final tokenRisk = File(tokenRiskPath).readAsStringSync();
  for (final marker in const [
    'decodeStrictJSON(raw, &entries)',
    'if !g.tokenRiskRegistryOK',
    'upstreamError("operator_registry"',
  ]) {
    if (!tokenRisk.contains(marker)) {
      failures.add(
        '$tokenRiskPath lost strict registry failure binding: $marker',
      );
    }
  }

  const strictJSONPath = 'backend/gateway/internal/handlers/strict_json.go';
  final strictJSON = File(strictJSONPath).readAsStringSync();
  for (final marker in const [
    'rejectNonCanonicalJSONFields(raw, reflect.TypeOf(target))',
    'decoder.UseNumber()',
    'unknown or non-canonical JSON field',
  ]) {
    if (!strictJSON.contains(marker)) {
      failures.add(
        '$strictJSONPath lost exact-case strict JSON binding: $marker',
      );
    }
  }
}

Set<String> _imports(String source) => {
  for (final match in RegExp(
    r'''^\s*import\s+['"]([^'"]+)['"]''',
    multiLine: true,
  ).allMatches(source))
    match.group(1)!,
};

Set<String> _mapLookupKeys(String source) => {
  for (final match in RegExp(r'''\[['"]([^'"]+)['"]\]''').allMatches(source))
    match.group(1)!,
};

String? _futureMethodSection(String source, String method) {
  final declaration = RegExp(
    'Future<[^>]+>\\s+${RegExp.escape(method)}\\(',
  ).firstMatch(source);
  if (declaration == null) return null;
  final start = declaration.start;
  final next = source.indexOf('\n  Future<', declaration.end);
  return source.substring(start, next < 0 ? source.length : next);
}

bool _answeredGatewayErrorTerminatesUnknown(String source) => RegExp(
  r"return\s+const\s+BroadcastOutcome\.unknown\(\s*'Gateway response unavailable'\s*,?\s*\);\s*$",
).hasMatch(source);

bool _answeredGatewayErrorCanSetTerminalFailure(String source) =>
    source.contains('isUnsupported') ||
    source.contains('isRateLimited') ||
    source.contains('isUpstreamError') ||
    RegExp(r'BroadcastOutcome\.(?:error|unsupported)\s*\(').hasMatch(source);

List<String> _selfTestFailures() {
  final failures = <String>[];
  if (!_mapLookupKeys("final x = row['status'];").contains('status')) {
    failures.add('map lookup extractor misses a remote field');
  }
  if (!_imports(
    "import 'package:firebase_remote_config/x.dart';",
  ).contains('package:firebase_remote_config/x.dart')) {
    failures.add('import extractor misses a remote SDK');
  }
  const strict = '''
  Future<SignedTransaction> signPreparedEvm() async {
    return _verifyNativeSignedResult(
      unsignedTx: prepared.unsignedTx,
      claimedSigner: prepared.from,
    );
  }
  Future<void> next() async {}
''';
  final section = _futureMethodSection(strict, 'signPreparedEvm');
  if (section == null || section.contains('Future<void> next')) {
    failures.add('method boundary extractor is not closed');
  }
  if (!_answeredGatewayErrorTerminatesUnknown('''
    if (submissionUnknown) {
      return const BroadcastOutcome.unknown(
        'Gateway response unavailable',
      );
    }
    return const BroadcastOutcome.unknown('Gateway response unavailable');
  ''')) {
    failures.add('answered-error terminal-unknown extractor misses valid code');
  }
  if (_answeredGatewayErrorTerminatesUnknown('''
    if (submissionUnknown) {
      return const BroadcastOutcome.unknown(
        'Gateway response unavailable',
      );
    }
    // Falls through and may submit again.
  ''')) {
    failures.add(
      'answered-error terminal-unknown extractor allows fallthrough',
    );
  }
  if (!_answeredGatewayErrorCanSetTerminalFailure('''
    if (e.isUpstreamError) {
      return BroadcastOutcome.error(RpcRejectionKind.rejected);
    }
    return const BroadcastOutcome.unknown('Gateway response unavailable');
  ''') ||
      _answeredGatewayErrorCanSetTerminalFailure('''
    return const BroadcastOutcome.unknown('Gateway response unavailable');
  ''')) {
    failures.add('answered-error terminal-authority extractor is not exact');
  }
  if (!_sameStringMap(const {'kt_a': 'A'}, const {'kt_a': 'A'}) ||
      _sameStringMap(const {'kt_a': 'B'}, const {'kt_a': 'A'}) ||
      _sameStringMap(
        const {'kt_a': 'A', 'kt_new': 'New'},
        const {'kt_a': 'A'},
      )) {
    failures.add('public method registry comparison is not exact');
  }
  return failures;
}

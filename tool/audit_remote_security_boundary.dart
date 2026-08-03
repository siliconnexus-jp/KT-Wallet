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
  'balance',
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
  'tokenName',
  'tokenSymbol',
  'tokens',
  'transaction',
  'txHash',
  'unlimited',
  'upstream',
  'usd',
  'verified',
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
  _auditGatewayIrreversibleRequestSchema(failures);
  _auditGatewayPublicRequestSchemas(failures);
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
    'hot and air-gapped broadcasts hash-bound before success metrics, '
    'all parameterized public Gateway requests exact-schema decoded.',
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

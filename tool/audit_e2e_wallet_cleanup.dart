import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

/// Known cleanup debt. Every entry must either be removed from this set after
/// registering authenticated cleanup, or remain visible in P0 reporting.
///
/// The audit fails on a new untracked `storeWallet` site and also fails when a
/// fixed file is accidentally left in this list, so the debt can only shrink.
const _knownDebt = <String>{};
const _strictCleanupHelpers = <String>{
  'apps/kt_wallet/integration_test/support/e2e_wallet_cleanup.dart',
  'apps/cold_signer/integration_test/support/e2e_wallet_cleanup.dart',
};

void main() {
  final selfTestFailures = <String>[
    ..._classifierSelfTestFailures(),
    ..._cleanupTargetSelfTestFailures(),
    ..._cleanupHelperSelfTestFailures(),
    ..._staleReplacementHelperSelfTestFailures(),
    ..._deleteOnlyEntrypointSelfTestFailures(),
  ];
  if (selfTestFailures.isNotEmpty) {
    for (final failure in selfTestFailures) {
      stderr.writeln('E2E cleanup audit self-test failed: $failure');
    }
    exitCode = 70;
    return;
  }

  final root = Directory.current;
  if (!File('${root.path}/pubspec.yaml').existsSync()) {
    stderr.writeln('Run this audit from the KT-Wallet repository root.');
    exitCode = 64;
    return;
  }

  final missingCleanup = <String>{};
  var guardedStoreSites = 0;
  for (final relativeHelper in _strictCleanupHelpers) {
    final helper = File('${root.path}/$relativeHelper');
    if (!helper.existsSync() ||
        !_cleanupHelperIsStrict(helper.readAsStringSync())) {
      missingCleanup.add(_relativePath(root.path, helper.path));
    }
  }
  final walletHelper = File(
    '${root.path}/apps/kt_wallet/integration_test/support/e2e_wallet_cleanup.dart',
  );
  if (!walletHelper.existsSync() ||
      !_staleReplacementHelperIsStrict(walletHelper.readAsStringSync())) {
    missingCleanup.add(_relativePath(root.path, walletHelper.path));
  }
  for (final relativeRoot in const [
    'apps/kt_wallet/integration_test',
    'apps/cold_signer/integration_test',
  ]) {
    final directory = Directory('${root.path}/$relativeRoot');
    if (!directory.existsSync()) continue;
    for (final entity in directory.listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      final audit = _auditCleanup(source);
      final relativePath = _relativePath(root.path, entity.path);
      guardedStoreSites += audit.nativeStoreSites;
      if (audit.missingWalletIds.isNotEmpty ||
          (!_strictCleanupHelpers.contains(relativePath) &&
              audit.nativeStoreSites == 0 &&
              audit.nativeDeleteSites > 0)) {
        missingCleanup.add(relativePath);
      }
    }
  }

  final untracked = missingCleanup.difference(_knownDebt).toList()..sort();
  final stale = _knownDebt.difference(missingCleanup).toList()..sort();
  if (untracked.isNotEmpty || stale.isNotEmpty) {
    if (untracked.isNotEmpty) {
      stderr.writeln('New E2E wallet cleanup debt:');
      for (final path in untracked) {
        stderr.writeln('  $path');
      }
    }
    if (stale.isNotEmpty) {
      stderr.writeln('Remove resolved entries from _knownDebt:');
      for (final path in stale) {
        stderr.writeln('  $path');
      }
    }
    exitCode = 1;
    return;
  }

  stdout.writeln(
    'E2E wallet cleanup audit passed: '
    '$guardedStoreSites native store sites, 0 cleanup debts.',
  );
}

final class _CleanupHelperVisitor extends RecursiveAstVisitor<void> {
  final List<MethodInvocation> tearDownCalls = <MethodInvocation>[];
  final List<MethodInvocation> storeCalls = <MethodInvocation>[];
  final List<MethodInvocation> registrationCalls = <MethodInvocation>[];
  final List<MethodInvocation> deleteCalls = <MethodInvocation>[];
  final List<CatchClause> catches = <CatchClause>[];

  @override
  void visitMethodInvocation(MethodInvocation node) {
    switch (node.methodName.name) {
      case 'addTearDown':
        tearDownCalls.add(node);
      case 'storeWallet':
        storeCalls.add(node);
      case 'registerE2eWalletCleanup':
        registrationCalls.add(node);
      case 'deleteWallet':
        deleteCalls.add(node);
    }
    super.visitMethodInvocation(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    catches.add(node);
    super.visitCatchClause(node);
  }
}

bool _staleReplacementHelperIsStrict(String source) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  final functions = parsed.unit.declarations
      .whereType<FunctionDeclaration>()
      .where((node) => node.name.lexeme == 'storeE2eWallet')
      .toList(growable: false);
  if (functions.length != 1) return false;
  final function = functions.single;
  final parameters = function.functionExpression.parameters?.toSource() ?? '';
  final functionSource = function.toSource();
  if (!RegExp(r'\bCoreCrypto\s+crypto\b').hasMatch(parameters) ||
      !RegExp(r'\brequired\s+String\s+walletId\b').hasMatch(parameters) ||
      !RegExp(r'\brequired\s+String\s+mnemonic\b').hasMatch(parameters) ||
      !RegExp(r'\bDuration\s+timeout\b').hasMatch(parameters) ||
      !functionSource.contains("!walletId.startsWith('kt-e2e-')") ||
      !functionSource.contains('throw ArgumentError.value(')) {
    return false;
  }

  final visitor = _CleanupHelperVisitor();
  function.functionExpression.body.accept(visitor);
  if (visitor.storeCalls.length != 2 ||
      visitor.registrationCalls.length != 2 ||
      visitor.deleteCalls.length != 1 ||
      visitor.catches.length != 1 ||
      visitor.catches.single.exceptionType?.toSource() !=
          'WalletAlreadyExistsException') {
    return false;
  }
  for (final store in visitor.storeCalls) {
    if (store.target?.toSource() != 'crypto' ||
        _namedArgument(store, 'walletId') != 'walletId' ||
        _namedArgument(store, 'mnemonic') != 'mnemonic') {
      return false;
    }
  }
  for (final registration in visitor.registrationCalls) {
    final arguments = _positionalArguments(registration);
    if (arguments.length != 2 ||
        arguments[0].toSource() != 'crypto' ||
        arguments[1].toSource() != 'walletId' ||
        _namedArgument(registration, 'timeout') != 'timeout') {
      return false;
    }
  }

  final deletion = visitor.deleteCalls.single;
  final deletionArguments = _positionalArguments(deletion);
  final timeoutCall = deletion.parent;
  final catchClause = visitor.catches.single;
  if (deletion.target?.toSource() != 'crypto' ||
      deletionArguments.length != 1 ||
      deletionArguments.single.toSource() != 'walletId' ||
      timeoutCall is! MethodInvocation ||
      timeoutCall.methodName.name != 'timeout' ||
      !identical(timeoutCall.target, deletion) ||
      _positionalArguments(timeoutCall).singleOrNull?.toSource() != 'timeout' ||
      deletion.offset < catchClause.offset ||
      deletion.end > catchClause.end) {
    return false;
  }

  final audit = _auditCleanup(functionSource);
  return audit.nativeStoreSites == 2 && audit.missingWalletIds.isEmpty;
}

List<String> _staleReplacementHelperSelfTestFailures() {
  const strict = '''
Future<void> storeE2eWallet(CoreCrypto crypto, {required String walletId, required String mnemonic, Duration timeout = const Duration(seconds: 45)}) async {
  if (!walletId.startsWith('kt-e2e-')) { throw ArgumentError.value(walletId); }
  try {
    await crypto.storeWallet(walletId: walletId, mnemonic: mnemonic).timeout(timeout);
    registerE2eWalletCleanup(crypto, walletId, timeout: timeout);
    return;
  } on WalletAlreadyExistsException {
    await crypto.deleteWallet(walletId).timeout(timeout);
  }
  await crypto.storeWallet(walletId: walletId, mnemonic: mnemonic).timeout(timeout);
  registerE2eWalletCleanup(crypto, walletId, timeout: timeout);
}
''';
  final cases = <({String name, String source, bool accepted})>[
    (
      name: 'strict stale E2E replacement helper is accepted',
      source: strict,
      accepted: true,
    ),
    (
      name: 'stale helper without reserved namespace is rejected',
      source: strict.replaceFirst(
        "if (!walletId.startsWith('kt-e2e-')) { throw ArgumentError.value(walletId); }",
        '',
      ),
      accepted: false,
    ),
    (
      name: 'stale helper swallowing authenticated deletion is rejected',
      source: strict.replaceFirst(
        'await crypto.deleteWallet(walletId).timeout(timeout);',
        'try { await crypto.deleteWallet(walletId).timeout(timeout); } on AuthFailedException {}',
      ),
      accepted: false,
    ),
    (
      name: 'stale helper registering another wallet is rejected',
      source: strict.replaceFirst(
        'registerE2eWalletCleanup(crypto, walletId, timeout: timeout);',
        'registerE2eWalletCleanup(crypto, otherId, timeout: timeout);',
      ),
      accepted: false,
    ),
  ];
  return [
    for (final item in cases)
      if (_staleReplacementHelperIsStrict(item.source) != item.accepted)
        item.name,
  ];
}

bool _cleanupHelperIsStrict(String source) {
  final parsed = parseString(content: source, throwIfDiagnostics: false);
  final functions = parsed.unit.declarations
      .whereType<FunctionDeclaration>()
      .where((node) => node.name.lexeme == 'registerE2eWalletCleanup')
      .toList(growable: false);
  if (functions.length != 1) return false;
  final function = functions.single;
  final parameters = function.functionExpression.parameters?.toSource() ?? '';
  if (!RegExp(r'\bCoreCrypto\s+crypto\b').hasMatch(parameters) ||
      !RegExp(r'\bString\s+walletId\b').hasMatch(parameters) ||
      !RegExp(r'\bDuration\s+timeout\b').hasMatch(parameters)) {
    return false;
  }

  final visitor = _CleanupHelperVisitor();
  function.functionExpression.body.accept(visitor);
  if (visitor.tearDownCalls.length != 1 || visitor.deleteCalls.length != 1) {
    return false;
  }
  final teardown = visitor.tearDownCalls.single;
  final deletion = visitor.deleteCalls.single;
  if (!identical(_owningTearDown(deletion), teardown) ||
      deletion.target?.toSource() != 'crypto') {
    return false;
  }
  final deletionArguments = _positionalArguments(deletion);
  if (deletionArguments.length != 1 ||
      deletionArguments.single.toSource() != 'walletId') {
    return false;
  }
  final timeoutCall = deletion.parent;
  if (timeoutCall is! MethodInvocation ||
      timeoutCall.methodName.name != 'timeout' ||
      !identical(timeoutCall.target, deletion)) {
    return false;
  }
  final timeoutArguments = _positionalArguments(timeoutCall);
  if (timeoutArguments.length != 1 ||
      timeoutArguments.single.toSource() != 'timeout') {
    return false;
  }
  final catches = visitor.catches
      .where(
        (clause) =>
            clause.offset >= teardown.offset && clause.end <= teardown.end,
      )
      .toList(growable: false);
  return catches.length == 1 &&
      catches.single.exceptionType?.toSource() == 'WalletNotFoundException';
}

List<String> _cleanupHelperSelfTestFailures() {
  const cases = <({String name, String source, bool accepted})>[
    (
      name: 'strict authenticated cleanup helper is accepted',
      source:
          'void registerE2eWalletCleanup(CoreCrypto crypto, String walletId, {Duration timeout = const Duration(seconds: 45)}) { addTearDown(() async { try { await crypto.deleteWallet(walletId).timeout(timeout); } on WalletNotFoundException {} }); }',
      accepted: true,
    ),
    (
      name: 'no-op cleanup helper is rejected',
      source:
          'void registerE2eWalletCleanup(CoreCrypto crypto, String walletId) {}',
      accepted: false,
    ),
    (
      name: 'cleanup helper swallowing timeout is rejected',
      source:
          'void registerE2eWalletCleanup(CoreCrypto crypto, String walletId, {Duration timeout = const Duration(seconds: 45)}) { addTearDown(() async { try { await crypto.deleteWallet(walletId).timeout(timeout); } on TimeoutException {} }); }',
      accepted: false,
    ),
  ];
  return [
    for (final item in cases)
      if (_cleanupHelperIsStrict(item.source) != item.accepted) item.name,
  ];
}

typedef _CleanupAudit = ({
  int nativeStoreSites,
  int nativeDeleteSites,
  Set<String> missingWalletIds,
});

final class _StoreSite {
  const _StoreSite({
    required this.walletId,
    required this.target,
    required this.statement,
  });

  final String walletId;
  final String? target;
  final Statement? statement;
}

final class _RegistrationSite {
  const _RegistrationSite({
    required this.walletId,
    required this.target,
    required this.statement,
  });

  final String walletId;
  final String? target;
  final Statement? statement;
}

final class _FinallyDeletionSite {
  const _FinallyDeletionSite({
    required this.walletId,
    required this.target,
    required this.owner,
  });

  final String walletId;
  final String? target;
  final TryStatement owner;
}

final class _CleanupVisitor extends RecursiveAstVisitor<void> {
  final Set<String> mockVariables = <String>{};
  final List<_StoreSite> stores = <_StoreSite>[];
  final List<String?> deletionTargets = <String?>[];
  final List<_RegistrationSite> registrations = <_RegistrationSite>[];
  final List<_FinallyDeletionSite> finallyDeletions = <_FinallyDeletionSite>[];

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final initializer = node.initializer?.toSource();
    if (initializer != null &&
        RegExp(r'^MockCoreCrypto\s*\(').hasMatch(initializer)) {
      mockVariables.add(node.name.lexeme);
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final method = node.methodName.name;
    if (method == 'storeWallet') {
      stores.add(
        _StoreSite(
          walletId:
              _namedArgument(node, 'walletId') ??
              '<unknown-store@${node.offset}>',
          target: node.target?.toSource(),
          statement: _statementFor(node),
        ),
      );
    } else if (method == 'registerE2eWalletCleanup') {
      final arguments = _positionalArguments(node);
      registrations.add(
        _RegistrationSite(
          walletId: arguments.length > 1
              ? arguments[1].toSource()
              : '<unknown-registration@${node.offset}>',
          target: arguments.isNotEmpty ? arguments.first.toSource() : null,
          statement: _statementFor(node),
        ),
      );
    } else if (method == 'deleteWallet') {
      deletionTargets.add(node.target?.toSource());
      final arguments = _positionalArguments(node);
      final walletId = arguments.isNotEmpty
          ? arguments.first.toSource()
          : '<unknown-deletion@${node.offset}>';
      final finallyOwner = _owningFinally(node);
      if (finallyOwner != null &&
          !_deletionFailureCanBeSwallowed(node, finallyOwner.finallyBlock!)) {
        finallyDeletions.add(
          _FinallyDeletionSite(
            walletId: walletId,
            target: node.target?.toSource(),
            owner: finallyOwner,
          ),
        );
      }
      final teardown = _owningTearDown(node);
      if (teardown != null && !_deletionFailureCanBeSwallowed(node, teardown)) {
        registrations.add(
          _RegistrationSite(
            walletId: walletId,
            target: node.target?.toSource(),
            statement: _statementFor(teardown),
          ),
        );
      }
    }
    super.visitMethodInvocation(node);
  }
}

_CleanupAudit _auditCleanup(String source) {
  final isFragment = !RegExp(
    r'\b(?:void|Future\s*<\s*void\s*>)\s+main\s*\(',
  ).hasMatch(source);
  final parsed = parseString(
    content: isFragment
        ? 'Future<void> _auditFragment() async { $source }'
        : source,
    throwIfDiagnostics: false,
  );
  final visitor = _CleanupVisitor();
  parsed.unit.accept(visitor);
  final nativeStores = visitor.stores
      .where((store) {
        final target = store.target;
        if (target == null) return true;
        if (visitor.mockVariables.contains(target)) return false;
        return !RegExp(r'^MockCoreCrypto\s*\(').hasMatch(target);
      })
      .toList(growable: false);
  final nativeDeleteSites = visitor.deletionTargets.where((target) {
    if (target == null) return true;
    if (visitor.mockVariables.contains(target)) return false;
    return !RegExp(r'^MockCoreCrypto\s*\(').hasMatch(target);
  }).length;

  final missing = <String>{};
  for (final store in nativeStores) {
    final hasImmediateRegistration = visitor.registrations.any(
      (registration) =>
          registration.walletId == store.walletId &&
          _cleanupTargetsMatch(store.target, registration.target) &&
          _isImmediatelyAfter(store.statement, registration.statement),
    );
    final hasFinallyDeletion = visitor.finallyDeletions.any(
      (deletion) =>
          deletion.walletId == store.walletId &&
          _cleanupTargetsMatch(store.target, deletion.target) &&
          _finallyCoversStore(deletion.owner, store.statement),
    );
    if (!hasImmediateRegistration && !hasFinallyDeletion) {
      missing.add(store.walletId);
    }
  }
  return (
    nativeStoreSites: nativeStores.length,
    nativeDeleteSites: nativeDeleteSites,
    missingWalletIds: Set<String>.unmodifiable(missing),
  );
}

bool _cleanupTargetsMatch(String? storeTarget, String? cleanupTarget) =>
    storeTarget == cleanupTarget ||
    (storeTarget == 'super' && cleanupTarget == 'this');

List<String> _cleanupTargetSelfTestFailures() => <String>[
  if (!_cleanupTargetsMatch('super', 'this'))
    'super store must be cleanable through the current instance',
  if (_cleanupTargetsMatch('super', 'other'))
    'super store must not be cleanable through another instance',
  if (_cleanupTargetsMatch('native', 'other'))
    'unrelated crypto instances must remain distinct',
];

String? _namedArgument(MethodInvocation node, String name) {
  for (final argument in node.argumentList.arguments) {
    if (argument is NamedExpression && argument.name.label.name == name) {
      return argument.expression.toSource();
    }
  }
  return null;
}

List<Expression> _positionalArguments(MethodInvocation node) => node
    .argumentList
    .arguments
    .whereType<Expression>()
    .where((argument) => argument is! NamedExpression)
    .toList(growable: false);

Statement? _statementFor(AstNode node) {
  AstNode? current = node;
  while (current != null) {
    if (current is Statement) return current;
    current = current.parent;
  }
  return null;
}

TryStatement? _owningFinally(AstNode node) {
  AstNode? current = node;
  while (current != null) {
    if (current is Block && current.parent is TryStatement) {
      final owner = current.parent! as TryStatement;
      if (identical(owner.finallyBlock, current)) return owner;
    }
    current = current.parent;
  }
  return null;
}

MethodInvocation? _owningTearDown(AstNode node) {
  AstNode? current = node.parent;
  while (current != null) {
    if (current is MethodInvocation &&
        current.methodName.name == 'addTearDown') {
      return current;
    }
    if (current is FunctionDeclaration || current is CompilationUnit) {
      return null;
    }
    current = current.parent;
  }
  return null;
}

bool _deletionFailureCanBeSwallowed(AstNode node, AstNode boundary) {
  AstNode? current = node;
  while (current != null && !identical(current, boundary)) {
    if (current is Block && current.parent is TryStatement) {
      final owner = current.parent! as TryStatement;
      if (identical(owner.body, current) && owner.catchClauses.isNotEmpty) {
        return true;
      }
    }
    current = current.parent;
  }
  return false;
}

bool _isImmediatelyAfter(Statement? first, Statement? second) {
  if (first == null || second == null) return false;
  final parent = first.parent;
  if (parent is! Block || !identical(parent, second.parent)) return false;
  final index = parent.statements.indexOf(first);
  return index >= 0 &&
      index + 1 < parent.statements.length &&
      identical(parent.statements[index + 1], second);
}

bool _finallyCoversStore(TryStatement owner, Statement? store) {
  if (store == null) return false;
  if (store.offset >= owner.body.offset && store.end <= owner.body.end) {
    return true;
  }
  return _isImmediatelyAfter(store, owner);
}

bool _requiresAuthenticatedCleanup(String source) =>
    _auditCleanup(source).nativeStoreSites > 0;

bool _hasAuthenticatedCleanup(String source) {
  final audit = _auditCleanup(source);
  return audit.nativeStoreSites > 0 && audit.missingWalletIds.isEmpty;
}

List<String> _deleteOnlyEntrypointSelfTestFailures() {
  const cases = <({String name, String source, bool accepted})>[
    (
      name: 'native delete-only entrypoint is rejected',
      source:
          'final c = MethodChannelCoreCrypto(); await c.deleteWallet(walletId);',
      accepted: false,
    ),
    (
      name: 'mock delete-only entrypoint has no native side effect',
      source: 'final c = MockCoreCrypto(); await c.deleteWallet(walletId);',
      accepted: true,
    ),
    (
      name: 'native store with authenticated cleanup remains accepted',
      source:
          'final c = MethodChannelCoreCrypto(); await c.storeWallet(walletId: walletId); registerE2eWalletCleanup(c, walletId);',
      accepted: true,
    ),
  ];
  return [
    for (final item in cases)
      if (_deleteOnlyEntrypointAccepted(item.source) != item.accepted)
        item.name,
  ];
}

bool _deleteOnlyEntrypointAccepted(String source) {
  final audit = _auditCleanup(source);
  return audit.nativeDeleteSites == 0 || audit.nativeStoreSites > 0;
}

List<String> _classifierSelfTestFailures() {
  const cases = <({String name, String source, bool requiresCleanup, bool hasCleanup})>[
    (
      name: 'native wallet without teardown is rejected',
      source:
          'final c = MethodChannelCoreCrypto(); await c.storeWallet(walletId: id);',
      requiresCleanup: true,
      hasCleanup: false,
    ),
    (
      name: 'registered production-auth teardown is accepted',
      source:
          'final c = MethodChannelCoreCrypto(); await c.storeWallet(walletId: id); registerE2eWalletCleanup(c, id);',
      requiresCleanup: true,
      hasCleanup: true,
    ),
    (
      name: 'production deletion in finally is accepted',
      source:
          'final c = MethodChannelCoreCrypto(); await c.storeWallet(walletId: id); try {} finally { await c.deleteWallet(id); }',
      requiresCleanup: true,
      hasCleanup: true,
    ),
    (
      name: 'known in-memory mock does not claim native key storage',
      source: 'final c = MockCoreCrypto(); await c.storeWallet(walletId: id);',
      requiresCleanup: false,
      hasCleanup: false,
    ),
    (
      name: 'mixed mock and native test remains guarded',
      source:
          'final m = MockCoreCrypto(); final c = MethodChannelCoreCrypto(); await c.storeWallet(walletId: id);',
      requiresCleanup: true,
      hasCleanup: false,
    ),
    (
      name: 'unknown implementation remains fail closed',
      source: 'await crypto.storeWallet(walletId: id);',
      requiresCleanup: true,
      hasCleanup: false,
    ),
    (
      name: 'cleanup text in a comment is rejected',
      source:
          'final c = MethodChannelCoreCrypto(); await c.storeWallet(walletId: id); // registerE2eWalletCleanup(c, id);',
      requiresCleanup: true,
      hasCleanup: false,
    ),
    (
      name: 'cleanup for another wallet id is rejected',
      source:
          'final c = MethodChannelCoreCrypto(); await c.storeWallet(walletId: first); registerE2eWalletCleanup(c, second);',
      requiresCleanup: true,
      hasCleanup: false,
    ),
    (
      name: 'cleanup through another crypto instance is rejected',
      source:
          'final native = MethodChannelCoreCrypto(); final other = MethodChannelCoreCrypto(); await native.storeWallet(walletId: id); registerE2eWalletCleanup(other, id);',
      requiresCleanup: true,
      hasCleanup: false,
    ),
    (
      name: 'ordinary-path deletion is not a teardown guarantee',
      source:
          'final c = MethodChannelCoreCrypto(); await c.storeWallet(walletId: id); await c.deleteWallet(id);',
      requiresCleanup: true,
      hasCleanup: false,
    ),
    (
      name: 'one cleanup cannot cover two wallet ids',
      source:
          'final c = MethodChannelCoreCrypto(); await c.storeWallet(walletId: first); await c.storeWallet(walletId: second); registerE2eWalletCleanup(c, first);',
      requiresCleanup: true,
      hasCleanup: false,
    ),
    (
      name: 'same-id deletion in finally is accepted',
      source:
          'final c = MethodChannelCoreCrypto(); await c.storeWallet(walletId: id); try {} finally { await c.deleteWallet(id); }',
      requiresCleanup: true,
      hasCleanup: true,
    ),
    (
      name: 'same-id deletion in addTearDown is accepted',
      source:
          'final c = MethodChannelCoreCrypto(); await c.storeWallet(walletId: id); addTearDown(() => c.deleteWallet(id));',
      requiresCleanup: true,
      hasCleanup: true,
    ),
    (
      name: 'swallowed teardown failure is rejected',
      source:
          'final c = MethodChannelCoreCrypto(); await c.storeWallet(walletId: id); try {} finally { try { await c.deleteWallet(id); } on TimeoutException {} }',
      requiresCleanup: true,
      hasCleanup: false,
    ),
  ];

  final failures = <String>[];
  for (final item in cases) {
    if (_requiresAuthenticatedCleanup(item.source) != item.requiresCleanup ||
        _hasAuthenticatedCleanup(item.source) != item.hasCleanup) {
      failures.add(item.name);
    }
  }
  return failures;
}

String _relativePath(String root, String path) {
  final prefix = root.endsWith(Platform.pathSeparator)
      ? root
      : '$root${Platform.pathSeparator}';
  return path.startsWith(prefix) ? path.substring(prefix.length) : path;
}

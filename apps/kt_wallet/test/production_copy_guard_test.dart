import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('production UI copy is localized instead of embedded in widgets', () {
    final root = _workspaceRoot();
    final findings = <String>[];

    for (final app in const ['kt_wallet', 'cold_signer']) {
      final lib = Directory('${root.path}/apps/$app/lib');
      for (final entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final relative = entity.path.substring(root.path.length + 1);
        if (relative.contains('/l10n/')) continue;
        if (_excludedProductionCopyFile(relative)) continue;

        findings.addAll(_findEmbeddedCopy(relative, entity.readAsStringSync()));
      }
    }

    expect(
      findings,
      isEmpty,
      reason:
          'Move user-facing copy into each app\'s ARB files. Only protocol '
          'symbols, language self-names and explicit gallery fixtures are '
          'allowed as literals.\n${findings.join('\n')}',
    );
  });

  test('production copy guard catches interpolated error helper messages', () {
    const relative = 'apps/kt_wallet/lib/src/screens/example.dart';
    final findings = _findEmbeddedCopy(relative, r'''
void showErrors(BuildContext context, TransferDraft draft) {
  _showTransferError(
    context,
    'No active network for ${draft.chain.name}',
  );
  _showTransferError(context, 'Missing EVM chain ID');
}
''');

    expect(
      findings,
      contains(
        '$relative embeds UI error '
        '"No active network for \${draft.chain.name}"',
      ),
    );
    expect(
      findings,
      contains('$relative embeds UI error "Missing EVM chain ID"'),
    );
  });

  test('production copy guard catches conditional accessibility labels', () {
    const relative = 'apps/kt_wallet/lib/src/widgets/example.dart';
    final findings = _findEmbeddedCopy(
      relative,
      "label: value == 'del' ? 'Delete' : value,",
    );

    expect(
      findings,
      contains('$relative embeds conditional UI label "Delete"'),
    );
  });
}

List<String> _findEmbeddedCopy(String relative, String rawSource) {
  final findings = <String>[];
  final source = _withoutComments(rawSource);

  for (final match in _directText.allMatches(source)) {
    final value = match.group(2)!;
    if (_isDynamic(value) || _allowedProtocolTextLiteral(value)) continue;
    findings.add('$relative embeds Text("$value")');
  }
  for (final match in _namedUiCopy.allMatches(source)) {
    final value = match.group(2)!;
    if (_isDynamic(value) || _allowedProtocolUiLiteral(value)) continue;
    findings.add('$relative embeds UI label "$value"');
  }
  for (final match in _conditionalNamedUiCopy.allMatches(source)) {
    final value = match.group(2)!;
    if (_isDynamic(value) || _allowedProtocolUiLiteral(value)) continue;
    findings.add('$relative embeds conditional UI label "$value"');
  }
  for (final match in _uiMessageCall.allMatches(source)) {
    final value = match.group(2)!;
    if (_allowedProtocolUiLiteral(value)) continue;
    findings.add('$relative embeds UI error "$value"');
  }
  for (final match in _cjkLiteral.allMatches(source)) {
    final value = match.group(2)!;
    if (_allowedCjkLiteral(relative, value)) continue;
    findings.add('$relative embeds CJK copy "$value"');
  }

  return findings;
}

final _directText = RegExp(
  r'''(?:Text|SelectableText)\s*\(\s*(?:const\s+)?(['"])([^'"\n]+)\1''',
);

final _namedUiCopy = RegExp(
  r'''(?:title|subtitle|label|hintText|helperText|errorText|tooltip|message)\s*:\s*(?:const\s+)?(['"])([^'"\n]+)\1''',
);

// A user-facing literal can hide behind a ternary expression, for example an
// accessibility label that is only used for the delete key. Scan the literal
// selected by the true branch instead of allowing the condition to bypass the
// direct named-property rule above.
final _conditionalNamedUiCopy = RegExp(
  r'''(?:title|subtitle|label|hintText|helperText|errorText|tooltip|message)\s*:\s*[^\n,;]*\?\s*(?:const\s+)?(['"])([^'"\n]+)\1''',
);

// Helper methods that ultimately render a Snackbar are still presentation
// boundaries. A literal passed through one of these helpers would bypass the
// direct Text(...) and named-property checks above.
final _uiMessageCall = RegExp(
  r'''(?:_?show[A-Za-z0-9]*Error|_?show[A-Za-z0-9]*Message)\s*\(\s*[^,\n]+,\s*(?:const\s+)?(['"])([^'"\n]+)\1''',
);

final _cjkLiteral = RegExp(r'''(['"])([^'"\n]*[\u3400-\u9fff][^'"\n]*)\1''');

Directory _workspaceRoot() {
  var current = Directory.current.absolute;
  while (true) {
    if (File('${current.path}/apps/kt_wallet/pubspec.yaml').existsSync() &&
        File('${current.path}/apps/cold_signer/pubspec.yaml').existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      throw StateError('KT-Wallet workspace root not found');
    }
    current = parent;
  }
}

String _withoutComments(String source) => source
    .replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '')
    .replaceAll(RegExp(r'//.*$', multiLine: true), '');

bool _excludedProductionCopyFile(String path) =>
    path.endsWith('/src/app_router.dart') ||
    path.endsWith('/src/signer_router.dart') ||
    path.endsWith('/src/signing/demo_airgap.dart');

bool _allowedProtocolUiLiteral(String value) =>
    const {'0', 'USDT', 'TRON · TRC-20'}.contains(value);

bool _allowedProtocolTextLiteral(String value) => const {
  'KT Wallet',
  '3,120.00 USDT',
  '-120.00 USDT',
  'REQ-9AB301 · TRON',
}.contains(value);

bool _isDynamic(String value) => value.contains(r'$');

bool _allowedCjkLiteral(String path, String value) {
  final allowed = <String, Set<String>>{
    'apps/kt_wallet/lib/main.dart': {'日常钱包', '储蓄钱包', '主钱包'},
    'apps/kt_wallet/lib/src/state/wallet_scope.dart': {'日常钱包'},
    'apps/kt_wallet/lib/src/wallets/pairing_airgap.dart': {'主钱包'},
    'apps/kt_wallet/lib/src/screens/settings_screens.dart': {'简体中文', '日本語'},
    'apps/kt_wallet/lib/src/screens/transfer_screens.dart': {'主钱包 TQm9…3kFa'},
    'apps/cold_signer/lib/src/screens/signer_settings_screens.dart': {
      '简体中文',
      '日本語',
    },
  };
  return allowed[path]?.contains(value) ?? false;
}

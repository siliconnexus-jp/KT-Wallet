// Local disposable E2E credential batch guard.
//
// This tool never prints or derives the mnemonic. It validates freshness and
// permissions, and can scan generated reports before they are shared.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:test_support/e2e_credentials.dart';

const _defaultConfig = 'apps/kt_wallet/integration_test/.sepolia-e2e.json';

void main(List<String> args) {
  if (args.isEmpty || args.contains('--help') || args.contains('-h')) {
    _usage();
    return;
  }

  final command = args.first;
  final options = _parseOptions(args.skip(1).toList());
  switch (command) {
    case 'provision':
      _provision(options);
    case 'validate':
      _validate(options);
    case 'scan':
      _scan(options);
    default:
      stderr.writeln('Unknown command: $command');
      _usage();
      exitCode = 64;
  }
}

void _provision(Map<String, List<String>> options) {
  final output = _single(options, '--output') ?? _defaultConfig;
  final daysText = _single(options, '--days') ?? '14';
  final days = int.tryParse(daysText);
  if (days == null || days < 1 || days > 14) {
    _fail(['--days must be between 1 and 14']);
  }
  if (FileSystemEntity.typeSync(output, followLinks: false) !=
      FileSystemEntityType.notFound) {
    _fail([
      'refusing to overwrite $output; archive the previous batch explicitly',
    ]);
  }
  if (!stdin.hasTerminal) {
    _fail(['provision requires an interactive terminal with hidden input']);
  }

  stdout.writeln(
    'Generate a fresh 12/18/24-word phrase in KT Wallet or KT Cold Signer.',
  );
  stdout.write('Paste it once (input hidden): ');
  final oldEcho = stdin.echoMode;
  String mnemonic;
  try {
    stdin.echoMode = false;
    mnemonic = stdin.readLineSync()?.trim() ?? '';
  } finally {
    stdin.echoMode = oldEcho;
    stdout.writeln();
  }

  final now = DateTime.now().toUtc();
  final batchId = _newBatchId(now);
  final document = buildE2eCredentialDocument(
    batchId: batchId,
    createdAtUtc: now,
    lifetime: Duration(days: days),
    mnemonic: mnemonic,
  );
  final failures = validateE2eCredentialDocument(document, nowUtc: now);
  if (failures.isNotEmpty) _fail(failures);

  final file = File(output);
  file.parent.createSync(recursive: true);
  file.createSync(exclusive: true);
  final chmod = Process.runSync('chmod', ['600', output]);
  if (chmod.exitCode != 0) {
    file.deleteSync();
    _fail(['could not set credential file mode 0600']);
  }
  final handle = file.openSync(mode: FileMode.writeOnly);
  try {
    handle.writeStringSync(
      '${const JsonEncoder.withIndent('  ').convert(document)}\n',
    );
    handle.flushSync();
  } finally {
    handle.closeSync();
  }
  if (!hasPrivateCredentialFileMode(file.statSync().mode)) {
    file.deleteSync();
    _fail(['credential mode verification failed; incomplete file removed']);
  }
  stdout.writeln(
    'Created disposable E2E batch $batchId at $output (secret not printed).',
  );
  stdout.writeln('Native Wallet Core validation is required before funding.');
}

String _newBatchId(DateTime now) {
  final date =
      '${now.year.toString().padLeft(4, '0')}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}';
  final random = Random.secure();
  final suffix = List.generate(
    8,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'batch_${date}_$suffix';
}

void _validate(Map<String, List<String>> options) {
  final configPath = _single(options, '--config') ?? _defaultConfig;
  final loaded = _load(configPath);
  final failures = <String>[
    ...loaded.failures,
    if (!hasPrivateCredentialFileMode(loaded.mode))
      'credential file must have POSIX mode 0600',
  ];
  if (failures.isNotEmpty) _fail(failures);

  final batchId = loaded.document[e2eBatchIdKey] as String;
  final expires = loaded.document[e2eExpiresAtKey] as String;
  stdout.writeln('E2E credential batch valid: $batchId (expires $expires)');
}

void _scan(Map<String, List<String>> options) {
  final configPath = _single(options, '--config') ?? _defaultConfig;
  final roots = options['--path'] ?? const <String>[];
  if (roots.isEmpty) {
    _fail(['scan requires at least one --path']);
  }
  final loaded = _load(configPath);
  final failures = <String>[
    ...loaded.failures,
    if (!hasPrivateCredentialFileMode(loaded.mode))
      'credential file must have POSIX mode 0600',
  ];
  if (failures.isNotEmpty) _fail(failures);

  final mnemonic = loaded.document[e2eMnemonicKey] as String;
  var scanned = 0;
  for (final root in roots) {
    for (final file in _textFiles(root)) {
      scanned += 1;
      final labels = findE2eSecretLeakLabels(
        file.readAsStringSync(),
        mnemonic: mnemonic,
      );
      if (labels.isNotEmpty) {
        failures.add('${file.path} contains sensitive material: $labels');
      }
    }
  }
  if (failures.isNotEmpty) _fail(failures);
  stdout.writeln('E2E report secret scan passed: $scanned text files');
}

({Map<String, Object?> document, int mode, List<String> failures}) _load(
  String path,
) {
  final failures = <String>[];
  if (FileSystemEntity.typeSync(path, followLinks: false) !=
      FileSystemEntityType.file) {
    _fail(['credential path must be a regular, non-symlink file: $path']);
  }
  final file = File(path);
  Map<String, Object?> document = const {};
  try {
    final decoded = jsonDecode(file.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      failures.add('credential document must be a JSON object');
    } else {
      document = decoded;
      failures.addAll(
        validateE2eCredentialDocument(document, nowUtc: DateTime.now().toUtc()),
      );
    }
  } on FormatException {
    failures.add('credential document is not valid JSON');
  }
  return (document: document, mode: file.statSync().mode, failures: failures);
}

Iterable<File> _textFiles(String root) sync* {
  final type = FileSystemEntity.typeSync(root, followLinks: false);
  if (type == FileSystemEntityType.file) {
    final file = File(root);
    if (isE2eSecretScanTextPath(file.path)) yield file;
    return;
  }
  if (type != FileSystemEntityType.directory) {
    _fail(['scan path does not exist or is a symlink: $root']);
  }
  for (final entity in Directory(root).listSync(recursive: true)) {
    if (entity is File && isE2eSecretScanTextPath(entity.path)) yield entity;
  }
}

Map<String, List<String>> _parseOptions(List<String> args) {
  final result = <String, List<String>>{};
  for (var i = 0; i < args.length; i += 2) {
    if (i + 1 >= args.length || !args[i].startsWith('--')) {
      _fail(['options must use --name value pairs']);
    }
    result.putIfAbsent(args[i], () => []).add(args[i + 1]);
  }
  return result;
}

String? _single(Map<String, List<String>> options, String name) {
  final values = options[name];
  if (values == null) return null;
  if (values.length != 1) _fail(['$name may be supplied only once']);
  return values.single;
}

Never _fail(List<String> failures) {
  for (final failure in failures) {
    stderr.writeln('E2E credential guard FAIL: $failure');
  }
  exit(1);
}

void _usage() {
  stdout.writeln('''
Usage:
  dart run tool/e2e_credential_guard.dart provision [--output FILE] [--days 1..14]
  dart run tool/e2e_credential_guard.dart validate [--config FILE]
  dart run tool/e2e_credential_guard.dart scan [--config FILE] --path PATH [--path PATH]

The JSON file must be a non-symlink regular file with mode 0600 and contain:
  KT_E2E_SCHEMA_VERSION, KT_E2E_BATCH_ID, KT_E2E_CREATED_AT_UTC,
  KT_E2E_EXPIRES_AT_UTC, SEPOLIA_E2E_MNEMONIC

Secret values are never printed.
''');
}

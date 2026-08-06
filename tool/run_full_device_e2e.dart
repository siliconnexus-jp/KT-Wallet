import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = _parseArgs(args);
  if (options.help) {
    _usage();
    return;
  }

  final repository = File.fromUri(Platform.script).parent.parent.absolute;
  final app = Directory('${repository.path}/apps/kt_wallet');
  final config = File(
    options.config ?? '${app.path}/integration_test/.sepolia-e2e.json',
  ).absolute;
  final output = Directory(
    options.output ?? '${app.path}/integration_test/.e2e-evidence',
  ).absolute;
  if (!config.existsSync()) {
    stderr.writeln('Missing E2E credential file: ${config.path}');
    exitCode = 66;
    return;
  }

  final validation = await Process.start(
    'dart',
    <String>[
      'run',
      'tool/e2e_credential_guard.dart',
      'validate',
      '--config',
      config.path,
    ],
    workingDirectory: repository.path,
    mode: ProcessStartMode.inheritStdio,
  );
  if (await validation.exitCode != 0) {
    exitCode = 1;
    return;
  }

  final device = options.device ?? await _findPhysicalIosDevice(repository);
  if (device == null) {
    stderr.writeln('No supported physical iOS device is connected.');
    exitCode = 69;
    return;
  }
  await output.create(recursive: true);
  final chmodRoot = await Process.run('chmod', <String>['go-rwx', output.path]);
  if (chmodRoot.exitCode != 0) {
    stderr.writeln('Could not make the evidence directory private.');
    exitCode = 73;
    return;
  }

  final target = switch (options.phase) {
    'full' => 'integration_test/full_device_journey_e2e_test.dart',
    'history-resume' =>
      'integration_test/full_device_history_resume_e2e_test.dart',
    'history-zero-detail' =>
      'integration_test/full_device_history_resume_e2e_test.dart',
    'history-local-explorer' =>
      'integration_test/full_device_history_resume_e2e_test.dart',
    _ => throw FormatException('Unknown phase: ${options.phase}'),
  };
  Directory? temporaryDefinesDirectory;
  var defines = <String>['--dart-define-from-file=${config.path}'];
  if (options.phase == 'history-resume' ||
      options.phase == 'history-zero-detail' ||
      options.phase == 'history-local-explorer') {
    final report = _findResumeReport(output, options.resumeReport);
    final payload = _historyResumePayload(report);
    temporaryDefinesDirectory = await Directory.systemTemp.createTemp(
      'kt-wallet-history-resume-',
    );
    final defineFile = File('${temporaryDefinesDirectory.path}/defines.json');
    await defineFile.writeAsString(
      jsonEncode(<String, String>{
        'KT_E2E_HISTORY_RESUME_JSON': jsonEncode(payload),
        'KT_E2E_HISTORY_RESUME_MODE': options.phase,
      }),
      flush: true,
    );
    await Process.run('chmod', <String>['600', defineFile.path]);
    defines = <String>['--dart-define-from-file=${defineFile.path}'];
    stdout.writeln(
      'Running only the history-resume phase from ${report.path} on $device.',
    );
    stdout.writeln(
      'Wallet creation, mnemonic import, receive walkthrough and new '
      'transfers are skipped.',
    );
  } else {
    stdout.writeln('Running the complete real-device journey on $device.');
  }
  stdout.writeln(
    'The private report contains unredacted mnemonics and will be copied to '
    '${output.path}.',
  );
  late final int code;
  try {
    final process = await Process.start(
      'flutter',
      <String>[
        'drive',
        '--driver=test_driver/full_device_e2e_driver.dart',
        '--target=$target',
        '-d',
        device,
        ...defines,
        '--dart-define=KT_E2E_DEVICE_UDID=$device',
      ],
      workingDirectory: app.path,
      environment: <String, String>{
        ...Platform.environment,
        'KT_E2E_OUTPUT_DIR': output.path,
      },
      mode: ProcessStartMode.inheritStdio,
    );
    code = await process.exitCode;
  } finally {
    await temporaryDefinesDirectory?.delete(recursive: true);
  }
  if (code != 0) {
    stderr.writeln(
      'Full-device E2E failed. If the app reached the test body, a partial '
      'private report was still copied.',
    );
    exitCode = code;
    return;
  }
  stdout.writeln('Full-device ${options.phase} E2E passed.');
}

File _findResumeReport(Directory output, String? explicitPath) {
  if (explicitPath != null) {
    final file = File(explicitPath).absolute;
    if (!file.existsSync()) {
      throw FormatException('Resume report does not exist: ${file.path}');
    }
    return file;
  }
  if (!output.existsSync()) {
    throw const FormatException('No private E2E evidence directory exists.');
  }
  final candidates =
      output
          .listSync()
          .whereType<Directory>()
          .map((directory) => File('${directory.path}/report.json'))
          .where((file) => file.existsSync())
          .toList()
        ..sort(
          (left, right) =>
              right.lastModifiedSync().compareTo(left.lastModifiedSync()),
        );
  for (final file in candidates) {
    try {
      final root = jsonDecode(file.readAsStringSync());
      if (root is Map<String, Object?> &&
          root['facts'] is Map<String, Object?> &&
          (root['facts']! as Map<String, Object?>)['sepolia_usdt_transaction']
              is Map<String, Object?>) {
        return file;
      }
    } on FormatException {
      // Ignore a partial/corrupt older artifact and keep searching.
    }
  }
  throw const FormatException(
    'No E2E report containing a completed Sepolia USDT transfer was found.',
  );
}

Map<String, Object?> _historyResumePayload(File report) {
  final root = jsonDecode(report.readAsStringSync());
  if (root is! Map<String, Object?> || root['facts'] is! Map<String, Object?>) {
    throw const FormatException('Resume report has an invalid root.');
  }
  final facts = root['facts']! as Map<String, Object?>;
  final funded = facts['funded_wallet_addresses'];
  final receiver = facts['created_wallet_addresses'];
  final transaction = facts['sepolia_usdt_transaction'];
  if (funded is! Map<String, Object?> ||
      receiver is! Map<String, Object?> ||
      transaction is! Map<String, Object?>) {
    throw const FormatException(
      'Resume report is missing wallet/transaction facts.',
    );
  }
  const expectedContract = '0xc4DCC311c028e341fd8602D8eB89c5de94625927';
  if ((funded['eth'] as String?)?.toLowerCase() !=
          '0xb787f3c2f96403b5a73dc66de68e4a6395d4e632' ||
      transaction['network_id'] != 'eth-sepolia' ||
      (transaction['contract'] as String?)?.toLowerCase() !=
          expectedContract.toLowerCase() ||
      transaction['amount_raw'] != '1000000' ||
      transaction['status'] != 'confirmed' ||
      (transaction['from'] as String?)?.toLowerCase() !=
          (funded['eth'] as String?)?.toLowerCase() ||
      (transaction['to'] as String?)?.toLowerCase() !=
          (receiver['eth'] as String?)?.toLowerCase() ||
      !_evmHash.hasMatch(transaction['hash'] as String? ?? '')) {
    throw const FormatException(
      'Resume report is not a confirmed real 1 USDT test-account transfer.',
    );
  }
  return <String, Object?>{
    'source_run_id': root['run_id'],
    'source_report': report.path,
    'funded_wallet_addresses': funded,
    'receiver_wallet_addresses': receiver,
    'transaction': transaction,
  };
}

final _evmHash = RegExp(r'^0x[0-9a-fA-F]{64}$');

Future<String?> _findPhysicalIosDevice(Directory repository) async {
  final result = await Process.run('flutter', const <String>[
    'devices',
    '--machine',
  ], workingDirectory: repository.path);
  if (result.exitCode != 0) return null;
  final decoded = jsonDecode(result.stdout as String);
  if (decoded is! List<Object?>) return null;
  for (final item in decoded) {
    if (item is! Map<Object?, Object?>) continue;
    if (item['targetPlatform'] == 'ios' &&
        item['emulator'] == false &&
        item['isSupported'] == true &&
        item['id'] is String) {
      return item['id']! as String;
    }
  }
  return null;
}

({
  String? device,
  String? config,
  String? output,
  String phase,
  String? resumeReport,
  bool help,
})
_parseArgs(List<String> args) {
  String? device;
  String? config;
  String? output;
  var phase = 'full';
  String? resumeReport;
  var help = false;
  for (var index = 0; index < args.length; index++) {
    final arg = args[index];
    if (arg == '--help' || arg == '-h') {
      help = true;
      continue;
    }
    if (arg != '--device' &&
        arg != '--config' &&
        arg != '--output' &&
        arg != '--phase' &&
        arg != '--resume-report') {
      throw FormatException('Unknown option: $arg');
    }
    if (++index >= args.length) {
      throw FormatException('$arg requires a value');
    }
    switch (arg) {
      case '--device':
        device = args[index];
      case '--config':
        config = args[index];
      case '--output':
        output = args[index];
      case '--phase':
        phase = args[index];
      case '--resume-report':
        resumeReport = args[index];
    }
  }
  return (
    device: device,
    config: config,
    output: output,
    phase: phase,
    resumeReport: resumeReport,
    help: help,
  );
}

void _usage() {
  stdout.writeln('''
Usage:
  dart run tool/run_full_device_e2e.dart [options]

Options:
  --device UDID   Physical iOS device; auto-detected when omitted
  --config FILE   Credential JSON (default: app's ignored Sepolia file)
  --output DIR    Private host evidence directory
  --phase NAME    full (default), history-resume, history-zero-detail,
                  or history-local-explorer
  --resume-report FILE
                  Prior private report for history-resume; newest compatible
                  report is selected automatically when omitted

The generated report intentionally contains complete unredacted mnemonics,
PIN, public addresses, balances, fees, transaction hashes, confirmations and
all structured visible UI/control state. The output directory is chmod 0700
and remains ignored by Git.
''');
}

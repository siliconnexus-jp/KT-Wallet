// Local fail-fast source gate for a KT Wallet public beta candidate.
//
// This is intentionally separate from signing and physical-device evidence.

import 'dart:io';

import 'package:test_support/public_beta_audit.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--help') || arguments.contains('-h')) {
    _usage();
    return;
  }
  final unknown = arguments
      .where((argument) => argument != '--full' && argument != '--list')
      .toList();
  if (unknown.isNotEmpty) {
    stderr.writeln('Unknown public-beta audit option: ${unknown.join(', ')}');
    _usage();
    exitCode = 64;
    return;
  }

  final root = _findRepositoryRoot();
  final includeDependencyAudit = arguments.contains('--full');
  final plan = buildPublicBetaAuditPlan(
    repoRoot: root.path,
    includeDependencyAudit: includeDependencyAudit,
  );

  if (arguments.contains('--list')) {
    _printPlan(plan);
    return;
  }

  stdout.writeln(
    'KT Wallet public-beta source audit: ${plan.length} fail-fast gates',
  );
  var index = 0;
  final result = await runPublicBetaAudit(
    plan,
    runner: (command) async {
      index += 1;
      stdout.writeln(
        '\n[$index/${plan.length}] ${command.description}\n'
        '  (${command.workingDirectory}) ${command.displayCommand}',
      );
      final executable = command.executable == 'dart'
          ? Platform.resolvedExecutable
          : command.executable;
      try {
        final process = await Process.start(
          executable,
          command.arguments,
          workingDirectory: command.workingDirectory,
          mode: ProcessStartMode.inheritStdio,
        );
        return process.exitCode;
      } on ProcessException catch (error) {
        stderr.writeln('Unable to start ${command.id}: ${error.errorCode}');
        return 127;
      }
    },
  );

  if (!result.passed) {
    stderr.writeln(
      '\nPUBLIC BETA SOURCE AUDIT FAILED at '
      '${result.failedCommand!.id} (exit ${result.exitCode}).',
    );
    exitCode = result.exitCode;
    return;
  }

  stdout.writeln(
    '\nPUBLIC BETA SOURCE AUDIT PASSED: ${result.completedCount}/${plan.length}.',
  );
  stdout.writeln(
    'This does not replace signed-artifact checks, physical-device review, '
    'real-chain broadcast evidence, or an independent security audit.',
  );
}

Directory _findRepositoryRoot() {
  var candidate = Directory.current.absolute;
  while (true) {
    final hasWorkspace =
        File('${candidate.path}/pubspec.yaml').existsSync() &&
        Directory('${candidate.path}/apps').existsSync() &&
        Directory('${candidate.path}/packages').existsSync() &&
        Directory('${candidate.path}/tool').existsSync();
    if (hasWorkspace) return candidate;
    final parent = candidate.parent;
    if (parent.path == candidate.path) break;
    candidate = parent;
  }
  stderr.writeln('Run this command from inside the KT Wallet repository.');
  exit(64);
}

void _printPlan(List<PublicBetaAuditCommand> plan) {
  for (var index = 0; index < plan.length; index += 1) {
    final command = plan[index];
    stdout.writeln(
      '${index + 1}. ${command.id}: ${command.description}\n'
      '   (${command.workingDirectory}) ${command.displayCommand}',
    );
  }
}

void _usage() {
  stdout.writeln('''
Usage:
  dart run tool/audit_public_beta.dart [--list] [--full]

Default: deterministic source, test, secret, cleanup, and Gateway gates.
--full: additionally run pinned native/runtime dependency and OSV audits.
--list: print the exact plan without executing it.

Signed artifacts, real devices, real-chain broadcasts, and external security
review remain separate mandatory evidence.
''');
}

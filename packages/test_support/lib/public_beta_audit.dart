/// Deterministic command plan for the local KT Wallet public-beta gate.
library;

/// One reviewable, non-shell-expanded audit command.
final class PublicBetaAuditCommand {
  PublicBetaAuditCommand({
    required this.id,
    required this.description,
    required this.executable,
    required List<String> arguments,
    required this.workingDirectory,
  }) : arguments = List.unmodifiable(arguments);

  final String id;
  final String description;
  final String executable;
  final List<String> arguments;
  final String workingDirectory;

  String get displayCommand => <String>[executable, ...arguments].join(' ');

  @override
  bool operator ==(Object other) =>
      other is PublicBetaAuditCommand &&
      other.id == id &&
      other.description == description &&
      other.executable == executable &&
      _listEquals(other.arguments, arguments) &&
      other.workingDirectory == workingDirectory;

  @override
  int get hashCode => Object.hash(
    id,
    description,
    executable,
    Object.hashAll(arguments),
    workingDirectory,
  );
}

typedef PublicBetaAuditRunner =
    Future<int> Function(PublicBetaAuditCommand command);

/// Result of a fail-fast audit run.
final class PublicBetaAuditResult {
  const PublicBetaAuditResult({
    required this.completedCount,
    required this.exitCode,
    this.failedCommand,
  });

  final int completedCount;
  final int exitCode;
  final PublicBetaAuditCommand? failedCommand;

  bool get passed => exitCode == 0 && failedCommand == null;
}

/// Builds the source-level gate used before any public beta build.
///
/// This deliberately does not claim to replace signed artifact, physical
/// device, real-chain broadcast, or external-security review evidence.
List<PublicBetaAuditCommand> buildPublicBetaAuditPlan({
  required String repoRoot,
  bool includeDependencyAudit = false,
}) {
  final root = _normalizeRoot(repoRoot);
  String at(String relative) => relative.isEmpty ? root : '$root/$relative';

  PublicBetaAuditCommand command({
    required String id,
    required String description,
    required String executable,
    required List<String> arguments,
    String directory = '',
  }) => PublicBetaAuditCommand(
    id: id,
    description: description,
    executable: executable,
    arguments: arguments,
    workingDirectory: at(directory),
  );

  final plan = <PublicBetaAuditCommand>[
    command(
      id: 'diff-integrity',
      description: 'Git whitespace and conflict-marker integrity',
      executable: 'git',
      arguments: const ['diff', '--check'],
    ),
    command(
      id: 'repository-security-gates',
      description: 'Dependency, production-route, secret, and cleanup gates',
      executable: 'dart',
      arguments: const ['run', 'tool/check_deps.dart'],
    ),
    command(
      id: 'static-analysis',
      description: 'Dart and Flutter static analysis',
      executable: 'dart',
      arguments: const ['analyze', 'apps', 'packages', 'tool'],
    ),
    for (final package in const [
      'test_support',
      'airgap_protocol',
      'chains',
      'wallet_data',
    ])
      command(
        id: 'dart-tests-$package',
        description: '$package pure Dart tests',
        executable: 'dart',
        arguments: const ['test'],
        directory: 'packages/$package',
      ),
    for (final target in const [
      ('ui-kit', 'packages/ui_kit'),
      ('core-crypto', 'packages/core_crypto'),
      ('kt-wallet', 'apps/kt_wallet'),
      ('cold-signer', 'apps/cold_signer'),
    ])
      command(
        id: 'flutter-tests-${target.$1}',
        description: '${target.$1} Flutter tests',
        executable: 'flutter',
        arguments: const ['test'],
        directory: target.$2,
      ),
    command(
      id: 'gateway-audit',
      description:
          'Gateway tests, race-independent vet, vulnerability, and ops gates',
      executable: 'make',
      arguments: const ['audit'],
      directory: 'backend/gateway',
    ),
    if (includeDependencyAudit)
      command(
        id: 'dependency-and-native-audit',
        description: 'Pinned runtime, Apple, Android, Gateway, and OSV audit',
        executable: 'bash',
        arguments: const ['tool/audit_dependencies.sh'],
      ),
  ];
  return List.unmodifiable(plan);
}

/// Executes [commands] sequentially and stops on the first non-zero result.
Future<PublicBetaAuditResult> runPublicBetaAudit(
  List<PublicBetaAuditCommand> commands, {
  required PublicBetaAuditRunner runner,
}) async {
  var completed = 0;
  for (final command in commands) {
    final exitCode = await runner(command);
    if (exitCode != 0) {
      return PublicBetaAuditResult(
        completedCount: completed,
        exitCode: exitCode,
        failedCommand: command,
      );
    }
    completed += 1;
  }
  return PublicBetaAuditResult(completedCount: completed, exitCode: 0);
}

String _normalizeRoot(String root) {
  var normalized = root.replaceAll('\\', '/');
  while (normalized.length > 1 && normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool _listEquals(List<String> left, List<String> right) {
  if (left.length != right.length) return false;
  for (var i = 0; i < left.length; i += 1) {
    if (left[i] != right[i]) return false;
  }
  return true;
}

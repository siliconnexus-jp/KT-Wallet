import 'package:test/test.dart';
import 'package:test_support/public_beta_audit.dart';

void main() {
  group('public beta audit plan', () {
    test('covers every deterministic P0 source gate in a fixed order', () {
      final plan = buildPublicBetaAuditPlan(repoRoot: '/repo');

      expect(plan.map((command) => command.displayCommand), [
        'git diff --check',
        'dart run tool/check_deps.dart',
        'dart analyze apps packages tool',
        'dart test',
        'dart test',
        'dart test',
        'dart test',
        'flutter test',
        'flutter test',
        'flutter test',
        'flutter test',
        'make audit',
      ]);
      expect(
        plan.map((command) => command.workingDirectory),
        containsAll(<String>[
          '/repo',
          '/repo/packages/test_support',
          '/repo/packages/airgap_protocol',
          '/repo/packages/chains',
          '/repo/packages/wallet_data',
          '/repo/packages/ui_kit',
          '/repo/packages/core_crypto',
          '/repo/apps/kt_wallet',
          '/repo/apps/cold_signer',
          '/repo/backend/gateway',
        ]),
      );
      expect(plan.map((command) => command.id).toSet(), hasLength(plan.length));
    });

    test('full plan appends the pinned dependency and native audit', () {
      final source = buildPublicBetaAuditPlan(repoRoot: '/repo');
      final full = buildPublicBetaAuditPlan(
        repoRoot: '/repo',
        includeDependencyAudit: true,
      );

      expect(full.take(source.length), source);
      expect(full.last.id, 'dependency-and-native-audit');
      expect(full.last.displayCommand, 'bash tool/audit_dependencies.sh');
      expect(full.last.workingDirectory, '/repo');
    });
  });

  group('public beta audit execution', () {
    test('stops at the first failure and identifies the failed gate', () async {
      final plan = buildPublicBetaAuditPlan(repoRoot: '/repo').take(4).toList();
      final invoked = <String>[];

      final result = await runPublicBetaAudit(
        plan,
        runner: (command) async {
          invoked.add(command.id);
          return command == plan[2] ? 23 : 0;
        },
      );

      expect(result.passed, isFalse);
      expect(result.exitCode, 23);
      expect(result.failedCommand, plan[2]);
      expect(result.completedCount, 2);
      expect(invoked, plan.take(3).map((command) => command.id));
    });

    test('reports success only after every command completes', () async {
      final plan = buildPublicBetaAuditPlan(repoRoot: '/repo').take(3).toList();

      final result = await runPublicBetaAudit(plan, runner: (_) async => 0);

      expect(result.passed, isTrue);
      expect(result.exitCode, 0);
      expect(result.failedCommand, isNull);
      expect(result.completedCount, plan.length);
    });
  });
}

import 'dart:io';

import 'package:integration_test/integration_test_driver.dart';

Future<void> main() async {
  await integrationDriver(
    timeout: const Duration(minutes: 20),
    writeResponseOnFailure: true,
    responseDataCallback: _copyPrivateEvidenceFromDevice,
  );
}

Future<void> _copyPrivateEvidenceFromDevice(
  Map<String, dynamic>? response,
) async {
  final source = response?['evidence_source'];
  final runId = response?['run_id'];
  final device = response?['device_udid'];
  if (source is! String ||
      source.isEmpty ||
      runId is! String ||
      runId.isEmpty ||
      device is! String ||
      device.isEmpty) {
    throw StateError('E2E app did not return its private evidence location');
  }

  final configuredRoot = Platform.environment['KT_E2E_OUTPUT_DIR'];
  final outputRoot = configuredRoot == null || configuredRoot.isEmpty
      ? Directory('integration_test/.e2e-evidence').absolute
      : Directory(configuredRoot).absolute;
  await outputRoot.create(recursive: true);
  final destination = Directory('${outputRoot.path}/$runId');
  if (await destination.exists()) {
    throw StateError('Refusing to overwrite E2E evidence: ${destination.path}');
  }

  final copy = await Process.run('xcrun', <String>[
    'devicectl',
    'device',
    'copy',
    'from',
    '--device',
    device,
    '--source',
    source,
    '--destination',
    destination.path,
    '--domain-type',
    'appDataContainer',
    '--domain-identifier',
    'cc.siliconnexus.ktwallet',
    '--timeout',
    '120',
    '--quiet',
  ]);
  if (copy.exitCode != 0) {
    throw StateError(
      'Could not copy E2E evidence from the iPhone: ${copy.stderr}',
    );
  }

  final chmod = await Process.run('chmod', <String>[
    '-R',
    'go-rwx',
    destination.path,
  ]);
  if (chmod.exitCode != 0) {
    throw StateError('Could not make E2E evidence private');
  }
  final reports = await destination
      .list(recursive: true, followLinks: false)
      .where((entity) => entity is File && entity.path.endsWith('report.json'))
      .toList();
  if (reports.length != 1) {
    throw StateError(
      'Copied E2E evidence does not contain exactly one report.json',
    );
  }
  final reportMode = (reports.single as File).statSync().mode & 0x1ff;
  if (reportMode & 0x3f != 0) {
    throw StateError('Copied report permissions are not private');
  }

  // This line contains only the private artifact path, never report contents.
  stdout.writeln('FULL_DEVICE_E2E_REPORT=${reports.single.absolute.path}');
}

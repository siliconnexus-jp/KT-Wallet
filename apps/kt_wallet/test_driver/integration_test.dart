import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// Host-side screenshot sink for `flutter drive` integration tests.
///
/// `flutter test` stores screenshots in the temporary app sandbox, which iOS
/// deletes when the test bundle is uninstalled. The extended driver receives
/// the same PNG bytes on the host and preserves them in the report tree.
Future<void> main() async {
  await integrationDriver(
    onScreenshot:
        (
          String screenshotName,
          List<int> screenshotBytes, [
          Map<String, Object?>? args,
        ]) async {
          final reportDir = Directory(
            '../../reports/p0-p1-wallet-audit-2026-07-31/screenshots',
          );
          await reportDir.create(recursive: true);
          final file = File('${reportDir.path}/$screenshotName.png');
          await file.writeAsBytes(screenshotBytes, flush: true);
          // ignore: avoid_print
          print('INTEGRATION_SCREENSHOT FILE=${file.absolute.path}');
          return true;
        },
  );
}

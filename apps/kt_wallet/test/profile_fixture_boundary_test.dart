import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/state/developer_mode.dart';

void main() {
  test('developer fixtures are Debug-only, never Profile or Release', () {
    expect(resolveDeveloperFixturesEnabled(isDebugBuild: true), isTrue);
    expect(resolveDeveloperFixturesEnabled(isDebugBuild: false), isFalse);
  });
}

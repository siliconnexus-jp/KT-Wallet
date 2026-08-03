import 'package:cold_signer/src/developer_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('developer fixtures are Debug-only, never Profile or Release', () {
    expect(resolveDeveloperFixturesEnabled(isDebugBuild: true), isTrue);
    expect(resolveDeveloperFixturesEnabled(isDebugBuild: false), isFalse);
  });
}

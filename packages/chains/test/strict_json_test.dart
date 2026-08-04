import 'package:chains/chains.dart';
import 'package:test/test.dart';

void main() {
  test('decodes unique members and rejects escaped or nested duplicates', () {
    expect(
      decodeJsonWithUniqueObjectMembers('{"transaction":"aa","txID":"bb"}'),
      {'transaction': 'aa', 'txID': 'bb'},
    );
    for (final source in [
      '{"transaction":"aa","trans\\u0061ction":"bb"}',
      '{"outer":{"txID":"aa","tx\\u0049D":"bb"}}',
      '[{"transaction":"aa","transaction":"bb"}]',
    ]) {
      expect(
        () => decodeJsonWithUniqueObjectMembers(source),
        throwsFormatException,
      );
    }
  });

  test('enforces size, depth and trailing-data boundaries', () {
    expect(
      () => decodeJsonWithUniqueObjectMembers('{"ok":true}', maxChars: 5),
      throwsFormatException,
    );
    expect(
      () => decodeJsonWithUniqueObjectMembers('{"ok":true} false'),
      throwsFormatException,
    );
    final tooDeep =
        '${List.filled(130, '[').join()}0'
        '${List.filled(130, ']').join()}';
    expect(
      () => decodeJsonWithUniqueObjectMembers(tooDeep),
      throwsFormatException,
    );
  });
}

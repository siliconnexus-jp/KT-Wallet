import 'package:test/test.dart';
import 'package:test_support/test_support.dart';

enum _S { idle, running, done }

enum _E { start, finish, reset }

_S _apply(_S s, _E e) {
  return switch ((s, e)) {
    (_S.idle, _E.start) => _S.running,
    (_S.running, _E.finish) => _S.done,
    (_S.done, _E.reset) => _S.idle,
    _ => throw StateError('illegal transition: $s + $e'),
  };
}

void main() {
  group('fixtures', () {
    test('readFixture loads file content', () {
      expect(readFixture('sample.txt').trim(), 'hello fixtures');
    });

    test('readJsonFixture parses JSON', () {
      final json = readJsonFixture('sample.json') as Map<String, dynamic>;
      expect(json['name'], 'kt-wallet');
    });

    test('readHexFixture decodes bytes and tolerates whitespace', () {
      expect(readHexFixture('sample.hex'), [0xde, 0xad, 0xbe, 0xef]);
    });

    test('missing fixture throws with a helpful message', () {
      expect(
        () => readFixture('nope.txt'),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Fixture not found'),
          ),
        ),
      );
    });
  });

  group('verifyTransitionTable', () {
    const allowed = [
      TransitionCase(_S.idle, _E.start, _S.running),
      TransitionCase(_S.running, _E.finish, _S.done),
      TransitionCase(_S.done, _E.reset, _S.idle),
    ];

    test('accepts a machine that matches its table', () {
      final report = verifyTransitionTable(
        states: _S.values,
        events: _E.values,
        apply: _apply,
        allowed: allowed,
      );
      expect(report.ok, isTrue, reason: report.toString());
    });

    test('flags a machine that silently allows an illegal transition', () {
      _S buggy(_S s, _E e) {
        if (s == _S.idle && e == _E.finish) return _S.done; // bug
        return _apply(s, e);
      }

      final report = verifyTransitionTable(
        states: _S.values,
        events: _E.values,
        apply: buggy,
        allowed: allowed,
      );
      expect(report.ok, isFalse);
      expect(report.problems.single, contains('expected throw'));
    });

    test('flags a machine that lands in the wrong state', () {
      _S wrong(_S s, _E e) {
        if (s == _S.running && e == _E.finish) return _S.idle; // bug
        return _apply(s, e);
      }

      final report = verifyTransitionTable(
        states: _S.values,
        events: _E.values,
        apply: wrong,
        allowed: allowed,
      );
      expect(report.ok, isFalse);
      expect(report.problems.single, contains('expected _S.done'));
    });

    test('flags duplicate table entries', () {
      final report = verifyTransitionTable(
        states: _S.values,
        events: _E.values,
        apply: _apply,
        allowed: [...allowed, const TransitionCase(_S.idle, _E.start, _S.running)],
      );
      expect(report.ok, isFalse);
      expect(report.problems.first, contains('duplicate'));
    });
  });
}

/// Table-driven state machine verification (detailed-design.md §9).
///
/// Flow state machines (transfer flows, aggregator, sign session) must
/// enumerate every (state, event) combination: allowed transitions produce the
/// expected target state, and every other combination must throw.
library;

/// One allowed transition.
class TransitionCase<S, E> {
  const TransitionCase(this.from, this.event, this.to);

  final S from;
  final E event;
  final S to;

  @override
  String toString() => '$from --$event--> $to';
}

/// Result of [verifyTransitionTable]; empty [problems] means the machine
/// matches its table exactly.
class TransitionReport {
  TransitionReport(this.problems);

  final List<String> problems;

  bool get ok => problems.isEmpty;

  @override
  String toString() => ok ? 'OK' : problems.join('\n');
}

/// Exercises [apply] over the full states × events grid.
///
/// * Combinations listed in [allowed] must return the expected target state.
/// * Every other combination must throw (any error type).
TransitionReport verifyTransitionTable<S, E>({
  required List<S> states,
  required List<E> events,
  required S Function(S state, E event) apply,
  required List<TransitionCase<S, E>> allowed,
}) {
  final problems = <String>[];
  final allowedMap = <(S, E), S>{
    for (final c in allowed) (c.from, c.event): c.to,
  };
  if (allowedMap.length != allowed.length) {
    problems.add('duplicate (state, event) entries in allowed table');
  }

  for (final state in states) {
    for (final event in events) {
      final expected = allowedMap[(state, event)];
      if (expected != null) {
        try {
          final actual = apply(state, event);
          if (actual != expected) {
            problems.add(
              '($state, $event): expected $expected, got $actual',
            );
          }
        } catch (e) {
          problems.add('($state, $event): expected $expected, threw $e');
        }
      } else {
        try {
          final actual = apply(state, event);
          problems.add(
            '($state, $event): expected throw, got $actual',
          );
        } catch (_) {
          // Expected: illegal transition rejected.
        }
      }
    }
  }
  return TransitionReport(problems);
}

import 'package:cold_signer/src/onboarding/onboarding_flow.dart';
import 'package:cold_signer/src/signing/mnemonic_quiz.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('onboarding flow', () {
    test('create walks welcome→warning→mnemonic→verify→pin→biometric→done', () {
      final f = OnboardingFlow(OnboardingMode.create);
      final visited = <OnboardingStep>[f.step];
      while (!f.isDone) {
        f.dispatch(OnboardingEvent.next);
        visited.add(f.step);
      }
      expect(visited, [
        OnboardingStep.welcome,
        OnboardingStep.securityWarning,
        OnboardingStep.showMnemonic,
        OnboardingStep.verifyMnemonic,
        OnboardingStep.setPassword,
        OnboardingStep.setBiometric,
        OnboardingStep.done,
      ]);
    });

    test('import skips the create-only mnemonic-display steps', () {
      final f = OnboardingFlow(OnboardingMode.importExisting);
      final visited = <OnboardingStep>[f.step];
      while (!f.isDone) {
        f.dispatch(OnboardingEvent.next);
        visited.add(f.step);
      }
      expect(visited, contains(OnboardingStep.importInput));
      expect(visited, isNot(contains(OnboardingStep.showMnemonic)));
      expect(visited, isNot(contains(OnboardingStep.verifyMnemonic)));
    });

    test('back returns to the previous step', () {
      final f = OnboardingFlow(OnboardingMode.create);
      f.dispatch(OnboardingEvent.next); // securityWarning
      f.dispatch(OnboardingEvent.next); // showMnemonic
      f.dispatch(OnboardingEvent.back);
      expect(f.step, OnboardingStep.securityWarning);
    });

    test('cannot go back from the first step or forward past done', () {
      final f = OnboardingFlow(OnboardingMode.create);
      expect(() => f.dispatch(OnboardingEvent.back), throwsA(isA<OnboardingError>()));
      while (!f.isDone) {
        f.dispatch(OnboardingEvent.next);
      }
      expect(() => f.dispatch(OnboardingEvent.next), throwsA(isA<OnboardingError>()));
    });

    test('skipBiometric jumps to done, only from the biometric step', () {
      final f = OnboardingFlow(OnboardingMode.importExisting);
      expect(() => f.dispatch(OnboardingEvent.skipBiometric),
          throwsA(isA<OnboardingError>()));
      while (f.step != OnboardingStep.setBiometric) {
        f.dispatch(OnboardingEvent.next);
      }
      f.dispatch(OnboardingEvent.skipBiometric);
      expect(f.step, OnboardingStep.done);
    });
  });

  group('mnemonic verification quiz', () {
    final mnemonic =
        'ripple canyon script harbor velvet noble orbit meadow signal pledge quartz ember'
            .split(' ');

    List<int> pick(int n, int c) => [8, 2, 5].take(c).toList();
    List<String> distractors(String correct, int n) =>
        ['aaa', 'bbb', 'ccc', 'ddd'].where((w) => w != correct).take(n).toList();

    test('builds distinct questions with the correct word among options', () {
      final questions = MnemonicQuiz.build(
        mnemonic,
        pickIndices: pick,
        distractorsFor: distractors,
      );
      expect(questions, hasLength(3));
      expect(questions[0].position, 9); // index 8 → 1-based 9
      expect(questions[0].correctWord, 'signal');
      for (final q in questions) {
        expect(q.options, contains(q.correctWord));
        expect(q.options, hasLength(4));
        expect(MnemonicQuiz.isCorrect(q, q.correctWord), isTrue);
        expect(MnemonicQuiz.isCorrect(q, 'wrong'), isFalse);
      }
    });

    test('rejects distractors that include the correct word', () {
      expect(
        () => MnemonicQuiz.build(
          mnemonic,
          pickIndices: pick,
          distractorsFor: (correct, n) => [correct, 'x', 'y'],
        ),
        throwsArgumentError,
      );
    });

    test('rejects a pickIndices that returns duplicates', () {
      expect(
        () => MnemonicQuiz.build(
          mnemonic,
          pickIndices: (n, c) => [1, 1, 1],
          distractorsFor: distractors,
        ),
        throwsArgumentError,
      );
    });

    test('rejects distractors with duplicates or wrong count', () {
      expect(
        () => MnemonicQuiz.build(
          mnemonic,
          pickIndices: pick,
          distractorsFor: (correct, n) => ['dup', 'dup', 'x'],
        ),
        throwsArgumentError,
      );
      expect(
        () => MnemonicQuiz.build(
          mnemonic,
          pickIndices: pick,
          distractorsFor: (correct, n) => ['only-one'],
        ),
        throwsArgumentError,
      );
    });
  });
}

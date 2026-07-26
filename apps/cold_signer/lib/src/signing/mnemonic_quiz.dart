/// Builds the mnemonic verification challenge (detailed-design.md §7.1,
/// ui-m.md §6.1 step 7): pick N positions and offer options containing the
/// correct word. Deterministic via an injected index picker for testability.
library;

class QuizQuestion {
  QuizQuestion({required this.position, required this.correctWord, required this.options});

  /// 1-based word position.
  final int position;
  final String correctWord;
  final List<String> options;
}

class MnemonicQuiz {
  /// Generates [count] questions for a [mnemonic]. [pickIndices] chooses the
  /// challenged positions (0-based); [distractorsFor] supplies wrong options.
  /// Both are injected so tests are deterministic.
  static List<QuizQuestion> build(List<String> mnemonic, {required List<int> Function(int wordCount, int count) pickIndices, required List<String> Function(String correct, int optionCount) distractorsFor, int count = 3, int optionCount = 4}) {
    if (mnemonic.length < count) {
      throw ArgumentError('mnemonic too short for $count questions');
    }
    final positions = pickIndices(mnemonic.length, count);
    if (positions.length != count || positions.toSet().length != count) {
      throw ArgumentError('pickIndices must return $count distinct positions');
    }
    return [
      for (final idx in positions)
        () {
          final correct = mnemonic[idx];
          final distractors = distractorsFor(correct, optionCount - 1);
          if (distractors.length != optionCount - 1) {
            throw ArgumentError('need ${optionCount - 1} distractors');
          }
          if (distractors.contains(correct)) {
            throw ArgumentError('distractors must not contain the correct word');
          }
          if (distractors.toSet().length != distractors.length) {
            throw ArgumentError('distractors must be distinct');
          }
          final options = [correct, ...distractors]..sort();
          return QuizQuestion(position: idx + 1, correctWord: correct, options: options);
        }(),
    ];
  }

  /// Whether an answer is correct for a question.
  static bool isCorrect(QuizQuestion q, String answer) => answer == q.correctWord;
}

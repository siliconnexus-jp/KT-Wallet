import 'dart:collection';

/// Why a recovery phrase is temporarily present in the navigation flow.
enum MnemonicReviewPurpose { onboarding, backup }

/// Ephemeral, in-memory-only recovery phrase hand-off between protected routes.
///
/// This object is deliberately not serializable and must never be persisted.
/// Navigating away with `go` removes it from the router history so the words
/// become eligible for garbage collection.
class MnemonicReviewFlow {
  MnemonicReviewFlow({required this.purpose, required List<String> words})
    : words = UnmodifiableListView<String>(List<String>.of(words));

  final MnemonicReviewPurpose purpose;
  final List<String> words;
}

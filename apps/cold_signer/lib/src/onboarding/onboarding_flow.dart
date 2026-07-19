/// Cold Signer onboarding flow state machines (detailed-design.md §7.1,
/// ui-m.md §6.1/§6.2). Create and import share the credential-setup tail.
library;

enum OnboardingStep {
  welcome,
  securityWarning, // create only: mnemonic risk notice
  showMnemonic, // create only
  verifyMnemonic, // create only
  importInput, // import only
  setPassword,
  setBiometric,
  done,
}

enum OnboardingEvent { next, back, skipBiometric }

enum OnboardingMode { create, importExisting }

class OnboardingError implements Exception {
  OnboardingError(this.message);
  final String message;
  @override
  String toString() => 'OnboardingError: $message';
}

/// Ordered steps for each mode; navigation only moves along this list.
List<OnboardingStep> stepsFor(OnboardingMode mode) => switch (mode) {
      OnboardingMode.create => const [
          OnboardingStep.welcome,
          OnboardingStep.securityWarning,
          OnboardingStep.showMnemonic,
          OnboardingStep.verifyMnemonic,
          OnboardingStep.setPassword,
          OnboardingStep.setBiometric,
          OnboardingStep.done,
        ],
      OnboardingMode.importExisting => const [
          OnboardingStep.welcome,
          OnboardingStep.importInput,
          OnboardingStep.setPassword,
          OnboardingStep.setBiometric,
          OnboardingStep.done,
        ],
    };

/// Linear flow controller: forbids skipping ahead; `back` returns to the prior
/// step; `skipBiometric` at the biometric step jumps to done (password-only).
///
/// This controls NAVIGATION only. Step completion (mnemonic quiz passed, a
/// valid password entered) is gated by the UI before it dispatches `next` —
/// the controller cannot advance past a step, but does not itself verify the
/// step's content.
class OnboardingFlow {
  OnboardingFlow(this.mode) : _index = 0;
  final OnboardingMode mode;
  int _index;

  List<OnboardingStep> get _steps => stepsFor(mode);
  OnboardingStep get step => _steps[_index];
  bool get isDone => step == OnboardingStep.done;

  OnboardingStep dispatch(OnboardingEvent event) {
    switch (event) {
      case OnboardingEvent.next:
        if (_index >= _steps.length - 1) {
          throw OnboardingError('already at final step');
        }
        _index++;
      case OnboardingEvent.back:
        if (_index == 0) throw OnboardingError('already at first step');
        _index--;
      case OnboardingEvent.skipBiometric:
        if (step != OnboardingStep.setBiometric) {
          throw OnboardingError('skipBiometric only valid at biometric step');
        }
        _index = _steps.indexOf(OnboardingStep.done);
    }
    return step;
  }
}

import Foundation
import LocalAuthentication

/// Wraps biometric/passcode evaluation and the failure-lockout ladder
/// (detailed-design.md §2.4). The fail count AND the active lockout deadline
/// persist (non-sensitive lockout counters live in UserDefaults) so a force
/// quit or restart during cooldown cannot reset the ladder; an app uninstall
/// clears them (product decision).
final class AuthGate {
  static let shared = AuthGate()

  private let counterKey = "com.ktwallet.core_crypto.authfail"
  private let lockedUntilKey = "com.ktwallet.core_crypto.lockeduntil"

  struct GateError: Error { let code: String; let cooldownSec: Int }

  private func cooldown(for fails: Int) -> Int {
    if fails >= 15 { return 900 }
    if fails >= 10 { return 300 }
    if fails >= 5 { return 60 }
    return 0
  }

  private var failCount: Int {
    get { UserDefaults.standard.integer(forKey: counterKey) }
    set { UserDefaults.standard.set(newValue, forKey: counterKey) }
  }

  private var lockedUntil: Date? {
    get {
      let t = UserDefaults.standard.double(forKey: lockedUntilKey)
      return t > 0 ? Date(timeIntervalSince1970: t) : nil
    }
    set {
      UserDefaults.standard.set(
        newValue?.timeIntervalSince1970 ?? 0, forKey: lockedUntilKey)
    }
  }

  var remainingCooldown: Int {
    guard let until = lockedUntil else { return 0 }
    return max(0, Int(until.timeIntervalSinceNow))
  }

  var state: [String: Any] {
    let remaining = remainingCooldown
    return ["locked": remaining > 0, "failCount": failCount, "cooldownSec": remaining]
  }

  /// Evaluates biometrics/passcode. Returns a fresh authenticated LAContext to
  /// reuse for the subsequent Keychain read, so the user is prompted once.
  func authenticate(reason: String) async throws -> LAContext {
    if remainingCooldown > 0 {
      throw GateError(code: "AUTH_LOCKED", cooldownSec: remainingCooldown)
    }
    let context = LAContext()
    context.localizedReason = reason
    do {
      let ok = try await context.evaluatePolicy(
        .deviceOwnerAuthentication, localizedReason: reason)
      if ok {
        failCount = 0
        lockedUntil = nil
        return context
      }
      throw GateError(code: "AUTH_FAILED", cooldownSec: 0)
    } catch let laError as LAError {
      switch laError.code {
      case .userCancel, .userFallback, .appCancel, .systemCancel:
        throw GateError(code: "AUTH_CANCELLED", cooldownSec: 0)
      case .authenticationFailed:
        return try registerFailureAndThrow()
      case .biometryLockout:
        // iOS owns this lockout and decides when credentials may be retried.
        // It is not another wrong attempt in KT Wallet's persisted ladder.
        throw GateError(code: "AUTH_LOCKED", cooldownSec: 0)
      default:
        // Missing passcode/enrollment/hardware, a non-interactive app, or a
        // provider/runtime failure is not evidence of a wrong credential.
        // Counting these errors can lock out an innocent user without one
        // failed authentication attempt.
        throw GateError(code: "AUTH_UNAVAILABLE", cooldownSec: 0)
      }
    }
  }

  private func registerFailureAndThrow() throws -> LAContext {
    failCount += 1
    let cd = cooldown(for: failCount)
    if cd > 0 {
      lockedUntil = Date().addingTimeInterval(TimeInterval(cd))
      throw GateError(code: "AUTH_LOCKED", cooldownSec: cd)
    }
    throw GateError(code: "AUTH_FAILED", cooldownSec: 0)
  }
}

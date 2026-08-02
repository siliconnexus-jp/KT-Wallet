import Foundation

enum WalletIdValidationError: Error {
  case invalid
}

/// Native trust-boundary validation for Keychain account identifiers. Dart
/// performs the same check, but direct MethodChannel calls must fail closed.
func requireValidWalletId(_ value: Any?) throws -> String {
  guard let walletId = value as? String,
    (1...64).contains(walletId.utf8.count),
    walletId.utf8.allSatisfy({ byte in
      (byte >= 0x41 && byte <= 0x5A)
        || (byte >= 0x61 && byte <= 0x7A)
        || (byte >= 0x30 && byte <= 0x39)
        || byte == 0x5F
        || byte == 0x2D
    })
  else {
    throw WalletIdValidationError.invalid
  }
  return walletId
}

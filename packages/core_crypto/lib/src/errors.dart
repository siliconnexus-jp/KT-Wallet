/// Typed exceptions mirroring the native error codes (detailed-design.md §2.1).
library;

sealed class CoreCryptoException implements Exception {
  const CoreCryptoException(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'CoreCryptoException($code): $message';
}

/// Single auth attempt failed; user may retry.
final class AuthFailedException extends CoreCryptoException {
  const AuthFailedException([String message = 'authentication failed'])
    : super('AUTH_FAILED', message);
}

/// Device authentication cannot currently run (no enrollment/hardware, a
/// provider error, or another non-credential system condition).
final class AuthUnavailableException extends CoreCryptoException {
  const AuthUnavailableException([
    String message = 'device authentication is unavailable',
  ]) : super('AUTH_UNAVAILABLE', message);
}

/// Too many failures; auth gate is cooling down.
final class AuthLockedException extends CoreCryptoException {
  const AuthLockedException(this.cooldownSec)
    : super('AUTH_LOCKED', 'auth locked for $cooldownSec s');

  final int cooldownSec;
}

/// User dismissed the biometric/passcode prompt.
final class AuthCancelledException extends CoreCryptoException {
  const AuthCancelledException() : super('AUTH_CANCELLED', 'user cancelled');
}

final class WalletNotFoundException extends CoreCryptoException {
  const WalletNotFoundException(String walletId)
    : super('WALLET_NOT_FOUND', 'wallet not found: $walletId');
}

/// A native wallet slot is create-only and cannot replace existing key
/// material. Callers must allocate a fresh random walletId instead.
final class WalletAlreadyExistsException extends CoreCryptoException {
  const WalletAlreadyExistsException()
    : super('WALLET_EXISTS', 'wallet already exists');
}

final class InvalidMnemonicException extends CoreCryptoException {
  const InvalidMnemonicException()
    : super('INVALID_MNEMONIC', 'mnemonic failed BIP-39 validation');
}

/// SigningInput bytes could not be parsed by wallet-core.
final class InvalidInputException extends CoreCryptoException {
  const InvalidInputException([String message = 'invalid signing input'])
    : super('INVALID_INPUT', message);
}

final class SignFailedException extends CoreCryptoException {
  const SignFailedException([String message = 'signing failed'])
    : super('SIGN_FAILED', message);
}

/// The native wallet-core binary is not linked into this build.
final class CryptoUnavailableException extends CoreCryptoException {
  const CryptoUnavailableException()
    : super('CRYPTO_UNAVAILABLE', 'Trust Wallet Core is unavailable');
}

/// Stored ciphertext failed integrity checks — wallet must be re-imported.
final class StoreCorruptedException extends CoreCryptoException {
  const StoreCorruptedException()
    : super('STORE_CORRUPTED', 'stored key material corrupted');
}

/// Biometric enrollment changed; key invalidated by design.
final class BiometryChangedException extends CoreCryptoException {
  const BiometryChangedException()
    : super('BIOMETRY_CHANGED', 'biometric set changed; re-authenticate');
}

/// Maps an allowlisted native error code (+ narrowly allowlisted details) to a
/// typed exception. Native message text is deliberately not accepted here:
/// lower-level exceptions can contain sensitive wallet operation context.
CoreCryptoException exceptionFromCode(
  String code, {
  Map<Object?, Object?>? details,
}) {
  return switch (code) {
    'AUTH_FAILED' => const AuthFailedException(),
    'AUTH_UNAVAILABLE' => const AuthUnavailableException(),
    'AUTH_LOCKED' => AuthLockedException(
      (details?['cooldownSec'] as int?) ?? 0,
    ),
    'AUTH_CANCELLED' => const AuthCancelledException(),
    'WALLET_NOT_FOUND' => WalletNotFoundException(
      (details?['walletId'] as String?) ?? '?',
    ),
    'WALLET_EXISTS' => const WalletAlreadyExistsException(),
    'INVALID_MNEMONIC' => const InvalidMnemonicException(),
    'INVALID_INPUT' => const InvalidInputException(),
    'SIGN_FAILED' => const SignFailedException(),
    'CRYPTO_UNAVAILABLE' => const CryptoUnavailableException(),
    'STORE_CORRUPTED' => const StoreCorruptedException(),
    'BIOMETRY_CHANGED' => const BiometryChangedException(),
    _ => const SignFailedException('unknown native failure'),
  };
}

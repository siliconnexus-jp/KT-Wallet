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

/// Maps a native error code (+ details map) to a typed exception.
CoreCryptoException exceptionFromCode(
  String code, {
  String? message,
  Map<Object?, Object?>? details,
}) {
  return switch (code) {
    'AUTH_FAILED' => AuthFailedException(message ?? 'authentication failed'),
    'AUTH_LOCKED' =>
      AuthLockedException((details?['cooldownSec'] as int?) ?? 0),
    'AUTH_CANCELLED' => const AuthCancelledException(),
    'WALLET_NOT_FOUND' =>
      WalletNotFoundException((details?['walletId'] as String?) ?? '?'),
    'INVALID_MNEMONIC' => const InvalidMnemonicException(),
    'INVALID_INPUT' => InvalidInputException(message ?? 'invalid signing input'),
    'SIGN_FAILED' => SignFailedException(message ?? 'signing failed'),
    'STORE_CORRUPTED' => const StoreCorruptedException(),
    'BIOMETRY_CHANGED' => const BiometryChangedException(),
    _ => SignFailedException('unknown native error $code: $message'),
  };
}

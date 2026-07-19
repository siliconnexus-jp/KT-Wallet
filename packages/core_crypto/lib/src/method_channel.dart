import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'errors.dart';
import 'types.dart';

/// Production [CoreCrypto] backed by the native plugin.
class MethodChannelCoreCrypto implements CoreCrypto {
  MethodChannelCoreCrypto();

  @visibleForTesting
  final MethodChannel channel = const MethodChannel('kt/core_crypto');

  Future<T> _invoke<T>(String method, [Map<String, Object?>? args]) async {
    try {
      final result = await channel.invokeMethod<T>(method, args);
      if (result == null) {
        throw SignFailedException('native returned null for $method');
      }
      return result;
    } on PlatformException catch (e) {
      throw exceptionFromCode(
        e.code,
        message: e.message,
        details: e.details is Map ? e.details as Map<Object?, Object?> : null,
      );
    }
  }

  @override
  Future<String> generateMnemonic({int strength = 128}) {
    CoreCryptoValidation.checkStrength(strength);
    return _invoke<String>('generateMnemonic', {'strength': strength});
  }

  @override
  Future<bool> validateMnemonic(String mnemonic) {
    CoreCryptoValidation.checkMnemonicNotEmpty(mnemonic);
    return _invoke<bool>('validateMnemonic', {'mnemonic': mnemonic});
  }

  @override
  Future<bool> validateWord(String word) {
    if (word.trim().isEmpty) return Future.value(false);
    return _invoke<bool>('validateWord', {'word': word});
  }

  @override
  Future<List<String>> suggestWords(String prefix, {int limit = 3}) async {
    if (prefix.trim().isEmpty) return const [];
    final words = await _invoke<List<Object?>>(
      'suggestWords',
      {'prefix': prefix, 'limit': limit},
    );
    return words.cast<String>();
  }

  @override
  Future<void> storeWallet({
    required String walletId,
    required String mnemonic,
    bool requireAuth = true,
    String? kdfPassword,
  }) {
    CoreCryptoValidation.checkWalletId(walletId);
    CoreCryptoValidation.checkMnemonicNotEmpty(mnemonic);
    return _invoke<bool>('storeWallet', {
      'walletId': walletId,
      'mnemonic': mnemonic,
      'requireAuth': requireAuth,
      'kdfPassword': kdfPassword,
    });
  }

  @override
  Future<ChainAddresses> deriveAddresses(String walletId) async {
    CoreCryptoValidation.checkWalletId(walletId);
    final map = await _invoke<Map<Object?, Object?>>(
      'deriveAddresses',
      {'walletId': walletId},
    );
    return ChainAddresses.fromMap(map);
  }

  @override
  Future<SignedTransaction> signTransaction({
    required String walletId,
    required Coin coin,
    required Uint8List signingInput,
  }) async {
    CoreCryptoValidation.checkWalletId(walletId);
    CoreCryptoValidation.checkSigningInput(signingInput);
    final map = await _invoke<Map<Object?, Object?>>('signTransaction', {
      'walletId': walletId,
      'coin': coin.name,
      'signingInput': signingInput,
    });
    return SignedTransaction(
      signedTx: map['signedTx']! as Uint8List,
      txHash: map['txHash']! as String,
    );
  }

  @override
  Future<String> exportMnemonic(String walletId) {
    CoreCryptoValidation.checkWalletId(walletId);
    return _invoke<String>('exportMnemonic', {'walletId': walletId});
  }

  @override
  Future<void> deleteWallet(String walletId) {
    CoreCryptoValidation.checkWalletId(walletId);
    return _invoke<bool>('deleteWallet', {'walletId': walletId});
  }

  @override
  Future<AuthState> getAuthState() async {
    final map = await _invoke<Map<Object?, Object?>>('getAuthState');
    return AuthState.fromMap(map);
  }
}

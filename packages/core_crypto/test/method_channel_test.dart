import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final api = MethodChannelCoreCrypto();

  void mockNative(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(api.channel, handler);
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(api.channel, null);
  });

  group('request encoding', () {
    test('generateMnemonic passes strength and returns mnemonic', () async {
      late MethodCall received;
      mockNative((call) async {
        received = call;
        return 'word1 word2';
      });
      final mnemonic = await api.generateMnemonic(strength: 192);
      expect(received.method, 'generateMnemonic');
      expect(received.arguments, {'strength': 192});
      expect(mnemonic, 'word1 word2');
    });

    test('signTransaction sends coin name + bytes, decodes result', () async {
      late MethodCall received;
      mockNative((call) async {
        received = call;
        return {
          'signedTx': Uint8List.fromList([9, 9]),
          'txHash': '0xabc',
        };
      });
      final result = await api.signTransaction(
        walletId: 'w1',
        coin: Coin.solana,
        signingInput: Uint8List.fromList([1, 2]),
      );
      expect(received.method, 'signTransaction');
      final args = received.arguments as Map<Object?, Object?>;
      expect(args['coin'], 'solana');
      expect(args['walletId'], 'w1');
      expect(args['signingInput'], [1, 2]);
      expect(result.signedTx, [9, 9]);
      expect(result.txHash, '0xabc');
    });

    test('deriveAddresses decodes address map', () async {
      mockNative((call) async => {
            'eth': '0xE',
            'polygon': '0xE',
            'tron': 'T1',
            'solana': 'S1',
          });
      final addrs = await api.deriveAddresses('w1');
      expect(addrs.forCoin(Coin.polygon), '0xE');
      expect(addrs.forCoin(Coin.tron), 'T1');
    });

    test('getAuthState decodes state map', () async {
      mockNative((call) async =>
          {'locked': true, 'failCount': 5, 'cooldownSec': 42});
      final state = await api.getAuthState();
      expect(state.locked, isTrue);
      expect(state.failCount, 5);
      expect(state.cooldownSec, 42);
    });
  });

  group('error code → typed exception mapping (DD §2.1)', () {
    final cases = <String, Matcher>{
      'AUTH_FAILED': isA<AuthFailedException>(),
      'AUTH_CANCELLED': isA<AuthCancelledException>(),
      'WALLET_NOT_FOUND': isA<WalletNotFoundException>(),
      'INVALID_MNEMONIC': isA<InvalidMnemonicException>(),
      'INVALID_INPUT': isA<InvalidInputException>(),
      'SIGN_FAILED': isA<SignFailedException>(),
      'STORE_CORRUPTED': isA<StoreCorruptedException>(),
      'BIOMETRY_CHANGED': isA<BiometryChangedException>(),
    };

    for (final entry in cases.entries) {
      test(entry.key, () async {
        mockNative((call) async {
          throw PlatformException(code: entry.key, message: 'boom');
        });
        expect(() => api.exportMnemonic('w1'), throwsA(entry.value));
      });
    }

    test('AUTH_LOCKED carries cooldown from details', () async {
      mockNative((call) async {
        throw PlatformException(
          code: 'AUTH_LOCKED',
          details: {'cooldownSec': 300},
        );
      });
      expect(
        () => api.exportMnemonic('w1'),
        throwsA(
          isA<AuthLockedException>()
              .having((e) => e.cooldownSec, 'cooldownSec', 300),
        ),
      );
    });

    test('unknown code degrades to SignFailedException, not a crash',
        () async {
      mockNative((call) async {
        throw PlatformException(code: 'SOMETHING_NEW');
      });
      expect(
        () => api.exportMnemonic('w1'),
        throwsA(isA<SignFailedException>()),
      );
    });
  });

  group('local validation happens before the channel', () {
    test('invalid walletId never reaches native', () async {
      var nativeCalled = false;
      mockNative((call) async {
        nativeCalled = true;
        return '';
      });
      await expectLater(
        () => api.exportMnemonic('bad id!'),
        throwsArgumentError,
      );
      expect(nativeCalled, isFalse);
    });

    test('empty prefix suggestion short-circuits', () async {
      var nativeCalled = false;
      mockNative((call) async {
        nativeCalled = true;
        return <String>[];
      });
      expect(await api.suggestWords('  '), isEmpty);
      expect(nativeCalled, isFalse);
    });
  });
}

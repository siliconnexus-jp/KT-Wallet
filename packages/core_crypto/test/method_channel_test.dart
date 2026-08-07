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
      mockNative(
        (call) async => {
          'eth': '0xE',
          'polygon': '0xE',
          'bnb': '0xB',
          'tron': 'T1',
          'solana': 'S1',
        },
      );
      final addrs = await api.deriveAddresses('w1');
      expect(addrs.forCoin(Coin.polygon), '0xE');
      expect(addrs.forCoin(Coin.bnb), '0xB');
      expect(addrs.forCoin(Coin.tron), 'T1');
    });

    test(
      'walletExists uses the non-interactive native presence method',
      () async {
        late MethodCall received;
        mockNative((call) async {
          received = call;
          return true;
        });

        expect(await api.walletExists('w1'), isTrue);
        expect(received.method, 'walletExists');
        expect(received.arguments, {'walletId': 'w1'});
      },
    );

    test('getAuthState decodes state map', () async {
      mockNative(
        (call) async => {'locked': true, 'failCount': 5, 'cooldownSec': 42},
      );
      final state = await api.getAuthState();
      expect(state.locked, isTrue);
      expect(state.failCount, 5);
      expect(state.cooldownSec, 42);
    });

    test(
      'private-key export uses opaque session and never returns full key',
      () async {
        final received = <MethodCall>[];
        mockNative((call) async {
          received.add(call);
          return switch (call.method) {
            'beginPrivateKeyExport' => 'native_session_1',
            'copyPrivateKey' => {'suffix': 'a1b2c3'},
            'endPrivateKeyExport' => true,
            _ => throw StateError('unexpected ${call.method}'),
          };
        });

        final session = await api.beginPrivateKeyExport('w1');
        final suffix = await api.copyPrivateKey(
          sessionId: session,
          coin: Coin.tron,
          mode: PrivateKeyCopyMode.safe,
        );
        await api.endPrivateKeyExport(session);

        expect(session, 'native_session_1');
        expect(suffix, 'a1b2c3');
        expect(received[0].arguments, {'walletId': 'w1'});
        expect(received[1].arguments, {
          'sessionId': 'native_session_1',
          'coin': 'tron',
          'mode': 'safe',
        });
        expect(received[2].arguments, {'sessionId': 'native_session_1'});
      },
    );

    test('full private-key copy requires an empty returned suffix', () async {
      mockNative((call) async => {'suffix': 'must-not-cross'});
      await expectLater(
        () => api.copyPrivateKey(
          sessionId: 'native_session_1',
          coin: Coin.eth,
          mode: PrivateKeyCopyMode.full,
        ),
        throwsA(isA<InvalidInputException>()),
      );
    });

    test('private-key responses are decoded strictly', () async {
      mockNative((call) async => '../invalid-session');
      await expectLater(
        () => api.beginPrivateKeyExport('w1'),
        throwsA(isA<InvalidInputException>()),
      );

      mockNative((call) async => {'suffix': 'a1b2c3', 'unexpected': true});
      await expectLater(
        () => api.copyPrivateKey(
          sessionId: 'native_session_1',
          coin: Coin.eth,
          mode: PrivateKeyCopyMode.safe,
        ),
        throwsA(isA<InvalidInputException>()),
      );

      mockNative((call) async => {'suffix': 'zzzzzz'});
      await expectLater(
        () => api.copyPrivateKey(
          sessionId: 'native_session_1',
          coin: Coin.tron,
          mode: PrivateKeyCopyMode.safe,
        ),
        throwsA(isA<InvalidInputException>()),
      );

      mockNative((call) async => false);
      await expectLater(
        () => api.endPrivateKeyExport('native_session_1'),
        throwsA(isA<InvalidInputException>()),
      );
    });

    test(
      'readBackup binds the payload to its declared format version',
      () async {
        late MethodCall received;
        mockNative((call) async {
          received = call;
          return 'word1 word2';
        });

        await api.readBackup(
          blob: Uint8List(60),
          password: 'correct horse',
          format: BackupCipherFormat.portableV2,
        );

        expect(received.method, 'readBackup');
        expect(received.arguments, {
          'blob': Uint8List(60),
          'password': 'correct horse',
          'formatVersion': 2,
        });
      },
    );
  });

  group('error code → typed exception mapping (DD §2.1)', () {
    final cases = <String, Matcher>{
      'AUTH_FAILED': isA<AuthFailedException>(),
      'AUTH_UNAVAILABLE': isA<AuthUnavailableException>(),
      'AUTH_CANCELLED': isA<AuthCancelledException>(),
      'WALLET_NOT_FOUND': isA<WalletNotFoundException>(),
      'WALLET_EXISTS': isA<WalletAlreadyExistsException>(),
      'INVALID_MNEMONIC': isA<InvalidMnemonicException>(),
      'INVALID_INPUT': isA<InvalidInputException>(),
      'SIGN_FAILED': isA<SignFailedException>(),
      'CRYPTO_UNAVAILABLE': isA<CryptoUnavailableException>(),
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
          isA<AuthLockedException>().having(
            (e) => e.cooldownSec,
            'cooldownSec',
            300,
          ),
        ),
      );
    });

    test('unknown code degrades to SignFailedException, not a crash', () async {
      mockNative((call) async {
        throw PlatformException(code: 'SOMETHING_NEW');
      });
      expect(
        () => api.exportMnemonic('w1'),
        throwsA(isA<SignFailedException>()),
      );
    });

    test(
      'native exception text and unapproved details never cross into Dart',
      () async {
        const canary =
            'abandon ability able about above absent absorb abstract absurd abuse access accident';
        mockNative((call) async {
          throw PlatformException(
            code: 'SIGN_FAILED',
            message: 'wallet w-secret failed while handling $canary',
            details: const {'walletId': 'w-secret', 'rawTransaction': canary},
          );
        });

        Object? thrown;
        try {
          await api.exportMnemonic('w1');
        } on Object catch (error) {
          thrown = error;
        }

        expect(thrown, isA<SignFailedException>());
        expect(thrown.toString(), isNot(contains(canary)));
        expect(thrown.toString(), isNot(contains('w-secret')));
      },
    );

    test('AUTH_LOCKED keeps only the allowlisted cooldown detail', () async {
      const canary = 'private-native-diagnostic-canary';
      mockNative((call) async {
        throw PlatformException(
          code: 'AUTH_LOCKED',
          message: canary,
          details: const {'cooldownSec': 45, 'nativeException': canary},
        );
      });

      Object? thrown;
      try {
        await api.exportMnemonic('w1');
      } on Object catch (error) {
        thrown = error;
      }

      expect(thrown, isA<AuthLockedException>());
      expect((thrown! as AuthLockedException).cooldownSec, 45);
      expect(thrown.toString(), isNot(contains(canary)));
    });
  });

  group('local validation happens before the channel', () {
    test('new backup passwords reject offline-guessable patterns', () {
      expect(
        CoreCryptoValidation.backupPasswordIssue('short pass'),
        BackupPasswordIssue.tooShort,
      );
      expect(
        CoreCryptoValidation.backupPasswordIssue('1234123412341234'),
        BackupPasswordIssue.predictable,
      );
      expect(
        CoreCryptoValidation.backupPasswordIssue('abcdefghijklmn'),
        BackupPasswordIssue.predictable,
      );
      expect(
        CoreCryptoValidation.backupPasswordIssue('correct horse battery'),
        isNull,
      );
      expect(
        CoreCryptoValidation.backupPasswordIssue('安全备份密码甲乙丙丁戊己庚辛壬癸'),
        isNull,
      );
      expect(
        CoreCryptoValidation.backupPasswordIssue(List.filled(129, 'x').join()),
        BackupPasswordIssue.tooLong,
      );
    });

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

    test('invalid private-key session id never reaches native', () async {
      var nativeCalled = false;
      mockNative((call) async {
        nativeCalled = true;
        return {'suffix': 'abcdef'};
      });
      await expectLater(
        () => api.copyPrivateKey(
          sessionId: '../escape',
          coin: Coin.eth,
          mode: PrivateKeyCopyMode.safe,
        ),
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

    test('suggestion limit is enforced before and after native', () async {
      var nativeCalled = false;
      mockNative((call) async {
        nativeCalled = true;
        expect(call.method, 'suggestWords');
        expect(call.arguments, {'prefix': 'ab', 'limit': 2});
        return <String>['abandon', 'ability', 'able'];
      });

      expect(await api.suggestWords('ab', limit: 2), ['abandon', 'ability']);
      expect(nativeCalled, isTrue);
      nativeCalled = false;
      expect(() => api.suggestWords('ab', limit: 21), throwsArgumentError);
      expect(nativeCalled, isFalse);
    });
  });
}

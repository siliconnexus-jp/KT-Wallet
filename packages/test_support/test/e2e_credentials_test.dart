import 'package:test/test.dart';
import 'package:test_support/e2e_credentials.dart';

Map<String, Object?> _validDocument() => {
  'KT_E2E_SCHEMA_VERSION': '1',
  'KT_E2E_BATCH_ID': 'batch_20260801_a1b2c3d4',
  'KT_E2E_CREATED_AT_UTC': '2026-08-01T00:00:00.000Z',
  'KT_E2E_EXPIRES_AT_UTC': '2026-08-08T00:00:00.000Z',
  'SEPOLIA_E2E_MNEMONIC':
      'legal winner thank year wave sausage worth useful legal winner thank yellow',
};

void main() {
  group('E2E credential document', () {
    test('builder emits only the versioned string contract', () {
      final document = buildE2eCredentialDocument(
        batchId: 'batch_20260801_a1b2c3d4',
        createdAtUtc: DateTime.utc(2026, 8, 1),
        lifetime: const Duration(days: 7),
        mnemonic:
            ' legal winner thank year wave sausage worth useful legal winner thank yellow ',
      );
      expect(document.keys.toSet(), e2eCredentialRequiredKeys);
      expect(document[e2eExpiresAtKey], '2026-08-08T00:00:00.000Z');
      expect(document[e2eMnemonicKey], startsWith('legal winner'));
    });

    test('accepts a fresh, bounded batch', () {
      expect(
        validateE2eCredentialDocument(
          _validDocument(),
          nowUtc: DateTime.utc(2026, 8, 2),
        ),
        isEmpty,
      );
    });

    test('rejects legacy documents without batch metadata', () {
      expect(
        validateE2eCredentialDocument({
          'SEPOLIA_E2E_MNEMONIC': 'one two three',
        }, nowUtc: DateTime.utc(2026, 8, 2)),
        contains('missing or empty KT_E2E_BATCH_ID'),
      );
    });

    test('rejects expired and overlong batches', () {
      final expired = _validDocument()
        ..['KT_E2E_EXPIRES_AT_UTC'] = '2026-08-01T12:00:00.000Z';
      expect(
        validateE2eCredentialDocument(
          expired,
          nowUtc: DateTime.utc(2026, 8, 2),
        ),
        contains('credential batch has expired'),
      );

      final overlong = _validDocument()
        ..['KT_E2E_EXPIRES_AT_UTC'] = '2026-08-20T00:00:00.000Z';
      expect(
        validateE2eCredentialDocument(
          overlong,
          nowUtc: DateTime.utc(2026, 8, 2),
        ),
        contains('credential lifetime exceeds 14 days'),
      );
    });

    test('rejects public or malformed mnemonic fixtures', () {
      final publicVector = _validDocument()
        ..['SEPOLIA_E2E_MNEMONIC'] =
            'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';
      expect(
        validateE2eCredentialDocument(
          publicVector,
          nowUtc: DateTime.utc(2026, 8, 2),
        ),
        contains(
          'public BIP-39 vector cannot be used as a funded test account',
        ),
      );
    });
  });

  group('E2E report redaction', () {
    const secret =
        'legal winner thank year wave sausage worth useful legal winner thank yellow';

    test('reports labels without returning secret values', () {
      final labels = findE2eSecretLeakLabels(
        'Evidence: $secret and token alch_abcdefghijklmnop',
        mnemonic: secret,
      );
      expect(labels, ['configured test mnemonic', 'Alchemy token']);
      expect(labels.join(' '), isNot(contains('legal winner')));
    });

    test('allows public addresses and transaction hashes', () {
      expect(
        findE2eSecretLeakLabels(
          'address 0xb787f3c2f96403b5a73dc66de68e4a6395d4e632 '
          'tx 0x4fdbf1768286373e4934b23d6daf0dc9bfe2ad8009ae5fd28b9c7510aa14a4f1',
          mnemonic: secret,
        ),
        isEmpty,
      );
    });

    test('detects every provider credential format used by the project', () {
      // Assemble signature-shaped fixtures at runtime so repository push
      // protection never mistakes test data for live credentials.
      final slackFixture = <String>[
        'xoxb',
        '123456789012',
        '123456789012',
        'abcdefghijklmnopqrstuvwx',
      ].join('-');
      final stripeFixture = <String>[
        'sk',
        'live',
        'abcdefghijklmnopqrstuvwx',
      ].join('_');
      final labels = findE2eSecretLeakLabels('''
ETHERSCAN_API_KEY=ABCDEFGHIJKLMNOPQRSTUVWX1234567890
HELIUS_API_KEY=helius-provider-key-1234567890
GOPLUS_ACCESS_TOKEN=eyJhbGciOiJIUzI1NiJ9.payload.signature
METRICS_BEARER_TOKEN=0123456789abcdef0123456789abcdef
slack=$slackFixture
stripe=$stripeFixture
google=AIzaSyA1234567890abcdefghijklmnopqrstuv
''');
      expect(
        labels,
        containsAll(<String>[
          'Etherscan API key',
          'Helius API key',
          'GoPlus access token',
          'metrics bearer token',
          'Slack token',
          'Stripe secret key',
          'Google API key',
        ]),
      );
    });

    test('allows empty and explicitly redacted provider configuration', () {
      expect(
        findE2eSecretLeakLabels('''
ETHERSCAN_API_KEY=
HELIUS_API_KEY=<stored only in the remote 0600 environment file>
GOPLUS_ACCESS_TOKEN=REDACTED
METRICS_BEARER_TOKEN=\${METRICS_BEARER_TOKEN}
'''),
        isEmpty,
      );
    });
  });

  test('credential file mode accepts only 0600', () {
    expect(hasPrivateCredentialFileMode(0x8180), isTrue); // regular + 0600
    expect(hasPrivateCredentialFileMode(0x81a0), isFalse); // regular + 0640
    expect(hasPrivateCredentialFileMode(0x81a4), isFalse); // regular + 0644
  });
}

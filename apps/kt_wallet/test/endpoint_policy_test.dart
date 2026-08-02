import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/state/endpoint_policy.dart';

void main() {
  group('EndpointPolicy', () {
    test('accepts HTTPS endpoints and trims surrounding whitespace', () {
      expect(
        EndpointPolicy.requireSafeUrl('  https://rpc.example/v1?key=test  '),
        'https://rpc.example/v1?key=test',
      );
    });

    test('accepts plain HTTP only for loopback development endpoints', () {
      for (final url in const [
        'http://localhost:8119',
        'http://127.0.0.1:8545',
        'http://[::1]:8899',
      ]) {
        expect(EndpointPolicy.isSafeUrl(url), isTrue, reason: url);
      }
    });

    test('rejects public HTTP, credentials, fragments and non-HTTP URLs', () {
      for (final url in const [
        'http://rpc.example',
        'https://user:secret@rpc.example',
        'https://@rpc.example',
        'https://rpc.example/path#fragment',
        'https://rpc.example/path#',
        'ftp://rpc.example',
        'rpc.example',
        'not a url',
        '',
      ]) {
        expect(EndpointPolicy.isSafeUrl(url), isFalse, reason: url);
        expect(
          () => EndpointPolicy.requireSafeUrl(url),
          throwsFormatException,
          reason: url,
        );
      }
    });
  });
}

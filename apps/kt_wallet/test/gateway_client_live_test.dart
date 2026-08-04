import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/market/gateway_client.dart';

void main() {
  final enabled = Platform.environment['KT_LIVE_GATEWAY_CLIENT'] == '1';

  test(
    'production Gateway health survives the strict response boundary',
    () async {
      final baseUrl =
          Platform.environment['KT_GATEWAY_URL'] ??
          'https://gateway.kt-wallet.com';
      final client = GatewayClient(baseUrl: baseUrl);

      expect(await client.health(), isTrue);
    },
    skip: enabled ? false : 'set KT_LIVE_GATEWAY_CLIENT=1 for live evidence',
  );
}

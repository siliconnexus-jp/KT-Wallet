import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every direct production JSON-RPC owner binds its response', () {
    final violations = <String>[];
    final jsonRpcRequest = RegExp(
      "['\\\"]jsonrpc['\\\"]\\s*:\\s*['\\\"]2\\.0['\\\"]",
    );

    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final source = entity.readAsStringSync();
      final ownsDirectHttp = source.contains('BoundedHttpClient(');
      if (!ownsDirectHttp || !jsonRpcRequest.hasMatch(source)) continue;
      if (!source.contains('isBoundJsonRpcResponse(')) {
        violations.add(entity.path);
      }
    }

    expect(
      violations,
      isEmpty,
      reason:
          'A direct JSON-RPC owner must reject stale, reordered or malformed '
          'response envelopes before using result/error.',
    );
  });
}

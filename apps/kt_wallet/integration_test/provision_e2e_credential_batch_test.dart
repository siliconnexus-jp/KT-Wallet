import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:test_support/e2e_credentials.dart';

/// Provisions a disposable real-chain E2E credential batch with the native
/// Wallet Core bridge. This test is disabled unless the operator supplies the
/// explicit build-time switch below.
///
/// The mnemonic is never printed or returned through the test protocol. The
/// generated JSON remains in the simulator/device Application Support
/// directory so the operator can copy it through platform tooling, set mode
/// 0600 on the host, validate it, and then delete the device copy.
const _provisionEnabled = bool.fromEnvironment(
  'KT_PROVISION_E2E_BATCH',
  defaultValue: false,
);
const _staleWalletId = String.fromEnvironment('KT_PROVISION_STALE_WALLET_ID');
const _cleanupOnly = bool.fromEnvironment(
  'KT_PROVISION_CLEANUP_ONLY',
  defaultValue: false,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  test(
    'native Wallet Core provisions a private, versioned E2E batch',
    () async {
      final crypto = MethodChannelCoreCrypto();
      if (_staleWalletId.isNotEmpty) {
        expect(_staleWalletId, startsWith('e2e-provision-batch_'));
        await crypto
            .deleteWallet(_staleWalletId)
            .timeout(const Duration(seconds: 45));
        // ignore: avoid_print
        print('E2E-STALE-NATIVE-KEY-DELETED walletId=$_staleWalletId');
      }
      if (_cleanupOnly) {
        expect(
          _staleWalletId,
          isNotEmpty,
          reason: 'Cleanup-only mode requires KT_PROVISION_STALE_WALLET_ID.',
        );
        return;
      }
      final now = DateTime.now().toUtc();
      final batchId = _newBatchId(now, Random.secure());
      final walletId = 'e2e-provision-$batchId';
      final mnemonic = await crypto.generateMnemonic();
      File? output;
      expect(await crypto.validateMnemonic(mnemonic), isTrue);

      try {
        await crypto.storeWallet(
          walletId: walletId,
          mnemonic: mnemonic,
          requireAuth: false,
        );
        final addresses = await crypto.deriveAddresses(walletId);
        expect(Addresses.validate(Chain.ethereum, addresses.eth).isValid, true);
        expect(Addresses.validate(Chain.tron, addresses.tron).isValid, true);
        expect(
          Addresses.validate(Chain.solana, addresses.solana).isValid,
          true,
        );

        final document = buildE2eCredentialDocument(
          batchId: batchId,
          createdAtUtc: now,
          lifetime: const Duration(days: 14),
          mnemonic: mnemonic,
        );
        expect(validateE2eCredentialDocument(document, nowUtc: now), isEmpty);

        final directory = await getApplicationSupportDirectory();
        output = File('${directory.path}/.kt-e2e-$batchId.json');
        expect(output.existsSync(), isFalse);
        output.createSync(exclusive: true);
        final handle = output.openSync(mode: FileMode.writeOnly);
        try {
          handle.writeStringSync(
            '${const JsonEncoder.withIndent('  ').convert(document)}\n',
          );
          handle.flushSync();
        } finally {
          handle.closeSync();
        }

        // Only public evidence is allowed in the device-test log.
        // ignore: avoid_print
        print(
          'E2E-BATCH-PROVISIONED batch=$batchId '
          'file=${output.uri.pathSegments.last} '
          'evm=${addresses.eth} tron=${addresses.tron} '
          'solana=${addresses.solana}',
        );
        await _waitForHostConsumption(directory, batchId);
        output.deleteSync();
        output = null;
        // ignore: avoid_print
        print('E2E-BATCH-CONSUMED batch=$batchId');
      } finally {
        if (output?.existsSync() == true) output!.deleteSync();
        await crypto
            .deleteWallet(walletId)
            .timeout(const Duration(seconds: 45));
        // ignore: avoid_print
        print('E2E-BATCH-NATIVE-KEY-DELETED batch=$batchId');
      }
    },
    skip: _provisionEnabled
        ? false
        : 'Set KT_PROVISION_E2E_BATCH=true explicitly to create a batch.',
    timeout: const Timeout(Duration(minutes: 6)),
  );
}

Future<void> _waitForHostConsumption(
  Directory directory,
  String batchId,
) async {
  final marker = File('${directory.path}/.kt-e2e-consumed-$batchId');
  final deadline = DateTime.now().add(const Duration(minutes: 5));
  while (DateTime.now().isBefore(deadline)) {
    if (marker.existsSync()) {
      marker.deleteSync();
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw TimeoutException('Host did not acknowledge the private batch file.');
}

String _newBatchId(DateTime now, Random random) {
  final date =
      '${now.year.toString().padLeft(4, '0')}'
      '${now.month.toString().padLeft(2, '0')}'
      '${now.day.toString().padLeft(2, '0')}';
  final suffix = List.generate(
    8,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  return 'batch_${date}_$suffix';
}

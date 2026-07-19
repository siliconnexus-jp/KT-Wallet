import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';

/// Native-bridge smoke app: exercises mnemonic generation and derivation on a
/// real device/simulator. Also the host app for integration_test vectors.
void main() {
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  final CoreCrypto _crypto = MethodChannelCoreCrypto();
  String _output = 'Tap a button to call the native bridge.';

  Future<void> _run(Future<String> Function() action) async {
    try {
      final result = await action();
      setState(() => _output = result);
    } catch (e) {
      setState(() => _output = 'ERROR: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('core_crypto bridge')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FilledButton(
                onPressed: () => _run(() => _crypto.generateMnemonic()),
                child: const Text('generateMnemonic (12 words)'),
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => _run(() async {
                  const walletId = 'example-wallet';
                  final mnemonic = await _crypto.generateMnemonic();
                  await _crypto.storeWallet(
                    walletId: walletId,
                    mnemonic: mnemonic,
                    requireAuth: false,
                  );
                  final addrs = await _crypto.deriveAddresses(walletId);
                  await _crypto.deleteWallet(walletId);
                  return addrs.toMap().toString();
                }),
                child: const Text('store → derive → delete'),
              ),
              const SizedBox(height: 16),
              Expanded(child: SingleChildScrollView(child: Text(_output))),
            ],
          ),
        ),
      ),
    );
  }
}

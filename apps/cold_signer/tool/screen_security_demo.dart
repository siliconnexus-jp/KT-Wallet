import 'package:cold_signer/main.dart';
import 'package:cold_signer/src/state/locale_controller.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    ColdSignerApp(
      localeController: LocaleController(initial: const Locale('zh')),
      initialLocation: '/mnemonic-show',
    ),
  );
}

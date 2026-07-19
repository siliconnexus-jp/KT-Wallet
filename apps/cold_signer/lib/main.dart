import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import 'src/signer_router.dart';

void main() {
  runApp(ColdSignerApp());
}

class ColdSignerApp extends StatelessWidget {
  ColdSignerApp({super.key});

  final _router = buildSignerRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Cold Signer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Inter',
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(seedColor: SignerColors.ok, brightness: Brightness.dark),
        scaffoldBackgroundColor: SignerColors.bg,
      ),
      routerConfig: _router,
    );
  }
}

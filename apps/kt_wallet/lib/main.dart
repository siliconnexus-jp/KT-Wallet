import 'package:flutter/material.dart';
import 'package:ui_kit/ui_kit.dart';

import 'src/app_router.dart';

void main() {
  runApp(KtWalletApp());
}

class KtWalletApp extends StatelessWidget {
  KtWalletApp({super.key});

  final _router = buildRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'KT Wallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(seedColor: WalletColors.accent),
        scaffoldBackgroundColor: WalletColors.bg,
      ),
      routerConfig: _router,
    );
  }
}

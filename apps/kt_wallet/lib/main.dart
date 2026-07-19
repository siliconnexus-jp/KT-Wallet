import 'package:flutter/material.dart';

void main() {
  runApp(const KtWalletApp());
}

class KtWalletApp extends StatelessWidget {
  const KtWalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KT Wallet',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2557E8)),
        scaffoldBackgroundColor: const Color(0xFFF5F6F8),
      ),
      home: const PlaceholderHomePage(),
    );
  }
}

class PlaceholderHomePage extends StatelessWidget {
  const PlaceholderHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.account_balance_wallet,
                size: 64, color: Color(0xFF2557E8)),
            SizedBox(height: 16),
            Text(
              'KT Wallet',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 4),
            Text('P0 placeholder', style: TextStyle(color: Color(0xFF626B7A))),
          ],
        ),
      ),
    );
  }
}

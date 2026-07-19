import 'package:flutter/material.dart';

void main() {
  runApp(const ColdSignerApp());
}

class ColdSignerApp extends StatelessWidget {
  const ColdSignerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cold Signer',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF34D77B),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF0A0C0F),
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
            Icon(Icons.shield, size: 64, color: Color(0xFF34D77B)),
            SizedBox(height: 16),
            Text(
              'Cold Signer',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 4),
            Text('P0 placeholder', style: TextStyle(color: Color(0xFF8E97A5))),
          ],
        ),
      ),
    );
  }
}

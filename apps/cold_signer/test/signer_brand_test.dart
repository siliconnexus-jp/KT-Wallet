import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> expectIconSize(String path, int pixels) async {
  final codec = await ui.instantiateImageCodec(await File(path).readAsBytes());
  final frame = await codec.getNextFrame();
  expect(frame.image.width, pixels, reason: path);
  expect(frame.image.height, pixels, reason: path);
  frame.image.dispose();
  codec.dispose();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('offline brand is bundled and distinct from online wallet', () async {
    final offline = await File('assets/brand/app_icon.png').readAsBytes();
    final online = await File(
      '../kt_wallet/assets/brand/app_icon.png',
    ).readAsBytes();
    expect(listEquals(offline, online), isFalse);
    await expectIconSize('assets/brand/app_icon.png', 1024);
  });

  test(
    'Android launcher densities have correctly sized offline assets',
    () async {
      for (final entry in {
        'mdpi': 48,
        'hdpi': 72,
        'xhdpi': 96,
        'xxhdpi': 144,
        'xxxhdpi': 192,
      }.entries) {
        final relative =
            'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png';
        await expectIconSize(relative, entry.value);
        expect(
          listEquals(
            await File(relative).readAsBytes(),
            await File('../kt_wallet/$relative').readAsBytes(),
          ),
          isFalse,
        );
      }
    },
  );

  test(
    'all iOS icon catalog slots resolve to correctly sized offline assets',
    () async {
      const root = 'ios/Runner/Assets.xcassets/AppIcon.appiconset';
      final catalog =
          jsonDecode(await File('$root/Contents.json').readAsString())
              as Map<String, dynamic>;
      for (final raw in catalog['images'] as List<dynamic>) {
        final entry = raw as Map<String, dynamic>;
        final points = double.parse((entry['size'] as String).split('x').first);
        final scale = double.parse(
          (entry['scale'] as String).replaceAll('x', ''),
        );
        await expectIconSize(
          '$root/${entry['filename']}',
          (points * scale).round(),
        );
      }
    },
  );
}

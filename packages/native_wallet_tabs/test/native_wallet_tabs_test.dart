import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:native_wallet_tabs/native_wallet_tabs.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final calls = <MethodCall>[];
  final channels = <String>[];
  final platformCalls = <MethodCall>[];
  const codec = StandardMethodCodec();
  late String currentChannel;
  Map<Object?, Object?> getConfig() =>
      calls.lastWhere((call) => call.method == 'update').arguments
          as Map<Object?, Object?>;

  setUp(() {
    calls.clear();
    channels.clear();
    platformCalls.clear();
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        platformCalls.add(call);
        if (call.method == 'create') {
          final args = call.arguments as Map<Object?, Object?>;
          currentChannel = 'kt/native_wallet_tabs/${args['id']}';
          channels.add(currentChannel);
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            MethodChannel(currentChannel),
            (method) async {
              calls.add(method);
              return null;
            },
          );
        }
        return null;
      },
    );
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      null,
    );
    for (final channel in channels) {
      binding.defaultBinaryMessenger.setMockMethodCallHandler(
        MethodChannel(channel),
        null,
      );
    }
  });

  Future<void> emit(Object? value) async {
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      currentChannel,
      codec.encodeMethodCall(MethodCall('selected', value)),
      (_) {},
    );
  }

  Widget screen({
    int selected = 0,
    String wallet = 'Wallet',
    bool enabled = true,
    bool dark = false,
    bool highContrast = false,
    ValueChanged<int>? onSelected,
  }) => MaterialApp(
    theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
    home: MediaQuery(
      data: MediaQueryData(
        viewPadding: const EdgeInsets.only(bottom: 34),
        highContrast: highContrast,
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: NativeWalletTabs(
          items: [
            NativeWalletTab(title: wallet, symbol: 'wallet.pass'),
            const NativeWalletTab(
              title: 'Activity',
              symbol: 'clock.arrow.circlepath',
            ),
            const NativeWalletTab(title: 'Settings', symbol: 'gearshape'),
          ],
          selectedIndex: selected,
          enabled: enabled,
          onSelected: onSelected ?? (_) {},
          fallback: const Text('Flutter tabs'),
        ),
      ),
    ),
  );

  testWidgets(
    'non-iOS keeps Flutter fallback without creating native views',
    (tester) async {
      await tester.pumpWidget(screen());
      expect(find.text('Flutter tabs'), findsOneWidget);
      expect(find.byType(UiKitView), findsNothing);
      expect(channels, isEmpty);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'native bridge only carries three navigation items and safe-area height',
    (tester) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      expect(getConfig().keys.toSet(), {
        'items',
        'selectedIndex',
        'dark',
        'highContrast',
        'enabled',
        'revision',
      });
      expect((getConfig()['items']! as List).length, 3);
      expect(tester.getSize(find.byType(UiKitView)).height, 114);
      expect(find.text('Flutter tabs'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'tab touches reach UIKit rather than the tappable asset list underneath',
    (tester) async {
      var assetTaps = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => assetTaps++,
                  child: const SizedBox.expand(),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: NativeWalletTabs(
                  items: const [
                    NativeWalletTab(title: 'Wallet', symbol: 'wallet.pass'),
                    NativeWalletTab(title: 'Activity', symbol: 'clock'),
                    NativeWalletTab(title: 'Settings', symbol: 'gearshape'),
                  ],
                  selectedIndex: 0,
                  onSelected: (_) {},
                  fallback: const SizedBox.shrink(),
                ),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rect = tester.getRect(find.byType(UiKitView));
      final gesture = await tester.startGesture(rect.center);
      await tester.pump();
      expect(
        platformCalls.any((call) => call.method == 'acceptGesture'),
        isTrue,
        reason:
            'UIKit needs touch-down immediately, before the pointer is lifted.',
      );
      await gesture.up();
      await tester.pumpAndSettle();
      expect(assetTaps, 0);
      expect(
        platformCalls.any((call) => call.method == 'rejectGesture'),
        isFalse,
      );
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'selection, language and appearance update the existing native view',
    (tester) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      final firstRevision = getConfig()['revision']! as int;
      await tester.pumpWidget(
        screen(selected: 2, wallet: '钱包', dark: true, highContrast: true),
      );
      await tester.pumpAndSettle();
      expect(channels.length, 1);
      expect(getConfig()['selectedIndex'], 2);
      expect((getConfig()['items']! as List).first, {
        'title': '钱包',
        'symbol': 'wallet.pass',
      });
      expect(getConfig()['dark'], true);
      expect(getConfig()['highContrast'], true);
      expect(getConfig()['revision'], greaterThan(firstRevision));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'invalid, delayed and disabled callbacks cannot change tabs',
    (tester) async {
      final selections = <int>[];
      await tester.pumpWidget(screen(onSelected: selections.add));
      await tester.pumpAndSettle();
      final revision = getConfig()['revision'];
      for (final index in [-1, 3, '1', null]) {
        await emit({'index': index, 'revision': revision});
      }
      await emit({'index': 1, 'revision': -1});
      await emit('invalid');
      expect(selections, isEmpty);
      await emit({'index': 1, 'revision': revision});
      expect(selections, [1]);
      await tester.pumpWidget(
        screen(enabled: false, onSelected: selections.add),
      );
      await tester.pumpAndSettle();
      expect(getConfig()['enabled'], false);
      await emit({'index': 2, 'revision': getConfig()['revision']});
      expect(selections, [1]);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'backgrounding disables native interaction, resume restores it',
    (tester) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(
        calls.any(
          (call) => call.method == 'setEnabled' && call.arguments == false,
        ),
        true,
      );
      expect(getConfig()['enabled'], false);
      binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(getConfig()['enabled'], true);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  testWidgets(
    'removing the tab bar explicitly disposes native containment',
    (tester) async {
      await tester.pumpWidget(screen());
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      expect(calls.where((call) => call.method == 'dispose').length, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}

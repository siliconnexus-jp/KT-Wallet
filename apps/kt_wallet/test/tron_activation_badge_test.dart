import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/market/balance_service.dart';
import 'package:kt_wallet/src/widgets/tron_activation_badge.dart';

Widget _host(Widget child, {Locale locale = const Locale('zh')}) => MaterialApp(
  locale: locale,
  supportedLocales: AppLocalizations.supportedLocales,
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('badge renders every honest activation state', (tester) async {
    const cases = <TronActivationStatus, String>{
      TronActivationStatus.checking: '检测中',
      TronActivationStatus.activated: '已激活',
      TronActivationStatus.unactivated: '未激活',
      TronActivationStatus.unknown: '状态未知',
    };

    for (final MapEntry(key: status, value: label) in cases.entries) {
      await tester.pumpWidget(_host(TronActivationBadge(status: status)));
      expect(find.byKey(ValueKey('tron-activation-${status.name}')), findsOne);
      expect(find.text(label), findsOne);
      expect(
        tester.getSemantics(find.byType(TronActivationBadge)).label,
        'TRON 账户状态: $label',
      );
    }
  });

  testWidgets('activation guidance appears only for an unactivated account', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const TronActivationNotice(status: TronActivationStatus.unactivated),
      ),
    );
    expect(find.byKey(const ValueKey('tron-activation-notice')), findsOne);
    expect(find.textContaining('暂时不能发起交易'), findsOne);

    await tester.pumpWidget(
      _host(const TronActivationNotice(status: TronActivationStatus.activated)),
    );
    expect(find.byKey(const ValueKey('tron-activation-notice')), findsNothing);
  });

  testWidgets('badge labels are localized', (tester) async {
    await tester.pumpWidget(
      _host(
        const TronActivationBadge(status: TronActivationStatus.unactivated),
        locale: const Locale('en'),
      ),
    );
    expect(find.text('Not activated'), findsOne);

    await tester.pumpWidget(
      _host(
        const TronActivationBadge(status: TronActivationStatus.activated),
        locale: const Locale('ja'),
      ),
    );
    expect(find.text('有効化済み'), findsOne);
  });
}

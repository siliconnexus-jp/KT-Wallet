import 'package:chains/rpc.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/l10n/app_localizations.dart';
import 'package:kt_wallet/src/transfer/transfer_error_localization.dart';

void main() {
  test(
    'every bounded rejection reason is localized in English, Chinese, and Japanese',
    () {
      final localized = <String, List<String>>{
        for (final language in const ['en', 'zh', 'ja'])
          language: [
            for (final kind in RpcRejectionKind.values)
              localizedRpcRejection(
                lookupAppLocalizations(Locale(language)),
                kind,
              ),
          ],
      };

      for (final messages in localized.values) {
        expect(messages, hasLength(RpcRejectionKind.values.length));
        expect(messages.every((message) => message.trim().isNotEmpty), isTrue);
      }

      final english = localized['en']!.join();
      final chinese = localized['zh']!.join();
      final japanese = localized['ja']!.join();
      expect(english, isNot(matches(RegExp(r'[\u3040-\u30ff\u3400-\u9fff]'))));
      expect(chinese, matches(RegExp(r'[\u3400-\u9fff]')));
      expect(japanese, matches(RegExp(r'[\u3040-\u30ff]')));
      expect(chinese, isNot(contains('transaction nonce is too low')));
      expect(japanese, isNot(contains('transaction nonce is too low')));
    },
  );

  test(
    'pre-sign network configuration failures never fall back to English',
    () {
      final english = lookupAppLocalizations(const Locale('en'));
      final chinese = lookupAppLocalizations(const Locale('zh'));
      final japanese = lookupAppLocalizations(const Locale('ja'));

      expect(
        english.transferNetworkUnavailable('ethereum'),
        'No active network is available for ethereum.',
      );
      expect(
        chinese.transferNetworkUnavailable('ethereum'),
        '当前没有可用于 ethereum 的活动网络。',
      );
      expect(
        japanese.transferNetworkUnavailable('ethereum'),
        'ethereum で使用できるアクティブなネットワークがありません。',
      );
      expect(english.transferChainIdUnavailable, contains('has no Chain ID'));
      expect(chinese.transferChainIdUnavailable, '当前选择的 EVM 网络缺少 Chain ID。');
      expect(
        japanese.transferChainIdUnavailable,
        '選択した EVM ネットワークに Chain ID がありません。',
      );
    },
  );
}

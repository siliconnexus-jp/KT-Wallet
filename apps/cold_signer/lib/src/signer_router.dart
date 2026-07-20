import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import 'screens/signer_onboarding_screens.dart';
import 'screens/signer_settings_screens.dart';
import 'screens/signer_signing_screens.dart';

/// Registry of every Cold Signer screen (C1–C21), powering the router + gallery.
final signerRegistry = <String, (String, WidgetBuilder)>{
  'C11 启动页': ('/splash', (c) => const SignerSplashScreen()),
  'C1 欢迎': ('/welcome', (c) => const SignerWelcomeScreen()),
  'C12 助记词安全提示': ('/mnemonic-warn', (c) => const SignerMnemonicWarnScreen()),
  'C3 助记词展示': ('/mnemonic-show', (c) => const SignerMnemonicShowScreen()),
  'C4 助记词校验': ('/mnemonic-verify', (c) => const SignerMnemonicVerifyScreen()),
  'C13 助记词输入': ('/mnemonic-import', (c) => const SignerMnemonicImportScreen()),
  'C14 设置密码': ('/set-password', (c) => const SignerSetPasswordScreen()),
  'C15 生物识别设置': ('/biometric', (c) => const SignerBiometricScreen()),
  'C16 创建成功': ('/created', (c) => const SignerCreatedScreen()),
  'C5 离线首页': ('/home', (c) => const SignerHomeScreen()),
  // The gallery/golden entry keeps the canned design snapshot so existing
  // goldens stay byte-identical; the live route is overridden below.
  'C2 离线安全检查': ('/security-check', (c) => const SignerSecurityCheckPreviewScreen()),
  'C6 扫描交易': ('/scan', (c) => const SignerScanScreen()),
  'C7 交易解析确认': ('/parse', (c) => const SignerParseScreen()),
  'C17 风险警告': ('/risk', (c) => const SignerRiskScreen()),
  'C8 身份验证': ('/auth', (c) => const SignerAuthScreen()),
  'C9 签名结果二维码': ('/result-qr', (c) => const SignerResultQrScreen()),
  'C10 地址导出': ('/export', (c) => const SignerAddressExportScreen()),
  'C18 签名记录': ('/records', (c) => const SignerRecordsScreen()),
  'C19 钱包管理': ('/wallet', (c) => const SignerWalletManageScreen()),
  'C20 安全设置': ('/security', (c) => const SignerSecuritySettingsScreen()),
  'C21 删除钱包': ('/delete', (c) => const SignerDeleteScreen()),
};

/// Live builders that replace a registry entry's design-snapshot builder when
/// the app actually navigates there (the registry itself is the golden/gallery
/// baseline and must keep rendering the original snapshot).
final _liveOverrides = <String, WidgetBuilder>{
  '/security-check': (c) => const SignerSecurityCheckScreen(),
};

GoRouter buildSignerRouter({String initialLocation = '/'}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/', builder: (c, s) => const _Gallery()),
        for (final entry in signerRegistry.entries)
          GoRoute(path: entry.value.$1, builder: (c, s) => (_liveOverrides[entry.value.$1] ?? entry.value.$2)(c)),
      ],
    );

class _Gallery extends StatelessWidget {
  const _Gallery();
  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: SignerColors.bg,
        appBar: AppBar(title: const Text('Cold Signer — 屏幕库', style: TextStyle(color: SignerColors.text)), backgroundColor: SignerColors.surface),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final entry in signerRegistry.entries)
              Card(
                color: SignerColors.surface,
                child: ListTile(
                  title: Text(entry.key, style: const TextStyle(color: SignerColors.text)),
                  subtitle: Text(entry.value.$1, style: const TextStyle(fontFamily: KtFonts.mono, fontSize: 12, color: SignerColors.text2)),
                  trailing: const Icon(Icons.chevron_right, color: SignerColors.text2),
                  onTap: () => context.go(entry.value.$1),
                ),
              ),
          ],
        ),
      );
}

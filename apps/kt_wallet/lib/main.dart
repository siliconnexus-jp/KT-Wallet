import 'package:cold_signer/cold_signer.dart';
import 'package:core_crypto/core_crypto.dart';
import 'package:core_crypto/testing.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import 'l10n/app_localizations.dart';
import 'src/app_router.dart';
import 'src/data/database_provider.dart';
import 'src/market/market_scope.dart';
import 'src/market/history_scope_host.dart';
import 'src/security/app_lock_gate.dart';
import 'src/security/secure_screen.dart';
import 'src/state/app_prefs.dart';
import 'src/state/device_mode.dart';
import 'src/state/locale_controller.dart';
import 'src/state/networks.dart';
import 'src/state/wallet_controller.dart';
import 'src/state/wallet_scope.dart';
import 'src/transfer/transfer_draft.dart';
import 'src/wallets/wallet_manager.dart';
import 'src/wallets/wallet_model.dart';
import 'src/wallets/wallet_store.dart';

/// Production entrypoint for the combined single-installer app: loads the
/// persisted language and device-mode preferences, then shows either the
/// first-launch mode picker (online wallet vs offline signer), the full
/// wallet experience, or the embedded Cold Signer experience.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final localeController = LocaleController();
  await localeController.load();
  final modeController = DeviceModeController();
  await modeController.load();

  runApp(
    RootApp(localeController: localeController, modeController: modeController),
  );
}

/// Wallet-mode bootstrap (runs only once the user has picked "online wallet"):
/// opens the on-device drift database, wires a persistent [WalletStore]
/// backed by the native [MethodChannelCoreCrypto], and loads saved wallets
/// (seeding a starter set on first run, named in the active language).
///
/// A deterministic mock can only be enabled explicitly for simulator UI
/// acceptance builds with `--dart-define=KT_ALLOW_MOCK_CRYPTO=true`. Normal
/// debug/release builds fail closed when Trust Wallet Core is not linked.
Future<WalletController> _bootstrapWallet() async {
  final db = openWalletDatabase();
  const requestedMockCrypto = bool.fromEnvironment('KT_ALLOW_MOCK_CRYPTO');
  final allowMockCrypto = !kReleaseMode && requestedMockCrypto;
  final CoreCrypto crypto = allowMockCrypto
      ? MockCoreCrypto()
      : MethodChannelCoreCrypto();
  final store = WalletStore(db);
  final manager = await store.load();
  return WalletController(manager, crypto: crypto, store: store);
}

/// Resolves the locale to load [AppLocalizations] for: the manual override if
/// set, else the system locale matched against the supported set (falling back
/// to the first supported locale).
ChainAddresses _addr(String seed) => ChainAddresses(
  eth: '0x${seed}71c8B29b3d4b79E19bE1',
  polygon: '0x${seed}71c8B29b3d4b79E19bE1',
  tron: 'T${seed}Pa2Wc8hJdU5eRnT6yGb1sVb7L3kFa',
  solana: '${seed}yKpXwMWd4qmDqVr2W',
);

/// In-memory demo controller for the design gallery and widget tests (no
/// persistence). Demo wallet names stay as fixed literals — this controller
/// only backs the developer gallery/goldens, never the shipped home. The daily
/// wallet stays un-backed-up so the backup banner/flow is exercisable.
WalletController _seedController() => WalletController(
  WalletManager(
    initial: [
      HotWallet(
        id: 'daily',
        name: '日常钱包',
        avatarColor: 0xFFF59E0B,
        addresses: _addr('a'),
        backedUp: false,
      ),
      HotWallet(
        id: 'savings',
        name: '储蓄钱包',
        avatarColor: 0xFF8B5CF6,
        addresses: _addr('b'),
        sortOrder: 1,
        backedUp: true,
      ),
      WatchWallet(
        id: 'cold',
        name: '主钱包',
        avatarColor: 0xFF0C1220,
        addresses: _addr('c'),
        sortOrder: 2,
        coldWalletId: 'WLT-3E8A91',
        protocolVersion: 1,
      ),
    ],
  ),
);

/// Resolves the app's copy for the native privacy overlay and pushes it down.
/// Loading a delegate is async, so this fires and forgets; the platform keeps
/// its own fallback until the strings land.
void _pushPrivacyStrings(Locale? override) {
  final locale = basicLocaleListResolution(
    override != null
        ? [override]
        : WidgetsBinding.instance.platformDispatcher.locales,
    AppLocalizations.supportedLocales,
  );
  AppLocalizations.delegate.load(locale).then((l10n) {
    SecureScreen.setPrivacyStrings(
      appName: l10n.appName,
      active: l10n.privacyOverlayActive,
      hidden: l10n.privacyOverlayHidden,
    );
  }).ignore();
}

/// Root gate of the combined installer. Listens to the [DeviceModeController]:
///
/// * no mode chosen yet → [ModeSelectApp] (first-launch picker);
/// * [DeviceMode.wallet] → the persistent wallet bootstrap + [KtWalletApp];
/// * [DeviceMode.signer] → the embedded [ColdSignerApp].
///
/// Both mode subtrees run under a [DeviceModeScope] whose `exitMode` clears
/// the persisted choice and returns to the picker.
class RootApp extends StatelessWidget {
  RootApp({
    super.key,
    DeviceModeController? modeController,
    LocaleController? localeController,
    this.walletBootstrap,
  }) : modeController = modeController ?? DeviceModeController(),
       localeController = localeController ?? LocaleController();

  final DeviceModeController modeController;
  final LocaleController localeController;

  /// Builds the wallet-mode [WalletController]. Production defaults to the
  /// persistent drift-backed bootstrap; tests inject an in-memory factory.
  final Future<WalletController> Function()? walletBootstrap;

  @override
  Widget build(BuildContext context) {
    // Listens to the locale too: the guard renders its warning outside the
    // MaterialApp, so it needs the chosen language handed to it explicitly.
    return ListenableBuilder(
      listenable: localeController,
      builder: (context, _) => ScreenSecurityGuard(
        // Null = the user is following the system, which is exactly the
        // guard's own fallback.
        locale: localeController.locale,
        child: ListenableBuilder(
          listenable: modeController,
          builder: (context, _) {
            // Hand the overlay wording to the platform, which draws it while
            // backgrounded and otherwise falls back to the system language.
            _pushPrivacyStrings(localeController.locale);
            switch (modeController.mode) {
              case null:
                return ModeSelectApp(
                  localeController: localeController,
                  modeController: modeController,
                );
              case DeviceMode.wallet:
                return DeviceModeScope(
                  exitMode: modeController.clear,
                  child: _WalletBootstrap(
                    localeController: localeController,
                    bootstrap: walletBootstrap ?? _bootstrapWallet,
                  ),
                );
              case DeviceMode.signer:
                return DeviceModeScope(
                  exitMode: modeController.clear,
                  child: ColdSignerApp(initialLocation: '/welcome'),
                );
            }
          },
        ),
      ),
    );
  }
}

/// Runs the async wallet bootstrap behind a plain dark splash (just the picker
/// background color) and hands off to [KtWalletApp] once loaded. A failed
/// bootstrap (e.g. unreadable database) shows a retryable error screen instead
/// of hanging on the splash. Leaving wallet mode closes the database.
class _WalletBootstrap extends StatefulWidget {
  const _WalletBootstrap({
    required this.localeController,
    required this.bootstrap,
  });

  final LocaleController localeController;
  final Future<WalletController> Function() bootstrap;

  @override
  State<_WalletBootstrap> createState() => _WalletBootstrapState();
}

class _WalletBootstrapState extends State<_WalletBootstrap> {
  late Future<WalletController> _controller = widget.bootstrap();

  /// One preferences object for the whole wallet mode. [AppLockGate] sits
  /// above [KtWalletApp] — outside [AppPrefsScope] — so the two used to hold
  /// separate controllers over the same SharedPreferences keys, and a toggle
  /// in 安全设置 only reached the other side on the next cold start.
  final AppPrefsController _prefs = AppPrefsController();

  @override
  void dispose() {
    _prefs.dispose();
    // Release the DB connection when this mode subtree is torn down (mode
    // switch back to the picker). A bootstrap that failed has nothing to close.
    _controller.then((c) => c.close()).ignore();
    super.dispose();
  }

  void _retry() => setState(() {
    _controller = widget.bootstrap();
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<WalletController>(
      future: _controller,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _BootstrapErrorApp(
            localeController: widget.localeController,
            error: snapshot.error,
            onRetry: _retry,
          );
        }
        final controller = snapshot.data;
        if (controller == null) return const ColoredBox(color: SignerColors.bg);
        // App lock: with the security-settings 应用锁 preference on, the
        // wallet stays behind a biometric lock screen (see AppLockGate for
        // the no-biometrics / no-PIN enrollment fallback).
        final walletApp = KtWalletApp(
          controller: controller,
          localeController: widget.localeController,
          prefs: _prefs,
          initialLocation: controller.current == null ? '/add-wallet' : '/home',
        );
        // There is nothing sensitive to unlock before the first wallet is
        // created/imported/paired. A stale persisted app-lock preference must
        // not trap an empty production install behind biometrics.
        if (controller.current == null) return walletApp;
        return AppLockGate(
          localeController: widget.localeController,
          prefs: _prefs,
          child: walletApp,
        );
      },
    );
  }
}

/// Full-screen retryable error shown when the wallet bootstrap fails. Hosts its
/// own minimal MaterialApp because it renders outside [KtWalletApp] (there is
/// no Directionality/l10n above it otherwise).
class _BootstrapErrorApp extends StatelessWidget {
  const _BootstrapErrorApp({
    required this.localeController,
    required this.error,
    required this.onRetry,
  });

  final LocaleController localeController;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: localeController,
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appName,
        debugShowCheckedModeBanner: false,
        locale: localeController.locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          fontFamily: 'Inter',
          brightness: Brightness.dark,
          colorScheme: ColorScheme.fromSeed(
            seedColor: WalletColors.accent,
            brightness: Brightness.dark,
          ),
          scaffoldBackgroundColor: SignerColors.bg,
        ),
        home: Builder(
          builder: (context) {
            final l10n = AppLocalizations.of(context);
            final cryptoUnavailable = error is CryptoUnavailableException;
            return Scaffold(
              backgroundColor: SignerColors.bg,
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: SignerColors.text2,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        cryptoUnavailable
                            ? l10n.cryptoUnavailableTitle
                            : l10n.walletLoadErrorTitle,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: SignerColors.text,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        cryptoUnavailable
                            ? l10n.cryptoUnavailableDesc
                            : l10n.walletLoadErrorDesc,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.6,
                          color: SignerColors.text2,
                        ),
                      ),
                      const SizedBox(height: 24),
                      KtPrimaryButton(
                        label: l10n.actionRetry,
                        onPressed: onRetry,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Minimal MaterialApp hosting the first-launch device-mode picker: dark theme
/// consistent with the ui_kit design system, full l10n via kt_wallet's ARBs.
class ModeSelectApp extends StatelessWidget {
  const ModeSelectApp({
    super.key,
    required this.localeController,
    required this.modeController,
  });

  final LocaleController localeController;
  final DeviceModeController modeController;

  @override
  Widget build(BuildContext context) {
    return LocaleScope(
      controller: localeController,
      child: ListenableBuilder(
        listenable: localeController,
        builder: (context, _) => MaterialApp(
          onGenerateTitle: (context) => AppLocalizations.of(context).appName,
          debugShowCheckedModeBanner: false,
          locale: localeController.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            fontFamily: 'Inter',
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: WalletColors.accent,
              brightness: Brightness.dark,
            ),
            scaffoldBackgroundColor: SignerColors.bg,
          ),
          home: KtDeviceChrome(
            mockStatusBar: false,
            child: ModeSelectScreen(onSelect: modeController.setMode),
          ),
        ),
      ),
    );
  }
}

/// First-launch picker: this phone is either the online wallet or the offline
/// signer. The signer choice is gated behind an air-gap warning dialog.
class ModeSelectScreen extends StatelessWidget {
  const ModeSelectScreen({super.key, required this.onSelect});

  final ValueChanged<DeviceMode> onSelect;

  Future<void> _chooseSigner(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => KtConfirmDialog(
        title: l10n.modeSignerConfirmTitle,
        message: l10n.modeSignerConfirmBody,
        cancelLabel: l10n.actionCancel,
        confirmLabel: l10n.actionConfirm,
        theme: AppTheme.signer,
        icon: Icons.phonelink_lock_rounded,
        iconColor: SignerColors.ok,
      ),
    );
    if (confirmed == true) onSelect(DeviceMode.signer);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: SignerColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: WalletColors.accent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Icon(
                    Icons.account_balance_wallet_outlined,
                    size: 32,
                    color: Color(0xFFFFFFFF),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Center(
                child: Text(
                  'KT Wallet',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: SignerColors.text,
                  ),
                ),
              ),
              const SizedBox(height: 40),
              Text(
                l10n.modeSelectTitle,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: SignerColors.text,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.modeSelectSubtitle,
                style: const TextStyle(fontSize: 13, color: SignerColors.text2),
              ),
              const SizedBox(height: 20),
              _ModeCard(
                icon: Icons.account_balance_wallet_outlined,
                iconColor: SignerColors.blue,
                title: l10n.modeWalletTitle,
                description: l10n.modeWalletDesc,
                onTap: () => onSelect(DeviceMode.wallet),
              ),
              const SizedBox(height: 14),
              _ModeCard(
                icon: Icons.qr_code_scanner,
                iconColor: SignerColors.ok,
                title: l10n.modeSignerTitle,
                description: l10n.modeSignerDesc,
                onTap: () => _chooseSigner(context),
              ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: SignerColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: SignerColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: SignerColors.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 22, color: iconColor),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: SignerColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.5,
                      color: SignerColors.text2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.chevron_right,
              size: 18,
              color: SignerColors.text2,
            ),
          ],
        ),
      ),
    );
  }
}

class KtWalletApp extends StatefulWidget {
  KtWalletApp({
    super.key,
    WalletController? controller,
    LocaleController? localeController,
    NetworkController? networkController,
    AppPrefsController? prefs,
    this.initialLocation = '/',
  }) : controller = controller ?? _seedController(),
       localeController = localeController ?? LocaleController(),
       networkController = networkController ?? NetworkController(),
       prefs = prefs ?? AppPrefsController();

  final WalletController controller;
  final LocaleController localeController;
  final NetworkController networkController;

  /// Preferences shared with [AppLockGate], which sits above this app and so
  /// cannot reach [AppPrefsScope]. Passing one object is what lets a toggle in
  /// 安全设置 reach the lock gate without a restart.
  final AppPrefsController prefs;

  final String initialLocation;

  @override
  State<KtWalletApp> createState() => _KtWalletAppState();
}

class _KtWalletAppState extends State<KtWalletApp> {
  late final GoRouter _router;
  bool _marketConfigReady = false;

  /// In-flight transfer flow state (draft → sign-request → decoded result),
  /// shared across the transfer screens via [TransferSessionScope].
  final TransferSession _transferSession = TransferSession();

  /// App-wide preferences (RPC endpoint overrides among them), shared between
  /// the settings screens and the market services via [AppPrefsScope].
  AppPrefsController get _prefs => widget.prefs;

  /// Active-network state (mainnet/testnet environment, per-chain overrides,
  /// custom networks), shared app-wide via [NetworkScope].
  NetworkController get _networks => widget.networkController;

  @override
  void initState() {
    super.initState();
    _router = buildRouter(initialLocation: widget.initialLocation);
    _loadConfiguration();
  }

  Future<void> _loadConfiguration() async {
    // Do not start a mainnet refresh before persisted RPC/network selections
    // have loaded. Apart from wasting requests, that could briefly hydrate a
    // cache belonging to the wrong network environment.
    await Future.wait([
      widget.localeController.load(),
      _prefs.load(),
      _networks.load(),
    ]);
    if (mounted) setState(() => _marketConfigReady = true);
  }

  @override
  void didUpdateWidget(KtWalletApp oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A rebuilt app widget can carry a different preferences object (a fresh
    // KtWalletApp in tests, a mode switch in the installer). initState has
    // already run for this State, so nothing else would load it.
    if (!identical(oldWidget.prefs, widget.prefs)) {
      _marketConfigReady = false;
      _loadConfiguration();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LocaleScope(
      controller: widget.localeController,
      child: ListenableBuilder(
        listenable: widget.localeController,
        builder: (context, _) => MaterialApp.router(
          onGenerateTitle: (context) => AppLocalizations.of(context).appName,
          debugShowCheckedModeBanner: false,
          locale: widget.localeController.locale,
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            fontFamily: 'Inter',
            colorScheme: ColorScheme.fromSeed(seedColor: WalletColors.accent),
            scaffoldBackgroundColor: WalletColors.bg,
          ),
          routerConfig: _router,
          builder: (context, child) => KtDeviceChrome(
            mockStatusBar: false,
            child: WalletScope(
              controller: widget.controller,
              child: NetworkScope(
                controller: _networks,
                child: AppPrefsScope(
                  controller: _prefs,
                  child: MarketScopeHost(
                    wallets: widget.controller,
                    prefs: _prefs,
                    ready: _marketConfigReady,
                    child: HistoryScopeHost(
                      wallets: widget.controller,
                      prefs: _prefs,
                      networks: _networks,
                      ready: _marketConfigReady,
                      child: TransferSessionScope(
                        session: _transferSession,
                        child: child!,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

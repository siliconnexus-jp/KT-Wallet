import 'package:core_crypto/core_crypto.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import 'l10n/app_localizations.dart';
import 'src/app_router.dart';
import 'src/data/database_provider.dart';
import 'src/market/market_controller.dart';
import 'src/market/market_scope.dart';
import 'src/market/history_scope_host.dart';
import 'src/observability/experience_metrics.dart';
import 'src/onboarding/product_intro_app.dart';
import 'src/security/app_lock_gate.dart';
import 'src/security/secure_screen.dart';
import 'src/state/app_prefs.dart';
import 'src/state/developer_mode.dart';
import 'src/state/locale_controller.dart';
import 'src/state/networks.dart';
import 'src/state/wallet_controller.dart';
import 'src/state/wallet_scope.dart';
import 'src/transfer/local_transfer_service.dart';
import 'src/transfer/transfer_draft.dart';
import 'src/wallets/wallet_manager.dart';
import 'src/wallets/wallet_model.dart';
import 'src/wallets/wallet_store.dart';

/// Production entrypoint for the standalone online wallet.
/// Loads the saved language and opens wallet onboarding or the wallet home.
Future<void> main() async {
  final startupStopwatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  ExperienceMetrics.instance.installErrorObservers();
  await ExperienceMetrics.instance.initializePersistence();
  await ExperienceMetrics.instance.ingestNativeIncidents();

  final localeController = LocaleController();
  await localeController.load();
  runApp(RootApp(localeController: localeController));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    ExperienceMetrics.instance.record(
      ExperienceMetricNames.appStartup,
      startupStopwatch.elapsed,
      success: true,
    );
  });
}

/// Online-wallet bootstrap:
/// opens the on-device drift database, wires a persistent [WalletStore]
/// backed by the native [MethodChannelCoreCrypto], and loads saved wallets
/// (seeding a starter set on first run, named in the active language).
///
/// Production always uses the native implementation. UI and Golden tests
/// inject their own controllers instead of enabling a runtime build flag; a
/// shipped binary therefore has no switch that can replace key operations.
Future<WalletController> _bootstrapWallet() async {
  final db = openWalletDatabase();
  final store = WalletStore(db);
  final manager = await store.load();
  final controller = WalletController(
    manager,
    crypto: MethodChannelCoreCrypto(),
    store: store,
  );
  await controller.recoverPendingDeletions();
  // Do not inspect native key material during startup. AppLockGate owns the
  // single unlock prompt; signing/export flows validate and open the selected
  // wallet only when the user explicitly needs its secret. Even a nominally
  // non-interactive Keychain/Keystore probe can report device-specific access
  // states and must not turn readable wallet metadata into a bootstrap error.
  await controller.restoreDurableFinalityMetrics();
  return controller;
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
WalletController _seedController(CoreCrypto? crypto) => WalletController(
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
  crypto: crypto,
  allowTestBypass: true,
);

Never _missingProductionController() => throw StateError(
  'A release KtWalletApp must receive its persistent WalletController.',
);

WalletController _resolveWalletController(
  WalletController? controller,
  CoreCrypto? galleryCrypto,
) {
  if (controller == null) {
    if (!developerFixturesEnabled) return _missingProductionController();
    return _seedController(galleryCrypto);
  }
  // A test-bypass controller enables fixture signatures and success paths in
  // several screens. Even an accidental alternate entrypoint must not be able
  // to inject one into a release process.
  if (!developerFixturesEnabled && controller.allowsTestBypass) {
    throw StateError(
      'A release KtWalletApp cannot use a test-bypass WalletController.',
    );
  }
  return controller;
}

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

/// Root of the standalone online wallet. Legacy device-mode preferences are
/// ignored; the offline signer is distributed as a separate application.
class RootApp extends StatelessWidget {
  RootApp({
    super.key,
    LocaleController? localeController,
    this.walletBootstrap,
    this.walletPrefs,
    this.walletNetworks,
    this.walletTransferSession,
  }) : localeController = localeController ?? LocaleController();
  final LocaleController localeController;

  /// Builds the wallet-mode [WalletController]. Production defaults to the
  /// persistent drift-backed bootstrap; tests inject an in-memory factory.
  final Future<WalletController> Function()? walletBootstrap;

  /// Optional wallet-mode preferences used by end-to-end app-shell tests.
  /// Production owns one controller inside [_WalletBootstrap].
  final AppPrefsController? walletPrefs;

  /// Optional live state seams for physical-device integration tests. The
  /// production bootstrap continues to create the normal defaults.
  final NetworkController? walletNetworks;
  final TransferSession? walletTransferSession;

  @override
  Widget build(BuildContext context) {
    // Listens to the locale too: the guard renders its warning outside the
    // MaterialApp, so it needs the chosen language handed to it explicitly.
    return ListenableBuilder(
      listenable: localeController,
      builder: (context, _) {
        _pushPrivacyStrings(localeController.locale);
        return ScreenSecurityGuard(
          locale: localeController.locale,
          child: _WalletBootstrap(
            localeController: localeController,
            bootstrap: walletBootstrap ?? _bootstrapWallet,
            prefs: walletPrefs,
            networks: walletNetworks,
            transferSession: walletTransferSession,
          ),
        );
      },
    );
  }
}

/// Runs wallet bootstrap behind a splash and opens [KtWalletApp] once loaded.
/// A failed bootstrap shows a retryable error screen. Disposing the app
/// releases the database connection.
class _WalletBootstrap extends StatefulWidget {
  const _WalletBootstrap({
    required this.localeController,
    required this.bootstrap,
    this.prefs,
    this.networks,
    this.transferSession,
  });

  final LocaleController localeController;
  final Future<WalletController> Function() bootstrap;
  final AppPrefsController? prefs;
  final NetworkController? networks;
  final TransferSession? transferSession;

  @override
  State<_WalletBootstrap> createState() => _WalletBootstrapState();
}

class _WalletBootstrapState extends State<_WalletBootstrap> {
  late Future<WalletController> _controller = widget.bootstrap();

  /// One preferences object for the whole wallet mode. [AppLockGate] sits
  /// above [KtWalletApp] — outside [AppPrefsScope] — so the two used to hold
  /// separate controllers over the same SharedPreferences keys, and a toggle
  /// in 安全设置 only reached the other side on the next cold start.
  late final AppPrefsController _prefs = widget.prefs ?? AppPrefsController();

  @override
  void dispose() {
    if (widget.prefs == null) _prefs.dispose();
    // Release the DB connection when the app subtree is torn down.
    // A bootstrap that failed has nothing to close.
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
          networkController: widget.networks,
          transferSession: widget.transferSession,
          initialLocation: controller.current == null ? '/add-wallet' : '/home',
        );
        // There is nothing sensitive to unlock before the first wallet is
        // created/imported/paired. A stale persisted app-lock preference must
        // not trap an empty production install behind biometrics.
        if (controller.current == null) {
          return WalletIntroApp(
            localeController: widget.localeController,
            child: walletApp,
          );
        }
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

class KtWalletApp extends StatefulWidget {
  KtWalletApp({
    super.key,
    WalletController? controller,
    this.marketController,
    bool? galleryMode,
    LocaleController? localeController,
    NetworkController? networkController,
    AppPrefsController? prefs,
    CoreCrypto? galleryCrypto,
    this.transferService,
    TransferSession? transferSession,
    this.initialLocation = '/',
  }) : galleryMode =
           developerFixturesEnabled && (galleryMode ?? controller == null),
       controller = _resolveWalletController(controller, galleryCrypto),
       localeController = localeController ?? LocaleController(),
       networkController = networkController ?? NetworkController(),
       prefs = prefs ?? AppPrefsController(),
       transferSession = transferSession ?? TransferSession();

  final WalletController controller;

  /// Enables the developer screen gallery and its deterministic fixtures.
  ///
  /// Production always injects its persistent controller, which makes this
  /// false. Tests that intentionally construct the app without a controller
  /// retain the gallery. This distinction also prevents a `/` deep link in a
  /// shipped build from exposing fixture-only routes.
  final bool galleryMode;

  /// Optional deterministic market source for integration/widget tests.
  ///
  /// Production never supplies this; [MarketScopeHost] builds its live
  /// gateway/RPC-backed controller. Keeping the seam at the app root lets
  /// navigation tests prove funded transfer flows without reintroducing
  /// fabricated balances into production screens.
  final MarketController? marketController;
  final LocalTransferService? transferService;
  final TransferSession transferSession;
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
  TransferSession get _transferSession => widget.transferSession;

  /// App-wide preferences (RPC endpoint overrides among them), shared between
  /// the settings screens and the market services via [AppPrefsScope].
  AppPrefsController get _prefs => widget.prefs;

  /// Active-network state (mainnet/testnet environment, per-chain overrides,
  /// custom networks), shared app-wide via [NetworkScope].
  NetworkController get _networks => widget.networkController;

  @override
  void initState() {
    super.initState();
    _router = buildRouter(
      initialLocation: widget.initialLocation,
      galleryMode: widget.galleryMode,
      walletController: widget.controller,
      transferService: widget.transferService,
      transferSession: _transferSession,
    );
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
          theme: ktWalletTheme(),
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
                    controller: widget.marketController,
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

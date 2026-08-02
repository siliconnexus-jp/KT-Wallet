import 'package:chains/chains.dart' show Chain;
import 'package:flutter/widgets.dart';

import '../state/app_prefs.dart';
import '../state/networks.dart';
import '../state/wallet_controller.dart';
import 'asset_ref.dart';
import 'history_controller.dart';
import 'history_service.dart';
import 'history_snapshot.dart';
import 'market_scope.dart';
import 'transaction_status_service.dart';
import '../widgets/transaction_status_notice.dart';

/// Owns one app-wide history controller so opening the wallet-wide history and
/// multiple asset details reuses the same fetched records, gateway capability
/// probe and HTTP connection pool.
class HistoryScopeHost extends StatefulWidget {
  const HistoryScopeHost({
    super.key,
    required this.wallets,
    required this.prefs,
    required this.networks,
    this.ready = true,
    required this.child,
  });

  final WalletController wallets;
  final AppPrefsController prefs;
  final NetworkController networks;
  final bool ready;
  final Widget child;

  @override
  State<HistoryScopeHost> createState() => _HistoryScopeHostState();
}

class _HistoryScopeHostState extends State<HistoryScopeHost> {
  late final controller = HistoryController(
    wallets: widget.wallets,
    networkChanges: widget.networks,
    activeNetworkIds: () => {
      for (final chain in Chain.values) widget.networks.activeFor(chain).id,
    },
    activeNetworkId: (coin) => widget.networks.activeFor(chainOf(coin)).id,
    service: HistoryService(
      endpoints: effectiveRpcEndpoints(widget.prefs, widget.networks),
      gateway: prefsGatewayResolver(widget.prefs, widget.networks),
      tokenRegistry: networkTokenRegistry(widget.networks),
    ),
    statusService: TransactionStatusService(
      endpoints: effectiveRpcEndpoints(widget.prefs, widget.networks),
      gateway: prefsGatewayResolver(widget.prefs, widget.networks),
    ),
    canRefresh: () => widget.ready,
    snapshots: WalletHistorySnapshotStore(widget.wallets),
    snapshotScope: () {
      final ids = [
        for (final chain in Chain.values) widget.networks.activeFor(chain).id,
      ]..sort();
      return ids.join('|');
    },
  );

  @override
  void didUpdateWidget(HistoryScopeHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.ready && widget.ready) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) controller.configurationReady();
      });
    }
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => HistoryScope(
    controller: controller,
    autoRefresh: true,
    child: TransactionStatusNoticeHost(
      controller: controller,
      child: widget.child,
    ),
  );
}

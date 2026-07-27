import 'package:chains/chains.dart' show Chain;
import 'package:flutter/foundation.dart';

import '../widgets/rpc_probe.dart';

/// Measured state of one network's RPC endpoint.
///
/// The network-settings rows used to render string literals — `'86 ms'`,
/// `'112 ms'`, `'64 ms'`, and a permanent `Timeout` for Solana — so the badges
/// claimed a health the app had never checked. Solana in particular showed a
/// red failure while its node was demonstrably fine.
sealed class RpcHealth {
  const RpcHealth();
}

/// No measurement yet (or one in flight).
class RpcHealthProbing extends RpcHealth {
  const RpcHealthProbing();
}

/// The endpoint answered the family liveness call in [millis].
class RpcHealthOk extends RpcHealth {
  const RpcHealthOk(this.millis);
  final int millis;
}

/// The endpoint did not answer, or answered unusably.
class RpcHealthDown extends RpcHealth {
  const RpcHealthDown();
}

/// Probes each active RPC endpoint once and publishes the round-trip time.
///
/// One probe per network id; results are keyed by that id so switching a
/// chain's active network re-measures instead of reusing the old figure.
class RpcHealthController extends ChangeNotifier {
  RpcHealthController({
    RpcProbe? probe,
    this.timeout = const Duration(seconds: 6),
  }) : _probe = probe ?? RpcProbe(timeout: const Duration(seconds: 6)),
       _ownsProbe = probe == null;

  final RpcProbe _probe;
  final bool _ownsProbe;
  final Duration timeout;

  final Map<String, RpcHealth> _byNetworkId = {};

  /// Guards against a rebuild storm re-probing the same endpoint repeatedly.
  final Set<String> _inFlight = {};

  bool _disposed = false;

  RpcHealth healthOf(String networkId) =>
      _byNetworkId[networkId] ?? const RpcHealthProbing();

  /// Measures [networkId] unless it already has a result or a probe is in
  /// flight. [force] re-measures regardless (pull-to-refresh, node edited).
  Future<void> measure({
    required String networkId,
    required Chain chain,
    required String rpcUrl,
    bool force = false,
  }) async {
    if (_disposed) return;
    if (_inFlight.contains(networkId)) return;
    if (!force && _byNetworkId.containsKey(networkId)) return;

    _inFlight.add(networkId);
    _byNetworkId[networkId] = const RpcHealthProbing();
    notifyListeners();

    final watch = Stopwatch()..start();
    RpcProbeResult result;
    try {
      result = await _probe.probe(chain: chain, rpcUrl: rpcUrl);
    } on Object {
      result = const RpcProbeFailure();
    }
    watch.stop();

    _inFlight.remove(networkId);
    if (_disposed) return;
    // A chain-id mismatch still proves the node is up and how fast it is; the
    // mismatch itself is the add-network form's business, not this badge's.
    _byNetworkId[networkId] = result is RpcProbeFailure
        ? const RpcHealthDown()
        : RpcHealthOk(watch.elapsedMilliseconds);
    notifyListeners();
  }

  /// Drops every measurement so the next build re-probes.
  void invalidate() {
    _byNetworkId.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    if (_ownsProbe) _probe.close();
    super.dispose();
  }
}

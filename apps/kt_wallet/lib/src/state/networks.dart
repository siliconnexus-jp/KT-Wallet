import 'dart:convert';

import 'package:chains/chains.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Network model: a concrete instance of a protocol family.
///
/// [Chain] stays the protocol family (address format, serialization, signing
/// algorithm — identical between mainnet and testnets); a [Network] picks the
/// actual RPC endpoint, EVM chain id, and explorer for that family. Wallets,
/// derivation, and the airgap protocol are network-agnostic by design.
class Network {
  const Network({
    required this.id,
    required this.chain,
    required this.name,
    required this.rpcUrl,
    required this.symbol,
    this.evmChainId,
    this.explorerUrl,
    this.faucetUrl,
    this.isTestnet = false,
    this.builtin = false,
  });

  /// Stable identifier ('eth-mainnet', 'eth-sepolia', 'custom-' + millis).
  final String id;

  /// Protocol family — reuses every existing validator/serializer.
  final Chain chain;

  final String name;
  final String rpcUrl;

  /// Native symbol shown next to amounts. Testnets keep the family symbol
  /// (amounts are real, prices are not — fiat is suppressed on testnets).
  final String symbol;

  /// EVM signing-domain id; REQUIRED for EVM instances (Sepolia 11155111,
  /// Amoy 80002). Wrong-chain signatures are invalid, which is exactly the
  /// isolation we want.
  final int? evmChainId;

  final String? explorerUrl;

  /// Where to get test funds; testnet-only affordance in the receive screen.
  final String? faucetUrl;

  final bool isTestnet;

  /// Built-ins cannot be deleted; custom networks can.
  final bool builtin;

  Map<String, Object?> toJson() => {
        'id': id,
        'chain': chain.name,
        'name': name,
        'rpcUrl': rpcUrl,
        'symbol': symbol,
        if (evmChainId != null) 'evmChainId': evmChainId,
        if (explorerUrl != null) 'explorerUrl': explorerUrl,
        if (faucetUrl != null) 'faucetUrl': faucetUrl,
        'isTestnet': isTestnet,
      };

  static Network? fromJson(Map<String, Object?> m) {
    final chainName = m['chain'];
    final chain =
        Chain.values.where((c) => c.name == chainName).firstOrNull;
    final id = m['id'];
    final name = m['name'];
    final rpcUrl = m['rpcUrl'];
    final symbol = m['symbol'];
    if (chain == null ||
        id is! String ||
        name is! String ||
        rpcUrl is! String ||
        symbol is! String) {
      return null;
    }
    return Network(
      id: id,
      chain: chain,
      name: name,
      rpcUrl: rpcUrl,
      symbol: symbol,
      evmChainId: m['evmChainId'] as int?,
      explorerUrl: m['explorerUrl'] as String?,
      faucetUrl: m['faucetUrl'] as String?,
      isTestnet: m['isTestnet'] == true,
    );
  }
}

/// The two built-in environments.
enum NetworkEnvironment { mainnet, testnet }

// ---- built-in registry ------------------------------------------------------

const ethMainnet = Network(
  id: 'eth-mainnet',
  chain: Chain.ethereum,
  name: 'Ethereum',
  rpcUrl: 'https://eth.llamarpc.com',
  symbol: 'ETH',
  evmChainId: 1,
  explorerUrl: 'https://etherscan.io',
  builtin: true,
);

const ethSepolia = Network(
  id: 'eth-sepolia',
  chain: Chain.ethereum,
  name: 'Sepolia',
  rpcUrl: 'https://ethereum-sepolia-rpc.publicnode.com',
  symbol: 'ETH',
  evmChainId: 11155111,
  explorerUrl: 'https://sepolia.etherscan.io',
  faucetUrl: 'https://sepoliafaucet.com',
  isTestnet: true,
  builtin: true,
);

const polygonMainnet = Network(
  id: 'polygon-mainnet',
  chain: Chain.polygon,
  name: 'Polygon',
  rpcUrl: 'https://polygon-rpc.com',
  symbol: 'POL',
  evmChainId: 137,
  explorerUrl: 'https://polygonscan.com',
  builtin: true,
);

const polygonAmoy = Network(
  id: 'polygon-amoy',
  chain: Chain.polygon,
  name: 'Amoy',
  rpcUrl: 'https://rpc-amoy.polygon.technology',
  symbol: 'POL',
  evmChainId: 80002,
  explorerUrl: 'https://amoy.polygonscan.com',
  faucetUrl: 'https://faucet.polygon.technology',
  isTestnet: true,
  builtin: true,
);

const tronMainnet = Network(
  id: 'tron-mainnet',
  chain: Chain.tron,
  name: 'TRON',
  rpcUrl: 'https://api.trongrid.io',
  symbol: 'TRX',
  explorerUrl: 'https://tronscan.org',
  builtin: true,
);

const tronNile = Network(
  id: 'tron-nile',
  chain: Chain.tron,
  name: 'Nile',
  rpcUrl: 'https://nile.trongrid.io',
  symbol: 'TRX',
  explorerUrl: 'https://nile.tronscan.org',
  faucetUrl: 'https://nileex.io/join/getJoinPage',
  isTestnet: true,
  builtin: true,
);

const solanaMainnet = Network(
  id: 'sol-mainnet',
  chain: Chain.solana,
  name: 'Solana',
  rpcUrl: 'https://api.mainnet-beta.solana.com',
  symbol: 'SOL',
  explorerUrl: 'https://explorer.solana.com',
  builtin: true,
);

const solanaDevnet = Network(
  id: 'sol-devnet',
  chain: Chain.solana,
  name: 'Devnet',
  rpcUrl: 'https://api.devnet.solana.com',
  symbol: 'SOL',
  explorerUrl: 'https://explorer.solana.com?cluster=devnet',
  // Devnet's faucet is the RPC requestAirdrop call itself — the receive
  // screen offers a one-tap airdrop instead of an external link.
  isTestnet: true,
  builtin: true,
);

const builtinNetworks = [
  ethMainnet,
  ethSepolia,
  polygonMainnet,
  polygonAmoy,
  tronMainnet,
  tronNile,
  solanaMainnet,
  solanaDevnet,
];

const _mainnetProfile = {
  Chain.ethereum: 'eth-mainnet',
  Chain.polygon: 'polygon-mainnet',
  Chain.tron: 'tron-mainnet',
  Chain.solana: 'sol-mainnet',
};

const _testnetProfile = {
  Chain.ethereum: 'eth-sepolia',
  Chain.polygon: 'polygon-amoy',
  Chain.tron: 'tron-nile',
  Chain.solana: 'sol-devnet',
};

// ---- controller -------------------------------------------------------------

/// Active-network state: the environment switch (mainnet/testnet), optional
/// per-chain overrides, and user-added custom networks. Persisted via
/// shared_preferences with the same defensive style as the other controllers
/// (silently in-memory when the plugin is unavailable, e.g. widget tests).
class NetworkController extends ChangeNotifier {
  NetworkController({
    NetworkEnvironment initialEnvironment = NetworkEnvironment.mainnet,
  }) : _environment = initialEnvironment;

  static const _keyEnvironment = 'network.environment';
  static const _keyOverrides = 'network.overrides'; // JSON {chainName: networkId}
  static const _keyCustom = 'network.custom'; // JSON list of Network.toJson

  NetworkEnvironment _environment;
  final Map<Chain, String> _overrides = {};
  final List<Network> _custom = [];

  NetworkEnvironment get environment => _environment;
  List<Network> get customNetworks => List.unmodifiable(_custom);

  /// All known networks (built-in + custom).
  List<Network> get allNetworks => [...builtinNetworks, ..._custom];

  /// Networks selectable for [chain].
  List<Network> networksFor(Chain chain) =>
      allNetworks.where((n) => n.chain == chain).toList();

  Network? byId(String id) =>
      allNetworks.where((n) => n.id == id).firstOrNull;

  /// The active instance for [chain]: per-chain override first, else the
  /// environment profile. Falls back to mainnet if an override points at a
  /// deleted custom network.
  Network activeFor(Chain chain) {
    final overrideId = _overrides[chain];
    if (overrideId != null) {
      final n = byId(overrideId);
      if (n != null) return n;
    }
    final profile = _environment == NetworkEnvironment.testnet
        ? _testnetProfile
        : _mainnetProfile;
    return byId(profile[chain]!)!;
  }

  /// True when ANY active chain instance is a testnet (drives the app-wide
  /// amber badge and fiat suppression).
  bool get anyTestnetActive =>
      Chain.values.any((c) => activeFor(c).isTestnet);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final env = prefs.getString(_keyEnvironment);
      if (env == NetworkEnvironment.testnet.name) {
        _environment = NetworkEnvironment.testnet;
      }
      final custom = prefs.getString(_keyCustom);
      if (custom != null && custom.isNotEmpty) {
        final list = json.decode(custom);
        if (list is List) {
          _custom
            ..clear()
            ..addAll(list
                .whereType<Map<String, Object?>>()
                .map(Network.fromJson)
                .whereType<Network>());
        }
      }
      final overrides = prefs.getString(_keyOverrides);
      if (overrides != null && overrides.isNotEmpty) {
        final m = json.decode(overrides);
        if (m is Map) {
          m.forEach((k, v) {
            final chain =
                Chain.values.where((c) => c.name == k).firstOrNull;
            if (chain != null && v is String) _overrides[chain] = v;
          });
        }
      }
      notifyListeners();
    } catch (_) {
      // No prefs plugin (tests) or corrupt data: stay on defaults.
    }
  }

  Future<void> setEnvironment(NetworkEnvironment env) async {
    if (env == _environment) return;
    _environment = env;
    // An explicit environment switch clears per-chain overrides — the user
    // asked for "everything mainnet/testnet", stale pins would betray that.
    _overrides.clear();
    notifyListeners();
    await _persist();
  }

  Future<void> setOverride(Chain chain, String? networkId) async {
    if (networkId == null) {
      _overrides.remove(chain);
    } else {
      _overrides[chain] = networkId;
    }
    notifyListeners();
    await _persist();
  }

  Future<Network> addCustom({
    required Chain chain,
    required String name,
    required String rpcUrl,
    required String symbol,
    int? evmChainId,
    String? explorerUrl,
    bool isTestnet = true,
  }) async {
    final network = Network(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      chain: chain,
      name: name,
      rpcUrl: rpcUrl,
      symbol: symbol,
      evmChainId: evmChainId,
      explorerUrl: explorerUrl,
      isTestnet: isTestnet,
    );
    _custom.add(network);
    notifyListeners();
    await _persist();
    return network;
  }

  Future<void> removeCustom(String id) async {
    _custom.removeWhere((n) => n.id == id && !n.builtin);
    _overrides.removeWhere((_, v) => v == id);
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyEnvironment, _environment.name);
      await prefs.setString(
          _keyCustom, json.encode([for (final n in _custom) n.toJson()]));
      await prefs.setString(_keyOverrides,
          json.encode({for (final e in _overrides.entries) e.key.name: e.value}));
    } catch (_) {
      // Best-effort; in-memory state still applies.
    }
  }
}

/// Exposes the app-wide [NetworkController]; absent scope (gallery/goldens)
/// falls back to a shared mainnet-default controller so every screen renders
/// exactly as before this feature existed.
class NetworkScope extends InheritedNotifier<NetworkController> {
  const NetworkScope(
      {super.key, required NetworkController controller, required super.child})
      : super(notifier: controller);

  static NetworkController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<NetworkScope>();
    return scope?.notifier ?? _fallback;
  }

  static NetworkController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NetworkScope>()?.notifier;

  static final NetworkController _fallback = NetworkController();
}

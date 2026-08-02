import 'dart:convert';

import 'package:chains/chains.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'endpoint_policy.dart';

bool _isEvmChain(Chain chain) => chain != Chain.tron && chain != Chain.solana;

bool _isValidNetworkIdentity(Chain chain, String? value) {
  if (_isEvmChain(chain)) return true;
  if (value == null) return false;
  final identity = value.trim();
  return switch (chain) {
    Chain.tron => RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(identity),
    Chain.solana => RegExp(r'^[1-9A-HJ-NP-Za-km-z]{32,44}$').hasMatch(identity),
    _ => true,
  };
}

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
    this.networkIdentity,
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

  /// Pinned non-EVM network identity.
  ///
  /// Solana uses `getGenesisHash`; TRON uses block 0's `blockID`. Built-ins
  /// carry audited constants and custom networks persist the value returned by
  /// their successful add-network probe. Transfers re-check this value before
  /// any key operation, so changing an RPC URL behind the same preference
  /// cannot silently move a transaction onto another network.
  final String? networkIdentity;

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
    if (networkIdentity != null) 'networkIdentity': networkIdentity,
    if (explorerUrl != null) 'explorerUrl': explorerUrl,
    if (faucetUrl != null) 'faucetUrl': faucetUrl,
    'isTestnet': isTestnet,
  };

  static Network? fromJson(Map<String, Object?> m) {
    final chainName = m['chain'];
    final chain = Chain.values.where((c) => c.name == chainName).firstOrNull;
    final id = m['id'];
    final name = m['name'];
    final rpcUrl = m['rpcUrl'];
    final symbol = m['symbol'];
    final evmChainId = m['evmChainId'];
    final networkIdentity = m['networkIdentity'];
    if (chain == null ||
        id is! String ||
        name is! String ||
        rpcUrl is! String ||
        symbol is! String ||
        id.isEmpty ||
        name.trim().isEmpty ||
        symbol.trim().isEmpty ||
        !EndpointPolicy.isSafeUrl(rpcUrl) ||
        (evmChainId != null && evmChainId is! int) ||
        (networkIdentity != null && networkIdentity is! String) ||
        (_isEvmChain(chain) && (evmChainId is! int || evmChainId <= 0)) ||
        (!_isEvmChain(chain) &&
            (networkIdentity is! String ||
                !_isValidNetworkIdentity(chain, networkIdentity)))) {
      return null;
    }
    final explorerUrl = m['explorerUrl'];
    if (explorerUrl != null &&
        (explorerUrl is! String || !EndpointPolicy.isSafeUrl(explorerUrl))) {
      return null;
    }
    final faucetUrl = m['faucetUrl'];
    if (faucetUrl != null &&
        (faucetUrl is! String || !EndpointPolicy.isSafeUrl(faucetUrl))) {
      return null;
    }
    return Network(
      id: id,
      chain: chain,
      name: name,
      rpcUrl: rpcUrl,
      symbol: symbol,
      evmChainId: evmChainId as int?,
      networkIdentity: networkIdentity as String?,
      explorerUrl: explorerUrl as String?,
      faucetUrl: faucetUrl as String?,
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
  rpcUrl: 'https://ethereum-rpc.publicnode.com',
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
  rpcUrl: 'https://polygon-bor-rpc.publicnode.com',
  symbol: 'POL',
  evmChainId: 137,
  explorerUrl: 'https://polygonscan.com',
  builtin: true,
);

const polygonAmoy = Network(
  id: 'polygon-amoy',
  chain: Chain.polygon,
  name: 'Amoy',
  rpcUrl: 'https://polygon-amoy-bor-rpc.publicnode.com',
  symbol: 'POL',
  evmChainId: 80002,
  explorerUrl: 'https://amoy.polygonscan.com',
  faucetUrl: 'https://faucet.polygon.technology',
  isTestnet: true,
  builtin: true,
);

const baseMainnet = Network(
  id: 'base-mainnet',
  chain: Chain.base,
  name: 'Base',
  rpcUrl: 'https://mainnet.base.org',
  symbol: 'ETH',
  evmChainId: 8453,
  explorerUrl: 'https://basescan.org',
  builtin: true,
);

const baseSepolia = Network(
  id: 'base-sepolia',
  chain: Chain.base,
  name: 'Base Sepolia',
  rpcUrl: 'https://sepolia.base.org',
  symbol: 'ETH',
  evmChainId: 84532,
  explorerUrl: 'https://sepolia.basescan.org',
  faucetUrl: 'https://docs.base.org/base-chain/tools/network-faucets',
  isTestnet: true,
  builtin: true,
);

const arbitrumMainnet = Network(
  id: 'arbitrum-mainnet',
  chain: Chain.arbitrum,
  name: 'Arbitrum One',
  rpcUrl: 'https://arb1.arbitrum.io/rpc',
  symbol: 'ETH',
  evmChainId: 42161,
  explorerUrl: 'https://arbiscan.io',
  builtin: true,
);

const arbitrumSepolia = Network(
  id: 'arbitrum-sepolia',
  chain: Chain.arbitrum,
  name: 'Arbitrum Sepolia',
  rpcUrl: 'https://sepolia-rollup.arbitrum.io/rpc',
  symbol: 'ETH',
  evmChainId: 421614,
  explorerUrl: 'https://sepolia.arbiscan.io',
  faucetUrl: 'https://faucet.quicknode.com/arbitrum/sepolia',
  isTestnet: true,
  builtin: true,
);

const avalancheMainnet = Network(
  id: 'avalanche-mainnet',
  chain: Chain.avalanche,
  name: 'Avalanche C-Chain',
  rpcUrl: 'https://api.avax.network/ext/bc/C/rpc',
  symbol: 'AVAX',
  evmChainId: 43114,
  explorerUrl: 'https://snowtrace.io',
  builtin: true,
);

const avalancheFuji = Network(
  id: 'avalanche-fuji',
  chain: Chain.avalanche,
  name: 'Avalanche Fuji',
  rpcUrl: 'https://api.avax-test.network/ext/bc/C/rpc',
  symbol: 'AVAX',
  evmChainId: 43113,
  explorerUrl: 'https://testnet.snowtrace.io',
  faucetUrl: 'https://core.app/tools/testnet-faucet',
  isTestnet: true,
  builtin: true,
);

const bnbMainnet = Network(
  id: 'bnb-mainnet',
  chain: Chain.bnb,
  name: 'BNB Smart Chain',
  rpcUrl: 'https://bsc-dataseed.bnbchain.org',
  symbol: 'BNB',
  evmChainId: 56,
  explorerUrl: 'https://bscscan.com',
  builtin: true,
);

const bnbTestnet = Network(
  id: 'bnb-testnet',
  chain: Chain.bnb,
  name: 'BNB Smart Chain Testnet',
  rpcUrl: 'https://bsc-testnet-dataseed.bnbchain.org',
  symbol: 'BNB',
  evmChainId: 97,
  explorerUrl: 'https://testnet.bscscan.com',
  faucetUrl: 'https://www.bnbchain.org/en/testnet-faucet',
  isTestnet: true,
  builtin: true,
);

const tronMainnet = Network(
  id: 'tron-mainnet',
  chain: Chain.tron,
  name: 'TRON',
  rpcUrl: 'https://api.trongrid.io',
  symbol: 'TRX',
  networkIdentity:
      '00000000000000001ebf88508a03865c71d452e25f4d51194196a1d22b6653dc',
  explorerUrl: 'https://tronscan.org',
  builtin: true,
);

const tronNile = Network(
  id: 'tron-nile',
  chain: Chain.tron,
  name: 'Nile',
  rpcUrl: 'https://nile.trongrid.io',
  symbol: 'TRX',
  networkIdentity:
      '0000000000000000d698d4192c56cb6be724a558448e2684802de4d6cd8690dc',
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
  networkIdentity: '5eykt4UsFv8P8NJdTREpY1vzqKqZKvdpKuc147dw2N9d',
  explorerUrl: 'https://explorer.solana.com',
  builtin: true,
);

const solanaDevnet = Network(
  id: 'sol-devnet',
  chain: Chain.solana,
  name: 'Devnet',
  rpcUrl: 'https://api.devnet.solana.com',
  symbol: 'SOL',
  networkIdentity: 'EtWTRABZaYq6iMfeYKouRu166VU2xqa1wcaWoxPkrZBG',
  explorerUrl: 'https://explorer.solana.com?cluster=devnet',
  faucetUrl: 'https://faucet.solana.com',
  isTestnet: true,
  builtin: true,
);

const builtinNetworks = [
  ethMainnet,
  ethSepolia,
  polygonMainnet,
  polygonAmoy,
  baseMainnet,
  baseSepolia,
  arbitrumMainnet,
  arbitrumSepolia,
  avalancheMainnet,
  avalancheFuji,
  bnbMainnet,
  bnbTestnet,
  tronMainnet,
  tronNile,
  solanaMainnet,
  solanaDevnet,
];

const _mainnetProfile = {
  Chain.ethereum: 'eth-mainnet',
  Chain.polygon: 'polygon-mainnet',
  Chain.base: 'base-mainnet',
  Chain.arbitrum: 'arbitrum-mainnet',
  Chain.avalanche: 'avalanche-mainnet',
  Chain.bnb: 'bnb-mainnet',
  Chain.tron: 'tron-mainnet',
  Chain.solana: 'sol-mainnet',
};

const _testnetProfile = {
  Chain.ethereum: 'eth-sepolia',
  Chain.polygon: 'polygon-amoy',
  Chain.base: 'base-sepolia',
  Chain.arbitrum: 'arbitrum-sepolia',
  Chain.avalanche: 'avalanche-fuji',
  Chain.bnb: 'bnb-testnet',
  Chain.tron: 'tron-nile',
  Chain.solana: 'sol-devnet',
};

// ---- controller -------------------------------------------------------------

/// Active-network state: the environment switch (mainnet/testnet), optional
/// per-chain overrides, and user-added custom networks. Persisted via
/// one versioned SharedPreferences snapshot. Mutations are serialized and
/// commit-before-publish: a failed write cannot silently change the chain or
/// RPC domain used by the running app.
class NetworkController extends ChangeNotifier {
  NetworkController({
    NetworkEnvironment initialEnvironment = NetworkEnvironment.mainnet,
    Future<SharedPreferences> Function()? preferencesProvider,
  }) : _environment = initialEnvironment,
       _preferencesProvider =
           preferencesProvider ?? SharedPreferences.getInstance;

  static const snapshotKey = 'network.snapshot.v1';
  static const _keyEnvironment = 'network.environment';
  static const _keyOverrides =
      'network.overrides'; // JSON {chainName: networkId}
  static const _keyCustom = 'network.custom'; // JSON list of Network.toJson

  final Future<SharedPreferences> Function() _preferencesProvider;
  Future<void> _writes = Future<void>.value();
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

  Network? byId(String id) => allNetworks.where((n) => n.id == id).firstOrNull;

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
  bool get anyTestnetActive => Chain.values.any((c) => activeFor(c).isTestnet);

  Future<void> load() => _queueMutation(_load);

  Future<void> _load() async {
    try {
      final prefs = await _preferencesProvider();
      final hasSnapshot = prefs.containsKey(snapshotKey);
      final snapshot = _decodeMap(prefs.getString(snapshotKey));
      final legacy = !hasSnapshot;

      // Once a snapshot key exists, a corrupt or unsupported snapshot must
      // never fall back to stale legacy keys. Keep the initial safe profile.
      final envName =
          snapshot?['environment'] ??
          (legacy ? prefs.getString(_keyEnvironment) : null);
      final nextEnvironment = envName == NetworkEnvironment.testnet.name
          ? NetworkEnvironment.testnet
          : envName == NetworkEnvironment.mainnet.name
          ? NetworkEnvironment.mainnet
          : _environment;

      final customValue =
          snapshot?['custom'] ??
          (legacy ? _decodeJson(prefs.getString(_keyCustom)) : null);
      final nextCustom = <Network>[];
      if (customValue is List) {
        for (final value in customValue) {
          if (value is! Map) continue;
          final network = Network.fromJson(
            value.map((key, value) => MapEntry(key.toString(), value)),
          );
          if (network != null &&
              !builtinNetworks.any((item) => item.id == network.id) &&
              !nextCustom.any((item) => item.id == network.id)) {
            nextCustom.add(network);
          }
        }
      }

      final knownNetworks = [...builtinNetworks, ...nextCustom];
      final overrideValue =
          snapshot?['overrides'] ??
          (legacy ? _decodeJson(prefs.getString(_keyOverrides)) : null);
      final nextOverrides = <Chain, String>{};
      if (overrideValue is Map) {
        for (final entry in overrideValue.entries) {
          final chain = Chain.values
              .where((item) => item.name == entry.key)
              .firstOrNull;
          final id = entry.value;
          final network = id is String
              ? knownNetworks.where((item) => item.id == id).firstOrNull
              : null;
          if (chain != null && network?.chain == chain) {
            nextOverrides[chain] = id as String;
          }
        }
      }

      _environment = nextEnvironment;
      _custom
        ..clear()
        ..addAll(nextCustom);
      _overrides
        ..clear()
        ..addAll(nextOverrides);
      notifyListeners();

      // Migrate legacy three-key storage and sanitize invalid entries. This is
      // best-effort during read; all future mutations require a successful
      // snapshot write before they become visible.
      if (legacy) {
        try {
          await _persistSnapshot(
            environment: nextEnvironment,
            custom: nextCustom,
            overrides: nextOverrides,
          );
          await prefs.remove(_keyEnvironment);
          await prefs.remove(_keyCustom);
          await prefs.remove(_keyOverrides);
        } on Object {
          // The already-persisted legacy state remains authoritative.
        }
      }
    } catch (_) {
      // No prefs plugin (tests) or corrupt data: stay on defaults.
    }
  }

  Future<void> setEnvironment(NetworkEnvironment env) =>
      _queueMutation(() async {
        if (env == _environment && _overrides.isEmpty) return;
        // An explicit environment switch clears per-chain overrides — the user
        // asked for "everything mainnet/testnet", stale pins would betray that.
        await _persistSnapshot(
          environment: env,
          custom: _custom,
          overrides: const {},
        );
        _environment = env;
        _overrides.clear();
        notifyListeners();
      });

  Future<void> setOverride(Chain chain, String? networkId) =>
      _queueMutation(() async {
        if (networkId != null) {
          final network = byId(networkId);
          if (network == null || network.chain != chain) {
            throw ArgumentError.value(
              networkId,
              'networkId',
              'Network does not belong to ${chain.name}',
            );
          }
        }
        if (_overrides[chain] == networkId ||
            (networkId == null && !_overrides.containsKey(chain))) {
          return;
        }
        final nextOverrides = {..._overrides};
        if (networkId == null) {
          nextOverrides.remove(chain);
        } else {
          nextOverrides[chain] = networkId;
        }
        await _persistSnapshot(
          environment: _environment,
          custom: _custom,
          overrides: nextOverrides,
        );
        _overrides
          ..clear()
          ..addAll(nextOverrides);
        notifyListeners();
      });

  Future<Network> addCustom({
    required Chain chain,
    required String name,
    required String rpcUrl,
    required String symbol,
    int? evmChainId,
    String? networkIdentity,
    String? explorerUrl,
    bool isTestnet = true,
  }) => _queueMutation(() async {
    final normalizedName = name.trim();
    final normalizedSymbol = symbol.trim().toUpperCase();
    if (normalizedName.isEmpty || normalizedSymbol.isEmpty) {
      throw const FormatException('Network name and symbol are required');
    }
    final normalizedRpcUrl = EndpointPolicy.requireSafeUrl(rpcUrl);
    final normalizedExplorerUrl =
        explorerUrl == null || explorerUrl.trim().isEmpty
        ? null
        : EndpointPolicy.requireSafeUrl(explorerUrl);
    if (_isEvmChain(chain) && (evmChainId == null || evmChainId <= 0)) {
      throw const FormatException('A positive EVM chain id is required');
    }
    if (!_isValidNetworkIdentity(chain, networkIdentity)) {
      throw const FormatException('A valid network identity is required');
    }
    final network = Network(
      id: 'custom-${DateTime.now().microsecondsSinceEpoch}',
      chain: chain,
      name: normalizedName,
      rpcUrl: normalizedRpcUrl,
      symbol: normalizedSymbol,
      evmChainId: evmChainId,
      networkIdentity: networkIdentity,
      explorerUrl: normalizedExplorerUrl,
      isTestnet: isTestnet,
    );
    final nextCustom = [..._custom, network];
    await _persistSnapshot(
      environment: _environment,
      custom: nextCustom,
      overrides: _overrides,
    );
    _custom.add(network);
    notifyListeners();
    return network;
  });

  Future<void> removeCustom(String id) => _queueMutation(() async {
    final nextCustom = [
      for (final network in _custom)
        if (network.id != id || network.builtin) network,
    ];
    if (nextCustom.length == _custom.length) return;
    final nextOverrides = {..._overrides}
      ..removeWhere((_, value) => value == id);
    await _persistSnapshot(
      environment: _environment,
      custom: nextCustom,
      overrides: nextOverrides,
    );
    _custom
      ..clear()
      ..addAll(nextCustom);
    _overrides
      ..clear()
      ..addAll(nextOverrides);
    notifyListeners();
  });

  Future<void> _persistSnapshot({
    required NetworkEnvironment environment,
    required Iterable<Network> custom,
    required Map<Chain, String> overrides,
  }) async {
    final prefs = await _preferencesProvider();
    final stored = await prefs.setString(
      snapshotKey,
      json.encode({
        'version': 1,
        'environment': environment.name,
        'custom': [for (final network in custom) network.toJson()],
        'overrides': {
          for (final entry in overrides.entries) entry.key.name: entry.value,
        },
      }),
    );
    if (!stored) throw StateError('network preference write failed');
  }

  Future<T> _queueMutation<T>(Future<T> Function() operation) {
    final result = _writes.then((_) => operation());
    _writes = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  static Object? _decodeJson(String? source) {
    if (source == null || source.isEmpty) return null;
    try {
      return json.decode(source);
    } on FormatException {
      return null;
    }
  }

  static Map<String, Object?>? _decodeMap(String? source) {
    final value = _decodeJson(source);
    if (value is! Map || value['version'] != 1) return null;
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
}

/// Exposes the app-wide [NetworkController]; absent scope (gallery/goldens)
/// falls back to a shared mainnet-default controller so every screen renders
/// exactly as before this feature existed.
class NetworkScope extends InheritedNotifier<NetworkController> {
  const NetworkScope({
    super.key,
    required NetworkController controller,
    required super.child,
  }) : super(notifier: controller);

  static NetworkController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<NetworkScope>();
    return scope?.notifier ?? _fallback;
  }

  static NetworkController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<NetworkScope>()?.notifier;

  static final NetworkController _fallback = NetworkController();
}

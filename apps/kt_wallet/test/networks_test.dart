import 'dart:convert';

import 'package:chains/chains.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kt_wallet/src/state/networks.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Foundation of the multi-network model: environment profiles, per-chain
/// overrides, custom networks, and persistence round-trips.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('registry covers every chain in both environments', () {
    for (final chain in Chain.values) {
      final all = builtinNetworks.where((n) => n.chain == chain);
      expect(
        all.where((n) => !n.isTestnet),
        hasLength(1),
        reason: '$chain mainnet',
      );
      expect(
        all.where((n) => n.isTestnet),
        hasLength(1),
        reason: '$chain testnet',
      );
    }
    // EVM instances must carry a chain id (signing-domain isolation).
    for (final n in builtinNetworks.where(
      (n) => n.chain != Chain.tron && n.chain != Chain.solana,
    )) {
      expect(n.evmChainId, isNotNull, reason: n.id);
    }
    expect(ethSepolia.evmChainId, 11155111);
    expect(polygonAmoy.evmChainId, 80002);
    expect(bnbMainnet.evmChainId, 56);
    expect(bnbTestnet.evmChainId, 97);
  });

  test('built-in network display identities remain canonical', () {
    const expected = <String, ({String name, String symbol})>{
      'eth-mainnet': (name: 'Ethereum', symbol: 'ETH'),
      'eth-sepolia': (name: 'Sepolia', symbol: 'ETH'),
      'polygon-mainnet': (name: 'Polygon', symbol: 'POL'),
      'polygon-amoy': (name: 'Amoy', symbol: 'POL'),
      'base-mainnet': (name: 'Base', symbol: 'ETH'),
      'base-sepolia': (name: 'Base Sepolia', symbol: 'ETH'),
      'arbitrum-mainnet': (name: 'Arbitrum One', symbol: 'ETH'),
      'arbitrum-sepolia': (name: 'Arbitrum Sepolia', symbol: 'ETH'),
      'avalanche-mainnet': (name: 'Avalanche C-Chain', symbol: 'AVAX'),
      'avalanche-fuji': (name: 'Avalanche Fuji', symbol: 'AVAX'),
      'bnb-mainnet': (name: 'BNB Smart Chain', symbol: 'BNB'),
      'bnb-testnet': (name: 'BNB Smart Chain Testnet', symbol: 'BNB'),
      'tron-mainnet': (name: 'TRON', symbol: 'TRX'),
      'tron-nile': (name: 'Nile', symbol: 'TRX'),
      'sol-mainnet': (name: 'Solana', symbol: 'SOL'),
      'sol-devnet': (name: 'Devnet', symbol: 'SOL'),
    };

    expect({
      for (final network in builtinNetworks)
        network.id: (name: network.name, symbol: network.symbol),
    }, expected);
  });

  test('environment switch flips every chain and clears overrides', () async {
    final c = NetworkController();
    expect(c.activeFor(Chain.ethereum).id, 'eth-mainnet');
    expect(c.anyTestnetActive, isFalse);

    await c.setOverride(Chain.solana, 'sol-devnet');
    expect(c.activeFor(Chain.solana).id, 'sol-devnet');
    expect(c.anyTestnetActive, isTrue);

    await c.setEnvironment(NetworkEnvironment.testnet);
    expect(c.activeFor(Chain.ethereum).id, 'eth-sepolia');
    expect(c.activeFor(Chain.tron).id, 'tron-nile');
    // Overrides cleared by the explicit environment switch.
    expect(c.activeFor(Chain.solana).id, 'sol-devnet');
    expect(c.anyTestnetActive, isTrue);
  });

  test('custom network round-trips through persistence', () async {
    final c = NetworkController();
    final added = await c.addCustom(
      chain: Chain.ethereum,
      name: 'Local Anvil',
      rpcUrl: 'http://127.0.0.1:8545',
      symbol: 'ETH',
      evmChainId: 31337,
    );
    await c.setOverride(Chain.ethereum, added.id);
    await c.setEnvironment(NetworkEnvironment.testnet);
    await c.setOverride(Chain.ethereum, added.id);

    final reloaded = NetworkController();
    await reloaded.load();
    expect(reloaded.environment, NetworkEnvironment.testnet);
    expect(reloaded.customNetworks, hasLength(1));
    expect(reloaded.activeFor(Chain.ethereum).evmChainId, 31337);
  });

  test('removing a custom network drops overrides pointing at it', () async {
    final c = NetworkController();
    final added = await c.addCustom(
      chain: Chain.tron,
      name: 'Shasta',
      rpcUrl: 'https://api.shasta.trongrid.io',
      symbol: 'TRX',
      networkIdentity: tronNile.networkIdentity,
    );
    await c.setOverride(Chain.tron, added.id);
    expect(c.activeFor(Chain.tron).name, 'Shasta');

    await c.removeCustom(added.id);
    expect(
      c.activeFor(Chain.tron).id,
      'tron-mainnet',
      reason: 'fallback to profile',
    );
  });

  test('corrupt persisted JSON is ignored', () async {
    SharedPreferences.setMockInitialValues({
      'network.custom': '{not json',
      'network.overrides': '[]',
      'network.environment': 'testnet',
    });
    final c = NetworkController();
    await c.load();
    expect(c.environment, NetworkEnvironment.testnet);
    expect(c.customNetworks, isEmpty);
    expect(c.activeFor(Chain.ethereum).id, 'eth-sepolia');

    // After migration, a damaged versioned snapshot cannot resurrect stale
    // legacy network keys. It fails closed to the controller's initial profile.
    SharedPreferences.setMockInitialValues({
      NetworkController.snapshotKey: '{not json',
      'network.environment': 'testnet',
      'network.overrides': jsonEncode({'ethereum': 'eth-sepolia'}),
    });
    final damagedSnapshot = NetworkController();
    await damagedSnapshot.load();
    expect(damagedSnapshot.environment, NetworkEnvironment.mainnet);
    expect(damagedSnapshot.activeFor(Chain.ethereum), ethMainnet);
  });

  test(
    'unsafe custom endpoints and cross-chain overrides fail closed',
    () async {
      final c = NetworkController();

      await expectLater(
        c.addCustom(
          chain: Chain.ethereum,
          name: 'Unsafe',
          rpcUrl: 'http://public-rpc.example',
          symbol: 'ETH',
          evmChainId: 31337,
        ),
        throwsFormatException,
      );
      expect(c.customNetworks, isEmpty);

      await expectLater(
        c.setOverride(Chain.ethereum, 'sol-devnet'),
        throwsArgumentError,
      );
      await expectLater(
        c.addCustom(
          chain: Chain.tron,
          name: 'Unpinned TRON',
          rpcUrl: 'https://api.shasta.trongrid.io',
          symbol: 'TRX',
        ),
        throwsFormatException,
      );
      expect(
        Network.fromJson({
          'id': 'custom-bad-faucet',
          'chain': Chain.ethereum.name,
          'name': 'Bad faucet',
          'rpcUrl': 'https://rpc.example',
          'symbol': 'ETH',
          'evmChainId': 31337,
          'faucetUrl': 'javascript:alert(1)',
          'isTestnet': true,
        }),
        isNull,
      );
      expect(c.activeFor(Chain.ethereum), ethMainnet);
    },
  );

  test('load drops unsafe custom networks and invalid overrides', () async {
    final unsafe = Network(
      id: 'custom-unsafe',
      chain: Chain.ethereum,
      name: 'Unsafe',
      rpcUrl: 'http://public-rpc.example',
      symbol: 'ETH',
      evmChainId: 31337,
    );
    SharedPreferences.setMockInitialValues({
      'network.custom': jsonEncode([unsafe.toJson()]),
      'network.overrides': jsonEncode({'ethereum': 'sol-devnet'}),
    });

    final c = NetworkController();
    await c.load();
    expect(c.customNetworks, isEmpty);
    expect(c.activeFor(Chain.ethereum), ethMainnet);
  });

  test('network mutations commit before publish when storage fails', () async {
    var storageOffline = false;
    final c = NetworkController(
      preferencesProvider: () async {
        if (storageOffline) throw StateError('storage offline');
        return SharedPreferences.getInstance();
      },
    );
    final custom = await c.addCustom(
      chain: Chain.ethereum,
      name: 'Local Anvil',
      rpcUrl: 'http://127.0.0.1:8545',
      symbol: 'ETH',
      evmChainId: 31337,
    );
    expect(c.customNetworks, [custom]);

    storageOffline = true;
    var notified = 0;
    c.addListener(() => notified++);

    await expectLater(
      c.setEnvironment(NetworkEnvironment.testnet),
      throwsStateError,
    );
    await expectLater(
      c.setOverride(Chain.ethereum, custom.id),
      throwsStateError,
    );
    await expectLater(c.removeCustom(custom.id), throwsStateError);
    await expectLater(
      c.addCustom(
        chain: Chain.tron,
        name: 'Shasta',
        rpcUrl: 'https://api.shasta.trongrid.io',
        symbol: 'TRX',
        networkIdentity: tronNile.networkIdentity,
      ),
      throwsStateError,
    );

    expect(c.environment, NetworkEnvironment.mainnet);
    expect(c.activeFor(Chain.ethereum), ethMainnet);
    expect(c.customNetworks, [custom]);
    expect(notified, 0);
  });

  test(
    'rapid network changes are serialized and newest intent persists',
    () async {
      final c = NetworkController();

      await Future.wait([
        c.setEnvironment(NetworkEnvironment.testnet),
        c.setEnvironment(NetworkEnvironment.mainnet),
        c.setEnvironment(NetworkEnvironment.testnet),
      ]);
      expect(c.environment, NetworkEnvironment.testnet);

      final reloaded = NetworkController();
      await reloaded.load();
      expect(reloaded.environment, NetworkEnvironment.testnet);
    },
  );

  test('one versioned snapshot persists network state atomically', () async {
    final c = NetworkController();
    final custom = await c.addCustom(
      chain: Chain.ethereum,
      name: 'Local Anvil',
      rpcUrl: 'http://127.0.0.1:8545',
      symbol: 'ETH',
      evmChainId: 31337,
    );
    await c.setOverride(Chain.ethereum, custom.id);

    final store = await SharedPreferences.getInstance();
    final snapshot =
        jsonDecode(store.getString(NetworkController.snapshotKey)!)
            as Map<String, dynamic>;
    expect(snapshot['version'], 1);
    expect(snapshot['environment'], 'mainnet');
    expect(snapshot['custom'], hasLength(1));
    expect(snapshot['overrides'], {'ethereum': custom.id});
  });

  test(
    'network snapshot rejects ambiguity open schemas partial state and resource abuse',
    () async {
      final source = NetworkController();
      await source.addCustom(
        chain: Chain.ethereum,
        name: 'Reviewed custom network',
        rpcUrl: 'https://rpc.example',
        symbol: 'ETH',
        evmChainId: 31337,
      );
      final prefs = await SharedPreferences.getInstance();
      final valid = prefs.getString(NetworkController.snapshotKey)!;
      final decoded = jsonDecode(valid) as Map<String, dynamic>;
      final record = ((decoded['custom'] as List).single as Map)
          .cast<String, Object?>();

      String changed(void Function(Map<String, dynamic>) mutate) {
        final value = jsonDecode(valid) as Map<String, dynamic>;
        mutate(value);
        return jsonEncode(value);
      }

      final malformed = <String, String>{
        'duplicate environment': valid.replaceFirst(
          '"environment":"mainnet"',
          '"environment":"testnet","environment":"mainnet"',
        ),
        'escaped duplicate environment': valid.replaceFirst(
          '"environment":"mainnet"',
          '"environment":"testnet","envir\\u006fnment":"mainnet"',
        ),
        'unknown top-level member':
            '${valid.substring(0, valid.length - 1)},"memo":"ignored"}',
        'unknown custom member': changed((value) {
          final custom = ((value['custom'] as List).single as Map);
          custom['memo'] = 'ignored';
        }),
        'missing testnet classification': changed((value) {
          final custom = ((value['custom'] as List).single as Map);
          custom.remove('isTestnet');
        }),
        'non-boolean testnet classification': changed((value) {
          final custom = ((value['custom'] as List).single as Map);
          custom['isTestnet'] = 'true';
        }),
        'nested duplicate RPC URL': valid.replaceFirst(
          '"rpcUrl":"https://rpc.example"',
          '"rpcUrl":"https://evil.example","rpcUrl":"https://rpc.example"',
        ),
        'unknown override chain': changed((value) {
          value['overrides'] = {'unknown': record['id']};
        }),
        'one invalid record beside a valid record': changed((value) {
          value['custom'] = [
            record,
            <String, Object?>{
              ...record,
              'id': 'custom-invalid',
              'rpcUrl': 'http://public-rpc.example',
            },
          ];
        }),
        'too many custom networks': changed((value) {
          value['custom'] = [
            for (var i = 0; i < 65; i++)
              <String, Object?>{...record, 'id': 'custom-$i'},
          ];
        }),
        'unbounded snapshot text': changed((value) {
          final custom = ((value['custom'] as List).single as Map);
          custom['name'] = 'x' * 262144;
        }),
        'oversized EVM chain id': changed((value) {
          final custom = ((value['custom'] as List).single as Map);
          custom['evmChainId'] = 2147483648;
        }),
      };

      for (final entry in malformed.entries) {
        SharedPreferences.setMockInitialValues({
          NetworkController.snapshotKey: entry.value,
        });
        final loaded = NetworkController();
        await loaded.load();
        expect(
          loaded.environment,
          NetworkEnvironment.mainnet,
          reason: entry.key,
        );
        expect(loaded.customNetworks, isEmpty, reason: entry.key);
        expect(loaded.activeFor(Chain.ethereum), ethMainnet, reason: entry.key);
      }
    },
  );

  test(
    'custom network writes enforce the persisted resource contract',
    () async {
      final controller = NetworkController();
      Future<void> add({
        String name = 'Network',
        String rpcUrl = 'https://rpc.example',
        String symbol = 'ETH',
        int chainId = 31337,
      }) => controller.addCustom(
        chain: Chain.ethereum,
        name: name,
        rpcUrl: rpcUrl,
        symbol: symbol,
        evmChainId: chainId,
      );

      await expectLater(add(name: 'x' * 81), throwsFormatException);
      await expectLater(add(symbol: 'X' * 17), throwsFormatException);
      await expectLater(
        add(rpcUrl: 'https://example.com/${'x' * 2048}'),
        throwsFormatException,
      );
      await expectLater(add(chainId: 2147483648), throwsFormatException);
      expect(controller.customNetworks, isEmpty);

      for (var i = 0; i < 64; i++) {
        await add(name: 'Network $i');
      }
      await expectLater(add(name: 'Network 65'), throwsStateError);
      expect(controller.customNetworks, hasLength(64));
    },
  );
}

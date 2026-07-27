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
      (n) => n.chain == Chain.ethereum || n.chain == Chain.polygon,
    )) {
      expect(n.evmChainId, isNotNull, reason: n.id);
    }
    expect(ethSepolia.evmChainId, 11155111);
    expect(polygonAmoy.evmChainId, 80002);
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
  });
}

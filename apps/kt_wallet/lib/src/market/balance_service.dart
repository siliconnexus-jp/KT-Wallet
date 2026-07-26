import 'package:chains/chains.dart' show Amount;
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;

import '../rpc/http_transport.dart';
import 'gateway_client.dart';

/// Default public mainnet endpoints (no API keys). Overridable per instance
/// for tests or self-hosted nodes.
const String defaultEthRpcUrl = 'https://ethereum-rpc.publicnode.com';
const String defaultPolygonRpcUrl = 'https://polygon-bor-rpc.publicnode.com';
const String defaultBaseRpcUrl = 'https://mainnet.base.org';
const String defaultArbitrumRpcUrl = 'https://arb1.arbitrum.io/rpc';
const String defaultAvalancheRpcUrl = 'https://api.avax.network/ext/bc/C/rpc';

/// TronGrid REST base URL — the [TronRpc] client speaks TronGrid's REST API
/// (`/v1/accounts/...`, `/wallet/...`), not JSON-RPC, so it takes the
/// [RestTransport].
const String defaultTronApiUrl = 'https://api.trongrid.io';
const String defaultSolanaRpcUrl = 'https://api.mainnet-beta.solana.com';

/// Resolves the endpoint (JSON-RPC URL, or REST base URL for TRON) to use for
/// one chain. Injected into the network services so the settings screen's
/// persisted overrides apply without the services knowing about preferences.
typedef RpcEndpointResolver = String Function(Coin coin);

/// The built-in default endpoint per chain — the resolver used when no
/// override source is wired up (tests, gallery).
String defaultRpcEndpointFor(Coin coin) => switch (coin) {
  Coin.eth => defaultEthRpcUrl,
  Coin.polygon => defaultPolygonRpcUrl,
  Coin.base => defaultBaseRpcUrl,
  Coin.arbitrum => defaultArbitrumRpcUrl,
  Coin.avalanche => defaultAvalancheRpcUrl,
  Coin.tron => defaultTronApiUrl,
  Coin.solana => defaultSolanaRpcUrl,
};

/// Per-chain fetch outcome. Chains are independent: one failing endpoint (or
/// one invalid address) never taints the others.
enum BalanceStatus { loading, ok, error, unsupported }

/// A native-coin balance for one chain, or the reason there isn't one.
/// [amount] is non-null iff [status] == [BalanceStatus.ok].
class BalanceResult {
  const BalanceResult.loading() : amount = null, status = BalanceStatus.loading;
  BalanceResult.ok(Amount this.amount) : status = BalanceStatus.ok;
  const BalanceResult.error() : amount = null, status = BalanceStatus.error;
  const BalanceResult.unsupported()
    : amount = null,
      status = BalanceStatus.unsupported;

  final Amount? amount;
  final BalanceStatus status;
}

/// Fetches live native balances for a wallet's [ChainAddresses] via the tested
/// `package:chains/rpc.dart` clients over injectable transports (production
/// defaults to the http-backed ones, which own the request timeouts).
///
/// HONESTY NOTE: today's demo wallets carry MockCoreCrypto-derived placeholder
/// addresses that are NOT valid on-chain addresses — nodes reject them (or the
/// request errors), which surfaces here as a graceful [BalanceStatus.error]
/// per chain, rendered as '--' in the UI. Real derived addresses arrive with
/// wallet-core; nothing here ever fabricates a "live" number.
class BalanceService {
  BalanceService({
    JsonRpcTransport? jsonRpcTransport,
    RestTransport? restTransport,
    RpcEndpointResolver? endpoints,
    GatewayResolver? gateway,
  }) : _jsonRpc = jsonRpcTransport ?? HttpJsonRpcTransport(),
       _rest = restTransport ?? HttpRestTransport(),
       _endpoints = endpoints ?? defaultRpcEndpointFor,
       _gateway = gateway ?? _noGateway;

  static GatewayClient? _noGateway() => null;

  final JsonRpcTransport _jsonRpc;
  final RestTransport _rest;

  /// Resolved on every fetch (not cached at construction) so a persisted
  /// override saved in settings applies from the very next refresh.
  final RpcEndpointResolver _endpoints;

  /// Optional gateway (null in direct mode), also resolved on every fetch.
  final GatewayResolver _gateway;

  /// Native-unit decimals per chain (wei / wei / SUN / lamports).
  static const decimalsFor = {
    Coin.eth: 18,
    Coin.polygon: 18,
    Coin.base: 18,
    Coin.arbitrum: 18,
    Coin.avalanche: 18,
    Coin.tron: 6,
    Coin.solana: 9,
  };

  /// Native-coin display symbol per chain.
  static const symbolFor = {
    Coin.eth: 'ETH',
    Coin.polygon: 'POL',
    Coin.base: 'ETH',
    Coin.arbitrum: 'ETH',
    Coin.avalanche: 'AVAX',
    Coin.tron: 'TRX',
    Coin.solana: 'SOL',
  };

  /// Fetches all four chains concurrently. Never throws: every per-chain
  /// failure (RPC error, HTTP status, timeout, malformed body) collapses to
  /// [BalanceStatus.error] for that chain only.
  ///
  /// GATEWAY SEMANTICS (resilience over purity): with a gateway configured,
  /// each chain first asks the gateway (`kt_getBalances`, native only — the
  /// token registry goes through [TokenBalanceService]); a failing gateway
  /// call falls back to that chain's direct node path, so a broken/unreachable
  /// gateway degrades to exactly today's behavior instead of a dead screen.
  /// In direct mode (null resolver) the gateway is never contacted.
  Future<Map<Coin, BalanceResult>> fetchAll(ChainAddresses addresses) async {
    final eth = EvmRpc(url: _endpoints(Coin.eth), transport: _jsonRpc);
    final polygon = EvmRpc(url: _endpoints(Coin.polygon), transport: _jsonRpc);
    final base = EvmRpc(url: _endpoints(Coin.base), transport: _jsonRpc);
    final arbitrum = EvmRpc(
      url: _endpoints(Coin.arbitrum),
      transport: _jsonRpc,
    );
    final avalanche = EvmRpc(
      url: _endpoints(Coin.avalanche),
      transport: _jsonRpc,
    );
    final tron = TronRpc(baseUrl: _endpoints(Coin.tron), transport: _rest);
    final solana = SolanaRpc(url: _endpoints(Coin.solana), transport: _jsonRpc);

    final direct = {
      Coin.eth: () => eth.getBalance(addresses.eth),
      Coin.polygon: () => polygon.getBalance(addresses.polygon),
      Coin.base: () => base.getBalance(addresses.base),
      Coin.arbitrum: () => arbitrum.getBalance(addresses.arbitrum),
      Coin.avalanche: () => avalanche.getBalance(addresses.avalanche),
      Coin.tron: () => tron.getTrxBalance(addresses.tron),
      Coin.solana: () => solana.getBalance(addresses.solana),
    };
    final gateway = _gateway();
    final entries = await Future.wait([
      for (final coin in addresses.enabledCoins)
        _fetchChain(gateway, coin, addresses.forCoin(coin), direct[coin]!),
    ]);
    return {for (final (coin, result) in entries) coin: result};
  }

  Future<(Coin, BalanceResult)> _fetchChain(
    GatewayClient? gateway,
    Coin coin,
    String address,
    Future<BigInt> Function() direct,
  ) async {
    if (gateway != null) {
      try {
        final balances = await gateway.getBalances(
          chain: coin,
          address: address,
        );
        final native = balances.native;
        return (
          coin,
          BalanceResult.ok(
            Amount(
              raw: native.raw,
              decimals: native.decimals,
              symbol: native.symbol,
            ),
          ),
        );
      } catch (_) {
        // GatewayException / transport failure / malformed answer: fall back
        // to this chain's direct node path below.
      }
    }
    return _guard(coin, direct);
  }

  Future<(Coin, BalanceResult)> _guard(
    Coin coin,
    Future<BigInt> Function() fetch,
  ) async {
    try {
      final raw = await fetch();
      return (
        coin,
        BalanceResult.ok(
          Amount(
            raw: raw,
            decimals: decimalsFor[coin]!,
            symbol: symbolFor[coin]!,
          ),
        ),
      );
    } catch (_) {
      // RpcException / TimeoutException / ClientException / FormatException /
      // AmountError — all mean "no trustworthy number", shown as '--'.
      return (coin, const BalanceResult.error());
    }
  }
}

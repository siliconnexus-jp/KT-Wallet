import 'package:chains/chains.dart' show Amount;
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;

import '../rpc/http_transport.dart';

/// Default public mainnet endpoints (no API keys). Overridable per instance
/// for tests or self-hosted nodes.
const String defaultEthRpcUrl = 'https://eth.llamarpc.com';
const String defaultPolygonRpcUrl = 'https://polygon-rpc.com';

/// TronGrid REST base URL — the [TronRpc] client speaks TronGrid's REST API
/// (`/v1/accounts/...`, `/wallet/...`), not JSON-RPC, so it takes the
/// [RestTransport].
const String defaultTronApiUrl = 'https://api.trongrid.io';
const String defaultSolanaRpcUrl = 'https://api.mainnet-beta.solana.com';

/// Per-chain fetch outcome. Chains are independent: one failing endpoint (or
/// one invalid address) never taints the others.
enum BalanceStatus { loading, ok, error, unsupported }

/// A native-coin balance for one chain, or the reason there isn't one.
/// [amount] is non-null iff [status] == [BalanceStatus.ok].
class BalanceResult {
  const BalanceResult.loading()
      : amount = null,
        status = BalanceStatus.loading;
  BalanceResult.ok(Amount this.amount) : status = BalanceStatus.ok;
  const BalanceResult.error()
      : amount = null,
        status = BalanceStatus.error;
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
    this.ethRpcUrl = defaultEthRpcUrl,
    this.polygonRpcUrl = defaultPolygonRpcUrl,
    this.tronApiUrl = defaultTronApiUrl,
    this.solanaRpcUrl = defaultSolanaRpcUrl,
  })  : _jsonRpc = jsonRpcTransport ?? HttpJsonRpcTransport(),
        _rest = restTransport ?? HttpRestTransport();

  final JsonRpcTransport _jsonRpc;
  final RestTransport _rest;
  final String ethRpcUrl;
  final String polygonRpcUrl;
  final String tronApiUrl;
  final String solanaRpcUrl;

  /// Native-unit decimals per chain (wei / wei / SUN / lamports).
  static const decimalsFor = {
    Coin.eth: 18,
    Coin.polygon: 18,
    Coin.tron: 6,
    Coin.solana: 9,
  };

  /// Native-coin display symbol per chain.
  static const symbolFor = {
    Coin.eth: 'ETH',
    Coin.polygon: 'POL',
    Coin.tron: 'TRX',
    Coin.solana: 'SOL',
  };

  /// Fetches all four chains concurrently. Never throws: every per-chain
  /// failure (RPC error, HTTP status, timeout, malformed body) collapses to
  /// [BalanceStatus.error] for that chain only.
  Future<Map<Coin, BalanceResult>> fetchAll(ChainAddresses addresses) async {
    final eth = EvmRpc(url: ethRpcUrl, transport: _jsonRpc);
    final polygon = EvmRpc(url: polygonRpcUrl, transport: _jsonRpc);
    final tron = TronRpc(baseUrl: tronApiUrl, transport: _rest);
    final solana = SolanaRpc(url: solanaRpcUrl, transport: _jsonRpc);

    final entries = await Future.wait([
      _guard(Coin.eth, () => eth.getBalance(addresses.eth)),
      _guard(Coin.polygon, () => polygon.getBalance(addresses.polygon)),
      _guard(Coin.tron, () => tron.getTrxBalance(addresses.tron)),
      _guard(Coin.solana, () => solana.getBalance(addresses.solana)),
    ]);
    return {for (final (coin, result) in entries) coin: result};
  }

  Future<(Coin, BalanceResult)> _guard(
      Coin coin, Future<BigInt> Function() fetch) async {
    try {
      final raw = await fetch();
      return (
        coin,
        BalanceResult.ok(Amount(
          raw: raw,
          decimals: decimalsFor[coin]!,
          symbol: symbolFor[coin]!,
        )),
      );
    } catch (_) {
      // RpcException / TimeoutException / ClientException / FormatException /
      // AmountError — all mean "no trustworthy number", shown as '--'.
      return (coin, const BalanceResult.error());
    }
  }
}

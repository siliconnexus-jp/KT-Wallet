import 'package:chains/chains.dart' show Amount;
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;

import '../rpc/http_transport.dart';
import 'balance_service.dart';
import 'gateway_client.dart';

/// One entry of the built-in token registry: a fungible token contract on one
/// of the supported chains. Pure data — display colors/glyphs live with the
/// UI (see `tokenRowMeta` in home_screen.dart).
class TokenInfo {
  const TokenInfo({
    required this.id,
    required this.symbol,
    required this.chain,
    required this.contract,
    required this.decimals,
    required this.network,
  });

  /// Stable registry id, used as the per-token result key.
  final String id;
  final String symbol;
  final Coin chain;

  /// 0x-hex for EVM chains, base58 ("T...") for TRON.
  final String contract;
  final int decimals;

  /// Display/filter label matching the network chips ('Ethereum', 'TRON', …).
  final String network;
}

// USDT on Ethereum mainnet — Tether's canonical ERC-20 contract, 6 decimals
// (https://etherscan.io/token/0xdAC17F958D2ee523a2206206994597C13D831ec7).
const usdtEthToken = TokenInfo(
  id: 'usdt-eth',
  symbol: 'USDT',
  chain: Coin.eth,
  contract: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
  decimals: 6,
  network: 'Ethereum',
);

/// ERC20Mock used as Test USDT on Sepolia by the real mobile E2E suite.
/// This is deliberately keyed only to `eth-sepolia`; it can never leak into
/// Ethereum mainnet balance queries.
const usdtSepoliaToken = TokenInfo(
  id: 'usdt-eth-sepolia',
  symbol: 'USDT',
  chain: Coin.eth,
  contract: '0xc4DCC311c028e341fd8602D8eB89c5de94625927',
  decimals: 18,
  network: 'Sepolia',
);

// USDC on Polygon PoS — Circle's NATIVE issuance (not the bridged USDC.e at
// 0x2791...), 6 decimals, per Circle's "USDC on Polygon PoS" contract list
// (https://developers.circle.com/stablecoins/usdc-on-main-networks).
const usdcPolygonToken = TokenInfo(
  id: 'usdc-polygon',
  symbol: 'USDC',
  chain: Coin.polygon,
  contract: '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359',
  decimals: 6,
  network: 'Polygon',
);

/// Circle's canonical USDC deployment on Polygon Amoy.
const usdcPolygonAmoyToken = TokenInfo(
  id: 'usdc-polygon-amoy',
  symbol: 'USDC',
  chain: Coin.polygon,
  contract: '0x41E94Eb019C0762f9Bfcf9Fb1E58725BfB0e7582',
  decimals: 6,
  network: 'Amoy',
);

const usdcBaseToken = TokenInfo(
  id: 'usdc-base',
  symbol: 'USDC',
  chain: Coin.base,
  contract: '0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913',
  decimals: 6,
  network: 'Base',
);

const usdcBaseSepoliaToken = TokenInfo(
  id: 'usdc-base-sepolia',
  symbol: 'USDC',
  chain: Coin.base,
  contract: '0x036CbD53842c5426634e7929541eC2318f3dCF7e',
  decimals: 6,
  network: 'Base Sepolia',
);

const usdcArbitrumToken = TokenInfo(
  id: 'usdc-arbitrum',
  symbol: 'USDC',
  chain: Coin.arbitrum,
  contract: '0xaf88d065e77c8cC2239327C5EDb3A432268e5831',
  decimals: 6,
  network: 'Arbitrum One',
);

const usdcArbitrumSepoliaToken = TokenInfo(
  id: 'usdc-arbitrum-sepolia',
  symbol: 'USDC',
  chain: Coin.arbitrum,
  contract: '0x75faf114eafb1BDbe2F0316DF893fd58CE46AA4d',
  decimals: 6,
  network: 'Arbitrum Sepolia',
);

const usdcAvalancheToken = TokenInfo(
  id: 'usdc-avalanche',
  symbol: 'USDC',
  chain: Coin.avalanche,
  contract: '0xB97EF9Ef8734C71904D8002F8b6Bc66Dd9c48a6E',
  decimals: 6,
  network: 'Avalanche C-Chain',
);

const usdcAvalancheFujiToken = TokenInfo(
  id: 'usdc-avalanche-fuji',
  symbol: 'USDC',
  chain: Coin.avalanche,
  contract: '0x5425890298aed601595a70AB815c96711a31Bc65',
  decimals: 6,
  network: 'Avalanche Fuji',
);

// USDT on TRON — Tether's canonical TRC-20 contract, 6 decimals
// (https://tronscan.org/#/token20/TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t).
const usdtTronToken = TokenInfo(
  id: 'usdt-tron',
  symbol: 'USDT',
  chain: Coin.tron,
  contract: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
  decimals: 6,
  network: 'TRON',
);

/// Nile faucet's test USDT deployment.
const usdtTronNileToken = TokenInfo(
  id: 'usdt-tron-nile',
  symbol: 'USDT',
  chain: Coin.tron,
  contract: 'TXYZopYRdj2D9XRtbG411XZZ3kM5VkAeBf',
  decimals: 6,
  network: 'Nile',
);

/// Circle's canonical USDC mint on Solana mainnet.
const usdcSolanaToken = TokenInfo(
  id: 'usdc-solana',
  symbol: 'USDC',
  chain: Coin.solana,
  contract: 'EPjFWdd5AufqSSqeM2q8puxyy5xY6Nn7C9nG4wEGGkZwyTDt1v',
  decimals: 6,
  network: 'Solana',
);

/// Circle's canonical USDC mint on Solana Devnet.
const usdcSolanaDevnetToken = TokenInfo(
  id: 'usdc-solana-devnet',
  symbol: 'USDC',
  chain: Coin.solana,
  contract: '4zMMC9srt5Ri5X14GAgXhaHii3GnPAEERYPJgZJDncDU',
  decimals: 6,
  network: 'Devnet',
);

/// Built-in token registry (V1: the three canonical stablecoin deployments;
/// user-added tokens stay display-only in the token-manage directory).
const builtinTokens = [usdtEthToken, usdcPolygonToken, usdtTronToken];

/// The built-in registry keyed by NETWORK id: these are MAINNET contract
/// deployments, so only the mainnet instances carry them — a testnet (or
/// custom) network has no built-in tokens and must never query these
/// contracts (same addresses on a testnet are a different, untrusted token
/// at best).
const builtinTokensByNetworkId = <String, List<TokenInfo>>{
  'eth-mainnet': [usdtEthToken],
  'eth-sepolia': [usdtSepoliaToken],
  'polygon-mainnet': [usdcPolygonToken],
  'polygon-amoy': [usdcPolygonAmoyToken],
  'base-mainnet': [usdcBaseToken],
  'base-sepolia': [usdcBaseSepoliaToken],
  'arbitrum-mainnet': [usdcArbitrumToken],
  'arbitrum-sepolia': [usdcArbitrumSepoliaToken],
  'avalanche-mainnet': [usdcAvalancheToken],
  'avalanche-fuji': [usdcAvalancheFujiToken],
  'tron-mainnet': [usdtTronToken],
  'tron-nile': [usdtTronNileToken],
  'sol-mainnet': [usdcSolanaToken],
  'sol-devnet': [usdcSolanaDevnetToken],
};

/// Resolves the token registry to fetch, re-evaluated on every fetch so a
/// network switch applies from the very next refresh.
typedef TokenRegistryResolver = List<TokenInfo> Function();

/// Fetches live token balances for the current wallet:
///
/// * ERC-20 on Ethereum/Polygon via `eth_call` with `balanceOf(address)`
///   calldata (the tested [EvmRpc.erc20Balance] helper in `chains/rpc`);
/// * TRC-20 via TronGrid's account endpoint (`/v1/accounts/{address}` → the
///   `trc20` array of `{contract: rawValue}` entries).
///
/// Same per-item honesty contract as [BalanceService]: one failing endpoint
/// (or the demo mock addresses being rejected on-chain) degrades only that
/// token to [BalanceStatus.error], rendered as '--' — never a made-up number.
/// An activated account with no balance record for the contract is a real
/// zero, not an error.
class TokenBalanceService {
  TokenBalanceService({
    JsonRpcTransport? jsonRpcTransport,
    RestTransport? restTransport,
    RpcEndpointResolver? endpoints,
    GatewayResolver? gateway,
    List<TokenInfo> tokens = builtinTokens,
    TokenRegistryResolver? registry,
  }) : _jsonRpc = jsonRpcTransport ?? HttpJsonRpcTransport(),
       _rest = restTransport ?? HttpRestTransport(),
       _endpoints = endpoints ?? defaultRpcEndpointFor,
       _gateway = gateway ?? _noGateway,
       _staticTokens = tokens,
       // ignore: prefer_initializing_formals
       _registry = registry;

  static GatewayClient? _noGateway() => null;

  final JsonRpcTransport _jsonRpc;
  final RestTransport _rest;
  final RpcEndpointResolver _endpoints;

  /// Optional gateway (null in direct mode), resolved on every fetch.
  final GatewayResolver _gateway;

  final List<TokenInfo> _staticTokens;

  /// Optional dynamic registry (network-aware wiring); wins over the static
  /// [tokens] list and is re-resolved on every fetch/read.
  final TokenRegistryResolver? _registry;

  /// The registry this instance fetches, in display order. With a [_registry]
  /// resolver wired this follows the active networks live; otherwise the
  /// static construction-time list (today's behavior).
  List<TokenInfo> get tokens => _registry?.call() ?? _staticTokens;

  /// Fetches every registry token concurrently. Never throws: each per-token
  /// failure collapses to [BalanceStatus.error] for that token only. Results
  /// are keyed by [TokenInfo.id].
  ///
  /// GATEWAY SEMANTICS (resilience over purity): with a gateway configured,
  /// the registry is grouped by chain and each chain issues ONE
  /// `kt_getBalances` call carrying its token entries; the gateway's
  /// per-token `error` rows map to [BalanceStatus.error] exactly like a
  /// failing direct call. If the gateway call itself fails, every token of
  /// that chain falls back to today's direct path — one broken gateway never
  /// costs more than the extra round trip. Direct mode never contacts it.
  Future<Map<String, BalanceResult>> fetchAll(ChainAddresses addresses) async {
    final gateway = _gateway();
    if (gateway != null) {
      final byChain = <Coin, List<TokenInfo>>{};
      for (final token in tokens) {
        byChain.putIfAbsent(token.chain, () => []).add(token);
      }
      final chainMaps = await Future.wait([
        for (final entry in byChain.entries)
          _gatewayChain(gateway, entry.key, entry.value, addresses),
      ]);
      return {for (final map in chainMaps) ...map};
    }
    final entries = await Future.wait([
      for (final token in tokens) _guard(token, addresses),
    ]);
    return {for (final (id, result) in entries) id: result};
  }

  /// One gateway `kt_getBalances` call for all of [chainTokens] (same chain);
  /// on any call-level failure, falls back to the direct path per token.
  Future<Map<String, BalanceResult>> _gatewayChain(
    GatewayClient gateway,
    Coin chain,
    List<TokenInfo> chainTokens,
    ChainAddresses addresses,
  ) async {
    try {
      final balances = await gateway.getBalances(
        chain: chain,
        address: addresses.forCoin(chain),
        tokens: [
          for (final token in chainTokens)
            GatewayTokenQuery(
              contract: token.contract,
              decimals: token.decimals,
              symbol: token.symbol,
            ),
        ],
      );
      final byContract = {for (final row in balances.tokens) row.contract: row};
      return {
        for (final token in chainTokens)
          token.id: _mapGatewayRow(token, byContract[token.contract]),
      };
    } catch (_) {
      // Gateway unreachable/erroring for this chain: direct fallback, same
      // per-token isolation as direct mode.
      final entries = await Future.wait([
        for (final token in chainTokens) _guard(token, addresses),
      ]);
      return {for (final (id, result) in entries) id: result};
    }
  }

  /// Missing row / per-token error / unparseable value → error for that token
  /// only; a parsed raw value is a real balance (registry decimals/symbol
  /// win for display consistency).
  BalanceResult _mapGatewayRow(TokenInfo token, GatewayTokenBalance? row) {
    final raw = row?.raw;
    if (row == null || row.error != null || raw == null) {
      return const BalanceResult.error();
    }
    try {
      return BalanceResult.ok(
        Amount(raw: raw, decimals: token.decimals, symbol: token.symbol),
      );
    } catch (_) {
      return const BalanceResult.error();
    }
  }

  Future<(String, BalanceResult)> _guard(
    TokenInfo token,
    ChainAddresses addresses,
  ) async {
    try {
      final raw = await _fetchRaw(token, addresses);
      return (
        token.id,
        BalanceResult.ok(
          Amount(raw: raw, decimals: token.decimals, symbol: token.symbol),
        ),
      );
    } on UnsupportedError {
      return (token.id, const BalanceResult.unsupported());
    } catch (_) {
      // RpcException / TimeoutException / FormatException / AmountError —
      // all mean "no trustworthy number", shown as '--'.
      return (token.id, const BalanceResult.error());
    }
  }

  Future<BigInt> _fetchRaw(TokenInfo token, ChainAddresses addresses) {
    switch (token.chain) {
      case Coin.eth:
      case Coin.polygon:
      case Coin.base:
      case Coin.arbitrum:
      case Coin.avalanche:
        final rpc = EvmRpc(url: _endpoints(token.chain), transport: _jsonRpc);
        return rpc.erc20Balance(token.contract, addresses.forCoin(token.chain));
      case Coin.tron:
        return _trc20Balance(token, addresses.tron);
      case Coin.solana:
        final rpc = SolanaRpc(
          url: _endpoints(token.chain),
          transport: _jsonRpc,
        );
        return rpc.getTokenBalance(addresses.solana, token.contract);
    }
  }

  /// TronGrid account response shape:
  /// `{data: [{balance: ..., trc20: [{"TR7...": "12345678"}, ...]}], ...}`.
  /// Empty `data` = unactivated account = zero; a `trc20` array without the
  /// contract = no balance record = zero; anything malformed throws (→ error).
  Future<BigInt> _trc20Balance(TokenInfo token, String address) async {
    final resp = await _rest.getJson(
      '${_endpoints(Coin.tron)}/v1/accounts/$address',
    );
    if (resp is! Map) throw const FormatException('bad account response');
    final data = resp['data'];
    if (data is! List) throw const FormatException('missing data list');
    if (data.isEmpty) return BigInt.zero; // unactivated account
    final account = data.first;
    if (account is! Map) throw const FormatException('bad account entry');
    final trc20 = account['trc20'];
    if (trc20 == null) return BigInt.zero; // no token balances at all
    if (trc20 is! List) throw const FormatException('bad trc20 list');
    for (final entry in trc20) {
      if (entry is Map && entry.containsKey(token.contract)) {
        final value = entry[token.contract];
        final raw = value is String ? BigInt.tryParse(value) : null;
        if (raw == null) throw const FormatException('non-numeric trc20 value');
        return raw;
      }
    }
    return BigInt.zero; // activated account, no record for this contract
  }
}

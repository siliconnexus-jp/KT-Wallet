import 'package:chains/chains.dart' show Amount;
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart' show ChainAddresses, Coin;

import '../rpc/http_transport.dart';
import 'balance_service.dart';

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

/// Built-in token registry (V1: the three canonical stablecoin deployments;
/// user-added tokens stay display-only in the token-manage directory).
const builtinTokens = [
  // USDT on Ethereum mainnet — Tether's canonical ERC-20 contract, 6 decimals
  // (https://etherscan.io/token/0xdAC17F958D2ee523a2206206994597C13D831ec7).
  TokenInfo(
    id: 'usdt-eth',
    symbol: 'USDT',
    chain: Coin.eth,
    contract: '0xdAC17F958D2ee523a2206206994597C13D831ec7',
    decimals: 6,
    network: 'Ethereum',
  ),
  // USDC on Polygon PoS — Circle's NATIVE issuance (not the bridged USDC.e at
  // 0x2791...), 6 decimals, per Circle's "USDC on Polygon PoS" contract list
  // (https://developers.circle.com/stablecoins/usdc-on-main-networks).
  TokenInfo(
    id: 'usdc-polygon',
    symbol: 'USDC',
    chain: Coin.polygon,
    contract: '0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359',
    decimals: 6,
    network: 'Polygon',
  ),
  // USDT on TRON — Tether's canonical TRC-20 contract, 6 decimals
  // (https://tronscan.org/#/token20/TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t).
  TokenInfo(
    id: 'usdt-tron',
    symbol: 'USDT',
    chain: Coin.tron,
    contract: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
    decimals: 6,
    network: 'TRON',
  ),
];

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
    this.tokens = builtinTokens,
  })  : _jsonRpc = jsonRpcTransport ?? HttpJsonRpcTransport(),
        _rest = restTransport ?? HttpRestTransport(),
        _endpoints = endpoints ?? defaultRpcEndpointFor;

  final JsonRpcTransport _jsonRpc;
  final RestTransport _rest;
  final RpcEndpointResolver _endpoints;

  /// The registry this instance fetches, in display order.
  final List<TokenInfo> tokens;

  /// Fetches every registry token concurrently. Never throws: each per-token
  /// failure collapses to [BalanceStatus.error] for that token only. Results
  /// are keyed by [TokenInfo.id].
  Future<Map<String, BalanceResult>> fetchAll(ChainAddresses addresses) async {
    final entries = await Future.wait(
        [for (final token in tokens) _guard(token, addresses)]);
    return {for (final (id, result) in entries) id: result};
  }

  Future<(String, BalanceResult)> _guard(
      TokenInfo token, ChainAddresses addresses) async {
    try {
      final raw = await _fetchRaw(token, addresses);
      return (
        token.id,
        BalanceResult.ok(Amount(
          raw: raw,
          decimals: token.decimals,
          symbol: token.symbol,
        )),
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
        final rpc = EvmRpc(url: _endpoints(token.chain), transport: _jsonRpc);
        return rpc.erc20Balance(token.contract, addresses.forCoin(token.chain));
      case Coin.tron:
        return _trc20Balance(token, addresses.tron);
      case Coin.solana:
        // No SPL entries in the built-in registry; decoding token accounts is
        // out of scope for this plumbing pass.
        throw UnsupportedError('SPL token balances not supported');
    }
  }

  /// TronGrid account response shape:
  /// `{data: [{balance: ..., trc20: [{"TR7...": "12345678"}, ...]}], ...}`.
  /// Empty `data` = unactivated account = zero; a `trc20` array without the
  /// contract = no balance record = zero; anything malformed throws (→ error).
  Future<BigInt> _trc20Balance(TokenInfo token, String address) async {
    final resp =
        await _rest.getJson('${_endpoints(Coin.tron)}/v1/accounts/$address');
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

import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart';

import '../market/balance_service.dart' show RpcEndpointResolver;
import '../market/gateway_client.dart';
import '../rpc/http_transport.dart';
import '../wallets/wallet_model.dart';
import 'airgap_codec.dart';
import 'broadcast_service.dart';
import 'chain_params_service.dart';
import 'transfer_draft.dart';

class LocalTransferException implements Exception {
  const LocalTransferException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Real hot-wallet path shared by the production auth sheet and integration
/// tests: fetch live EVM state, build the active network's unsigned envelope,
/// sign inside native Wallet Core, then broadcast exactly once.
class LocalTransferService {
  LocalTransferService({
    ChainParamsService? params,
    BroadcastService? broadcaster,
    RpcEndpointResolver? endpoints,
    GatewayResolver? gateway,
    JsonRpcTransport? jsonRpcTransport,
    RestTransport? restTransport,
  }) : _params =
           params ??
           ChainParamsService(
             endpoints: endpoints,
             gateway: gateway,
             jsonRpcTransport: jsonRpcTransport,
           ),
       _broadcaster =
           broadcaster ??
           BroadcastService(
             endpoints: endpoints,
             gateway: gateway,
             jsonRpcTransport: jsonRpcTransport,
             restTransport: restTransport,
           ),
       _endpoints = endpoints,
       _jsonRpc = jsonRpcTransport ?? HttpJsonRpcTransport(),
       _rest = restTransport ?? HttpRestTransport();

  final ChainParamsService _params;
  final BroadcastService _broadcaster;
  final RpcEndpointResolver? _endpoints;
  final JsonRpcTransport _jsonRpc;
  final RestTransport _rest;

  Future<String> execute({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required TransferDraft draft,
    required int evmChainId,
  }) async {
    final from = addressForChain(wallet.addresses, draft.chain);
    if (draft.chain == Chain.tron) {
      return _executeTron(
        wallet: wallet,
        crypto: crypto,
        draft: draft,
        from: from,
      );
    }
    if (draft.chain == Chain.solana) {
      return _executeSolana(
        wallet: wallet,
        crypto: crypto,
        draft: draft,
        from: from,
      );
    }
    final params = await _params.fetchEvmParams(draft.chain, from);
    final fees = params.tierFor(draft.feeTier);
    final unsigned = rawTxFor(
      draft,
      from: from,
      nonce: BigInt.from(params.nonce),
      maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
      maxFeePerGas: fees.maxFeePerGas,
      evmChainId: evmChainId,
    );
    final signed = await wallet.sign(
      crypto,
      coin: rpcCoinForChain(draft.chain),
      signingInput: unsigned,
    );
    final outcome = await _broadcaster.broadcast(draft.chain, signed.signedTx);
    if (outcome.status != BroadcastStatus.ok || outcome.txHash == null) {
      throw LocalTransferException(
        outcome.message ?? 'The network rejected the transaction',
      );
    }
    return outcome.txHash!;
  }

  String _endpoint(Coin coin) =>
      _endpoints?.call(coin) ??
      switch (coin) {
        Coin.tron => 'https://api.trongrid.io',
        Coin.solana => 'https://api.mainnet-beta.solana.com',
        _ => throw const LocalTransferException('Missing RPC endpoint'),
      };

  Future<String> _executeTron({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required TransferDraft draft,
    required String from,
  }) async {
    final rpc = TronRpc(baseUrl: _endpoint(Coin.tron), transport: _rest);
    final block = await rpc.getNowBlock();
    final blockId = _hexDecode(block.blockId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final intent = TransferIntent(
      chain: Chain.tron,
      operation: draft.operation,
      from: from,
      to: draft.recipient,
      amount: draft.amount,
      tokenContract: draft.tokenContract,
      tokenSymbol: draft.tokenContract == null ? null : draft.symbol,
    );
    final raw = TronRawTx.forTransfer(
      intent,
      refBlockBytes: Uint8List.fromList([
        (block.number >> 8) & 0xff,
        block.number & 0xff,
      ]),
      refBlockHash: Uint8List.sublistView(blockId, 8, 16),
      timestamp: now,
      expiration: now + const Duration(minutes: 10).inMilliseconds,
      feeLimit: draft.operation == TxOperation.tokenTransfer ? 100000000 : null,
    ).encodeRawData();
    final signed = await wallet.sign(
      crypto,
      coin: Coin.tron,
      signingInput: raw,
    );
    return _broadcast(Chain.tron, signed.signedTx);
  }

  Future<String> _executeSolana({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required TransferDraft draft,
    required String from,
  }) async {
    final rpc = SolanaRpc(url: _endpoint(Coin.solana), transport: _jsonRpc);
    final blockhash = await rpc.getLatestBlockhash();
    final SolanaMessage message;
    if (draft.operation == TxOperation.nativeTransfer) {
      message = SolanaMessage.systemTransfer(
        from: from,
        to: draft.recipient,
        lamports: draft.amount.raw,
        recentBlockhash: blockhash,
      );
    } else {
      final mint = draft.tokenContract;
      if (mint == null) {
        throw const LocalTransferException('Missing SPL token mint');
      }
      final sources = await rpc.getTokenAccounts(from, mint);
      final destinations = await rpc.getTokenAccounts(draft.recipient, mint);
      final source = sources
          .where((account) => account.amount >= draft.amount.raw)
          .firstOrNull;
      if (source == null) {
        throw const LocalTransferException(
          'No SPL token account has enough balance',
        );
      }
      if (destinations.isEmpty) {
        throw const LocalTransferException(
          'Recipient has no token account for this SPL mint',
        );
      }
      message = SolanaMessage.splTransfer(
        source: source.address,
        destination: destinations.first.address,
        owner: from,
        amount: draft.amount.raw,
        recentBlockhash: blockhash,
      );
    }
    final signed = await wallet.sign(
      crypto,
      coin: Coin.solana,
      signingInput: message.serialize(),
    );
    return _broadcast(Chain.solana, signed.signedTx);
  }

  Future<String> _broadcast(Chain chain, Uint8List signedTx) async {
    final outcome = await _broadcaster.broadcast(chain, signedTx);
    if (outcome.status != BroadcastStatus.ok || outcome.txHash == null) {
      throw LocalTransferException(
        outcome.message ?? 'The network rejected the transaction',
      );
    }
    return outcome.txHash!;
  }
}

Uint8List _hexDecode(String input) {
  if (input.length.isOdd) throw const FormatException('odd hex length');
  return Uint8List.fromList([
    for (var i = 0; i < input.length; i += 2)
      int.parse(input.substring(i, i + 2), radix: 16),
  ]);
}

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

class EvmNonceAlreadyConsumed extends LocalTransferException {
  const EvmNonceAlreadyConsumed({
    required this.nonce,
    required this.confirmedNonce,
  }) : super(
         'Nonce $nonce has already been consumed '
         '(confirmed nonce: $confirmedNonce)',
       );

  final int nonce;
  final int confirmedNonce;
}

/// An exact EIP-1559 envelope ready for native signing. Persist these fields
/// before signing/broadcasting so a restart can safely accelerate or cancel
/// the transaction with the same nonce.
class PreparedEvmTransfer {
  PreparedEvmTransfer({
    required this.chain,
    required this.coin,
    required this.from,
    required this.recipient,
    required this.amountRaw,
    required this.tokenContract,
    required this.nonce,
    required this.maxPriorityFeePerGas,
    required this.maxFeePerGas,
    required this.gasLimit,
    required Uint8List unsignedTx,
  }) : unsignedTx = Uint8List.fromList(unsignedTx);

  final Chain chain;
  final Coin coin;
  final String from;
  final String recipient;
  final BigInt amountRaw;
  final String? tokenContract;
  final BigInt nonce;
  final BigInt maxPriorityFeePerGas;
  final BigInt maxFeePerGas;
  final BigInt gasLimit;
  final Uint8List unsignedTx;

  BigInt get maximumFee => gasLimit * maxFeePerGas;
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
    final prepared = await prepareEvm(
      draft: draft,
      from: from,
      evmChainId: evmChainId,
    );
    return signAndBroadcastEvm(
      wallet: wallet,
      crypto: crypto,
      prepared: prepared,
    );
  }

  Future<PreparedEvmTransfer> prepareEvm({
    required TransferDraft draft,
    required String from,
    required int evmChainId,
  }) async {
    _requireEvm(draft.chain);
    final params = await _params.fetchEvmParams(draft.chain, from);
    final fees = params.tierFor(draft.feeTier);
    final tokenContract = draft.tokenContract;
    final calldata = tokenContract == null
        ? Uint8List(0)
        : Erc20.transferCalldata(to: draft.recipient, amount: draft.amount.raw);
    final gasLimit = await _params.estimateEvmGas(
      draft.chain,
      from: from,
      to: tokenContract ?? draft.recipient,
      value: tokenContract == null ? draft.amount.raw : BigInt.zero,
      data: '0x${_hexEncodeBytes(calldata)}',
    );
    final unsigned = rawTxFor(
      draft,
      from: from,
      nonce: BigInt.from(params.nonce),
      maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
      maxFeePerGas: fees.maxFeePerGas,
      gasLimit: gasLimit,
      evmChainId: evmChainId,
    );
    return PreparedEvmTransfer(
      chain: draft.chain,
      coin: rpcCoinForChain(draft.chain),
      from: from,
      recipient: draft.recipient,
      amountRaw: draft.amount.raw,
      tokenContract: tokenContract,
      nonce: BigInt.from(params.nonce),
      maxPriorityFeePerGas: fees.maxPriorityFeePerGas,
      maxFeePerGas: fees.maxFeePerGas,
      gasLimit: gasLimit,
      unsignedTx: unsigned,
    );
  }

  Future<String> signAndBroadcastEvm({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required PreparedEvmTransfer prepared,
  }) async {
    final signed = await wallet.sign(
      crypto,
      coin: prepared.coin,
      signingInput: prepared.unsignedTx,
    );
    return _broadcast(prepared.chain, signed.signedTx);
  }

  /// Rebuilds [original] with the same nonce and an EIP-1559 fee bump. A speed
  /// up preserves the original value/calldata byte-for-byte; cancellation sends
  /// zero native value back to the sender. No signing happens here, allowing
  /// the caller to reserve the replacement row atomically before native auth.
  Future<PreparedEvmTransfer> prepareEvmReplacement({
    required Chain chain,
    required int evmChainId,
    required String from,
    required String recipient,
    required BigInt amountRaw,
    required String? tokenContract,
    required BigInt nonce,
    required BigInt previousMaxPriorityFeePerGas,
    required BigInt previousMaxFeePerGas,
    required BigInt previousGasLimit,
    required bool cancel,
  }) async {
    _requireEvm(chain);
    final nonceState = await _params.fetchEvmNonceState(chain, from);
    if (nonceState.confirmed > nonce.toInt()) {
      throw EvmNonceAlreadyConsumed(
        nonce: nonce.toInt(),
        confirmedNonce: nonceState.confirmed,
      );
    }
    final live = await _params.fetchEvmParams(chain, from);
    final fast = live.fees.fast;
    final priority = _maxBigInt(
      _replacementBump(previousMaxPriorityFeePerGas),
      fast.maxPriorityFeePerGas,
    );
    var maxFee = _maxBigInt(
      _replacementBump(previousMaxFeePerGas),
      fast.maxFeePerGas,
    );
    if (maxFee < priority) maxFee = priority;

    final replacementRecipient = cancel ? from : recipient;
    final replacementContract = cancel ? null : tokenContract;
    final replacementAmount = cancel ? BigInt.zero : amountRaw;
    final calldata = replacementContract == null
        ? Uint8List(0)
        : Erc20.transferCalldata(
            to: replacementRecipient,
            amount: replacementAmount,
          );
    final gasLimit = cancel
        ? await _params.estimateEvmGas(
            chain,
            from: from,
            to: from,
            value: BigInt.zero,
            data: '0x',
          )
        : previousGasLimit;
    final tx = Eip1559Tx(
      chainId: BigInt.from(evmChainId),
      nonce: nonce,
      maxPriorityFeePerGas: priority,
      maxFeePerGas: maxFee,
      gasLimit: gasLimit,
      to: Eip1559Tx.addressBytes(replacementContract ?? replacementRecipient),
      value: replacementContract == null ? replacementAmount : BigInt.zero,
      data: calldata,
    );
    return PreparedEvmTransfer(
      chain: chain,
      coin: rpcCoinForChain(chain),
      from: from,
      recipient: replacementRecipient,
      amountRaw: replacementAmount,
      tokenContract: replacementContract,
      nonce: nonce,
      maxPriorityFeePerGas: priority,
      maxFeePerGas: maxFee,
      gasLimit: gasLimit,
      unsignedTx: tx.encodeUnsigned(),
    );
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
    int? feeLimit;
    if (draft.operation == TxOperation.tokenTransfer) {
      final calldata = Trc20.transferCalldata(
        to: draft.recipient,
        amount: draft.amount.raw,
      );
      final energy = await rpc.estimateTokenEnergy(
        owner: from,
        contract: draft.tokenContract!,
        parameter: _hexEncodeBytes(calldata.sublist(4)),
      );
      feeLimit = energy.feeLimitSun;
    }
    final raw = TronRawTx.forTransfer(
      intent,
      refBlockBytes: Uint8List.fromList([
        (block.number >> 8) & 0xff,
        block.number & 0xff,
      ]),
      refBlockHash: Uint8List.sublistView(blockId, 8, 16),
      timestamp: now,
      expiration: now + const Duration(minutes: 10).inMilliseconds,
      feeLimit: feeLimit,
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
      final tokenProgram = draft.tokenProgram ?? solanaTokenProgram;
      final createDestination = destinations.isEmpty;
      final destination = createDestination
          ? SolanaMessage.associatedTokenAddress(
              owner: draft.recipient,
              mint: mint,
              tokenProgram: tokenProgram,
            )
          : destinations.first.address;
      message = SolanaMessage.splTransferChecked(
        source: source.address,
        destination: destination,
        owner: from,
        recipientOwner: draft.recipient,
        mint: mint,
        amount: draft.amount.raw,
        decimals: draft.decimals,
        recentBlockhash: blockhash,
        tokenProgram: tokenProgram,
        createDestination: createDestination,
      );
    }
    final serialized = message.serialize();
    final fee = await rpc.getFeeForMessage(serialized);
    final solBalance = await rpc.getBalance(from);
    final nativeSpend = draft.operation == TxOperation.nativeTransfer
        ? draft.amount.raw
        : BigInt.zero;
    if (solBalance < nativeSpend + fee) {
      throw const LocalTransferException(
        'Insufficient SOL for the transfer and network fee',
      );
    }
    await rpc.simulateMessage(serialized);
    final signed = await wallet.sign(
      crypto,
      coin: Coin.solana,
      signingInput: serialized,
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

  static void _requireEvm(Chain chain) {
    if (chain == Chain.tron || chain == Chain.solana) {
      throw ArgumentError('not an EVM chain: $chain');
    }
  }
}

BigInt _replacementBump(BigInt value) {
  // 12.5%, rounded up, and always at least one wei higher. This clears the
  // common 10% replacement threshold without depending on floating point.
  final bumped = (value * BigInt.from(9) + BigInt.from(7)) ~/ BigInt.from(8);
  return bumped > value ? bumped : value + BigInt.one;
}

BigInt _maxBigInt(BigInt a, BigInt b) => a >= b ? a : b;

String _hexEncodeBytes(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List _hexDecode(String input) {
  if (input.length.isOdd) throw const FormatException('odd hex length');
  return Uint8List.fromList([
    for (var i = 0; i < input.length; i += 2)
      int.parse(input.substring(i, i + 2), radix: 16),
  ]);
}

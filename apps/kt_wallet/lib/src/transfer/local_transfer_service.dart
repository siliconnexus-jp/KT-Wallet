import 'dart:typed_data';

import 'package:chains/chains.dart';
import 'package:chains/rpc.dart';
import 'package:core_crypto/core_crypto.dart';

import '../market/balance_service.dart' show RpcEndpointResolver;
import '../market/gateway_client.dart';
import '../observability/experience_metrics.dart';
import '../rpc/http_transport.dart';
import '../wallets/wallet_model.dart';
import 'airgap_codec.dart';
import 'broadcast_service.dart';
import 'chain_params_service.dart';
import 'network_identity.dart';
import 'transfer_draft.dart';

class LocalTransferException implements Exception {
  const LocalTransferException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The node explicitly rejected a syntactically valid broadcast request.
class LocalTransferRejectedException extends LocalTransferException {
  LocalTransferRejectedException(this.kind)
    : super(publicRpcRejectionMessage(kind));

  final RpcRejectionKind kind;
}

/// A broadcast request began but no authoritative answer reached the app.
/// The signed transaction may already be on-chain and must not be re-sent.
class LocalTransferUncertainException extends LocalTransferException {
  const LocalTransferUncertainException(super.message);
}

/// This app cannot submit the signed payload on the selected network.
class LocalTransferUnsupportedException extends LocalTransferException {
  const LocalTransferUnsupportedException()
    : super('Broadcast is unsupported on this network');
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

class EvmPreflightFailed extends LocalTransferException {
  const EvmPreflightFailed(String reason)
    : super('Transaction simulation failed: $reason');
}

class TransferInsufficientFunds extends LocalTransferException {
  const TransferInsufficientFunds(this.asset)
    : super('Insufficient $asset balance for amount and maximum network fee');

  final String asset;
}

class EvmInsufficientFunds extends TransferInsufficientFunds {
  const EvmInsufficientFunds(super.asset);
}

class NonEvmTransferResult {
  const NonEvmTransferResult({
    required this.hash,
    this.referenceBlockHeight,
    this.expiresAt,
    this.lastValidBlockHeight,
  });

  final String hash;
  final int? referenceBlockHeight;
  final int? expiresAt;
  final int? lastValidBlockHeight;
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
    NetworkIdentityVerifier? identityVerifier,
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
       _rest = restTransport ?? HttpRestTransport(),
       _identity =
           identityVerifier ??
           (endpoints == null
               ? null
               : RpcNetworkIdentityVerifier(
                   jsonRpcTransport: jsonRpcTransport,
                   restTransport: restTransport,
                   endpoints: endpoints,
                   gateway: gateway,
                 ));

  final ChainParamsService _params;
  final BroadcastService _broadcaster;
  final RpcEndpointResolver? _endpoints;
  final JsonRpcTransport _jsonRpc;
  final RestTransport _rest;
  final NetworkIdentityVerifier? _identity;

  Future<String> execute({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required TransferDraft draft,
    required int evmChainId,
    String? expectedNetworkIdentity,
  }) async {
    final from = addressForChain(wallet.addresses, draft.chain);
    if (draft.chain == Chain.tron) {
      return (await _executeTron(
        wallet: wallet,
        crypto: crypto,
        draft: draft,
        from: from,
        expectedNetworkIdentity: expectedNetworkIdentity,
      )).hash;
    }
    if (draft.chain == Chain.solana) {
      return (await _executeSolana(
        wallet: wallet,
        crypto: crypto,
        draft: draft,
        from: from,
        expectedNetworkIdentity: expectedNetworkIdentity,
      )).hash;
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

  /// Executes a TRON or Solana transfer and returns the validity boundary
  /// paired with the exact raw transaction. Production callers persist this
  /// result together with the local Pending row.
  Future<NonEvmTransferResult> executeNonEvm({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required TransferDraft draft,
    String? expectedNetworkIdentity,
  }) {
    final from = addressForChain(wallet.addresses, draft.chain);
    return switch (draft.chain) {
      Chain.tron => _executeTron(
        wallet: wallet,
        crypto: crypto,
        draft: draft,
        from: from,
        expectedNetworkIdentity: expectedNetworkIdentity,
      ),
      Chain.solana => _executeSolana(
        wallet: wallet,
        crypto: crypto,
        draft: draft,
        from: from,
        expectedNetworkIdentity: expectedNetworkIdentity,
      ),
      _ => throw ArgumentError('executeNonEvm only supports TRON and Solana'),
    };
  }

  Future<PreparedEvmTransfer> prepareEvm({
    required TransferDraft draft,
    required String from,
    required int evmChainId,
  }) async {
    _requireEvm(draft.chain);
    await _identity?.verifyEvm(draft.chain, evmChainId);
    final params = await _params.fetchEvmParams(draft.chain, from);
    final fees = params.tierFor(draft.feeTier);
    final tokenContract = draft.tokenContract;
    final calldata = switch (draft.operation) {
      TxOperation.nativeTransfer => Uint8List(0),
      TxOperation.tokenTransfer => Erc20.transferCalldata(
        to: draft.recipient,
        amount: draft.amount.raw,
      ),
      TxOperation.approvalRevoke => Erc20.revokeApprovalCalldata(
        spender: draft.recipient,
      ),
    };
    final callTo = tokenContract ?? draft.recipient;
    final callValue = tokenContract == null ? draft.amount.raw : BigInt.zero;
    final callData = '0x${_hexEncodeBytes(calldata)}';
    EvmNonceState? nonceState;
    Future<EvmNonceState> verifiedEmptyPendingQueue() async {
      final state = nonceState ??= await _params.fetchEvmNonceState(
        draft.chain,
        from,
      );
      if (state.confirmed != state.pending || params.nonce != state.confirmed) {
        throw const EvmPreflightFailed(
          'Pending state unavailable while queued transactions exist',
        );
      }
      return state;
    }

    try {
      await _params.simulateEvmTransfer(
        draft.chain,
        from: from,
        to: callTo,
        value: callValue,
        data: callData,
        tokenTransfer: tokenContract != null,
      );
    } on RpcException catch (error) {
      if (!isEvmPendingStateUnavailable(error)) {
        throw EvmPreflightFailed(error.message);
      }
      try {
        // A few otherwise-valid EVM nodes expose pending nonce but not a
        // pending block state. Falling back to latest is safe only when this
        // same node proves there is no known queued nonce at all.
        await verifiedEmptyPendingQueue();
        await _params.simulateEvmTransfer(
          draft.chain,
          from: from,
          to: callTo,
          value: callValue,
          data: callData,
          tokenTransfer: tokenContract != null,
          blockTag: 'latest',
        );
      } on EvmPreflightFailed {
        rethrow;
      } on RpcException catch (latestError) {
        throw EvmPreflightFailed(latestError.message);
      }
    }
    late final BigInt gasLimit;
    late final EvmSpendableBalances balances;
    try {
      gasLimit = await _params.estimateEvmGas(
        draft.chain,
        from: from,
        to: callTo,
        value: callValue,
        data: callData,
      );
      balances = await _params.fetchEvmSpendableBalances(
        draft.chain,
        address: from,
        tokenContract: draft.operation == TxOperation.tokenTransfer
            ? tokenContract
            : null,
      );
    } on RpcException catch (error) {
      throw EvmPreflightFailed(error.message);
    }
    if (!balances.pendingAvailable) {
      try {
        await verifiedEmptyPendingQueue();
      } on RpcException catch (error) {
        throw EvmPreflightFailed(error.message);
      }
    }
    final maximumFee = gasLimit * fees.maxFeePerGas;
    if (balances.native < maximumFee + callValue) {
      throw EvmInsufficientFunds(switch (draft.chain) {
        Chain.polygon => 'POL',
        Chain.avalanche => 'AVAX',
        Chain.bnb => 'BNB',
        _ => 'ETH',
      });
    }
    if (draft.operation == TxOperation.tokenTransfer &&
        (balances.token == null || balances.token! < draft.amount.raw)) {
      throw EvmInsufficientFunds(draft.symbol);
    }
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
      evmChainId: evmChainId,
      coin: rpcCoinForChain(draft.chain),
      operation: draft.operation,
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
    final signed = await signPreparedEvm(
      wallet: wallet,
      crypto: crypto,
      prepared: prepared,
    );
    return broadcastSigned(
      prepared.chain,
      signed.signedTx,
      expectedTxHash: signed.txHash,
    );
  }

  /// Signs without broadcasting so callers can durably store the locally
  /// derived transaction hash before making the irreversible network call.
  Future<SignedTransaction> signPreparedEvm({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required PreparedEvmTransfer prepared,
  }) async {
    _requirePreparedSender(wallet, prepared.chain, prepared.from);
    return ExperienceMetrics.instance.measure(
      ExperienceMetricNames.transactionSign,
      () async {
        final signed = await wallet.sign(
          crypto,
          coin: prepared.coin,
          signingInput: prepared.unsignedTx,
        );
        return _verifyNativeSignedResult(
          chain: prepared.chain,
          unsignedTx: prepared.unsignedTx,
          claimedSigner: prepared.from,
          signed: signed,
        );
      },
    );
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
    TxOperation? operation,
    required BigInt nonce,
    required BigInt previousMaxPriorityFeePerGas,
    required BigInt previousMaxFeePerGas,
    required BigInt previousGasLimit,
    required bool cancel,
  }) async {
    _requireEvm(chain);
    await _identity?.verifyEvm(chain, evmChainId);
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
    final originalOperation =
        operation ??
        (tokenContract == null
            ? TxOperation.nativeTransfer
            : TxOperation.tokenTransfer);
    final replacementOperation = cancel
        ? TxOperation.nativeTransfer
        : originalOperation;
    final calldata = switch (replacementOperation) {
      TxOperation.nativeTransfer => Uint8List(0),
      TxOperation.tokenTransfer => Erc20.transferCalldata(
        to: replacementRecipient,
        amount: replacementAmount,
      ),
      TxOperation.approvalRevoke => Erc20.revokeApprovalCalldata(
        spender: replacementRecipient,
      ),
    };
    final callTo = replacementContract ?? replacementRecipient;
    final callValue = replacementContract == null
        ? replacementAmount
        : BigInt.zero;
    final callData = '0x${_hexEncodeBytes(calldata)}';
    try {
      await _params.simulateEvmTransfer(
        chain,
        from: from,
        to: callTo,
        value: callValue,
        data: callData,
        tokenTransfer: replacementContract != null,
        // A replacement competes with the pending candidate at the same
        // nonce. Simulating it after that candidate is semantically wrong and
        // unsupported by some nodes (notably Avalanche's pending block view).
        // Pending/latest balance checks below still cover queued liabilities.
        blockTag: 'latest',
      );
    } on RpcException catch (error) {
      throw EvmPreflightFailed(error.message);
    }
    final gasLimit = cancel
        ? await _params.estimateEvmGas(
            chain,
            from: from,
            to: from,
            value: BigInt.zero,
            data: '0x',
          )
        : previousGasLimit;
    late final EvmSpendableBalances balances;
    try {
      balances = await _params.fetchEvmSpendableBalances(chain, address: from);
    } on RpcException catch (error) {
      throw EvmPreflightFailed(error.message);
    }
    if (!balances.pendingAvailable && nonceState.confirmed != nonce.toInt()) {
      throw const EvmPreflightFailed(
        'Pending balance state unavailable for queued replacement',
      );
    }
    final replacementLiability =
        gasLimit * maxFee +
        (replacementContract == null ? replacementAmount : BigInt.zero);
    final originalLiability =
        previousGasLimit * previousMaxFeePerGas +
        (originalOperation == TxOperation.nativeTransfer
            ? amountRaw
            : BigInt.zero);
    final incrementalLiability = replacementLiability > originalLiability
        ? replacementLiability - originalLiability
        : BigInt.zero;
    // `latest` proves the account can fund the complete winning transaction;
    // `pending` proves it can fund the extra liability after the node applies
    // the original candidate. Nodes that explicitly lack a pending state may
    // use latest only when this is the current confirmed nonce, so there can
    // be no unknown lower-nonce liability ahead of the replacement.
    if (balances.nativeLatest < replacementLiability ||
        balances.native < incrementalLiability) {
      throw EvmInsufficientFunds(switch (chain) {
        Chain.polygon => 'POL',
        Chain.avalanche => 'AVAX',
        Chain.bnb => 'BNB',
        _ => 'ETH',
      });
    }
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
      evmChainId: evmChainId,
      coin: rpcCoinForChain(chain),
      operation: replacementOperation,
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

  Future<NonEvmTransferResult> _executeTron({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required TransferDraft draft,
    required String from,
    required String? expectedNetworkIdentity,
  }) async {
    final prepared = await prepareTron(
      draft: draft,
      from: from,
      expectedNetworkIdentity: expectedNetworkIdentity,
    );
    return signAndBroadcastTron(
      wallet: wallet,
      crypto: crypto,
      prepared: prepared,
      expectedNetworkIdentity: expectedNetworkIdentity,
    );
  }

  Future<PreparedTronTransfer> prepareTron({
    required TransferDraft draft,
    required String from,
    required String? expectedNetworkIdentity,
  }) async {
    if (draft.chain != Chain.tron) {
      throw ArgumentError('prepareTron requires a TRON draft');
    }
    if (draft.operation == TxOperation.approvalRevoke) {
      throw ArgumentError('approval revoke is only supported on EVM chains');
    }
    final identity = _requiredIdentity(Chain.tron, expectedNetworkIdentity);
    if (identity != null) await _identity!.verifyTron(identity);
    final rpc = TronRpc(baseUrl: _endpoint(Coin.tron), transport: _rest);
    final tokenContract = draft.tokenContract;
    final balancesFuture = rpc.getAccountBalances(
      from,
      tokenContract: tokenContract,
    );
    final recipientFuture = tokenContract == null
        ? rpc.getAccountBalances(draft.recipient)
        : null;
    final block = await rpc.getNowBlock();
    final blockId = _hexDecode(block.blockId);
    final now = block.timestamp;
    final expiresAt = now + const Duration(minutes: 10).inMilliseconds;
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
    if (tokenContract != null) {
      final calldata = Trc20.transferCalldata(
        to: draft.recipient,
        amount: draft.amount.raw,
      );
      final energy = await rpc.estimateTokenEnergy(
        owner: from,
        contract: tokenContract,
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
      expiration: expiresAt,
      feeLimit: feeLimit,
    ).encodeRawData();
    final recipient = await recipientFuture;
    final activatesRecipient = tokenContract == null && !recipient!.activated;
    final bandwidth = await rpc.estimateBandwidthFee(
      owner: from,
      rawDataLength: raw.length,
      activatesRecipient: activatesRecipient,
    );
    final maximumFee = bandwidth.maximumFeeSun + BigInt.from(feeLimit ?? 0);
    final balances = await balancesFuture;
    final nativeSpend = tokenContract == null ? draft.amount.raw : BigInt.zero;
    if (balances.trx < nativeSpend + maximumFee) {
      throw const TransferInsufficientFunds('TRX');
    }
    if (tokenContract != null &&
        (balances.token == null || balances.token! < draft.amount.raw)) {
      throw TransferInsufficientFunds(draft.symbol);
    }
    return PreparedTronTransfer(
      from: from,
      recipient: draft.recipient,
      amountRaw: draft.amount.raw,
      tokenContract: tokenContract,
      maximumFeeSun: maximumFee,
      referenceBlockHeight: block.number,
      expiresAt: expiresAt,
      rawTx: raw,
    );
  }

  Future<NonEvmTransferResult> signAndBroadcastTron({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required PreparedTronTransfer prepared,
    required String? expectedNetworkIdentity,
  }) async {
    final signed = await signPreparedTron(
      wallet: wallet,
      crypto: crypto,
      prepared: prepared,
      expectedNetworkIdentity: expectedNetworkIdentity,
    );
    return NonEvmTransferResult(
      hash: await broadcastSigned(
        Chain.tron,
        signed.signedTx,
        expectedTxHash: signed.txHash,
      ),
      referenceBlockHeight: prepared.referenceBlockHeight,
      expiresAt: prepared.expiresAt,
    );
  }

  Future<SignedTransaction> signPreparedTron({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required PreparedTronTransfer prepared,
    required String? expectedNetworkIdentity,
  }) async {
    _requirePreparedSender(wallet, Chain.tron, prepared.from);
    final identity = _requiredIdentity(Chain.tron, expectedNetworkIdentity);
    if (identity != null) await _identity!.verifyTron(identity);
    return ExperienceMetrics.instance.measure(
      ExperienceMetricNames.transactionSign,
      () async {
        final signed = await wallet.sign(
          crypto,
          coin: Coin.tron,
          signingInput: prepared.rawTx,
        );
        return _verifyNativeSignedResult(
          chain: Chain.tron,
          unsignedTx: prepared.rawTx,
          claimedSigner: prepared.from,
          signed: signed,
        );
      },
    );
  }

  Future<NonEvmTransferResult> _executeSolana({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required TransferDraft draft,
    required String from,
    required String? expectedNetworkIdentity,
  }) async {
    final prepared = await prepareSolana(
      draft: draft,
      from: from,
      expectedNetworkIdentity: expectedNetworkIdentity,
    );
    return signAndBroadcastSolana(
      wallet: wallet,
      crypto: crypto,
      prepared: prepared,
      expectedNetworkIdentity: expectedNetworkIdentity,
    );
  }

  Future<PreparedSolanaTransfer> prepareSolana({
    required TransferDraft draft,
    required String from,
    required String? expectedNetworkIdentity,
  }) async {
    if (draft.chain != Chain.solana) {
      throw ArgumentError('prepareSolana requires a Solana draft');
    }
    if (draft.operation == TxOperation.approvalRevoke) {
      throw ArgumentError('approval revoke is only supported on EVM chains');
    }
    final identity = _requiredIdentity(Chain.solana, expectedNetworkIdentity);
    if (identity != null) await _identity!.verifySolana(identity);
    final rpc = SolanaRpc(url: _endpoint(Coin.solana), transport: _jsonRpc);
    final latest = await rpc.getLatestBlockhashInfo();
    final blockhash = latest.blockhash;
    final SolanaMessage message;
    String? tokenProgram;
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
      final source = sources
          .where((account) => account.amount >= draft.amount.raw)
          .firstOrNull;
      if (source == null) {
        throw const LocalTransferException(
          'No SPL token account has enough balance',
        );
      }
      tokenProgram = draft.tokenProgram ?? solanaTokenProgram;
      // Always use the recipient's canonical ATA and prepend the Associated
      // Token Program's idempotent create instruction. Besides closing the
      // race where the ATA appears after preparation, this is a security
      // property for air-gapped signing: the raw message now carries the
      // recipient owner, mint and token program even when the ATA already
      // exists. The offline signer can therefore recompute the ATA and show
      // the wallet address the user intended, without trusting QR summary.
      final destination = SolanaMessage.associatedTokenAddress(
        owner: draft.recipient,
        mint: mint,
        tokenProgram: tokenProgram,
      );
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
        createDestination: true,
      );
    }
    final serialized = message.serialize();
    final fee = await rpc.getFeeForMessage(serialized);
    final solBalance = await rpc.getBalance(from);
    final nativeSpend = draft.operation == TxOperation.nativeTransfer
        ? draft.amount.raw
        : BigInt.zero;
    if (solBalance < nativeSpend + fee) {
      throw const TransferInsufficientFunds('SOL');
    }
    final simulation = await rpc.simulateMessage(
      serialized,
      accountAddresses: [from],
    );
    if (simulation.feeLamports == null || simulation.feeLamports != fee) {
      throw const LocalTransferException(
        'Solana simulation returned an inconsistent network fee',
      );
    }
    final postBalance = simulation.accountLamports[from];
    if (postBalance == null || postBalance > solBalance) {
      throw const LocalTransferException(
        'Solana simulation did not return a valid fee-payer balance',
      );
    }
    final totalDebit = solBalance - postBalance;
    final minimumDebit = nativeSpend + fee;
    if (totalDebit < minimumDebit) {
      throw const LocalTransferException(
        'Solana simulation returned an inconsistent fee-payer debit',
      );
    }
    final rentDeposit = totalDebit - minimumDebit;
    return PreparedSolanaTransfer(
      from: from,
      recipient: draft.recipient,
      amountRaw: draft.amount.raw,
      tokenMint: draft.tokenContract,
      tokenProgram: tokenProgram,
      networkFeeLamports: fee,
      rentDepositLamports: rentDeposit,
      lastValidBlockHeight: latest.lastValidBlockHeight,
      message: serialized,
    );
  }

  Future<NonEvmTransferResult> signAndBroadcastSolana({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required PreparedSolanaTransfer prepared,
    required String? expectedNetworkIdentity,
  }) async {
    final signed = await signPreparedSolana(
      wallet: wallet,
      crypto: crypto,
      prepared: prepared,
      expectedNetworkIdentity: expectedNetworkIdentity,
    );
    return NonEvmTransferResult(
      hash: await broadcastSigned(
        Chain.solana,
        signed.signedTx,
        expectedTxHash: signed.txHash,
      ),
      lastValidBlockHeight: prepared.lastValidBlockHeight,
    );
  }

  Future<SignedTransaction> signPreparedSolana({
    required HotWallet wallet,
    required CoreCrypto crypto,
    required PreparedSolanaTransfer prepared,
    required String? expectedNetworkIdentity,
  }) async {
    _requirePreparedSender(wallet, Chain.solana, prepared.from);
    final identity = _requiredIdentity(Chain.solana, expectedNetworkIdentity);
    if (identity != null) await _identity!.verifySolana(identity);
    return ExperienceMetrics.instance.measure(
      ExperienceMetricNames.transactionSign,
      () async {
        final signed = await wallet.sign(
          crypto,
          coin: Coin.solana,
          signingInput: prepared.message,
        );
        return _verifyNativeSignedResult(
          chain: Chain.solana,
          unsignedTx: prepared.message,
          claimedSigner: prepared.from,
          signed: signed,
        );
      },
    );
  }

  /// Independent post-signing boundary for the hot-wallet path.
  ///
  /// Native Wallet Core owns the private key and performs the signature, but
  /// its bridge result is still untrusted input at this layer. Before any
  /// signed bytes or hash are persisted/broadcast, recover or derive the
  /// signer from the signature, bind the signed payload to the exact immutable
  /// quote shown to the user, and derive the transaction hash independently.
  /// This mirrors the Cold Signer QR ingestion gate and prevents a compromised
  /// or regressed native bridge from substituting a different transaction.
  Future<SignedTransaction> _verifyNativeSignedResult({
    required Chain chain,
    required Uint8List unsignedTx,
    required String claimedSigner,
    required SignedTransaction signed,
  }) async {
    // Own the bytes while asynchronous Ed25519 verification is in flight; a
    // platform implementation must not be able to mutate a previously
    // returned buffer after it has passed verification.
    final signedBytes = Uint8List.fromList(signed.signedTx);
    final verified = await verifySignedTransaction(
      chain: chain,
      unsignedTx: Uint8List.fromList(unsignedTx),
      signedTx: signedBytes,
      claimedSigner: claimedSigner,
    );
    if (verified.txHash != signed.txHash) {
      throw const SignatureVerificationError(
        'native transaction hash mismatch',
      );
    }
    return SignedTransaction(signedTx: signedBytes, txHash: verified.txHash);
  }

  /// Irreversible network boundary. Callers must persist [expectedTxHash]
  /// before invoking this method so a lost or inconsistent node response can
  /// be reconciled without submitting the signed bytes again.
  Future<String> broadcastSigned(
    Chain chain,
    Uint8List signedTx, {
    required String expectedTxHash,
  }) => _broadcast(chain, signedTx, expectedTxHash: expectedTxHash);

  Future<String> _broadcast(
    Chain chain,
    Uint8List signedTx, {
    required String expectedTxHash,
  }) async {
    if (expectedTxHash.isEmpty) {
      throw const SignatureVerificationError(
        'missing locally verified transaction hash',
      );
    }
    final outcome = await _broadcaster.broadcast(
      chain,
      signedTx,
      expectedTxHash: expectedTxHash,
    );
    switch (outcome.status) {
      case BroadcastStatus.ok:
        final txHash = outcome.txHash;
        if (txHash == null || txHash.isEmpty) {
          throw const LocalTransferUncertainException(
            'The node accepted the request but returned no transaction hash',
          );
        }
        if (!transactionHashesMatch(chain, expectedTxHash, txHash)) {
          // The signed bytes may have reached the node, so a mismatched answer
          // is outcome-unknown rather than a rejection. Keep polling the
          // already persisted local hash and never submit the bytes again.
          throw const LocalTransferUncertainException(
            'The node returned an inconsistent transaction hash',
          );
        }
        return expectedTxHash;
      case BroadcastStatus.error:
        throw LocalTransferRejectedException(
          outcome.rejectionKind ?? RpcRejectionKind.rejected,
        );
      case BroadcastStatus.unknown:
        throw LocalTransferUncertainException(
          outcome.message ?? 'The broadcast result is unknown',
        );
      case BroadcastStatus.unsupported:
        throw const LocalTransferUnsupportedException();
    }
  }

  static void _requireEvm(Chain chain) {
    if (chain == Chain.tron || chain == Chain.solana) {
      throw ArgumentError('not an EVM chain: $chain');
    }
  }

  static void _requirePreparedSender(
    HotWallet wallet,
    Chain chain,
    String preparedFrom,
  ) {
    final walletAddress = addressForChain(wallet.addresses, chain);
    final matches = switch (chain) {
      Chain.tron || Chain.solana => walletAddress == preparedFrom,
      _ => walletAddress.toLowerCase() == preparedFrom.toLowerCase(),
    };
    if (!matches) {
      throw const LocalTransferException(
        'The approved transaction sender does not belong to this wallet',
      );
    }
  }

  String? _requiredIdentity(Chain chain, String? expected) {
    if (_identity == null) return null;
    if (expected == null || expected.isEmpty) {
      throw LocalTransferException(
        'Missing pinned network identity for ${chain.name}',
      );
    }
    return expected;
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

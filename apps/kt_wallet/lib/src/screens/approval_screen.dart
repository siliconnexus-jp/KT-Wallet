import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:wallet_data/wallet_data.dart';

import '../../l10n/app_localizations.dart';
import '../market/gateway_client.dart';
import '../market/market_scope.dart';
import '../security/transaction_auth.dart';
import '../state/app_prefs.dart';
import '../state/networks.dart';
import '../state/wallet_scope.dart';
import '../transfer/airgap_codec.dart' show addressForChain;
import '../transfer/local_transfer_service.dart';
import '../transfer/transfer_error_localization.dart';
import '../transfer/transfer_draft.dart';
import '../wallets/wallet_model.dart';

enum _ApprovalViewState { idle, loading, ready, unavailable, unsupported }

const _approvalChains = <(Chain, Coin, String, Color)>[
  (Chain.ethereum, Coin.eth, 'Ethereum', ChainColors.ethereum),
  (Chain.polygon, Coin.polygon, 'Polygon', ChainColors.polygon),
  (Chain.base, Coin.base, 'Base', Color(0xFF0052FF)),
  (Chain.arbitrum, Coin.arbitrum, 'Arbitrum', Color(0xFF28A0F0)),
  (Chain.bnb, Coin.bnb, 'BNB', Color(0xFFF3BA2F)),
];

const _supportedApprovalNetworks = {
  'eth-mainnet',
  'polygon-mainnet',
  'base-mainnet',
  'arbitrum-mainnet',
  'bnb-mainnet',
};

/// Privacy-gated, read-only ERC-20 authorization center.
///
/// An empty state is shown only after a complete provider response. Network,
/// gateway, parsing and provider failures are all rendered as unavailable;
/// unsupported/test networks are a separate state. This prevents the most
/// dangerous failure mode for an approval center: presenting "none" when the
/// scan never actually completed.
class TokenApprovalsScreen extends StatefulWidget {
  const TokenApprovalsScreen({
    super.key,
    this.gateway,
    this.transferService,
    this.authGate = const LocalTransactionAuthGate(),
    this.clock,
  });

  /// Deterministic injection for widget tests. Production resolves the shared
  /// Gateway client from AppPrefs after consent is granted.
  final GatewayClient? gateway;
  final LocalTransferService? transferService;
  final TransactionAuthGate authGate;
  final DateTime Function()? clock;

  @override
  State<TokenApprovalsScreen> createState() => _TokenApprovalsScreenState();
}

class _TokenApprovalsScreenState extends State<TokenApprovalsScreen> {
  Chain _chain = Chain.ethereum;
  _ApprovalViewState _state = _ApprovalViewState.idle;
  GatewayTokenApprovals? _result;
  int _generation = 0;
  String? _revokingKey;
  final Map<String, String> _pendingRevokes = {};

  AppPrefsController get _prefs => AppPrefsScope.maybeOf(context)!;
  DateTime get _now => (widget.clock ?? DateTime.now)();

  (Coin, String, Color) get _chainMeta {
    final row = _approvalChains.firstWhere((row) => row.$1 == _chain);
    return (row.$2, row.$3, row.$4);
  }

  void _selectChain(Chain chain) {
    if (chain == _chain) return;
    setState(() {
      _chain = chain;
      _state = _ApprovalViewState.idle;
      _result = null;
      _generation++;
    });
  }

  Future<void> _allowAndScan() async {
    try {
      await _prefs.setExternalApprovalScanConsent(true);
    } on Object {
      _showPreferenceFailure();
      return;
    }
    if (mounted) await _scan();
  }

  Future<void> _disable() async {
    try {
      await _prefs.setExternalApprovalScanConsent(false);
    } on Object {
      _showPreferenceFailure();
      return;
    }
    if (!mounted) return;
    _generation++;
    setState(() {
      _state = _ApprovalViewState.idle;
      _result = null;
    });
  }

  void _showPreferenceFailure() {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context).walletUpdateFailed),
        ),
      );
  }

  Future<void> _scan() async {
    if (!_prefs.externalApprovalScanConsent) return;
    final wallet = WalletScope.maybeOf(context)?.current;
    if (wallet == null) return;
    final network = NetworkScope.maybeOf(context)?.activeFor(_chain);
    if (network == null || !_supportedApprovalNetworks.contains(network.id)) {
      setState(() {
        _state = _ApprovalViewState.unsupported;
        _result = null;
      });
      return;
    }
    final generation = ++_generation;
    setState(() {
      _state = _ApprovalViewState.loading;
      _result = null;
    });
    try {
      await _restorePendingRevokes(network.id);
      if (!mounted || generation != _generation) return;
      final gateway = widget.gateway ?? prefsGatewayResolver(_prefs)();
      if (gateway == null) {
        throw StateError('approval scans require a configured Gateway');
      }
      final result = await gateway.getEvmTokenApprovals(
        chain: _chainMeta.$1,
        address: addressForChain(wallet.addresses, _chain),
        privacyConsent: true,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _result = result;
        _state = _ApprovalViewState.ready;
      });
    } on GatewayException catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _result = null;
        _state = error.isUnsupported
            ? _ApprovalViewState.unsupported
            : _ApprovalViewState.unavailable;
      });
    } on Object {
      if (!mounted || generation != _generation) return;
      setState(() {
        _result = null;
        _state = _ApprovalViewState.unavailable;
      });
    }
  }

  String _approvalKey(GatewayTokenApproval row) =>
      '${_chain.name}|${row.tokenAddress.toLowerCase()}|${row.spender.toLowerCase()}';

  Future<void> _restorePendingRevokes(String networkId) async {
    final transactions = await WalletScope.of(
      context,
    ).localTransactions(networkIds: {networkId});
    final restored = <String, String>{};
    for (final transaction in transactions) {
      if (transaction.operation != TxOperationKind.approvalRevoke ||
          transaction.networkId != networkId ||
          (transaction.status != TxStatus.submitted &&
              transaction.status != TxStatus.awaitingSig &&
              transaction.status != TxStatus.signed &&
              transaction.status != TxStatus.broadcast &&
              transaction.status != TxStatus.pending)) {
        continue;
      }
      final contract = transaction.contract;
      if (contract == null) continue;
      final chain = _approvalChains
          .where((row) => row.$2.name == transaction.coin)
          .map((row) => row.$1)
          .firstOrNull;
      if (chain == null) continue;
      final key =
          '${chain.name}|${contract.toLowerCase()}|${transaction.toAddr.toLowerCase()}';
      restored[key] = transaction.hash ?? transaction.id;
    }
    if (!mounted) return;
    setState(() {
      _pendingRevokes
        ..clear()
        ..addAll(restored);
    });
  }

  String _nativeSymbol(Chain chain) => switch (chain) {
    Chain.polygon => 'POL',
    Chain.avalanche => 'AVAX',
    Chain.bnb => 'BNB',
    _ => 'ETH',
  };

  Future<void> _revoke(GatewayTokenApproval row) async {
    final l10n = AppLocalizations.of(context);
    final controller = WalletScope.of(context);
    final wallet = controller.current;
    final networks = NetworkScope.maybeOf(context);
    final network = networks?.activeFor(_chain);
    final chainId = network?.evmChainId;
    if (network == null ||
        chainId == null ||
        !_supportedApprovalNetworks.contains(network.id)) {
      _message(l10n.approvalUnsupportedBody);
      return;
    }
    final key = _approvalKey(row);
    if (_revokingKey != null || _pendingRevokes.containsKey(key)) return;
    setState(() => _revokingKey = key);

    final draft = TransferDraft(
      symbol: row.tokenSymbol.isEmpty ? row.tokenName : row.tokenSymbol,
      networkLabel: network.name,
      chain: _chain,
      recipient: row.spender,
      amount: Amount(raw: BigInt.zero, decimals: row.decimals),
      feeTier: 1,
      tokenContract: row.tokenAddress,
      operation: TxOperation.approvalRevoke,
    );
    if (wallet is WatchWallet) {
      final session = TransferSessionScope.maybeOf(context);
      if (session == null) {
        setState(() => _revokingKey = null);
        _message(l10n.approvalRevokeFailed);
        return;
      }
      session.begin(draft);
      setState(() => _revokingKey = null);
      await context.push('/confirm-watch');
      return;
    }
    if (wallet is! HotWallet) {
      _message(l10n.approvalRevokeHotOnly);
      return;
    }
    final from = addressForChain(wallet.addresses, _chain);
    final service =
        widget.transferService ??
        LocalTransferService(
          endpoints: effectiveRpcEndpoints(_prefs, networks),
          gateway: prefsGatewayResolver(_prefs),
        );
    var reserved = false;
    var signedHashPersisted = false;
    var broadcastAttempted = false;
    String? localSignedHash;
    String? broadcastHash;
    String? localId;
    try {
      final prepared = await service.prepareEvm(
        draft: draft,
        from: from,
        evmChainId: chainId,
      );
      // Parse the exact bytes again before presenting confirmation. This
      // proves the quote is approve(spender, 0), not an arbitrary approval or
      // a summary-only claim.
      decodeEvmAssetChanges(
        prepared: prepared,
        draft: draft,
        nativeDecimals: 18,
        nativeSymbol: _nativeSymbol(_chain),
      );
      if (!mounted) return;
      final fee = Amount(
        raw: prepared.maximumFee,
        decimals: 18,
        symbol: _nativeSymbol(_chain),
      ).toString();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => KtConfirmDialog(
          title: l10n.approvalRevokeTitle,
          message: l10n.approvalRevokeBody,
          cancelLabel: l10n.actionCancel,
          confirmLabel: l10n.approvalRevokeConfirm,
          icon: Icons.shield_outlined,
          iconColor: WalletColors.amber,
          details: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WalletColors.bg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                KtDetailRow(
                  label: l10n.approvalTokenContract,
                  value: row.tokenAddress,
                  mono: true,
                ),
                const SizedBox(height: 10),
                KtDetailRow(
                  label: l10n.approvalSpender,
                  value: row.spender,
                  mono: true,
                ),
                const SizedBox(height: 10),
                KtDetailRow(
                  label: l10n.networkFee,
                  value: l10n.approvalRevokeMaximumFee(fee),
                ),
              ],
            ),
          ),
        ),
      );
      if (confirmed != true || !mounted) return;
      final authenticated = await widget.authGate.authenticate(
        context,
        method: _prefs.authMethod,
        reason: l10n.approvalRevokeConfirm,
      );
      if (!authenticated || !mounted) {
        if (mounted) _message(l10n.approvalRevokeAuthFailed);
        return;
      }

      final createdAt = _now.millisecondsSinceEpoch;
      localId =
          'approval_revoke_${createdAt}_${row.tokenAddress.substring(2, 8)}';
      await controller.reserveOutgoingEvmTransaction(
        id: localId,
        coin: prepared.coin,
        networkId: network.id,
        contract: prepared.tokenContract,
        operation: TxOperationKind.approvalRevoke,
        from: prepared.from,
        to: prepared.recipient,
        amountRaw: '0',
        feeRaw: prepared.maximumFee.toString(),
        signMode: SignMode.local,
        createdAt: createdAt,
        nonce: prepared.nonce.toString(),
        maxPriorityFeeRaw: prepared.maxPriorityFeePerGas.toString(),
        maxFeeRaw: prepared.maxFeePerGas.toString(),
        gasLimitRaw: prepared.gasLimit.toString(),
      );
      reserved = true;
      final signed = await service.signPreparedEvm(
        wallet: wallet,
        crypto: controller.crypto,
        prepared: prepared,
      );
      localSignedHash = signed.txHash;
      await controller.updateTransactionStatus(
        localId,
        TxStatus.submitted,
        hash: signed.txHash,
        broadcastAt: _now.millisecondsSinceEpoch,
      );
      signedHashPersisted = true;
      broadcastAttempted = true;
      final hash = await service.broadcastSigned(
        prepared.chain,
        signed.signedTx,
        expectedTxHash: signed.txHash,
      );
      broadcastHash = hash;
      await controller.updateTransactionStatus(
        localId,
        TxStatus.pending,
        hash: hash,
        broadcastAt: _now.millisecondsSinceEpoch,
      );
      if (!mounted) return;
      setState(() => _pendingRevokes[key] = hash);
      _message(l10n.approvalRevokeSubmitted);
    } on EvmNonceConflict {
      if (mounted) _message(l10n.nonceConflict);
    } on LocalTransferUncertainException {
      if (localSignedHash != null && mounted) {
        setState(() => _pendingRevokes[key] = localSignedHash!);
        _message(l10n.txSubmissionUnknownMessage);
      }
    } on LocalTransferRejectedException catch (error) {
      if (reserved && localId != null) {
        try {
          await controller.updateTransactionStatus(
            localId,
            TxStatus.failed,
            hash: localSignedHash,
          );
        } catch (_) {
          // Preserve the authoritative node rejection in the UI.
        }
      }
      if (mounted) _message(localizedRpcRejection(l10n, error.kind));
    } on LocalTransferUnsupportedException {
      if (reserved && localId != null) {
        try {
          await controller.updateTransactionStatus(
            localId,
            TxStatus.failed,
            hash: localSignedHash,
          );
        } catch (_) {
          // Preserve the unsupported-broadcast reason in the UI.
        }
      }
      if (mounted) _message(l10n.broadcastUnsupported);
    } on Object {
      if (broadcastHash != null) {
        if (mounted) {
          setState(() => _pendingRevokes[key] = broadcastHash!);
          _message(l10n.approvalRevokeSubmitted);
        }
        return;
      }
      if (broadcastAttempted && localSignedHash != null) {
        if (mounted) {
          setState(() => _pendingRevokes[key] = localSignedHash!);
          _message(l10n.txSubmissionUnknownMessage);
        }
        return;
      }
      if (reserved && localId != null) {
        try {
          await controller.updateTransactionStatus(
            localId,
            TxStatus.failed,
            hash: signedHashPersisted ? localSignedHash : null,
          );
        } catch (_) {
          // Keep the original pre-broadcast error. A secondary database
          // failure must not escape this guarded UI action.
        }
      }
      if (mounted) _message(l10n.approvalRevokeFailed);
    } finally {
      if (mounted) setState(() => _revokingKey = null);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = AppPrefsScope.maybeOf(context);
    final wallet = WalletScope.maybeOf(context)?.current;
    if (prefs == null) {
      return _ApprovalGalleryFallback(l10n: l10n);
    }
    final consent = prefs.externalApprovalScanConsent;
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: l10n.approvalsTitle, onBack: () => context.pop()),
      children: [
        Text(
          l10n.approvalsSubtitle,
          style: const TextStyle(
            fontSize: 14,
            height: 1.5,
            color: WalletColors.text2,
          ),
        ),
        if (wallet == null)
          _StateCard(
            key: const ValueKey('approval-no-wallet'),
            icon: Icons.account_balance_wallet_outlined,
            color: WalletColors.text2,
            title: l10n.approvalNoWallet,
          )
        else if (!consent)
          _PrivacyConsentCard(onAllow: _allowAndScan, l10n: l10n)
        else ...[
          _ConsentEnabledCard(onDisable: _disable, l10n: l10n),
          _NetworkPicker(selected: _chain, onSelected: _selectChain),
          _CurrentNetworkLine(chain: _chain),
          _buildResult(l10n),
          if (_state != _ApprovalViewState.loading)
            KtPrimaryButton(
              key: const ValueKey('approval-scan-action'),
              label: l10n.approvalScanAgain,
              icon: Icons.refresh_rounded,
              onPressed: _scan,
            ),
          _ReadOnlyNotice(l10n: l10n),
        ],
      ],
    );
  }

  Widget _buildResult(AppLocalizations l10n) {
    switch (_state) {
      case _ApprovalViewState.idle:
        return const SizedBox.shrink();
      case _ApprovalViewState.loading:
        return _StateCard(
          key: const ValueKey('approval-loading'),
          icon: Icons.manage_search_rounded,
          color: WalletColors.accent,
          title: l10n.approvalLoading,
          loading: true,
        );
      case _ApprovalViewState.unavailable:
        return _StateCard(
          key: const ValueKey('approval-unavailable'),
          icon: Icons.cloud_off_outlined,
          color: WalletColors.amber,
          title: l10n.approvalUnavailableTitle,
          body: l10n.approvalUnavailableBody,
        );
      case _ApprovalViewState.unsupported:
        return _StateCard(
          key: const ValueKey('approval-unsupported'),
          icon: Icons.info_outline_rounded,
          color: WalletColors.text2,
          title: l10n.approvalUnsupportedTitle,
          body: l10n.approvalUnsupportedBody,
        );
      case _ApprovalViewState.ready:
        final rows = _result?.approvals ?? const <GatewayTokenApproval>[];
        if (rows.isEmpty) {
          return _StateCard(
            key: const ValueKey('approval-empty'),
            icon: Icons.verified_user_outlined,
            color: WalletColors.green,
            title: l10n.approvalEmptyTitle,
            body: l10n.approvalEmptyBody,
          );
        }
        return Column(
          key: const ValueKey('approval-results'),
          children: [
            for (var i = 0; i < rows.length; i++) ...[
              _ApprovalCard(
                row: rows[i],
                l10n: l10n,
                onRevoke:
                    WalletScope.maybeOf(context)?.current is HotWallet ||
                        WalletScope.maybeOf(context)?.current is WatchWallet
                    ? () => _revoke(rows[i])
                    : null,
                revoking: _revokingKey == _approvalKey(rows[i]),
                pending: _pendingRevokes.containsKey(_approvalKey(rows[i])),
              ),
              if (i != rows.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
    }
  }
}

class _PrivacyConsentCard extends StatelessWidget {
  const _PrivacyConsentCard({required this.onAllow, required this.l10n});
  final VoidCallback onAllow;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => KtCard(
    key: const ValueKey('approval-consent'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.privacy_tip_outlined, color: WalletColors.accent),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                l10n.approvalPrivacyTitle,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: WalletColors.text,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          l10n.approvalPrivacyBody,
          style: const TextStyle(
            fontSize: 13,
            height: 1.55,
            color: WalletColors.text2,
          ),
        ),
        const SizedBox(height: 18),
        KtPrimaryButton(
          key: const ValueKey('approval-consent-action'),
          label: l10n.approvalEnableAndScan,
          icon: Icons.manage_search_rounded,
          onPressed: onAllow,
        ),
      ],
    ),
  );
}

class _ConsentEnabledCard extends StatelessWidget {
  const _ConsentEnabledCard({required this.onDisable, required this.l10n});
  final VoidCallback onDisable;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final status = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(
            Icons.shield_outlined,
            size: 20,
            color: WalletColors.green,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l10n.approvalPrivacyEnabled,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: WalletColors.text,
            ),
          ),
        ),
      ],
    );
    final disable = TextButton(
      key: const ValueKey('approval-disable-consent'),
      onPressed: onDisable,
      child: Text(l10n.approvalDisableScan),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: WalletColors.green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          status,
          const SizedBox(height: 4),
          Align(alignment: Alignment.centerRight, child: disable),
        ],
      ),
    );
  }
}

class _NetworkPicker extends StatelessWidget {
  const _NetworkPicker({required this.selected, required this.onSelected});
  final Chain selected;
  final ValueChanged<Chain> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final row in _approvalChains) ...[
          ChoiceChip(
            key: ValueKey('approval-chain-${row.$1.name}'),
            selected: selected == row.$1,
            onSelected: (_) => onSelected(row.$1),
            avatar: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: row.$4, shape: BoxShape.circle),
            ),
            label: Text(row.$3),
            showCheckmark: false,
            backgroundColor: WalletColors.surface,
            selectedColor: WalletColors.accent.withValues(alpha: 0.1),
            side: BorderSide(
              color: selected == row.$1
                  ? WalletColors.accent
                  : WalletColors.border,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );
}

class _CurrentNetworkLine extends StatelessWidget {
  const _CurrentNetworkLine({required this.chain});
  final Chain chain;

  @override
  Widget build(BuildContext context) {
    final network = NetworkScope.maybeOf(context)?.activeFor(chain);
    if (network == null) return const SizedBox.shrink();
    final largeText = MediaQuery.textScalerOf(context).scale(13) > 18;
    final name = Text(
      network.name,
      style: const TextStyle(fontSize: 13, color: WalletColors.text2),
    );
    final id = Text(
      network.id,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        fontSize: 11,
        fontFamily: KtFonts.mono,
        color: WalletColors.text3,
      ),
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.hub_outlined, size: 16, color: WalletColors.text3),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: largeText
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [name, const SizedBox(height: 2), id],
                )
              : Row(
                  children: [
                    Expanded(child: name),
                    const SizedBox(width: 8),
                    Flexible(child: id),
                  ],
                ),
        ),
      ],
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  const _ApprovalCard({
    required this.row,
    required this.l10n,
    this.onRevoke,
    this.revoking = false,
    this.pending = false,
  });
  final GatewayTokenApproval row;
  final AppLocalizations l10n;
  final VoidCallback? onRevoke;
  final bool revoking;
  final bool pending;

  static String _short(String value) => value.length <= 18
      ? value
      : '${value.substring(0, 8)}…${value.substring(value.length - 6)}';

  static String _date(int seconds) {
    if (seconds <= 0) return '—';
    final date = DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
    String two(int value) => value.toString().padLeft(2, '0');
    return '${date.year}-${two(date.month)}-${two(date.day)} '
        '${two(date.hour)}:${two(date.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final risky = row.risk == GatewayTokenApprovalRisk.unsafe;
    final title = row.tokenSymbol.isNotEmpty
        ? row.tokenSymbol
        : row.tokenName.isNotEmpty
        ? row.tokenName
        : _short(row.tokenAddress);
    final spenderLabel = row.spenderTag.isNotEmpty
        ? row.spenderTag
        : row.spenderName.isNotEmpty
        ? row.spenderName
        : _short(row.spender);
    final statusColor = risky
        ? WalletColors.red
        : row.unlimited
        ? WalletColors.amber
        : WalletColors.text2;
    final largeText = MediaQuery.textScalerOf(context).scale(13) > 18;
    final identity = Row(
      children: [
        Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Text(
            title.characters.firstOrNull?.toUpperCase() ?? '?',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: statusColor,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: largeText ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: WalletColors.text,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                spenderLabel,
                maxLines: largeText ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: WalletColors.text2),
              ),
            ],
          ),
        ),
      ],
    );
    final riskBadge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        risky
            ? l10n.approvalRisky
            : row.unlimited
            ? l10n.approvalUnlimited
            : l10n.approvalIdentityUnknown,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: statusColor,
        ),
      ),
    );
    return KtCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (largeText) ...[
            identity,
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: riskBadge),
          ] else
            Row(
              children: [
                Expanded(child: identity),
                const SizedBox(width: 10),
                riskBadge,
              ],
            ),
          const SizedBox(height: 14),
          _detail(l10n.approvalSpender, row.spender),
          const SizedBox(height: 10),
          _detail(l10n.approvalTokenContract, row.tokenAddress),
          const SizedBox(height: 10),
          _detail(
            row.unlimited
                ? l10n.approvalUnlimited
                : l10n.approvalAmount(row.amount),
            _date(row.approvedAt),
          ),
          if (row.spenderTrusted) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: WalletColors.accent,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.approvalKnownSpender,
                    style: const TextStyle(
                      fontSize: 12,
                      color: WalletColors.text2,
                    ),
                  ),
                ),
              ],
            ),
          ],
          if (onRevoke != null || pending) ...[
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton.icon(
                key: ValueKey(
                  'approval-revoke-${row.tokenAddress}-${row.spender}',
                ),
                onPressed: pending || revoking ? null : onRevoke,
                icon: revoking
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        pending ? Icons.schedule_rounded : Icons.block_rounded,
                        size: 18,
                      ),
                label: Text(
                  revoking
                      ? l10n.approvalRevokePreparing
                      : pending
                      ? l10n.approvalRevokePending
                      : l10n.approvalRevoke,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: pending
                      ? WalletColors.text2
                      : WalletColors.red,
                  side: BorderSide(
                    color: pending ? WalletColors.border : WalletColors.red,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detail(String label, String value) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        flex: 2,
        child: Text(
          label,
          style: const TextStyle(fontSize: 12, color: WalletColors.text3),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        flex: 3,
        child: Text(
          value,
          textAlign: TextAlign.right,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            fontFamily: KtFonts.mono,
            color: WalletColors.text2,
          ),
        ),
      ),
    ],
  );
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.body,
    this.loading = false,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String? body;
  final bool loading;

  @override
  Widget build(BuildContext context) => KtCard(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox.square(
          dimension: 36,
          child: loading
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: color,
                  ),
                )
              : Icon(icon, size: 24, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: WalletColors.text,
                ),
              ),
              if (body != null) ...[
                const SizedBox(height: 6),
                Text(
                  body!,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: WalletColors.text2,
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

class _ReadOnlyNotice extends StatelessWidget {
  const _ReadOnlyNotice({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: WalletColors.amber.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: WalletColors.amber.withValues(alpha: 0.24)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          size: 19,
          color: WalletColors.amber,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            l10n.approvalReadOnlyNotice,
            style: const TextStyle(
              fontSize: 12,
              height: 1.5,
              color: WalletColors.text2,
            ),
          ),
        ),
      ],
    ),
  );
}

class _ApprovalGalleryFallback extends StatelessWidget {
  const _ApprovalGalleryFallback({required this.l10n});
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => KtScreen(
    gap: 16,
    navBar: KtNavBar(
      title: l10n.approvalsTitle,
      onBack: () => Navigator.of(context).maybePop(),
    ),
    children: [
      Text(
        l10n.approvalsSubtitle,
        style: const TextStyle(fontSize: 14, color: WalletColors.text2),
      ),
      _StateCard(
        icon: Icons.privacy_tip_outlined,
        color: WalletColors.accent,
        title: l10n.approvalPrivacyTitle,
        body: l10n.approvalPrivacyBody,
      ),
    ],
  );
}

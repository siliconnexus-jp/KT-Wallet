import 'dart:async';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:ui_kit/ui_kit.dart';

import '../../l10n/app_localizations.dart';
import '../market/market_scope.dart' show prefsRpcEndpoints;
import '../security/biometric_auth.dart';
import '../state/app_prefs.dart' show AppPrefsScope;
import '../transfer/airgap_codec.dart';
import '../transfer/broadcast_service.dart';
import '../transfer/chain_params_service.dart';
import '../transfer/frame_scan.dart';
import '../transfer/transfer_draft.dart';
import '../widgets/scan_viewfinder.dart';
import '../widgets/token_icon.dart';
import '../state/wallet_scope.dart';
import '../wallets/wallet_model.dart';

Color _chainDot(Chain chain) => switch (chain) {
      Chain.ethereum => ChainColors.ethereum,
      Chain.polygon => ChainColors.polygon,
      Chain.tron => ChainColors.tron,
      Chain.solana => ChainColors.solana,
    };

Widget _amberWarn(String text) => Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: WalletColors.amber.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.warning_amber_rounded, size: 16, color: WalletColors.amber),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF9A6503)))),
      ]),
    );

/// W4 转账输入. Live: recipient address is validated against the token's chain
/// (rejecting mispastes and wrong-network addresses) and the amount is parsed
/// with the tested [Amount] type and checked against the available balance.
class TransferInputScreen extends StatefulWidget {
  const TransferInputScreen({super.key});
  @override
  State<TransferInputScreen> createState() => _TransferInputScreenState();
}

/// A demo asset selectable on the transfer screen (mirrors the home list).
class _TransferAsset {
  const _TransferAsset(this.symbol, this.network, this.networkName, this.chain, this.decimals, this.available, this.availableLabel, this.color, this.initial, {this.contract});
  final String symbol, network, networkName;
  final Chain chain;
  final int decimals;
  final String available, availableLabel;
  final Color color;
  final String initial;

  /// Token contract for token assets; null for native coins.
  final String? contract;
  Amount get availableAmount => Amount.parse(available, decimals, symbol: symbol);
}

class _TransferInputScreenState extends State<TransferInputScreen> {
  static const _assets = [
    _TransferAsset('USDT', 'TRON · TRC-20', 'TRON', Chain.tron, 6, '3120.00', '3,120.00', Color(0xFF26A17B), '₮', contract: usdtTronContract),
    _TransferAsset('ETH', 'Ethereum', 'Ethereum', Chain.ethereum, 18, '0.0842', '0.0842', Color(0xFF627EEA), 'Ξ'),
    _TransferAsset('SOL', 'Solana', 'Solana', Chain.solana, 9, '0.531', '0.531', Color(0xFF9945FF), '◎'),
  ];
  int _assetIndex = 0;
  _TransferAsset get _asset => _assets[_assetIndex];

  final _addrController = TextEditingController(text: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t');
  final _amountController = TextEditingController(text: '120.00');
  int _fee = 1;

  @override
  void dispose() {
    _addrController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  AddressValidation get _addrCheck => Addresses.validate(_asset.chain, _addrController.text.trim());

  /// Returns the parsed amount if it is valid and within balance, else null.
  Amount? get _amount {
    final text = _amountController.text.trim();
    if (text.isEmpty) return null;
    try {
      final a = Amount.parse(text, _asset.decimals, symbol: _asset.symbol);
      if (a.raw == BigInt.zero || !(_asset.availableAmount >= a)) return null;
      return a;
    } on AmountError {
      return null;
    }
  }

  String? _amountErrorFor(AppLocalizations l10n) {
    final text = _amountController.text.trim();
    if (text.isEmpty) return null; // don't nag before typing
    try {
      final a = Amount.parse(text, _asset.decimals, symbol: _asset.symbol);
      if (a.raw == BigInt.zero) return l10n.amountMustBePositive;
      if (!(_asset.availableAmount >= a)) return l10n.insufficientBalance;
      return null;
    } on AmountError {
      return l10n.amountFormatInvalid;
    }
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    if (text.isNotEmpty) setState(() => _addrController.text = text);
  }

  /// Opens the mock address scanner; a simulated scan pops with the address.
  Future<void> _scanAddress() async {
    final scanned = await context.push<String>('/scan-address');
    if (scanned != null && mounted) setState(() => _addrController.text = scanned);
  }

  /// Opens the custom fee screen and maps its result back onto the segmented
  /// tier selection.
  Future<void> _customFee() async {
    final tier = await context.push<int>('/fee');
    if (tier != null && mounted) setState(() => _fee = tier);
  }

  /// Bottom sheet listing the demo assets (same visual pattern as the language
  /// picker sheet); selecting one switches chain / decimals / symbol / balance.
  Future<void> _pickAsset() async {
    final l10n = AppLocalizations.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: WalletColors.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Text(l10n.selectAsset, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: WalletColors.text)),
            ]),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _assets.length; i++)
            ListTile(
              leading: TokenIcon(symbol: _assets[i].symbol, size: 36, fallbackColor: _assets[i].color, fallbackInitial: _assets[i].initial),
              title: Text(_assets[i].symbol, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.text)),
              subtitle: Text('${_assets[i].network} · ${l10n.availableBalance(_assets[i].availableLabel, _assets[i].symbol)}', style: const TextStyle(fontSize: 12, color: WalletColors.text3)),
              trailing: i == _assetIndex ? const Icon(Icons.check, size: 20, color: WalletColors.accent) : null,
              onTap: () {
                setState(() => _assetIndex = i);
                Navigator.of(ctx).pop();
              },
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final isHot = WalletScope.of(context).current is HotWallet;
    final addrCheck = _addrCheck;
    final canProceed = addrCheck.isValid && _amount != null;
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: l10n.actionSend, onBack: () => Navigator.of(context).maybePop(), trailing: Icons.qr_code_scanner, onTrailing: _scanAddress),
      bottom: KtPrimaryButton(
        label: l10n.actionNext,
        onPressed: canProceed
            ? () {
                // Hand the entered transfer to the downstream screens. Starting
                // a new draft invalidates any earlier request/result.
                TransferSessionScope.maybeOf(context)
                  ?..draft = TransferDraft(
                    symbol: _asset.symbol,
                    networkLabel: _asset.network,
                    chain: _asset.chain,
                    decimals: _asset.decimals,
                    recipient: addrCheck.normalized ?? _addrController.text.trim(),
                    amount: _amount!,
                    feeTier: _fee,
                    tokenContract: _asset.contract,
                  )
                  ..request = null
                  ..result = null
                  ..broadcastTxHash = null;
                context.push(isHot ? '/confirm-hot' : '/confirm-watch');
              }
            : null,
      ),
      children: [
        KtCard(
          padding: const EdgeInsets.all(14),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _pickAsset,
            child: Row(children: [
              TokenIcon(symbol: _asset.symbol, size: 36, fallbackColor: _asset.color, fallbackInitial: _asset.initial),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_asset.symbol, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.text)),
                  const SizedBox(height: 2),
                  Text(_asset.network, style: const TextStyle(fontSize: 12, color: WalletColors.text2)),
                ]),
              ),
              const Icon(Icons.keyboard_arrow_down, size: 18, color: WalletColors.text3),
            ]),
          ),
        ),
        KtCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(l10n.recipientAddress, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WalletColors.text2)),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: TextField(
                  controller: _addrController,
                  onChanged: (_) => setState(() {}),
                  autocorrect: false,
                  enableSuggestions: false,
                  maxLines: null,
                  style: const TextStyle(fontSize: 14, fontFamily: KtFonts.mono, color: WalletColors.text),
                  decoration: InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: l10n.pasteOrEnterAddress, hintStyle: const TextStyle(color: WalletColors.text3)),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(onTap: _paste, child: const Icon(Icons.content_paste, size: 18, color: WalletColors.accent)),
              const SizedBox(width: 10),
              GestureDetector(onTap: _scanAddress, child: const Icon(Icons.qr_code_scanner, size: 18, color: WalletColors.accent)),
            ]),
            const SizedBox(height: 12),
            if (_addrController.text.trim().isEmpty)
              Text(l10n.enterChainAddress(_asset.networkName), style: const TextStyle(fontSize: 12, color: WalletColors.text3))
            else if (addrCheck.isValid)
              Row(children: [
                const Icon(Icons.check_circle, size: 14, color: WalletColors.green),
                const SizedBox(width: 6),
                Text(l10n.addressValidOn(_asset.networkName), style: const TextStyle(fontSize: 12, color: WalletColors.green)),
              ])
            else
              Row(children: [
                const Icon(Icons.error_outline, size: 14, color: WalletColors.red),
                const SizedBox(width: 6),
                Expanded(child: Text(addrCheck.reason ?? l10n.addressInvalid, style: const TextStyle(fontSize: 12, color: WalletColors.red))),
              ]),
          ]),
        ),
        KtCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(l10n.amountLabel, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WalletColors.text2)),
              GestureDetector(
                onTap: () => setState(() => _amountController.text = _asset.available),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: WalletColors.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                  child: Text(l10n.max, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: WalletColors.accent)),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  onChanged: (_) => setState(() {}),
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: WalletColors.text),
                  decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none, hintText: '0', hintStyle: TextStyle(color: WalletColors.text3)),
                ),
              ),
              const SizedBox(width: 8),
              Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(_asset.symbol, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: WalletColors.text2))),
            ]),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Builder(builder: (_) {
                final amountError = _amountErrorFor(l10n);
                return Text(amountError ?? '≈ \$${_amountController.text.trim().isEmpty ? '0.00' : _amountController.text.trim()}', style: TextStyle(fontSize: 12, color: amountError == null ? WalletColors.text3 : WalletColors.red));
              }),
              Text(l10n.availableBalance(_asset.availableLabel, _asset.symbol), style: const TextStyle(fontSize: 12, color: WalletColors.text3)),
            ]),
          ]),
        ),
        KtCard(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text(l10n.networkFee, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WalletColors.text2)),
              GestureDetector(onTap: _customFee, child: Text(l10n.feeCustom, style: const TextStyle(fontSize: 12, color: WalletColors.accent))),
            ]),
            const SizedBox(height: 12),
            KtSegmented(options: [l10n.feeSlow, l10n.feeStandard, l10n.feeFast], selected: _fee, onChanged: (i) => setState(() => _fee = i)),
          ]),
        ),
      ],
    );
  }
}

/// W31 手续费选择.
class FeeSelectScreen extends StatefulWidget {
  const FeeSelectScreen({super.key});
  @override
  State<FeeSelectScreen> createState() => _FeeSelectScreenState();
}

class _FeeSelectScreenState extends State<FeeSelectScreen> {
  int _selected = 1; // default 标准

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final tiers = [
      (l10n.feeSlow, l10n.feeEtaSlow, '6.8 TRX', r'$0.94'),
      (l10n.feeStandard, l10n.feeEtaStandard, '13.7 TRX', r'$1.90'),
      (l10n.feeFast, l10n.feeEtaFast, '27.4 TRX', r'$3.80'),
    ];
    return KtScreen(
      navBar: KtNavBar(title: l10n.networkFee, onBack: () => Navigator.of(context).maybePop()),
      // Pops the selected tier index so the transfer screen can mirror it in
      // its slow/standard/fast segmented control.
      bottom: KtPrimaryButton(label: l10n.confirmFee, onPressed: () => context.pop(_selected)),
      children: [
        Text(l10n.feeExplainer,
            style: const TextStyle(fontSize: 13, height: 1.5, color: WalletColors.text2)),
        Column(children: [
          for (final (i, tier) in tiers.indexed)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _selected = i),
                child: () {
                  final sel = i == _selected;
                  final (name, eta, fee, fiat) = tier;
                  return Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: sel ? WalletColors.accent.withValues(alpha: 0.04) : WalletColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: sel ? WalletColors.accent : WalletColors.border, width: sel ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      Icon(sel ? Icons.radio_button_checked : Icons.radio_button_unchecked, size: 20, color: sel ? WalletColors.accent : const Color(0xFFD2D7E0)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.text)),
                          const SizedBox(height: 3),
                          Text(eta, style: const TextStyle(fontSize: 12, color: WalletColors.text3)),
                        ]),
                      ),
                      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text(fee, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, fontFamily: KtFonts.mono, color: WalletColors.text)),
                        const SizedBox(height: 3),
                        Text(fiat, style: const TextStyle(fontSize: 12, color: WalletColors.text3)),
                      ]),
                    ]),
                  );
                }(),
              ),
            ),
        ]),
        _amberWarn(l10n.feeLowWarning),
      ],
    );
  }
}

/// Shared confirm layout for W5 (watch) / W29 (hot). With a live
/// [TransferDraft] in scope, every displayed field is derived from the draft
/// through the chains [TxPreview]; without one (gallery / goldens) the design
/// demo values render unchanged.
class TransferConfirmScreen extends StatelessWidget {
  const TransferConfirmScreen({super.key, required this.isHot});
  final bool isHot;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final draft = TransferSessionScope.maybeOf(context)?.draft;
    final wallet = WalletScope.of(context).current;

    // Demo defaults (Pencil design literals).
    var headline = '-120.00 USDT';
    var fiat = '≈ \$120.00';
    var networkLabel = 'TRON · TRC-20';
    var dotColor = ChainColors.tron;
    var fromValue = '主钱包 TQm9…3kFa';
    var toValue = 'TWd4qCEU…nMxR38uQz';
    var feeValue = '≈ 13.7 TRX（\$1.90）';
    var totalValue = '120.00 USDT';

    if (draft != null) {
      final from = wallet == null ? demoFromAddress : addressForChain(wallet.addresses, draft.chain);
      final preview = previewForDraft(draft, from: from);
      final total = preview.totalNativeSpend;
      headline = '-${draft.amountText}';
      // Demo 1:1 USD peg, consistent with the input screen's ≈ display.
      fiat = '≈ \$${preview.amount.format()}';
      networkLabel = draft.networkLabel;
      dotColor = _chainDot(draft.chain);
      fromValue = '${wallet?.name ?? ''} ${truncateMiddle(preview.from, head: 4, tail: 4)}'.trim();
      toValue = truncateMiddle(preview.to, head: 8, tail: 9);
      feeValue = '≈ ${preview.networkFee}';
      totalValue = total == null ? draft.amountText : '$total';
    }

    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: l10n.confirmTransactionTitle, onBack: () => Navigator.of(context).maybePop()),
      bottom: Column(children: [
        KtPrimaryButton(label: isHot ? l10n.confirmTransfer : l10n.generateSignQr, onPressed: () => context.push(isHot ? '/transfer-auth' : '/sign-qr')),
        const SizedBox(height: 10),
        Text(isHot ? l10n.hotConfirmHint : l10n.watchConfirmHint,
            style: const TextStyle(fontSize: 12, color: WalletColors.text3)),
      ]),
      children: [
        Column(children: [
          Text(headline, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: WalletColors.text)),
          const SizedBox(height: 8),
          Text(fiat, style: const TextStyle(fontSize: 14, color: WalletColors.text2)),
          const SizedBox(height: 8),
          NetworkBadge(label: networkLabel, dotColor: dotColor),
        ]),
        KtCard(
          child: Column(children: [
            KtDetailRow(label: l10n.fromAddress, value: fromValue, mono: true),
            const SizedBox(height: 14),
            KtDetailRow(label: l10n.recipientAddress, value: toValue, mono: true),
            const SizedBox(height: 14),
            KtDetailRow(label: l10n.networkFee, value: feeValue),
            const SizedBox(height: 14),
            KtDetailRow(label: l10n.totalSpend, value: totalValue, valueColor: WalletColors.text),
          ]),
        ),
        if (isHot) _amberWarn(l10n.unbackedTransferWarning),
      ],
    );
  }
}

/// W6 待签名二维码. Displays a REAL animated AIRGAP-V1 sign-request: the draft
/// (or the demo transfer when opened from the gallery) is encoded to a
/// [SignRequest], fragmented into frames, and each frame's bytes are rendered
/// as a scannable QR, cycling every ~600ms. The shard label/progress reflect
/// the actual frame count.
///
/// Live EVM drafts first fetch the sender's real nonce and current fees via
/// [ChainParamsService] (brief spinner in place of the QR); on failure the
/// documented demo constants apply and a fallback hint is shown. Demo/gallery
/// renderings and non-EVM chains build synchronously, exactly as before.
class SignRequestQrScreen extends StatefulWidget {
  const SignRequestQrScreen({super.key, this.paramsService});

  /// Injectable chain-params fetcher for tests; defaults to one resolving
  /// the prefs-overridable endpoints.
  final ChainParamsService? paramsService;

  @override
  State<SignRequestQrScreen> createState() => _SignRequestQrScreenState();
}

class _SignRequestQrScreenState extends State<SignRequestQrScreen> {
  static const _frameInterval = Duration(milliseconds: 600);

  TransferDraft? _draft;
  SignRequest? _request;
  List<String> _frames = const [];
  int _frameIndex = 0;
  Timer? _timer;

  /// True while the live EVM chain-state fetch is in flight (spinner state).
  bool _building = false;

  /// True when the fetch failed and the demo constants were used instead.
  bool _paramsFellBack = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_request != null || _building) return; // build once per screen instance
    final session = TransferSessionScope.maybeOf(context);
    _draft = session?.draft;
    final wallet = WalletScope.of(context).current;
    final draft = _draft;
    final chain = (draft ?? demoDraft).chain;
    final walletId = wallet?.id ?? demoWalletId;
    final from = wallet == null ? demoFromAddress : addressForChain(wallet.addresses, chain);
    if (draft != null && (chain == Chain.ethereum || chain == Chain.polygon)) {
      // Live EVM path: real nonce/fees first, QR after the fetch.
      _building = true;
      final service = widget.paramsService ??
          ChainParamsService(endpoints: prefsRpcEndpoints(AppPrefsScope.maybeOf(context)));
      unawaited(_buildLiveEvm(service, session, draft, walletId: walletId, from: from));
    } else {
      _install(buildSignRequest(draft: draft, walletId: walletId, fromAddress: from), session);
    }
  }

  Future<void> _buildLiveEvm(
    ChainParamsService service,
    TransferSession? session,
    TransferDraft draft, {
    required String walletId,
    required String from,
  }) async {
    BigInt? nonce, maxPriority, maxFee;
    try {
      final params = await service.fetchEvmParams(draft.chain, from);
      final tier = params.tierFor(draft.feeTier);
      nonce = BigInt.from(params.nonce);
      maxPriority = tier.maxPriorityFeePerGas;
      maxFee = tier.maxFeePerGas;
    } catch (_) {
      // Node unreachable / erroring: the demo constants keep the request
      // buildable; the fallback banner tells the user what happened.
      _paramsFellBack = true;
    }
    if (!mounted) return;
    setState(() {
      _building = false;
      _install(
        buildSignRequest(
          draft: draft,
          walletId: walletId,
          fromAddress: from,
          nonce: nonce,
          maxPriorityFeePerGas: maxPriority,
          maxFeePerGas: maxFee,
        ),
        session,
      );
    });
  }

  /// Registers [request] as the outstanding one and starts the frame cycle.
  void _install(SignRequest request, TransferSession? session) {
    _request = request;
    // This is now the outstanding request the scanned result must answer.
    session
      ?..request = request
      ..result = null;
    _frames = encodeQrFrames(request, reqId: request.reqId);
    if (_frames.length > 1) {
      _timer = Timer.periodic(_frameInterval, (_) {
        setState(() => _frameIndex = (_frameIndex + 1) % _frames.length);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _cancel() {
    final session = TransferSessionScope.maybeOf(context);
    if (session?.request == _request) session?.request = null;
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final request = _request;
    final draft = _draft;
    if (request == null) {
      // Brief spinner while the live EVM nonce/fee fetch is in flight.
      return KtScreen(
        gap: 16,
        navBar: KtNavBar(title: l10n.pendingSignTitle, onBack: () => Navigator.of(context).maybePop(), trailingText: l10n.actionCancel, onTrailing: _cancel),
        children: const [
          KtCard(
            padding: EdgeInsets.all(24),
            child: SizedBox(height: 280, child: Center(child: CircularProgressIndicator())),
          ),
        ],
      );
    }
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: l10n.pendingSignTitle, onBack: () => Navigator.of(context).maybePop(), trailingText: l10n.actionCancel, onTrailing: _cancel),
      children: [
        if (_paramsFellBack) _amberWarn(l10n.chainParamsFallback),
        KtCard(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            KtQrCode(data: _frames[_frameIndex], size: 240),
            const SizedBox(height: 16),
            Text(l10n.dynamicShard(_frameIndex + 1, _frames.length), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WalletColors.text2)),
            const SizedBox(height: 8),
            ShardProgressBar(received: _frameIndex + 1, total: _frames.length),
          ]),
        ),
        KtCard(
          child: Column(children: [
            KtDetailRow(label: l10n.networkRow, value: draft?.networkLabel ?? 'TRON · TRC-20'),
            const SizedBox(height: 14),
            KtDetailRow(label: l10n.amountLabel, value: draft?.amountText ?? '120.00 USDT'),
            const SizedBox(height: 14),
            KtDetailRow(label: l10n.requestId, value: 'REQ-${request.reqIdHex.substring(0, 6).toUpperCase()}', mono: true),
          ]),
        ),
        Center(child: Text(l10n.scanWithOfflinePhone, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: WalletColors.text))),
      ],
    );
  }
}

/// W7 扫描签名结果 (dark camera screen). With a camera available the live
/// scanner feeds every decoded QR string — one base64url AIRGAP-V1 frame — to
/// a real [FrameAggregator]; without one, tapping the simulated viewfinder
/// still produces a protocol-genuine session: the frames the Cold Signer
/// would display for the outstanding request are generated, aggregated and
/// decoded back into a verified [SignResult] exactly as a real scan would be.
class ScanResultScreen extends StatefulWidget {
  const ScanResultScreen({super.key, this.availability});

  /// Camera probe override for tests; defaults to the process-wide instance.
  final CameraAvailability? availability;

  @override
  State<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends State<ScanResultScreen> {
  /// Live camera aggregation session (untouched by the simulated tap, which
  /// synthesizes and verifies a complete frame set in one step, as before).
  final _session = QrFrameScanSession();
  AggregatorProgress? _progress;
  bool _navigated = false;

  void _simulateScan(BuildContext context, TransferSession? session, Wallet? wallet) {
    if (_navigated) return;
    final request = session?.request;
    if (session != null && request != null) {
      // Signer side of the (simulated) air gap: the paired signer answers with
      // deterministic demo signature bytes for the same reqId.
      final signer = wallet == null
          ? demoFromAddress
          : addressForChain(wallet.addresses, chainForCoin(request.coin));
      final frames = encodeQrFrames(buildDemoSignResult(request, signer: signer), reqId: request.reqId);
      // Wallet side: aggregate + decode + verify against the outstanding
      // request; broadcast-confirm renders only what was decoded.
      session.result = decodeSignResultFrames(frames, expected: request);
    }
    _navigated = true;
    context.push('/broadcast-confirm');
  }

  /// Discards the current (unverifiable or failed) session and rescans.
  void _restartSession() {
    _session.reset();
    setState(() => _progress = null);
  }

  void _onScanned(String raw) {
    if (_navigated) return;
    final progress = _session.add(raw); // invalid strings: silent anomalies
    if (progress.received > 0) setState(() => _progress = progress);
    if (_session.isFailed) return _restartSession();
    if (!_session.isDone) return;

    final session = TransferSessionScope.maybeOf(context);
    final request = session?.request;
    if (session == null || request == null) {
      // Nothing to answer (no outstanding request): drop the payload.
      return _restartSession();
    }
    final SignResult result;
    try {
      result = verifySignResultPayload(_session.payload!, expected: request);
    } on Object {
      // Foreign or malformed payload: silently start over, keep scanning.
      return _restartSession();
    }
    session.result = result;
    _navigated = true;
    context.push('/broadcast-confirm');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = TransferSessionScope.maybeOf(context);
    final wallet = WalletScope.of(context).current;
    // Demo shard counters until a live scan makes real progress (gallery /
    // goldens render exactly the design literals).
    final received = _progress?.received ?? 5;
    final total = _progress?.total ?? 12;
    return Scaffold(
      backgroundColor: SignerColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          const KtStatusBar(theme: AppTheme.signer),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: KtNavBar(title: l10n.scanSignResultTitle, theme: AppTheme.signer, leading: Icons.close, onBack: () => Navigator.of(context).maybePop()),
          ),
          const SizedBox(height: 24),
          ScanViewfinder(
            height: 380,
            frameColor: SignerColors.blue,
            onSimulatedTap: () => _simulateScan(context, session, wallet),
            onScanned: _onScanned,
            availability: widget.availability,
          ),
          const SizedBox(height: 24),
          Text(l10n.recognizedShard(received, total), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
          const SizedBox(height: 10),
          ShardProgressBar(received: received, total: total, color: SignerColors.blue, trackColor: SignerColors.border, width: 240),
        ]),
      ),
    );
  }
}

/// W8 广播确认. With a decoded [SignResult] in scope, the tx hash, signer and
/// network are read from the protocol payload (and the amount/recipient from
/// the outstanding request it answered); without one (gallery / goldens) the
/// demo constants render unchanged.
///
/// The broadcast button pushes the signed bytes through [BroadcastService]:
/// demo signatures short-circuit to the simulated-success path (never sent to
/// a node), a real signature goes over the wire, and a rejection surfaces the
/// node's message here — the broadcastError → failed step; retry stays
/// user-explicit (INV-15, no auto-retry).
class BroadcastConfirmScreen extends StatefulWidget {
  const BroadcastConfirmScreen({super.key, this.broadcaster});

  /// Injectable broadcast pipe for tests; defaults to one resolving the
  /// prefs-overridable endpoints.
  final BroadcastService? broadcaster;

  @override
  State<BroadcastConfirmScreen> createState() => _BroadcastConfirmScreenState();
}

class _BroadcastConfirmScreenState extends State<BroadcastConfirmScreen> {
  bool _busy = false;

  /// Node/transport message of the last failed broadcast, if any.
  String? _error;

  Future<void> _broadcast() async {
    final session = TransferSessionScope.maybeOf(context);
    final result = session?.result;
    if (session == null || result == null) {
      // Gallery / demo rendering without a decoded result: keep the design's
      // direct navigation (nothing to broadcast).
      context.go('/broadcast-result');
      return;
    }
    final service = widget.broadcaster ??
        BroadcastService(endpoints: prefsRpcEndpoints(AppPrefsScope.maybeOf(context)));
    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await service.broadcast(chainForCoin(result.coin), result.signedTx);
    if (!mounted) return;
    switch (outcome.status) {
      case BroadcastStatus.ok:
      case BroadcastStatus.simulated:
        session.broadcastTxHash = outcome.txHash ?? result.txHash;
        context.go('/broadcast-result');
      case BroadcastStatus.error:
      case BroadcastStatus.unsupported:
        setState(() {
          _busy = false;
          _error = outcome.message ?? '';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = TransferSessionScope.maybeOf(context);
    final result = session?.result;
    final request = session?.request;

    // Demo defaults (Pencil design literals).
    var headline = '-120.00 USDT';
    var networkLabel = 'TRON · TRC-20';
    var dotColor = ChainColors.tron;
    var toValue = 'TWd4qCEU…nMxR38uQz';
    var signerValue = 'TQm9xPa2…Vb7L3kFa';
    var hashValue = '8f6d2c…a94e07';

    if (result != null) {
      final summary = request?.summary;
      final chain = chainForCoin(result.coin);
      headline = '-${summary?[SummaryKeys.amount] ?? ''}';
      networkLabel = summary?[SummaryKeys.network] as String? ?? chain.name;
      dotColor = _chainDot(chain);
      final recipient = summary?[SummaryKeys.recipient] as String?;
      if (recipient != null) toValue = truncateMiddle(recipient, head: 8, tail: 9);
      signerValue = truncateMiddle(result.signer);
      hashValue = truncateMiddle(result.txHash, head: 6, tail: 6);
    }

    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: l10n.broadcastTitle, onBack: () => Navigator.of(context).maybePop()),
      bottom: Column(children: [
        KtPrimaryButton(label: l10n.broadcastTitle, onPressed: _busy ? null : _broadcast),
        const SizedBox(height: 12),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Text(l10n.dontBroadcastYet, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: WalletColors.text2)),
        ),
      ]),
      children: [
        // Failed-broadcast state: the node's rejection message, verbatim.
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: WalletColors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.error_outline, size: 18, color: WalletColors.red),
              const SizedBox(width: 10),
              Expanded(child: Text(l10n.broadcastFailedMessage(_error!),
                  style: const TextStyle(fontSize: 13, height: 1.5, fontWeight: FontWeight.w500, color: WalletColors.red))),
            ]),
          ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: WalletColors.green.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.verified_user, size: 18, color: WalletColors.green),
            const SizedBox(width: 10),
            Expanded(child: Text(l10n.signatureVerified,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF0A7A45)))),
          ]),
        ),
        Column(children: [
          Text(headline, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: WalletColors.text)),
          const SizedBox(height: 8),
          NetworkBadge(label: networkLabel, dotColor: dotColor),
        ]),
        KtCard(
          child: Column(children: [
            KtDetailRow(label: l10n.recipientAddress, value: toValue, mono: true),
            const SizedBox(height: 14),
            KtDetailRow(label: l10n.signerAddress, value: signerValue, mono: true),
            const SizedBox(height: 14),
            KtDetailRow(label: l10n.txHashPreview, value: hashValue, mono: true),
          ]),
        ),
      ],
    );
  }
}

/// W9 广播结果.
class BroadcastResultScreen extends StatelessWidget {
  const BroadcastResultScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Prefer the hash the broadcast step actually produced (node answer or
    // simulated short-circuit); else keep the decoded result's hash for
    // consistency with broadcast-confirm; demo constant otherwise.
    final session = TransferSessionScope.maybeOf(context);
    final fullHash = session?.broadcastTxHash ?? session?.result?.txHash;
    final hashValue = fullHash == null ? '8f6d2c…a94e07' : truncateMiddle(fullHash, head: 6, tail: 6);
    return KtScreen(
      gap: 24,
      bottom: KtPrimaryButton(label: l10n.backToHome, onPressed: () => context.go('/home')),
      children: [
        const SizedBox(height: 24),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(color: WalletColors.green.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: WalletColors.green, shape: BoxShape.circle),
                child: const Icon(Icons.check, size: 32, color: Colors.white),
              ),
            ),
          ),
        ),
        Column(children: [
          Text(l10n.txSubmitted, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: WalletColors.text)),
          const SizedBox(height: 8),
          const Text('-120.00 USDT · TRON', style: TextStyle(fontSize: 14, color: WalletColors.text2)),
        ]),
        KtCard(
          child: Column(children: [
            KtDetailRow(label: l10n.txHash, value: hashValue, mono: true),
            const SizedBox(height: 14),
            KtDetailRow(label: l10n.statusLabel, value: l10n.confirming(3, 19), valueColor: WalletColors.accent),
          ]),
        ),
      ],
    );
  }
}

/// W15 交易详情.
class TxDetailScreen extends StatelessWidget {
  const TxDetailScreen({super.key});

  /// Demo tx hash of the displayed transaction (matches the broadcast flow).
  static const _txHash = '8f6d2c…a94e07';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(
        title: l10n.txDetailTitle,
        onBack: () => Navigator.of(context).maybePop(),
        trailing: Icons.open_in_new,
        onTrailing: () {
          Clipboard.setData(const ClipboardData(text: 'https://tronscan.org/#/transaction/$_txHash'));
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(content: Text(l10n.explorerLinkCopied)));
        },
      ),
      children: [
        Column(children: [
          Container(
            width: 56, height: 56,
            decoration: BoxDecoration(color: WalletColors.green.withValues(alpha: 0.08), shape: BoxShape.circle),
            child: const Icon(Icons.check_circle, size: 28, color: WalletColors.green),
          ),
          const SizedBox(height: 10),
          const Text('-120.00 USDT', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: WalletColors.text)),
          const SizedBox(height: 6),
          Text('${l10n.confirmedPrefix} · ${l10n.dateToday} 14:38', style: const TextStyle(fontSize: 13, color: WalletColors.text3)),
        ]),
        KtCard(
          child: Column(children: [
            KtDetailRow(label: l10n.networkRow, value: 'TRON · TRC-20'),
            const SizedBox(height: 14),
            KtDetailRow(label: l10n.recipientAddress, value: 'TWd4qCEU…nMxR38uQz', mono: true),
            const SizedBox(height: 14),
            KtDetailRow(label: l10n.networkFee, value: '13.72 TRX（\$1.91）'),
            const SizedBox(height: 14),
            KtDetailRow(label: l10n.confirmations, value: '19 / 19'),
            const SizedBox(height: 14),
            KtDetailRow(label: l10n.requestId, value: 'REQ-7F3A2C', mono: true),
          ]),
        ),
      ],
    );
  }
}

/// W30 转账身份验证 (bottom sheet). The Face ID button runs a real biometric
/// prompt through [BiometricAuth]: success proceeds, failure stays on the
/// sheet with a snackbar, and an unavailable platform (no hardware / nothing
/// enrolled / tests) proceeds like before — an honest demo shortcut, since
/// the online app has no PIN of its own to fall back to yet.
class TransferAuthSheet extends StatelessWidget {
  const TransferAuthSheet({super.key, this.auth});

  /// Injectable authenticator; defaults to [BiometricAuth.instance].
  final BiometricAuth? auth;

  Future<void> _faceId(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final outcome = await (auth ?? BiometricAuth.instance)
        .authenticate(reason: l10n.authToConfirmTransfer);
    if (!context.mounted) return;
    switch (outcome) {
      case BiometricOutcome.success:
      case BiometricOutcome.unavailable: // demo shortcut, see class comment
        context.go('/broadcast-result');
      case BiometricOutcome.failure:
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(l10n.biometricFailedRetry)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: WalletColors.text.withValues(alpha: 0.5),
      body: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          width: double.infinity,
          decoration: const BoxDecoration(color: WalletColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 36, height: 4, decoration: BoxDecoration(color: WalletColors.border, borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Container(
              width: 88, height: 88,
              decoration: BoxDecoration(color: WalletColors.accent.withValues(alpha: 0.06), shape: BoxShape.circle),
              child: const Icon(Icons.face, size: 44, color: WalletColors.accent),
            ),
            const SizedBox(height: 20),
            Text(l10n.authToConfirmTransfer, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: WalletColors.text)),
            const SizedBox(height: 8),
            Text(l10n.authEveryTransfer, style: const TextStyle(fontSize: 13, color: WalletColors.text2)),
            const SizedBox(height: 20),
            KtPrimaryButton(label: l10n.useFaceId, onPressed: () => _faceId(context)),
            const SizedBox(height: 12),
            // Demo passcode path: same simulated auth success as Face ID.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => context.go('/broadcast-result'),
              child: Text(l10n.usePasscode, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: WalletColors.text2)),
            ),
          ]),
        ),
      ),
    );
  }
}

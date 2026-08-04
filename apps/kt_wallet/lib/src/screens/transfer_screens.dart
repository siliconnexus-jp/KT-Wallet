import 'dart:async';
import 'dart:io';

import 'package:airgap_protocol/airgap_protocol.dart';
import 'package:chains/chains.dart';
import 'package:chains/rpc.dart' show RpcRejectionKind;
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:wallet_data/wallet_data.dart'
    show
        Contact,
        EvmNonceConflict,
        SignMode,
        Transaction,
        TxCheckOutcome,
        TxDirection,
        TxOperationKind,
        TxReplacementKind,
        TxStatus;

import '../../l10n/app_localizations.dart';
import 'home_screen.dart' show tokenRowMeta;
import '../market/balance_service.dart' show BalanceService, BalanceStatus;
import '../market/asset_ref.dart' show AssetDeployment, AssetRef, chainOf;
import '../market/explorer_links.dart' show explorerTxUrl;
import '../market/history_service.dart' show ChainTxRecord, ChainTxStatus;
import '../market/gateway_client.dart'
    show GatewayTokenRisk, GatewayTokenRiskStatus;
import '../market/fiat_math.dart' show fiatValueForDisplay;
import '../market/market_scope.dart'
    show
        MarketScope,
        effectiveRpcEndpoints,
        effectiveTransactionRpcEndpoints,
        formatFiatForContext,
        prefsGatewayResolver;
import '../market/token_balance_service.dart'
    show
        TokenInfo,
        builtinTokenForNetwork,
        builtinTokensByNetworkId,
        usdcArbitrumToken,
        usdcAvalancheToken,
        usdcBaseToken,
        usdcSolanaToken,
        usdtEthToken,
        usdtTronToken;
import '../market/transaction_card.dart';
import '../market/transaction_status_service.dart';
import '../observability/experience_metrics.dart';
import '../platform/external_actions.dart';
import '../platform/media_gallery.dart';
import '../security/biometric_auth.dart';
import '../security/transaction_auth.dart';
import '../security/wallet_pin.dart';
import '../state/app_prefs.dart' show AppPrefsScope, AuthMethod;
import '../state/developer_mode.dart';
import '../state/flutter_test_env.dart' show isFlutterTestEnv;
import '../state/networks.dart' show Network, NetworkScope;
import '../transfer/airgap_codec.dart';
import '../transfer/broadcast_service.dart';
import '../transfer/chain_params_service.dart';
import '../transfer/local_transfer_service.dart';
import '../transfer/frame_scan.dart';
import '../transfer/recipient_risk.dart';
import '../transfer/transaction_confirmation_service.dart';
import '../transfer/transfer_error_localization.dart';
import '../transfer/transfer_draft.dart';
import '../widgets/scan_viewfinder.dart';
import '../widgets/pin_pad.dart';
import '../widgets/token_icon.dart';
import '../state/wallet_scope.dart';
import '../wallets/wallet_model.dart';

bool _isEvmCoinName(String coin) =>
    coin == 'eth' ||
    coin == 'polygon' ||
    coin == 'base' ||
    coin == 'arbitrum' ||
    coin == 'avalanche' ||
    coin == 'bnb';

Future<void> _persistAirgapTransaction(
  BuildContext context,
  TransferSession session,
  TxStatus status, {
  String? hash,
  SignRequest? requestOverride,
}) async {
  final draft = session.draft;
  final request = requestOverride ?? session.request;
  final wallet = WalletScope.of(context).current;
  if (draft == null || request == null || wallet == null) return;
  // Do not publish the generated id to the in-memory session until the row is
  // durable. A failed first write must not leave a phantom transaction id that
  // a later request (with a different reqId) would accidentally reuse.
  final existingId = session.localTransactionId;
  final id = existingId ?? 'airgap_${request.reqIdHex.toLowerCase()}';
  await WalletScope.of(context).saveOutgoingTransaction(
    id: id,
    reqId: request.reqIdHex,
    coin: rpcCoinForChain(draft.chain),
    // The network instance this request was built for — the row must record
    // WHICH chain instance it belongs to, not just the protocol family.
    networkId: NetworkScope.of(context).activeFor(draft.chain).id,
    contract: draft.tokenContract,
    operation: draft.operation == TxOperation.approvalRevoke
        ? TxOperationKind.approvalRevoke
        : TxOperationKind.transfer,
    from: addressForChain(wallet.addresses, draft.chain),
    to: draft.recipient,
    amountRaw: draft.amount.raw.toString(),
    hash: hash,
    status: status,
    signMode: SignMode.airgap,
    createdAt: request.createdAt * 1000,
    broadcastAt:
        (status == TxStatus.submitted && hash != null) ||
            status == TxStatus.pending ||
            status == TxStatus.failed ||
            status == TxStatus.dropped
        ? DateTime.now().millisecondsSinceEpoch
        : null,
    referenceBlockHeight: session.referenceBlockHeight,
    expiresAt: session.expiresAt,
    lastValidBlockHeight: session.lastValidBlockHeight,
  );
  session.localTransactionId ??= id;
}

bool get _isFlutterTest => isFlutterTestEnv;

Color _chainDot(Chain chain) => switch (chain) {
  Chain.ethereum => ChainColors.ethereum,
  Chain.polygon => ChainColors.polygon,
  Chain.base => const Color(0xFF0052FF),
  Chain.arbitrum => const Color(0xFF28A0F0),
  Chain.avalanche => const Color(0xFFE84142),
  Chain.bnb => const Color(0xFFF3BA2F),
  Chain.tron => ChainColors.tron,
  Chain.solana => ChainColors.solana,
};

/// Spot USD price of ONE unit of the transferred asset, or null when it is
/// genuinely unavailable: no market scope, no successful price fetch yet, an
/// unpegged token with no feed, or a testnet (amounts there are real, market
/// prices are not). Callers render the codebase's honest `--` for null — a
/// price is never invented, and there is no 1:1 USD peg anywhere.
double? _unitPriceUsd(
  BuildContext context, {
  required Chain chain,
  required String symbol,
  required String? tokenContract,
}) {
  if (NetworkScope.maybeOf(context)?.activeFor(chain).isTestnet ?? false) {
    return null;
  }
  final market = MarketScope.maybeOf(context);
  final coin = rpcCoinForChain(chain);
  if (tokenContract != null) {
    return market?.tokenPriceUsdFor(coin, symbol);
  }
  return market?.priceUsd(coin);
}

/// Selected-fiat value, or `--` when either the USD quote or FX rate is absent.
String _fiatText(BuildContext context, double? value) =>
    formatFiatForContext(context, value);

/// The fiat value of [amount] at [unitPrice], or null when either is unknown.
/// Display-only double math (the same convention as [MarketController]).
double? _fiatValue(Amount? amount, double? unitPrice) {
  return fiatValueForDisplay(amount, unitPrice);
}

String _chainTxStatusLabel(AppLocalizations l10n, ChainTxStatus status) =>
    switch (status) {
      ChainTxStatus.confirmed => l10n.txStatusConfirmed,
      ChainTxStatus.failed => l10n.txStatusFailed,
      ChainTxStatus.pending => l10n.txStatusPending,
      ChainTxStatus.unknown => l10n.txStatusUnknown,
    };

Color _chainTxStatusColor(ChainTxStatus status) => switch (status) {
  ChainTxStatus.confirmed => WalletColors.green,
  ChainTxStatus.failed => WalletColors.red,
  ChainTxStatus.pending => WalletColors.accent,
  ChainTxStatus.unknown => WalletColors.text3,
};

TransactionCardTone _chainTxCardTone(ChainTxStatus status) => switch (status) {
  ChainTxStatus.confirmed => TransactionCardTone.success,
  ChainTxStatus.failed => TransactionCardTone.failed,
  ChainTxStatus.pending => TransactionCardTone.pending,
  ChainTxStatus.unknown => TransactionCardTone.neutral,
};

Widget _amberWarn(String text) => Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(
    color: WalletColors.amber.withValues(alpha: 0.08),
    borderRadius: BorderRadius.circular(12),
  ),
  child: Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Icon(
        Icons.warning_amber_rounded,
        size: 16,
        color: WalletColors.amber,
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: Color(0xFF7A4E00),
          ),
        ),
      ),
    ],
  ),
);

/// W4 转账输入. Live: recipient address is validated against the token's chain
/// (rejecting mispastes and wrong-network addresses) and the amount is parsed
/// with the tested [Amount] type and checked against the available balance.
class TransferInputScreen extends StatefulWidget {
  const TransferInputScreen({super.key, this.asset});

  /// The asset to send, when the caller already knows it — arriving from a
  /// token detail page. The symbol is then FIXED: the only thing the picker
  /// offers is that symbol's other chains.
  ///
  /// Null from the home Send button, which is the one legitimate "choose what
  /// to send" entry point and keeps the full asset list.
  final AssetRef? asset;

  @override
  State<TransferInputScreen> createState() => _TransferInputScreenState();
}

/// A demo asset selectable on the transfer screen (mirrors the home list).
class _TransferAsset {
  const _TransferAsset(
    this.symbol,
    this.network,
    this.networkName,
    this.chain,
    this.decimals,
    this.available,
    this.availableLabel,
    this.color,
    this.initial, {
    this.contract,
    this.tokenProgram,
    this.supported = true,
  });
  final String symbol, network, networkName;
  final Chain chain;
  final int decimals;
  final String available, availableLabel;
  final Color color;
  final String initial;

  /// Token contract for token assets; null for native coins.
  final String? contract;
  final String? tokenProgram;
  final bool supported;

  factory _TransferAsset.native({
    required String symbol,
    required String network,
    required String networkName,
    required Coin coin,
    required String available,
    required String availableLabel,
    required Color color,
    required String initial,
  }) => _TransferAsset(
    symbol,
    network,
    networkName,
    chainOf(coin),
    BalanceService.decimalsFor[coin]!,
    available,
    availableLabel,
    color,
    initial,
  );

  factory _TransferAsset.token(
    TokenInfo token, {
    required String network,
    required String networkName,
    required String available,
    required String availableLabel,
    required Color color,
    required String initial,
  }) => _TransferAsset(
    token.symbol,
    network,
    networkName,
    chainOf(token.chain),
    token.decimals,
    available,
    availableLabel,
    color,
    initial,
    contract: token.contract,
    tokenProgram: token.tokenProgram,
  );

  Amount get availableAmount =>
      Amount.parse(available, decimals, symbol: symbol);

  _TransferAsset withAvailable(String value) => _TransferAsset(
    symbol,
    network,
    networkName,
    chain,
    decimals,
    value,
    value,
    color,
    initial,
    contract: contract,
    tokenProgram: tokenProgram,
    supported: supported,
  );

  /// Fail-closed state used by the live app before a wallet-scoped market
  /// snapshot exists. The parsable raw value is zero (so Max/Next cannot
  /// spend invented funds), while the UI label remains honestly unavailable.
  _TransferAsset withUnavailableBalance() => _TransferAsset(
    symbol,
    network,
    networkName,
    chain,
    decimals,
    '0',
    '--',
    color,
    initial,
    contract: contract,
    tokenProgram: tokenProgram,
    supported: supported,
  );

  _TransferAsset forNetwork(Network activeNetwork) {
    if (contract == null) {
      return _TransferAsset(
        symbol,
        activeNetwork.name,
        activeNetwork.name,
        chain,
        BalanceService.decimalsFor[rpcCoinForChain(chain)]!,
        available,
        availableLabel,
        color,
        initial,
      );
    }

    final token = builtinTokenForNetwork(
      networkId: activeNetwork.id,
      chain: rpcCoinForChain(chain),
      symbol: symbol,
    );
    if (token == null) {
      return _TransferAsset(
        symbol,
        activeNetwork.name,
        activeNetwork.name,
        chain,
        decimals,
        '0',
        '0',
        color,
        initial,
        contract: contract,
        tokenProgram: tokenProgram,
        supported: false,
      );
    }
    return _TransferAsset.token(
      token,
      network: '${activeNetwork.name} · ${_tokenStandard(chain)}',
      networkName: activeNetwork.name,
      available: available,
      availableLabel: availableLabel,
      color: color,
      initial: initial,
    );
  }

  static String _tokenStandard(Chain chain) => switch (chain) {
    Chain.tron => 'TRC-20',
    Chain.solana => 'SPL',
    _ => 'ERC-20',
  };
}

class _TransferInputScreenState extends State<TransferInputScreen> {
  static final _assets = [
    _TransferAsset.token(
      usdtTronToken,
      network: 'TRON · TRC-20',
      networkName: 'TRON',
      available: '3120.00',
      availableLabel: '3,120.00',
      color: const Color(0xFF26A17B),
      initial: '₮',
    ),
    _TransferAsset.native(
      symbol: 'ETH',
      network: 'Ethereum',
      networkName: 'Ethereum',
      coin: Coin.eth,
      available: '0.0842',
      availableLabel: '0.0842',
      color: const Color(0xFF627EEA),
      initial: 'Ξ',
    ),
    _TransferAsset.token(
      usdtEthToken,
      network: 'Ethereum · ERC-20',
      networkName: 'Ethereum',
      available: '100.00',
      availableLabel: '100.00',
      color: const Color(0xFF26A17B),
      initial: '₮',
    ),
    _TransferAsset.native(
      symbol: 'SOL',
      network: 'Solana',
      networkName: 'Solana',
      coin: Coin.solana,
      available: '0.531',
      availableLabel: '0.531',
      color: const Color(0xFF9945FF),
      initial: '◎',
    ),
    _TransferAsset.token(
      usdcSolanaToken,
      network: 'Solana · SPL',
      networkName: 'Solana',
      available: '100.00',
      availableLabel: '100.00',
      color: const Color(0xFF2775CA),
      initial: r'$',
    ),
    _TransferAsset.native(
      symbol: 'ETH',
      network: 'Base',
      networkName: 'Base',
      coin: Coin.base,
      available: '0.1',
      availableLabel: '0.1',
      color: const Color(0xFF0052FF),
      initial: 'B',
    ),
    _TransferAsset.token(
      usdcBaseToken,
      network: 'Base · ERC-20',
      networkName: 'Base',
      available: '100.00',
      availableLabel: '100.00',
      color: const Color(0xFF2775CA),
      initial: r'$',
    ),
    _TransferAsset.native(
      symbol: 'ETH',
      network: 'Arbitrum One',
      networkName: 'Arbitrum One',
      coin: Coin.arbitrum,
      available: '0.1',
      availableLabel: '0.1',
      color: const Color(0xFF28A0F0),
      initial: 'A',
    ),
    _TransferAsset.token(
      usdcArbitrumToken,
      network: 'Arbitrum One · ERC-20',
      networkName: 'Arbitrum One',
      available: '100.00',
      availableLabel: '100.00',
      color: const Color(0xFF2775CA),
      initial: r'$',
    ),
    _TransferAsset.native(
      symbol: 'AVAX',
      network: 'Avalanche C-Chain',
      networkName: 'Avalanche C-Chain',
      coin: Coin.avalanche,
      available: '1.0',
      availableLabel: '1.0',
      color: const Color(0xFFE84142),
      initial: 'A',
    ),
    _TransferAsset.token(
      usdcAvalancheToken,
      network: 'Avalanche C-Chain · ERC-20',
      networkName: 'Avalanche C-Chain',
      available: '100.00',
      availableLabel: '100.00',
      color: const Color(0xFF2775CA),
      initial: r'$',
    ),
  ];
  int _assetIndex = 0;
  bool _liveInputInitialized = false;

  /// True when the caller already decided WHAT to send. The picker then only
  /// offers that symbol's other chains — arriving from the USDT page and
  /// finding ETH and USDC in the dropdown is how a user sends the wrong coin.
  bool get _assetLocked => widget.asset != null;

  /// The rows the picker may switch between: this symbol's deployments when
  /// locked, the full list when the user came from the home Send button.
  List<_TransferAsset> get _options {
    final asset = widget.asset;
    if (asset == null) return _assets;
    return [for (final at in asset.group) _refAsset(asset, at)];
  }

  /// A transfer row for one deployment of the incoming asset. Balance is left
  /// at zero here; [_assetAt] fills in the live figure the same way it does
  /// for the built-in list.
  static _TransferAsset _refAsset(AssetRef ref, AssetDeployment at) {
    final (color, glyph) =
        tokenRowMeta[ref.symbol] ??
        (WalletColors.accent, ref.symbol.substring(0, 1));
    return _TransferAsset(
      ref.symbol,
      at.network,
      at.network,
      chainOf(at.coin),
      at.decimals,
      '0',
      '0',
      color,
      glyph,
      contract: at.contract,
      tokenProgram: at.tokenProgram,
    );
  }

  @override
  void initState() {
    super.initState();
    // Open on the chain the caller was looking at, not on index 0.
    _assetIndex = widget.asset?.chainIndex ?? 0;
  }

  _TransferAsset _assetAt(int index) {
    final options = _options;
    final selected = options[index.clamp(0, options.length - 1)];
    final network = NetworkScope.maybeOf(context)?.activeFor(selected.chain);
    final networkAsset = network == null
        ? selected
        : selected.forNetwork(network);
    final market = MarketScope.maybeOf(context);
    // A missing scope means a gallery/golden fixture and retains the design
    // values. A mounted production scope must never expose those fixture
    // balances while its first wallet-scoped refresh is still in flight.
    final wallet = WalletScope.of(context).current;
    if (market == null) return networkAsset;
    if (!market.hasRefreshed ||
        wallet == null ||
        !wallet.addresses.hasExpandedEvm) {
      return networkAsset.withUnavailableBalance();
    }

    final result = networkAsset.contract == null
        ? market.balanceFor(switch (networkAsset.chain) {
            Chain.ethereum => Coin.eth,
            Chain.polygon => Coin.polygon,
            Chain.base => Coin.base,
            Chain.arbitrum => Coin.arbitrum,
            Chain.avalanche => Coin.avalanche,
            Chain.bnb => Coin.bnb,
            Chain.tron => Coin.tron,
            Chain.solana => Coin.solana,
          })
        : market.tokens
              .where(
                (token) =>
                    token.chain ==
                        switch (networkAsset.chain) {
                          Chain.ethereum => Coin.eth,
                          Chain.polygon => Coin.polygon,
                          Chain.base => Coin.base,
                          Chain.arbitrum => Coin.arbitrum,
                          Chain.avalanche => Coin.avalanche,
                          Chain.bnb => Coin.bnb,
                          Chain.tron => Coin.tron,
                          Chain.solana => Coin.solana,
                        } &&
                    token.contract.toLowerCase() ==
                        networkAsset.contract!.toLowerCase(),
              )
              .map((token) => market.tokenBalanceFor(token.id))
              .firstOrNull;
    final amount = result?.amount;
    return networkAsset.withAvailable(
      result?.status == BalanceStatus.ok && amount != null
          ? amount.format()
          : '0',
    );
  }

  _TransferAsset get _asset {
    return _assetAt(_assetIndex);
  }

  /// The recipient and amount fields start EMPTY. They are only seeded with
  /// the Pencil design literals when the screen renders with NO market scope
  /// — the standalone design-gallery / golden capture — so those recordings
  /// stay byte-identical.
  ///
  /// This used to be the other way round (seeded by default, cleared only for
  /// wallets with expanded EVM addresses), which meant a paired watch wallet
  /// never cleared them and the user was shown a pre-filled, `Addresses
  /// .validate`-passing recipient that is actually the mainnet USDT CONTRACT,
  /// plus an amount of 120.00. Funds sent there are unrecoverable. Never
  /// pre-fill a recipient the user did not type.
  final _addrController = TextEditingController();
  final _amountController = TextEditingController();
  Contact? _selectedContact;
  List<KnownRecipientAddress> _knownRecipients = const [];
  bool _recipientRiskRequested = false;
  String? _acknowledgedRiskAddress;
  int _fee = 1;

  /// True in the real app (any live surface mounts a [MarketScope]); false
  /// only for the standalone gallery/golden rendering of this screen.
  bool get _isLiveContext => MarketScope.maybeOf(context) != null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_liveInputInitialized) {
      _liveInputInitialized = true;
      if (!_isLiveContext) {
        _addrController.text = _demoRecipient;
        _amountController.text = _demoAmount;
      }
    }
    if (_isLiveContext && !_recipientRiskRequested) {
      _recipientRiskRequested = true;
      unawaited(_loadRecipientRiskSources());
    }
  }

  Future<void> _loadRecipientRiskSources() async {
    final controller = WalletScope.of(context);
    final values = await Future.wait<Object>([
      controller.loadContacts(),
      controller.localTransactions(),
    ]);
    if (!mounted) return;
    final contacts = values[0] as List<Contact>;
    final transactions = values[1] as List<Transaction>;
    final known = <KnownRecipientAddress>[
      for (final contact in contacts)
        KnownRecipientAddress(address: contact.address, label: contact.name),
      for (final wallet in controller.wallets)
        for (final coin in Coin.values)
          KnownRecipientAddress(
            address: wallet.addresses.forCoin(coin),
            label: wallet.name,
          ),
      for (final transaction in transactions)
        KnownRecipientAddress(
          address: transaction.direction == TxDirection.outgoing
              ? transaction.toAddr
              : transaction.fromAddr,
          label: truncateMiddle(
            transaction.direction == TxDirection.outgoing
                ? transaction.toAddr
                : transaction.fromAddr,
            head: 8,
            tail: 8,
          ),
        ),
    ];
    setState(() => _knownRecipients = known);
  }

  /// Design-demo literals — gallery/goldens ONLY (see [_addrController]).
  static const _demoRecipient = 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t';
  static const _demoAmount = '120.00';

  @override
  void dispose() {
    _addrController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  AddressValidation get _addrCheck =>
      Addresses.validate(_asset.chain, _addrController.text.trim());

  RecipientLookalikeRisk? get _recipientRisk => detectRecipientLookalike(
    chain: _asset.chain,
    candidate: _addrController.text,
    knownAddresses: _knownRecipients,
  );

  /// The identity badge is shown only while the field still contains exactly
  /// the address chosen from the book and that address remains compatible
  /// with the active chain. A manual edit can never leave a stale name beside
  /// a different recipient.
  Contact? get _visibleContact {
    final contact = _selectedContact;
    if (contact == null ||
        _addrController.text.trim() != contact.address ||
        !_addrCheck.isValid) {
      return null;
    }
    return contact;
  }

  /// Returns the parsed amount if it is valid and within balance, else null.
  Amount? get _amount {
    if (!_asset.supported) return null;
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

  /// Strips leading zeros as the user types: tapping Max writes `0`, and the
  /// next keystroke used to leave `01.5` sitting in the field.
  ///
  /// `0.` and a lone `0` are left alone — those are prefixes of a number the
  /// user is still typing, not junk.
  void _normalizeAmount() {
    final text = _amountController.text;
    final trimmed = text.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (trimmed == text) return;
    _amountController.value = _amountController.value.copyWith(
      text: trimmed,
      selection: TextSelection.collapsed(
        offset:
            (_amountController.selection.baseOffset -
                    (text.length - trimmed.length))
                .clamp(0, trimmed.length),
      ),
      composing: TextRange.empty,
    );
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

  /// The `≈ …` line under the amount. Live: the entered amount valued at the
  /// asset's REAL spot price, or `--` when no price is available — never the
  /// old 1:1 `$<amount>` peg, which made 0.5 ETH read as "$0.5". Without a
  /// market scope (gallery/goldens) the design literal renders unchanged.
  String _amountFiatText() {
    final text = _amountController.text.trim();
    if (!_isLiveContext) return '\$${text.isEmpty ? '0.00' : text}';
    Amount? parsed;
    if (text.isNotEmpty) {
      try {
        parsed = Amount.parse(text, _asset.decimals, symbol: _asset.symbol);
      } on AmountError {
        parsed = null;
      }
    } else {
      parsed = Amount(raw: BigInt.zero, decimals: _asset.decimals);
    }
    return _fiatText(
      context,
      _fiatValue(
        parsed,
        _unitPriceUsd(
          context,
          chain: _asset.chain,
          symbol: _asset.symbol,
          tokenContract: _asset.contract,
        ),
      ),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = (data?.text ?? '').trim();
    if (text.isNotEmpty) {
      setState(() {
        _selectedContact = null;
        _acknowledgedRiskAddress = null;
        _addrController.text = text;
      });
    }
  }

  /// Opens the mock address scanner; a simulated scan pops with the address.
  Future<void> _scanAddress() async {
    final scanned = await context.push<String>('/scan-address');
    if (scanned != null && mounted) {
      setState(() {
        _selectedContact = null;
        _acknowledgedRiskAddress = null;
        _addrController.text = scanned;
      });
    }
  }

  /// Opens the address book with only recipients whose address format is
  /// valid on the active chain. Compatibility is intentionally based on the
  /// address family rather than the contact's saved label: one EVM address is
  /// usable on Ethereum, Arbitrum, Base, Polygon, Avalanche and BNB, while
  /// TRON and Solana remain isolated. The current wallet's own recipient is
  /// omitted, including a saved contact that resolves to the same address.
  /// Saved contacts come first; other local wallets remain convenient
  /// shortcuts below them.
  Future<void> _pickContact() async {
    final controller = WalletScope.of(context);
    final contacts = await controller.loadContacts();
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    final current = controller.current;
    final currentAddress = current == null
        ? ''
        : addressForChain(current.addresses, _asset.chain).trim();
    final localWallets =
        [
              for (final wallet in controller.wallets)
                if (wallet.id != current?.id)
                  Contact(
                    id: 'local-wallet:${wallet.id}:${_asset.chain.name}',
                    name: wallet.name,
                    address: addressForChain(wallet.addresses, _asset.chain),
                    chain: _asset.chain.name,
                    createdAt: 0,
                  ),
            ]
            .where(
              (entry) =>
                  entry.address.trim().isNotEmpty &&
                  !_sameRecipientAddress(entry.address, currentAddress),
            )
            .toList();
    final compatibleContacts = contacts
        .where(
          (contact) =>
              Addresses.validate(_asset.chain, contact.address).isValid &&
              !_sameRecipientAddress(contact.address, currentAddress),
        )
        .toList();
    final compatible = [...compatibleContacts, ...localWallets];

    final selected = await showModalBottomSheet<Contact>(
      context: context,
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: WalletColors.border,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Text(
                      l10n.addressBookTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: WalletColors.text,
                      ),
                    ),
                    const Spacer(),
                    ChainIcon(chain: _asset.chain, size: 20),
                    const SizedBox(width: 7),
                    Text(
                      _asset.networkName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: WalletColors.text2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  l10n.compatibleContactsHint(_asset.networkName),
                  style: const TextStyle(
                    fontSize: 12,
                    color: WalletColors.text3,
                  ),
                ),
                const SizedBox(height: 14),
                if (compatible.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Column(
                        children: [
                          const Icon(
                            Icons.contact_page_outlined,
                            size: 30,
                            color: WalletColors.text3,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            l10n.noCompatibleContacts(_asset.networkName),
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 13,
                              color: WalletColors.text3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (var i = 0; i < compatible.length; i++) ...[
                    if (i > 0)
                      const Divider(height: 1, color: WalletColors.border),
                    ListTile(
                      key: ValueKey('transfer-contact-${compatible[i].id}'),
                      contentPadding: EdgeInsets.zero,
                      leading: KtAvatar(
                        color: const Color(0xFFF2F4F7),
                        initial: compatible[i].name.characters.first
                            .toUpperCase(),
                        size: 38,
                      ),
                      title: Text(
                        compatible[i].name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: WalletColors.text,
                        ),
                      ),
                      subtitle: Text(
                        truncateMiddle(compatible[i].address, head: 9, tail: 9),
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: KtFonts.mono,
                          color: WalletColors.text3,
                        ),
                      ),
                      trailing: compatible[i].id.startsWith('local-wallet:')
                          ? NetworkBadge(
                              label:
                                  compatible[i].id.contains(
                                    ':${controller.current?.id}:',
                                  )
                                  ? l10n.currentWalletLabel
                                  : l10n.localWalletLabel,
                              dotColor: WalletColors.accent,
                            )
                          : const Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: WalletColors.text3,
                            ),
                      onTap: () => Navigator.of(ctx).pop(compatible[i]),
                    ),
                  ],
              ],
            ),
          ),
        ),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        _selectedContact = selected;
        _acknowledgedRiskAddress = null;
        _addrController.text = selected.address;
      });
    }
  }

  bool _sameRecipientAddress(String left, String right) {
    final a = left.trim();
    final b = right.trim();
    if (a.isEmpty || b.isEmpty) return false;
    final isEvm = switch (_asset.chain) {
      Chain.ethereum ||
      Chain.polygon ||
      Chain.base ||
      Chain.arbitrum ||
      Chain.avalanche ||
      Chain.bnb => true,
      _ => false,
    };
    return isEvm ? a.toLowerCase() == b.toLowerCase() : a == b;
  }

  /// Opens the custom fee screen and maps its result back onto the segmented
  /// tier selection. Reachable ONLY from the standalone gallery rendering —
  /// see the entry point in [build] and [FeeSelectScreen]'s own doc.
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: WalletColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Text(
                      _assetLocked ? l10n.chooseNetwork : l10n.selectAsset,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: WalletColors.text,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < _options.length; i++)
                ListTile(
                  // Locked to one symbol: the row identifies the CHAIN, so it
                  // carries the chain's logo and name. Unlocked, it identifies
                  // the asset.
                  leading: _assetLocked
                      ? ChainIcon(chain: _assetAt(i).chain, size: 36)
                      : TokenIcon(
                          symbol: _assetAt(i).symbol,
                          size: 36,
                          fallbackColor: _assetAt(i).color,
                          fallbackInitial: _assetAt(i).initial,
                        ),
                  title: Text(
                    _assetLocked
                        ? _assetAt(i).networkName
                        : switch (_assetAt(i).chain) {
                            Chain.base ||
                            Chain.arbitrum ||
                            Chain.avalanche ||
                            Chain.bnb =>
                              '${_assetAt(i).symbol} · ${_assetAt(i).networkName}',
                            _ => _assetAt(i).symbol,
                          },
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: WalletColors.text,
                    ),
                  ),
                  subtitle: Text(
                    _assetLocked
                        ? l10n.availableBalance(
                            _assetAt(i).availableLabel,
                            _assetAt(i).symbol,
                          )
                        : '${_assetAt(i).network} · ${l10n.availableBalance(_assetAt(i).availableLabel, _assetAt(i).symbol)}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: WalletColors.text3,
                    ),
                  ),
                  trailing: i == _assetIndex
                      ? const Icon(
                          Icons.check,
                          size: 20,
                          color: WalletColors.accent,
                        )
                      : null,
                  onTap: () {
                    setState(() {
                      _assetIndex = i;
                      _acknowledgedRiskAddress = null;
                    });
                    Navigator.of(ctx).pop();
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final largeText = MediaQuery.textScalerOf(context).scale(13) >= 20;
    final isHot = WalletScope.of(context).current is HotWallet;
    final addrCheck = _addrCheck;
    final selectedContact = _visibleContact;
    final recipientRisk = _recipientRisk;
    final riskAcknowledged =
        recipientRisk == null ||
        _acknowledgedRiskAddress == recipientRisk.candidate;
    final canProceed = addrCheck.isValid && riskAcknowledged && _amount != null;
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(
        title: l10n.actionSend,
        onBack: () => Navigator.of(context).maybePop(),
        trailing: Icons.qr_code_scanner,
        trailingTooltip: l10n.scanAddressTitle,
        onTrailing: _scanAddress,
      ),
      bottom: KtPrimaryButton(
        label: l10n.actionNext,
        onPressed: canProceed
            ? () {
                // Hand the entered transfer to the downstream screens. Starting
                // a new draft invalidates any earlier request/result.
                TransferSessionScope.maybeOf(context)?.begin(
                  TransferDraft(
                    symbol: _asset.symbol,
                    networkLabel: _asset.network,
                    chain: _asset.chain,
                    recipient:
                        addrCheck.normalized ?? _addrController.text.trim(),
                    amount: _amount!,
                    feeTier: _fee,
                    tokenContract: _asset.contract,
                    tokenProgram: _asset.tokenProgram,
                  ),
                );
                context.push(isHot ? '/confirm-hot' : '/confirm-watch');
              }
            : null,
      ),
      children: [
        KtCard(
          padding: const EdgeInsets.all(14),
          child: GestureDetector(
            key: const ValueKey('transfer-asset'),
            behavior: HitTestBehavior.opaque,
            // Nothing to choose when the asset is locked to a single chain —
            // an inert row that still shows a chevron just invites a tap that
            // does nothing.
            onTap: _options.length > 1 ? _pickAsset : null,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 48),
              child: Row(
                children: [
                  TokenIcon(
                    symbol: _asset.symbol,
                    size: 36,
                    fallbackColor: _asset.color,
                    fallbackInitial: _asset.initial,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _asset.symbol,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: WalletColors.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _asset.network,
                          style: const TextStyle(
                            fontSize: 12,
                            color: WalletColors.text2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_options.length > 1)
                    const Icon(
                      Icons.keyboard_arrow_down,
                      size: 18,
                      color: WalletColors.text3,
                    ),
                ],
              ),
            ),
          ),
        ),
        KtCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.recipientAddress,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: WalletColors.text2,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addrController,
                      onChanged: (value) => setState(() {
                        _acknowledgedRiskAddress = null;
                        if (_selectedContact?.address != value.trim()) {
                          _selectedContact = null;
                        }
                      }),
                      autocorrect: false,
                      enableSuggestions: false,
                      maxLines: null,
                      style: const TextStyle(
                        fontSize: 14,
                        fontFamily: KtFonts.mono,
                        color: WalletColors.text,
                      ),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: l10n.pasteOrEnterAddress,
                        hintStyle: const TextStyle(color: WalletColors.text3),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Semantics(
                    button: true,
                    label: l10n.addressBookTitle,
                    child: GestureDetector(
                      key: const ValueKey('transfer-address-book'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _pickContact,
                      child: Tooltip(
                        message: l10n.addressBookTitle,
                        child: const SizedBox.square(
                          dimension: 48,
                          child: Icon(
                            Icons.contacts_outlined,
                            size: 18,
                            color: WalletColors.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: l10n.pasteOrEnterAddress,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _paste,
                      child: const SizedBox.square(
                        dimension: 48,
                        child: Icon(
                          Icons.content_paste,
                          size: 18,
                          color: WalletColors.accent,
                        ),
                      ),
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: l10n.scanAddressTitle,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _scanAddress,
                      child: const SizedBox.square(
                        dimension: 48,
                        child: Icon(
                          Icons.qr_code_scanner,
                          size: 18,
                          color: WalletColors.accent,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (selectedContact != null) ...[
                Semantics(
                  label:
                      '${selectedContact.id.startsWith('local-wallet:') ? l10n.localWalletLabel : l10n.addressBookTitle}: '
                      '${selectedContact.name}',
                  child: Container(
                    key: const ValueKey('transfer-selected-contact'),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: WalletColors.accent.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.person_outline_rounded,
                          size: 16,
                          color: WalletColors.accent,
                        ),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            selectedContact.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: WalletColors.text,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.check_circle,
                          size: 15,
                          color: WalletColors.green,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (_addrController.text.trim().isEmpty)
                Text(
                  l10n.enterChainAddress(_asset.networkName),
                  style: const TextStyle(
                    fontSize: 12,
                    color: WalletColors.text3,
                  ),
                )
              else if (addrCheck.isValid)
                Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      size: 14,
                      color: WalletColors.green,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.addressValidOn(_asset.networkName),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: WalletColors.green,
                        ),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 14,
                      color: WalletColors.red,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        addrCheck.reason ?? l10n.addressInvalid,
                        style: const TextStyle(
                          fontSize: 12,
                          color: WalletColors.red,
                        ),
                      ),
                    ),
                  ],
                ),
              if (recipientRisk != null) ...[
                const SizedBox(height: 12),
                Container(
                  key: const ValueKey('recipient-lookalike-warning'),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7E6),
                    border: Border.all(color: const Color(0xFFF6C453)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            size: 18,
                            color: Color(0xFFB26A00),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l10n.recipientLookalikeWarning(
                                recipientRisk.known.label,
                              ),
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.45,
                                color: Color(0xFF7A4A00),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        key: const ValueKey('recipient-lookalike-acknowledge'),
                        onPressed: riskAcknowledged
                            ? null
                            : () => setState(
                                () => _acknowledgedRiskAddress =
                                    recipientRisk.candidate,
                              ),
                        icon: Icon(
                          riskAcknowledged
                              ? Icons.check_circle
                              : Icons.fact_check_outlined,
                          size: 17,
                        ),
                        label: Text(l10n.recipientLookalikeReview),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
        KtCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    l10n.amountLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: WalletColors.text2,
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: l10n.max,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(
                        () => _amountController.text = _asset.available,
                      ),
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: WalletColors.accent.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              l10n.max,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: WalletColors.accent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amountController,
                      onChanged: (_) => setState(_normalizeAmount),
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: WalletColors.text,
                      ),
                      decoration: const InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: '0',
                        hintStyle: TextStyle(color: WalletColors.text3),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      _asset.symbol,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: WalletColors.text2,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Builder(
                    builder: (_) {
                      final amountError = _amountErrorFor(l10n);
                      return Text(
                        amountError ?? '≈ ${_amountFiatText()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: amountError == null
                              ? WalletColors.text3
                              : WalletColors.red,
                        ),
                      );
                    },
                  ),
                  Flexible(
                    child: Text(
                      l10n.availableBalance(
                        _asset.availableLabel,
                        _asset.symbol,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: const TextStyle(
                        fontSize: 12,
                        color: WalletColors.text3,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        KtCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Builder(
                builder: (context) {
                  final feeLabel = Text(
                    l10n.networkFee,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: WalletColors.text2,
                    ),
                  );
                  // W31 serves a hardcoded TRON tier list with invented fiat
                  // to every chain. Rather than lie about the fee a live
                  // transfer will pay, it is unreachable outside the gallery:
                  // the segmented control below selects the same tier index,
                  // and that index resolves to the chain's REAL fee tier
                  // (ChainParamsService.tierFor) on the confirm screen and in
                  // the signed transaction.
                  final customFee = Semantics(
                    button: true,
                    label: l10n.feeCustom,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _customFee,
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: Text(
                            l10n.feeCustom,
                            style: const TextStyle(
                              fontSize: 12,
                              color: WalletColors.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                  final children = [feeLabel, if (!_isLiveContext) customFee];
                  return largeText
                      ? Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 12,
                          runSpacing: 4,
                          children: children,
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: children,
                        );
                },
              ),
              const SizedBox(height: 12),
              KtSegmented(
                options: [l10n.feeSlow, l10n.feeStandard, l10n.feeFast],
                selected: _fee,
                onChanged: (i) => setState(() => _fee = i),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// W31 手续费选择 — DESIGN / GALLERY ONLY.
///
/// The tier list below is a hardcoded TRON schedule with invented fiat. It is
/// deliberately NOT reachable from a live transfer (the 自定义 entry point on
/// the send screen is hidden whenever a market scope is mounted): showing a
/// TRON tier list to someone sending ETH, with a fee they will not pay, is
/// worse than not offering the screen. Live tier selection happens on the
/// segmented slow/standard/fast control, whose index resolves to the chain's
/// REAL fee tier via [EvmChainParams.tierFor]. Wiring per-chain live tiers
/// here is deferred; until then this screen only backs the gallery/goldens.
class FeeSelectScreen extends StatefulWidget {
  const FeeSelectScreen({super.key});
  @override
  State<FeeSelectScreen> createState() => _FeeSelectScreenState();
}

class _FeeSelectScreenState extends State<FeeSelectScreen> {
  int _selected = 1; // default 标准

  @override
  Widget build(BuildContext context) {
    final liveController = WalletScope.maybeOf(context);
    if (liveController != null && !liveController.allowsTestBypass) {
      return const InvalidTransferState();
    }
    final l10n = AppLocalizations.of(context);
    final tiers = [
      (l10n.feeSlow, l10n.feeEtaSlow, '6.8 TRX', r'$0.94'),
      (l10n.feeStandard, l10n.feeEtaStandard, '13.7 TRX', r'$1.90'),
      (l10n.feeFast, l10n.feeEtaFast, '27.4 TRX', r'$3.80'),
    ];
    final compactLarge =
        MediaQuery.sizeOf(context).width < 360 &&
        MediaQuery.textScalerOf(context).scale(14) >= 20;
    return KtScreen(
      navBar: KtNavBar(
        title: l10n.networkFee,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      // Pops the selected tier index so the transfer screen can mirror it in
      // its slow/standard/fast segmented control.
      bottom: KtPrimaryButton(
        label: l10n.confirmFee,
        onPressed: () => context.pop(_selected),
      ),
      children: [
        Text(
          l10n.feeExplainer,
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: WalletColors.text2,
          ),
        ),
        Column(
          children: [
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
                        color: sel
                            ? WalletColors.accent.withValues(alpha: 0.04)
                            : WalletColors.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: sel
                              ? WalletColors.accent
                              : WalletColors.border,
                          width: sel ? 1.5 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            sel
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 20,
                            color: sel
                                ? WalletColors.accent
                                : const Color(0xFFD2D7E0),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  name,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: WalletColors.text,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  eta,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: WalletColors.text3,
                                  ),
                                ),
                                if (compactLarge) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    fee,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      fontFamily: KtFonts.mono,
                                      color: WalletColors.text,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    fiat,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: WalletColors.text3,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (!compactLarge)
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  fee,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    fontFamily: KtFonts.mono,
                                    color: WalletColors.text,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  fiat,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: WalletColors.text3,
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    );
                  }(),
                ),
              ),
          ],
        ),
        _amberWarn(l10n.feeLowWarning),
      ],
    );
  }
}

/// How far the live network-fee estimate for the confirm screen has got.
enum _FeeEstimate {
  /// No live draft: the design's demo schedule backs the gallery/goldens.
  demo,

  /// Live draft, chain-state fetch in flight.
  estimating,

  /// Live draft, exact chain fee available.
  ready,

  /// Live draft, the fee could NOT be fetched — sending is blocked
  /// rather than showing a number the user would not actually pay.
  failed,
}

/// Shared confirm layout for W5 (watch) / W29 (hot).
///
/// With a live [TransferDraft] in scope every displayed field is derived from
/// the draft, and the network fee is the REAL one: `gasLimit x maxFeePerGas`
/// for the selected tier, fetched through [ChainParamsService] exactly like
/// the transaction that will actually be signed
/// (`LocalTransferService.prepareEvm` / `_buildLiveEvm`). It is never the demo
/// schedule, which used to be shown here while a completely different figure
/// was signed. Fiat comes from the real spot price and renders `--` when
/// unavailable. Without a draft (gallery / goldens) the design demo values
/// render unchanged.
class TransferConfirmScreen extends StatefulWidget {
  const TransferConfirmScreen({
    super.key,
    required this.isHot,
    this.paramsService,
    this.transferService,
    this.tokenRiskLookup,
  });

  final bool isHot;

  /// Injectable chain-params fetcher for tests; production resolves the
  /// prefs/network-aware endpoints.
  final ChainParamsService? paramsService;
  final LocalTransferService? transferService;

  /// Injectable exact network + contract risk check. Production resolves the
  /// configured KT Gateway; tests can provide deterministic safe/unsafe/
  /// unknown results without a network call.
  final Future<GatewayTokenRisk> Function(Coin chain, String contract)?
  tokenRiskLookup;

  @override
  State<TransferConfirmScreen> createState() => _TransferConfirmScreenState();
}

class _TransferConfirmScreenState extends State<TransferConfirmScreen> {
  _FeeEstimate _state = _FeeEstimate.demo;
  Amount? _networkFee;
  Amount? _rentReserve;
  EvmAssetChanges? _evmAssetChanges;
  bool _requested = false;
  bool _insufficientFunds = false;
  _TokenRiskUiState _tokenRisk = _TokenRiskUiState.notApplicable;
  Timer? _quoteRefreshTimer;

  @override
  void dispose() {
    _quoteRefreshTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    final draft = TransferSessionScope.maybeOf(context)?.draft;
    if (draft == null) return; // gallery / goldens: demo rendering
    final isEvm = switch (draft.chain) {
      Chain.ethereum ||
      Chain.polygon ||
      Chain.base ||
      Chain.arbitrum ||
      Chain.avalanche ||
      Chain.bnb => true,
      Chain.tron || Chain.solana => false,
    };
    final network = NetworkScope.maybeOf(context)?.activeFor(draft.chain);
    final chainId = network?.evmChainId ?? _defaultEvmChainId(draft.chain);
    if (isEvm && chainId == null) {
      _state = _FeeEstimate.failed;
      return;
    }
    final wallet = WalletScope.of(context).current;
    final from = wallet == null
        ? ''
        : addressForChain(wallet.addresses, draft.chain);
    final prefs = AppPrefsScope.maybeOf(context);
    final networkScope = NetworkScope.maybeOf(context);
    final quoteService =
        widget.transferService ??
        (widget.paramsService == null
            ? LocalTransferService(
                endpoints: effectiveRpcEndpoints(prefs, networkScope),
                gateway: prefsGatewayResolver(prefs),
              )
            : LocalTransferService(params: widget.paramsService));
    _state = _FeeEstimate.estimating;
    if (draft.tokenContract != null &&
        draft.operation != TxOperation.approvalRevoke) {
      _tokenRisk = _TokenRiskUiState.checking;
      final lookup = widget.tokenRiskLookup;
      unawaited(
        _checkTokenRisk(
          draft,
          lookup ??
              (chain, contract) async {
                if (_isFlutterTest) {
                  throw StateError('token risk service not injected in test');
                }
                final gateway = prefsGatewayResolver(prefs)();
                if (gateway == null) {
                  throw StateError('token risk service unavailable');
                }
                return gateway.checkTokenRisk(chain: chain, contract: contract);
              },
        ),
      );
    }
    unawaited(
      _estimate(
        quoteService,
        draft,
        from: from,
        symbol: _nativeSymbol(draft.chain),
        networkId: network?.id ?? _defaultNetworkId(draft.chain),
        evmChainId: chainId,
        expectedNetworkIdentity: network?.networkIdentity,
      ),
    );
  }

  Future<void> _checkTokenRisk(
    TransferDraft draft,
    Future<GatewayTokenRisk> Function(Coin chain, String contract) lookup,
  ) async {
    final contract = draft.tokenContract;
    if (contract == null) return;
    try {
      final result = await lookup(rpcCoinForChain(draft.chain), contract);
      if (!mounted) return;
      setState(() {
        _tokenRisk = switch (result.status) {
          GatewayTokenRiskStatus.safe => _TokenRiskUiState.verifiedIdentity,
          GatewayTokenRiskStatus.unsafe => _TokenRiskUiState.unsafe,
          GatewayTokenRiskStatus.unknown => _TokenRiskUiState.unknown,
        };
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _tokenRisk = _TokenRiskUiState.unavailable);
    }
  }

  /// Native symbol of the ACTIVE network for [chain] (POL on Polygon, AVAX on
  /// Avalanche, ETH on the ETH-denominated L2s).
  String _nativeSymbol(Chain chain) =>
      NetworkScope.maybeOf(context)?.activeFor(chain).symbol ??
      switch (chain) {
        Chain.polygon => 'POL',
        Chain.avalanche => 'AVAX',
        Chain.bnb => 'BNB',
        Chain.tron => 'TRX',
        Chain.solana => 'SOL',
        _ => 'ETH',
      };

  int? _defaultEvmChainId(Chain chain) => switch (chain) {
    Chain.ethereum => 1,
    Chain.polygon => 137,
    Chain.base => 8453,
    Chain.arbitrum => 42161,
    Chain.avalanche => 43114,
    Chain.bnb => 56,
    Chain.tron || Chain.solana => null,
  };

  String _defaultNetworkId(Chain chain) => switch (chain) {
    Chain.ethereum => 'eth-mainnet',
    Chain.polygon => 'polygon-mainnet',
    Chain.base => 'base-mainnet',
    Chain.arbitrum => 'arbitrum-mainnet',
    Chain.avalanche => 'avalanche-mainnet',
    Chain.bnb => 'bnb-mainnet',
    Chain.tron => 'tron-mainnet',
    Chain.solana => 'sol-mainnet',
  };

  /// The same two calls `prepareEvm` makes before signing, so the number shown
  /// here is the number the signed envelope carries.
  Future<void> _estimate(
    LocalTransferService service,
    TransferDraft draft, {
    required String from,
    required String symbol,
    required String networkId,
    required int? evmChainId,
    required String? expectedNetworkIdentity,
  }) async {
    final metricStopwatch = Stopwatch()..start();
    var metricSucceeded = false;
    final session = TransferSessionScope.maybeOf(context);
    session
      ?..preparedEvm = null
      ..preparedTron = null
      ..preparedSolana = null
      ..preparedNetworkId = null
      ..preparedAtMs = null;
    _insufficientFunds = false;
    _rentReserve = null;
    _evmAssetChanges = null;
    try {
      late final Amount fee;
      PreparedEvmTransfer? evm;
      EvmAssetChanges? evmAssetChanges;
      PreparedTronTransfer? tron;
      PreparedSolanaTransfer? solana;
      switch (draft.chain) {
        case Chain.ethereum:
        case Chain.polygon:
        case Chain.base:
        case Chain.arbitrum:
        case Chain.avalanche:
        case Chain.bnb:
          evm = await service.prepareEvm(
            draft: draft,
            from: from,
            evmChainId: evmChainId!,
          );
          fee = Amount(
            raw: evm.maximumFee,
            decimals: BalanceService.decimalsFor[rpcCoinForChain(draft.chain)]!,
            symbol: symbol,
          );
          evmAssetChanges = decodeEvmAssetChanges(
            prepared: evm,
            draft: draft,
            nativeDecimals:
                BalanceService.decimalsFor[rpcCoinForChain(draft.chain)]!,
            nativeSymbol: symbol,
          );
        case Chain.tron:
          tron = await service.prepareTron(
            draft: draft,
            from: from,
            expectedNetworkIdentity: expectedNetworkIdentity,
          );
          fee = Amount(
            raw: tron.maximumFeeSun,
            decimals: BalanceService.decimalsFor[Coin.tron]!,
            symbol: symbol,
          );
        case Chain.solana:
          solana = await service.prepareSolana(
            draft: draft,
            from: from,
            expectedNetworkIdentity: expectedNetworkIdentity,
          );
          fee = Amount(
            raw: solana.networkFeeLamports,
            decimals: BalanceService.decimalsFor[Coin.solana]!,
            symbol: symbol,
          );
      }
      metricSucceeded = true;
      if (!mounted) return;
      final quotedAt = DateTime.now().millisecondsSinceEpoch;
      setState(() {
        _networkFee = fee;
        _evmAssetChanges = evmAssetChanges;
        _rentReserve =
            solana == null || solana.rentDepositLamports == BigInt.zero
            ? null
            : Amount(
                raw: solana.rentDepositLamports,
                decimals: BalanceService.decimalsFor[Coin.solana]!,
                symbol: symbol,
              );
        _state = _FeeEstimate.ready;
        session
          ?..preparedEvm = evm
          ..preparedTron = tron
          ..preparedSolana = solana
          ..preparedNetworkId = networkId
          ..preparedAtMs = quotedAt
          ..referenceBlockHeight = tron?.referenceBlockHeight
          ..expiresAt = tron?.expiresAt
          ..lastValidBlockHeight = solana?.lastValidBlockHeight;
      });
      _quoteRefreshTimer?.cancel();
      _quoteRefreshTimer = Timer(TransferSession.quoteValidity, () {
        if (!mounted) return;
        setState(() => _state = _FeeEstimate.estimating);
        unawaited(
          _estimate(
            service,
            draft,
            from: from,
            symbol: symbol,
            networkId: networkId,
            evmChainId: evmChainId,
            expectedNetworkIdentity: expectedNetworkIdentity,
          ),
        );
      });
    } on TransferInsufficientFunds {
      if (!mounted) return;
      setState(() {
        _insufficientFunds = true;
        _state = _FeeEstimate.failed;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _state = _FeeEstimate.failed);
    } finally {
      ExperienceMetrics.instance.record(
        ExperienceMetricNames.transactionPrepare,
        metricStopwatch.elapsed,
        success: metricSucceeded,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isHot = widget.isHot;
    final l10n = AppLocalizations.of(context);
    final draft = TransferSessionScope.maybeOf(context)?.draft;
    final walletController = WalletScope.of(context);
    final wallet = walletController.current;
    if (draft == null &&
        WalletScope.maybeOf(context) != null &&
        !walletController.allowsTestBypass) {
      return const InvalidTransferState();
    }
    final showUnbackedWarning =
        isHot && (draft == null || (wallet is HotWallet && !wallet.backedUp));

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
      final isTestnet =
          NetworkScope.maybeOf(context)?.activeFor(draft.chain).isTestnet ??
          false;
      final from = wallet == null
          ? ''
          : addressForChain(wallet.addresses, draft.chain);
      final fee = _networkFee;
      // The chains preview type still frames the amount/addresses; the fee it
      // carries is the demo schedule, so it is deliberately NOT displayed —
      // `fee` above is the live one.
      final preview = previewForDraft(draft, from: from);
      final revokingApproval = draft.operation == TxOperation.approvalRevoke;
      headline = revokingApproval
          ? l10n.approvalRevoke
          : '-${draft.amountText}';
      fiat = revokingApproval
          ? l10n.approvalRevokeBody
          : isTestnet
          ? l10n.fiatHiddenTestnet
          : '≈ ${_fiatText(context, _fiatValue(draft.amount, _unitPriceUsd(context, chain: draft.chain, symbol: draft.symbol, tokenContract: draft.tokenContract)))}';
      networkLabel = draft.networkLabel;
      dotColor = _chainDot(draft.chain);
      fromValue =
          '${wallet?.name ?? ''} ${truncateMiddle(preview.from, head: 4, tail: 4)}'
              .trim();
      toValue = truncateMiddle(preview.to, head: 8, tail: 9);
      feeValue = switch (_state) {
        _FeeEstimate.estimating => l10n.feeEstimating,
        _FeeEstimate.failed when _insufficientFunds => l10n.insufficientBalance,
        _FeeEstimate.failed => l10n.feeUnavailable,
        _ when fee == null => '--',
        _ when isTestnet => '≈ $fee',
        _ =>
          '≈ $fee（${_fiatText(context, _fiatValue(fee, _unitPriceUsd(context, chain: draft.chain, symbol: fee.symbol, tokenContract: null)))}）',
      };
      // Total spend only adds the fee when it is a REAL one and the transfer
      // actually spends the native coin; otherwise it is the amount alone.
      final total =
          fee != null &&
              draft.operation == TxOperation.nativeTransfer &&
              draft.amount.decimals == fee.decimals
          ? draft.amount + fee
          : null;
      totalValue = revokingApproval
          ? (fee == null ? '--' : '$fee')
          : total == null
          ? draft.amountText
          : '$total';
    }
    // Every live chain must have a complete, immutable quote before signing.
    final riskPendingOrUnsafe =
        _tokenRisk == _TokenRiskUiState.checking ||
        _tokenRisk == _TokenRiskUiState.unsafe;
    final blocked =
        draft != null && (_state != _FeeEstimate.ready || riskPendingOrUnsafe);

    return KtScreen(
      gap: 16,
      navBar: KtNavBar(
        title: l10n.confirmTransactionTitle,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      bottom: Column(
        children: [
          KtPrimaryButton(
            label: isHot ? l10n.confirmTransfer : l10n.generateSignQr,
            onPressed: blocked
                ? null
                : () => context.push(isHot ? '/transfer-auth' : '/sign-qr'),
          ),
          const SizedBox(height: 10),
          Text(
            blocked
                ? (_tokenRisk == _TokenRiskUiState.checking
                      ? l10n.tokenRiskChecking
                      : _tokenRisk == _TokenRiskUiState.unsafe
                      ? l10n.tokenRiskBlockedHint
                      : _insufficientFunds
                      ? l10n.insufficientBalance
                      : l10n.feeUnavailableHint)
                : (isHot ? l10n.hotConfirmHint : l10n.watchConfirmHint),
            style: TextStyle(
              fontSize: 12,
              color: blocked ? WalletColors.red : WalletColors.text3,
            ),
          ),
        ],
      ),
      children: [
        Column(
          children: [
            Text(
              headline,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: WalletColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              fiat,
              style: const TextStyle(fontSize: 14, color: WalletColors.text2),
            ),
            const SizedBox(height: 8),
            NetworkBadge(label: networkLabel, dotColor: dotColor),
          ],
        ),
        KtCard(
          child: Column(
            children: [
              KtDetailRow(
                label: l10n.fromAddress,
                value: fromValue,
                mono: true,
              ),
              const SizedBox(height: 14),
              KtDetailRow(
                label: draft?.operation == TxOperation.approvalRevoke
                    ? l10n.approvalSpender
                    : l10n.recipientAddress,
                value: toValue,
                mono: true,
              ),
              const SizedBox(height: 14),
              KtDetailRow(label: l10n.networkFee, value: feeValue),
              if (_rentReserve case final rent?) ...[
                const SizedBox(height: 14),
                KtDetailRow(label: l10n.solanaRentReserve, value: '$rent'),
              ],
              const SizedBox(height: 14),
              KtDetailRow(
                label: draft?.operation == TxOperation.approvalRevoke
                    ? l10n.maximumNetworkFee
                    : l10n.totalSpend,
                value: totalValue,
                valueColor: WalletColors.text,
              ),
            ],
          ),
        ),
        if (_evmAssetChanges case final changes?)
          KtCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    l10n.expectedAssetChanges,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: WalletColors.text,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                KtDetailRow(
                  key: const ValueKey('expected-asset-change-outgoing'),
                  label: draft?.operation == TxOperation.approvalRevoke
                      ? l10n.approvalRevoke
                      : l10n.outgoingAsset(changes.outgoing.symbol),
                  value: draft?.operation == TxOperation.approvalRevoke
                      ? 'approve(spender, 0)'
                      : '-${changes.outgoing}',
                  valueColor: draft?.operation == TxOperation.approvalRevoke
                      ? WalletColors.accent
                      : WalletColors.red,
                ),
                const SizedBox(height: 14),
                KtDetailRow(
                  key: const ValueKey('expected-asset-change-max-fee'),
                  label: l10n.maximumNetworkFee,
                  value: l10n.upToNegativeAmount(
                    changes.maximumNetworkFee.toString(),
                  ),
                  valueColor: WalletColors.red,
                ),
              ],
            ),
          ),
        if (_tokenRisk != _TokenRiskUiState.notApplicable)
          _tokenRiskNotice(l10n, _tokenRisk),
        if (showUnbackedWarning) _amberWarn(l10n.unbackedTransferWarning),
      ],
    );
  }
}

enum _TokenRiskUiState {
  notApplicable,
  checking,
  verifiedIdentity,
  unsafe,
  unknown,
  unavailable,
}

Widget _tokenRiskNotice(AppLocalizations l10n, _TokenRiskUiState state) {
  final (
    Color color,
    IconData icon,
    String title,
    String body,
  ) = switch (state) {
    _TokenRiskUiState.checking => (
      WalletColors.accent,
      Icons.shield_outlined,
      l10n.tokenRiskChecking,
      l10n.tokenRiskCheckingBody,
    ),
    _TokenRiskUiState.verifiedIdentity => (
      WalletColors.accent,
      Icons.verified_rounded,
      l10n.tokenRiskVerifiedTitle,
      l10n.tokenRiskVerifiedBody,
    ),
    _TokenRiskUiState.unsafe => (
      WalletColors.red,
      Icons.gpp_bad_rounded,
      l10n.tokenRiskUnsafeTitle,
      l10n.tokenRiskUnsafeBody,
    ),
    _TokenRiskUiState.unknown => (
      WalletColors.amber,
      Icons.help_outline_rounded,
      l10n.tokenRiskUnknownTitle,
      l10n.tokenRiskUnknownBody,
    ),
    _TokenRiskUiState.unavailable => (
      WalletColors.amber,
      Icons.cloud_off_rounded,
      l10n.tokenRiskUnavailableTitle,
      l10n.tokenRiskUnavailableBody,
    ),
    _TokenRiskUiState.notApplicable => throw StateError('not applicable'),
  };
  return Semantics(
    key: const ValueKey('token-risk-notice'),
    label: '$title. $body',
    container: true,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  body,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: WalletColors.text2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

/// W6 待签名二维码. Displays a REAL animated AIRGAP-V1 sign-request: the draft
/// (or the demo transfer when opened from the gallery) is encoded to a
/// [SignRequest], fragmented into frames, and each frame's bytes are rendered
/// as a scannable QR, cycling every ~600ms. The shard label/progress reflect
/// the actual frame count.
///
/// Live EVM drafts consume the exact short-lived quote approved on the
/// confirmation screen. Production never rebuilds different fees or a
/// different nonce after confirmation. Injectable Flutter tests retain a
/// direct chain-parameter path so the QR encoder can be exercised in
/// isolation. Demo/gallery renderings and non-EVM chains build synchronously.
typedef SignRequestPersistence =
    Future<void> Function(
      BuildContext context,
      TransferSession session,
      TxStatus status,
      SignRequest request,
    );

class SignRequestQrScreen extends StatefulWidget {
  const SignRequestQrScreen({
    super.key,
    this.paramsService,
    this.requestPersistence,
  });

  /// Injectable chain-params fetcher for tests; defaults to one resolving
  /// the prefs-overridable endpoints.
  final ChainParamsService? paramsService;

  /// Failure-injection seam used by widget tests. Production always uses the
  /// Drift-backed transaction writer above.
  final SignRequestPersistence? requestPersistence;

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

  bool _paramsFailed = false;

  /// A signing QR is a publish boundary: it remains absent until its
  /// `awaitingSig` transaction row has committed successfully.
  bool _persistenceFailed = false;
  int _installGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_request != null || _building) return; // build once per screen instance
    final session = TransferSessionScope.maybeOf(context);
    _draft = session?.draft;
    final wallet = WalletScope.of(context).current;
    final draft = _draft;
    final liveController = WalletScope.maybeOf(context);
    if (draft == null &&
        liveController != null &&
        !liveController.allowsTestBypass) {
      _paramsFailed = true;
      return;
    }
    final chain = (draft ?? demoDraft).chain;
    final walletId =
        wallet?.id ?? (developerFixturesEnabled ? demoWalletId : '');
    final from = wallet == null ? '' : addressForChain(wallet.addresses, chain);
    // The ACTIVE network instance for the draft's chain: its evmChainId is
    // the signing domain the raw tx must carry (Sepolia 11155111, ...), and
    // for a testnet its name overrides the summary's network label so the
    // signer displays the truth. Live drafts only — demo/goldens (no draft)
    // keep the mainnet constants and stay byte-identical.
    final Network? network = draft == null
        ? null
        : NetworkScope.maybeOf(context)?.activeFor(chain);
    final evmChainId = network?.evmChainId;
    final networkLabel = network != null && network.isTestnet
        ? network.name
        : null;
    if (draft != null &&
        (chain == Chain.ethereum ||
            chain == Chain.polygon ||
            chain == Chain.base ||
            chain == Chain.arbitrum ||
            chain == Chain.avalanche ||
            chain == Chain.bnb)) {
      final approved = network != null && evmChainId != null
          ? session?.validEvmQuote(
              forDraft: draft,
              networkId: network.id,
              evmChainId: evmChainId,
              from: from,
            )
          : null;
      if (approved != null) {
        _install(
          buildSignRequest(
            draft: draft,
            walletId: walletId,
            fromAddress: from,
            nonce: approved.nonce,
            maxPriorityFeePerGas: approved.maxPriorityFeePerGas,
            maxFeePerGas: approved.maxFeePerGas,
            gasLimit: approved.gasLimit,
            evmChainId: approved.evmChainId,
            networkLabel: networkLabel,
          ),
          session,
        );
        return;
      }
      // A missing/stale quote in production must return to confirmation; it
      // must never be silently replaced after the user approved it.
      if (!_isFlutterTest && widget.paramsService == null) {
        _returnToQuote();
        return;
      }
      // Isolated encoder/widget tests can still inject deterministic chain
      // parameters without constructing the preceding confirmation screen.
      _building = true;
      final service =
          widget.paramsService ??
          ChainParamsService(
            endpoints: effectiveRpcEndpoints(
              AppPrefsScope.maybeOf(context),
              NetworkScope.maybeOf(context),
            ),
            gateway: prefsGatewayResolver(AppPrefsScope.maybeOf(context)),
          );
      unawaited(
        _buildLiveEvm(
          service,
          session,
          draft,
          walletId: walletId,
          from: from,
          evmChainId: evmChainId,
          networkLabel: networkLabel,
        ),
      );
    } else if (draft != null && chain == Chain.tron) {
      final approved = network == null
          ? null
          : session?.validTronQuote(
              forDraft: draft,
              networkId: network.id,
              from: from,
            );
      if (approved != null) {
        _install(
          buildSignRequest(
            draft: draft,
            walletId: walletId,
            fromAddress: from,
            networkLabel: networkLabel,
            preparedRawTx: approved.rawTx,
          ),
          session,
        );
      } else if (_isFlutterTest) {
        // Isolated widget fixtures retain the deterministic synchronous path.
        _install(
          buildSignRequest(
            draft: draft,
            walletId: walletId,
            fromAddress: from,
            networkLabel: networkLabel,
          ),
          session,
        );
      } else {
        _returnToQuote();
      }
    } else if (draft != null && chain == Chain.solana) {
      final approved = network == null
          ? null
          : session?.validSolanaQuote(
              forDraft: draft,
              networkId: network.id,
              from: from,
            );
      if (approved != null) {
        _install(
          buildSignRequest(
            draft: draft,
            walletId: walletId,
            fromAddress: from,
            networkLabel: networkLabel,
            preparedRawTx: approved.message,
          ),
          session,
        );
      } else if (_isFlutterTest) {
        _install(
          buildSignRequest(
            draft: draft,
            walletId: walletId,
            fromAddress: from,
            networkLabel: networkLabel,
          ),
          session,
        );
      } else {
        _returnToQuote();
      }
    } else {
      _install(
        buildSignRequest(
          draft: draft,
          walletId: walletId,
          fromAddress: from,
          evmChainId: evmChainId,
          networkLabel: networkLabel,
        ),
        session,
      );
    }
  }

  void _returnToQuote() {
    _paramsFailed = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final wallet = WalletScope.of(context).current;
      context.go(wallet is HotWallet ? '/confirm-hot' : '/confirm-watch');
    });
  }

  Future<void> _buildLiveEvm(
    ChainParamsService service,
    TransferSession? session,
    TransferDraft draft, {
    required String walletId,
    required String from,
    int? evmChainId,
    String? networkLabel,
  }) async {
    BigInt? nonce, maxPriority, maxFee, gasLimit;
    try {
      final params = await service.fetchEvmParams(draft.chain, from);
      final tier = params.tierFor(draft.feeTier);
      nonce = BigInt.from(params.nonce);
      maxPriority = tier.maxPriorityFeePerGas;
      maxFee = tier.maxFeePerGas;
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
      final callData = '0x${hexEncode(calldata)}';
      await service.simulateEvmTransfer(
        draft.chain,
        from: from,
        to: callTo,
        value: callValue,
        data: callData,
        tokenTransfer: tokenContract != null,
      );
      gasLimit = await service.estimateEvmGas(
        draft.chain,
        from: from,
        to: callTo,
        value: callValue,
        data: callData,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _building = false;
        _paramsFailed = true;
      });
      return;
    }
    if (!mounted) return;
    _building = false;
    _install(
      buildSignRequest(
        draft: draft,
        walletId: walletId,
        fromAddress: from,
        nonce: nonce,
        maxPriorityFeePerGas: maxPriority,
        maxFeePerGas: maxFee,
        gasLimit: gasLimit,
        evmChainId: evmChainId,
        networkLabel: networkLabel,
      ),
      session,
    );
  }

  /// Persists [request] before registering or rendering it. Until that commit
  /// succeeds there are no QR bytes on screen and no outstanding request in
  /// the session, so a disk/database failure cannot create a signable orphan.
  void _install(SignRequest request, TransferSession? session) {
    final generation = ++_installGeneration;
    _timer?.cancel();
    _request = null;
    _frames = const [];
    _frameIndex = 0;
    _paramsFailed = false;
    _persistenceFailed = false;

    if (session == null) {
      _publishRequest(request, null);
      return;
    }

    _building = true;
    unawaited(_persistThenPublish(request, session, generation));
  }

  Future<void> _persistThenPublish(
    SignRequest request,
    TransferSession session,
    int generation,
  ) async {
    try {
      final persist = widget.requestPersistence;
      if (persist == null) {
        await _persistAirgapTransaction(
          context,
          session,
          TxStatus.awaitingSig,
          requestOverride: request,
        );
      } else {
        await persist(context, session, TxStatus.awaitingSig, request);
      }
    } catch (_) {
      if (!mounted || generation != _installGeneration) return;
      setState(() {
        _building = false;
        _persistenceFailed = true;
      });
      return;
    }
    if (!mounted || generation != _installGeneration) return;
    setState(() {
      _building = false;
      _publishRequest(request, session);
    });
  }

  void _publishRequest(SignRequest request, TransferSession? session) {
    _request = request;
    // This is now the durable outstanding request the scanned result must
    // answer. Never expose it earlier than the persistence commit above.
    session
      ?..request = request
      ..result = null;
    _frames = encodeQrFrames(request, reqId: request.reqId);
    if (_frames.length > 1) {
      _timer = Timer.periodic(_frameInterval, (_) {
        if (!mounted) return;
        setState(() => _frameIndex = (_frameIndex + 1) % _frames.length);
      });
    }
  }

  @override
  void dispose() {
    _installGeneration++;
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
        navBar: KtNavBar(
          title: l10n.pendingSignTitle,
          onBack: () => Navigator.of(context).maybePop(),
          trailingText: l10n.actionCancel,
          onTrailing: _cancel,
        ),
        children: [
          KtCard(
            padding: const EdgeInsets.all(24),
            child: SizedBox(
              height: 280,
              child: Center(
                child: _paramsFailed
                    ? Text(
                        l10n.signRequestBuildFailed,
                        textAlign: TextAlign.center,
                      )
                    : _persistenceFailed
                    ? Text(
                        l10n.signRequestSaveFailed,
                        textAlign: TextAlign.center,
                      )
                    : const CircularProgressIndicator(),
              ),
            ),
          ),
        ],
      );
    }
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(
        title: l10n.pendingSignTitle,
        onBack: () => Navigator.of(context).maybePop(),
        trailingText: l10n.actionCancel,
        onTrailing: _cancel,
      ),
      children: [
        KtCard(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              KtQrCode(data: _frames[_frameIndex], size: 240),
              const SizedBox(height: 16),
              Text(
                l10n.dynamicShard(_frameIndex + 1, _frames.length),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: WalletColors.text2,
                ),
              ),
              const SizedBox(height: 8),
              ShardProgressBar(
                received: _frameIndex + 1,
                total: _frames.length,
              ),
            ],
          ),
        ),
        KtCard(
          child: Column(
            children: [
              KtDetailRow(
                label: l10n.networkRow,
                value: draft?.networkLabel ?? 'TRON · TRC-20',
              ),
              const SizedBox(height: 14),
              KtDetailRow(
                label: l10n.amountLabel,
                value: draft?.operation == TxOperation.approvalRevoke
                    ? 'approve(spender, 0)'
                    : draft?.amountText ?? '120.00 USDT',
              ),
              const SizedBox(height: 14),
              KtDetailRow(
                label: l10n.requestId,
                value: 'REQ-${request.reqIdHex.substring(0, 6).toUpperCase()}',
                mono: true,
              ),
            ],
          ),
        ),
        Center(
          child: Text(
            l10n.scanWithOfflinePhone,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: WalletColors.text,
            ),
          ),
        ),
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

  void _simulateScan(
    BuildContext context,
    TransferSession? session,
    Wallet? wallet,
  ) {
    if (_navigated) return;
    if (!developerFixturesEnabled) return;
    final request = session?.request;
    if (session != null && request != null) {
      // Signer side of the (simulated) air gap: the paired signer answers with
      // deterministic demo signature bytes for the same reqId.
      final signer = wallet == null
          ? ''
          : addressForChain(wallet.addresses, chainForCoin(request.coin));
      final frames = encodeQrFrames(
        buildDemoSignResult(request, signer: signer),
        reqId: request.reqId,
      );
      // Wallet side: aggregate + decode + verify against the outstanding
      // request; broadcast-confirm renders only what was decoded.
      session.result = decodeSignResultFrames(frames, expected: request);
      unawaited(_persistAirgapTransaction(context, session, TxStatus.signed));
    }
    _navigated = true;
    context.push('/broadcast-confirm');
  }

  /// Discards the current (unverifiable or failed) session and rescans.
  void _restartSession() {
    _session.reset();
    setState(() => _progress = null);
  }

  Future<void> _onScanned(String raw) async {
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
      final wallet = WalletScope.of(context).current;
      final expectedSigner = wallet == null
          ? null
          : addressForChain(wallet.addresses, chainForCoin(request.coin));
      result = await verifySignResultCryptographically(
        _session.payload!,
        expected: request,
        expectedSigner: expectedSigner,
      );
      if (!mounted) return;
    } on Object {
      // Foreign or malformed payload: silently start over, keep scanning.
      return _restartSession();
    }
    session.result = result;
    await _persistAirgapTransaction(
      context,
      session,
      TxStatus.signed,
      hash: result.txHash,
    );
    if (!mounted) return;
    _navigated = true;
    unawaited(context.push('/broadcast-confirm'));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = TransferSessionScope.maybeOf(context);
    final wallet = WalletScope.of(context).current;
    final liveController = WalletScope.maybeOf(context);
    if (session?.request == null &&
        liveController != null &&
        !liveController.allowsTestBypass) {
      return const InvalidTransferState();
    }
    // The gallery keeps its fixed 5/12 design snapshot, but a production
    // session must not claim that frames were recognized before the camera
    // has delivered anything. Besides being confusing, that made a stalled
    // or permission-denied camera look as though a real QR session existed.
    final fixtureMode =
        liveController == null || liveController.allowsTestBypass;
    final showProgress = fixtureMode || _progress != null;
    final received = _progress?.received ?? 5;
    final total = _progress?.total ?? 12;
    return Scaffold(
      backgroundColor: SignerColors.bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            const KtStatusBar(theme: AppTheme.signer),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: KtNavBar(
                title: l10n.scanSignResultTitle,
                theme: AppTheme.signer,
                leading: Icons.close,
                onBack: () => Navigator.of(context).maybePop(),
              ),
            ),
            const SizedBox(height: 24),
            Flexible(
              child: ScanViewfinder(
                height: 380,
                frameColor: SignerColors.blue,
                semanticLabel: l10n.scanSignResultTitle,
                onSimulatedTap: developerFixturesEnabled
                    ? () => _simulateScan(context, session, wallet)
                    : null,
                onScanned: _onScanned,
                availability: widget.availability,
              ),
            ),
            const SizedBox(height: 24),
            if (showProgress) ...[
              Text(
                l10n.recognizedShard(received, total),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 10),
              ShardProgressBar(
                received: received,
                total: total,
                color: SignerColors.blue,
                trackColor: SignerColors.border,
                width: 240,
              ),
            ],
          ],
        ),
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
/// a node), a real signature goes over the wire, and a rejection surfaces a
/// localized bounded reason — the broadcastError → failed step; retry stays
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

  /// Localized, bounded presentation copy for the last failed broadcast.
  /// Raw exceptions and provider strings must never be assigned here.
  String? _error;

  Future<void> _broadcast() async {
    final session = TransferSessionScope.maybeOf(context);
    final result = session?.result;
    if (session == null || result == null) {
      // Gallery rendering keeps its deterministic transition. A production
      // deep link has no signed payload and must never manufacture a success.
      if (WalletScope.of(context).allowsTestBypass) {
        context.go('/broadcast-result');
      } else {
        context.go('/home');
      }
      return;
    }
    final service =
        widget.broadcaster ??
        BroadcastService(
          endpoints: effectiveRpcEndpoints(
            AppPrefsScope.maybeOf(context),
            NetworkScope.maybeOf(context),
          ),
          gateway: prefsGatewayResolver(AppPrefsScope.maybeOf(context)),
        );
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _persistAirgapTransaction(
        context,
        session,
        TxStatus.submitted,
        hash: result.txHash,
      );
    } on Object {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = AppLocalizations.of(context).transactionNotSubmitted;
      });
      return;
    }
    if (!mounted) return;
    final outcome = await service.broadcast(
      chainForCoin(result.coin),
      result.signedTx,
      expectedTxHash: result.txHash,
    );
    if (!mounted) return;
    switch (outcome.status) {
      case BroadcastStatus.ok:
        final nodeHash = outcome.txHash;
        if (nodeHash == null ||
            !transactionHashesMatch(
              chainForCoin(result.coin),
              result.txHash,
              nodeHash,
            )) {
          // Submission may already have reached the node. A response for a
          // different transaction is not proof of rejection or acceptance of
          // the signed request, so retain the locally verified identity and
          // reconcile it without offering a second broadcast.
          session
            ..broadcastTxHash = result.txHash
            ..broadcastOutcomeUnknown = true;
          context.go('/broadcast-result');
          return;
        }
        session
          ..broadcastTxHash = result.txHash
          ..broadcastOutcomeUnknown = false;
        try {
          await _persistAirgapTransaction(
            context,
            session,
            TxStatus.pending,
            hash: session.broadcastTxHash,
          );
        } catch (_) {
          // The node accepted the bytes and the submitted row already carries
          // the recovery hash. Do not invite an unsafe second broadcast only
          // because the best-effort pending transition could not be stored.
        }
        if (!mounted) return;
        context.go('/broadcast-result');
      case BroadcastStatus.unknown:
        // The signed bytes may have reached the node. Keep the pre-broadcast
        // submitted row and locally derived hash, start reconciliation on W9,
        // and never offer an unsafe second submission.
        session
          ..broadcastTxHash = result.txHash
          ..broadcastOutcomeUnknown = true;
        context.go('/broadcast-result');
      case BroadcastStatus.error:
      case BroadcastStatus.unsupported:
        try {
          await _persistAirgapTransaction(
            context,
            session,
            TxStatus.failed,
            hash: result.txHash,
          );
        } catch (_) {
          // Keep the authoritative node message visible even if the local
          // failed-state update itself cannot be persisted.
        }
        if (!mounted) return;
        final l10n = AppLocalizations.of(context);
        setState(() {
          _busy = false;
          _error = outcome.status == BroadcastStatus.error
              ? localizedRpcRejection(
                  l10n,
                  outcome.rejectionKind ?? RpcRejectionKind.rejected,
                )
              : l10n.broadcastUnsupported;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final session = TransferSessionScope.maybeOf(context);
    final result = session?.result;
    final request = session?.request;
    if ((session?.draft == null || result == null || request == null) &&
        !WalletScope.of(context).allowsTestBypass) {
      return const InvalidTransferState();
    }

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
      headline = session?.draft?.operation == TxOperation.approvalRevoke
          ? l10n.approvalRevoke
          : '-${summary?[SummaryKeys.amount] ?? ''}';
      networkLabel = summary?[SummaryKeys.network] as String? ?? chain.name;
      dotColor = _chainDot(chain);
      final recipient = summary?[SummaryKeys.recipient] as String?;
      if (recipient != null) {
        toValue = truncateMiddle(recipient, head: 8, tail: 9);
      }
      signerValue = truncateMiddle(result.signer);
      hashValue = truncateMiddle(result.txHash, head: 6, tail: 6);
    }

    return KtScreen(
      gap: 16,
      navBar: KtNavBar(
        title: l10n.broadcastTitle,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      bottom: Column(
        children: [
          KtPrimaryButton(
            label: l10n.broadcastTitle,
            onPressed: _busy ? null : _broadcast,
          ),
          const SizedBox(height: 12),
          Semantics(
            button: true,
            label: l10n.dontBroadcastYet,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Center(
                  child: Text(
                    l10n.dontBroadcastYet,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: WalletColors.text2,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      children: [
        // Failed-broadcast state: localized bounded reason only.
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: WalletColors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 18,
                  color: WalletColors.red,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.broadcastFailedMessage(_error!),
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.5,
                      fontWeight: FontWeight.w500,
                      color: WalletColors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: WalletColors.green.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.verified_user,
                size: 18,
                color: WalletColors.green,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.signatureVerified,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: WalletColors.green,
                  ),
                ),
              ),
            ],
          ),
        ),
        Column(
          children: [
            Text(
              headline,
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: WalletColors.text,
              ),
            ),
            const SizedBox(height: 8),
            NetworkBadge(label: networkLabel, dotColor: dotColor),
          ],
        ),
        KtCard(
          child: Column(
            children: [
              KtDetailRow(
                label: session?.draft?.operation == TxOperation.approvalRevoke
                    ? l10n.approvalSpender
                    : l10n.recipientAddress,
                value: toValue,
                mono: true,
              ),
              const SizedBox(height: 14),
              KtDetailRow(
                label: l10n.signerAddress,
                value: signerValue,
                mono: true,
              ),
              const SizedBox(height: 14),
              KtDetailRow(
                label: l10n.txHashPreview,
                value: hashValue,
                mono: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// W9 广播结果. An accepted transaction starts as pending; an attempt whose
/// response was lost stays submitted with its locally derived hash. This
/// screen reconciles both states against the chain while visible.
/// It never retries the broadcast.
class BroadcastResultScreen extends StatefulWidget {
  const BroadcastResultScreen({
    super.key,
    this.confirmationService,
    this.statusService,
    this.pollInterval = const Duration(seconds: 3),
  });

  final TransactionConfirmationService? confirmationService;
  final TransactionStatusService? statusService;
  final Duration pollInterval;

  @override
  State<BroadcastResultScreen> createState() => _BroadcastResultScreenState();
}

class _BroadcastResultScreenState extends State<BroadcastResultScreen>
    with WidgetsBindingObserver {
  Transaction? _transaction;
  TransactionStatusService? _statusService;
  TransactionConfirmationService? _confirmationService;
  Timer? _timer;
  bool _loading = false;
  bool _checkingConfirmations = false;
  int? _confirmations;
  int? _lastCheckedAt;
  TxCheckOutcome? _lastCheckOutcome;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefs = AppPrefsScope.maybeOf(context);
    final networks = NetworkScope.maybeOf(context);
    final endpoints = effectiveRpcEndpoints(prefs, networks);
    _statusService ??=
        widget.statusService ??
        TransactionStatusService(
          endpoints: endpoints,
          networkEndpoints: networks == null
              ? null
              : effectiveTransactionRpcEndpoints(prefs, networks),
          gateway: prefsGatewayResolver(prefs, networks),
          onEvmNonceObserved: (transaction, nonce) async {
            await WalletScope.of(context).setTransactionNonceIfAbsentForWallet(
              transaction.walletId,
              transaction.id,
              nonce,
            );
          },
        );
    _confirmationService ??=
        widget.confirmationService ??
        TransactionConfirmationService(endpoints: endpoints);
    if (!_loading && _transaction == null) _reload();
  }

  Future<void> _reload() async {
    final id = TransferSessionScope.maybeOf(context)?.localTransactionId;
    if (id == null) return;
    _loading = true;
    final transaction = await WalletScope.of(context).localTransactionById(id);
    if (!mounted) return;
    setState(() {
      _transaction = transaction;
      _lastCheckedAt = transaction?.lastCheckedAt;
      _lastCheckOutcome = transaction?.lastCheckOutcome;
      _loading = false;
    });
    if (transaction != null) _scheduleCheck(transaction, immediately: true);
  }

  bool _pending(Transaction tx) =>
      tx.hash != null &&
      (tx.status == TxStatus.submitted ||
          tx.status == TxStatus.pending ||
          tx.status == TxStatus.broadcast);

  String _date(int millis) {
    final value = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  void _scheduleCheck(Transaction tx, {bool immediately = false}) {
    _timer?.cancel();
    if (!_pending(tx)) return;
    _timer = Timer(
      immediately ? Duration.zero : widget.pollInterval,
      () => _check(tx),
    );
  }

  Future<void> _check(Transaction tx) async {
    if (!mounted || !_pending(tx)) return;
    // Finality is the user-visible truth and must use the Gateway-first
    // service before attempting a device-to-public-RPC depth lookup. The old
    // order waited for an unreachable public RPC (notably on mainland-China
    // networks) before accepting an already-confirmed Gateway result, leaving
    // the screen visibly pending for a full direct timeout.
    final chainStatus = await _statusService?.check(tx);
    if (!mounted) return;
    final next = switch (chainStatus) {
      ChainTransactionStatus.confirmed => TxStatus.confirmed,
      ChainTransactionStatus.failed => TxStatus.failed,
      ChainTransactionStatus.pending => TxStatus.pending,
      ChainTransactionStatus.replaced => TxStatus.replaced,
      ChainTransactionStatus.expired => TxStatus.expired,
      ChainTransactionStatus.unknown || null => null,
    };
    final outcome = switch (chainStatus) {
      ChainTransactionStatus.unknown => TxCheckOutcome.unknown,
      ChainTransactionStatus.pending => TxCheckOutcome.pending,
      _ => null,
    };
    final terminal =
        next == TxStatus.confirmed ||
        next == TxStatus.failed ||
        next == TxStatus.replaced ||
        next == TxStatus.expired;
    final checkedAt = DateTime.now().millisecondsSinceEpoch;
    final changed = next != null && next != tx.status;
    final controller = WalletScope.of(context);
    final persisted = changed ? next : tx.status;
    var applied = false;
    if (_isEvmCoinName(tx.coin) &&
        changed &&
        (persisted == TxStatus.confirmed || persisted == TxStatus.failed)) {
      final settlement = await controller.settleEvmTransactionForWallet(
        walletId: tx.walletId,
        id: tx.id,
        status: persisted,
        hash: tx.hash,
        lastCheckedAt: checkedAt,
      );
      applied = settlement.applied;
    } else {
      applied = await controller.updateTransactionStatusForWallet(
        tx.walletId,
        tx.id,
        persisted,
        hash: tx.hash,
        lastCheckedAt: checkedAt,
        lastCheckOutcome: outcome,
        clearLastCheckOutcome: terminal,
        onlyIfLive: true,
        finalityMetricAt: changed && terminal ? checkedAt : null,
      );
    }
    if (!mounted) return;
    if (!applied) {
      await _reload();
      return;
    }
    setState(() {
      _lastCheckedAt = checkedAt;
      _lastCheckOutcome = terminal ? null : outcome;
    });
    // Confirmation depth is presentation-only. Fetch it after authoritative
    // terminal state has been persisted, and never let a blocked public RPC
    // delay the status transition. A missing depth remains honestly absent.
    if (terminal &&
        (chainStatus == ChainTransactionStatus.confirmed ||
            chainStatus == ChainTransactionStatus.failed)) {
      unawaited(_readConfirmationDepth());
    }
    if (changed) {
      await _reload();
      return;
    }
    if (next == TxStatus.pending) {
      _scheduleCheck(tx);
      return;
    }
    _scheduleCheck(tx);
  }

  /// Reads the direct chain receipt/status only to enrich the terminal screen
  /// with an actual block/slot depth. Finality itself is resolved first by
  /// [TransactionStatusService]; this best-effort request never gates it.
  Future<TxStatus?> _readConfirmationDepth() async {
    if (_checkingConfirmations) return null;
    final session = TransferSessionScope.maybeOf(context);
    final draft = session?.draft;
    final hash = session?.broadcastTxHash;
    final service = _confirmationService;
    if (draft == null || hash == null || service == null) return null;
    _checkingConfirmations = true;
    try {
      final snapshot = await service.check(draft.chain, hash);
      if (mounted) {
        setState(() => _confirmations = snapshot.confirmations);
      }
      return snapshot.status;
    } catch (_) {
      return null;
    } finally {
      _checkingConfirmations = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _reload();
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    if (widget.confirmationService == null) _confirmationService?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Prefer the hash the broadcast step actually produced (node answer or
    // simulated short-circuit); else keep the decoded result's hash for
    // consistency with broadcast-confirm; demo constant otherwise.
    final session = TransferSessionScope.maybeOf(context);
    final fullHash = session?.broadcastTxHash ?? session?.result?.txHash;
    final draft = session?.draft;
    // Signing is not submission. W9 requires a durable row and a hash plus an
    // actual broadcast attempt. The hash can be either the node answer or the
    // locally derived recovery key when the response was lost.
    final hasSubmissionEvidence =
        draft != null &&
        session?.localTransactionId != null &&
        session?.broadcastTxHash != null;
    if (!hasSubmissionEvidence && !WalletScope.of(context).allowsTestBypass) {
      return const InvalidTransferState();
    }
    final transferLabel = draft == null
        ? '-120.00 USDT · TRON'
        : draft.operation == TxOperation.approvalRevoke
        ? '${l10n.approvalRevoke} · ${draft.networkLabel}'
        : '-${draft.amountText} · ${draft.networkLabel}';
    final hashValue = fullHash == null
        ? '8f6d2c…a94e07'
        : truncateMiddle(fullHash, head: 6, tail: 6);
    final submissionUnknown = session?.broadcastOutcomeUnknown ?? false;
    final status =
        _transaction?.status ??
        (submissionUnknown ? TxStatus.submitted : TxStatus.pending);
    final statusUnknown =
        submissionUnknown ||
        ((status == TxStatus.submitted ||
                status == TxStatus.pending ||
                status == TxStatus.broadcast) &&
            _lastCheckOutcome == TxCheckOutcome.unknown);
    final failed =
        status == TxStatus.failed ||
        status == TxStatus.dropped ||
        status == TxStatus.expired;
    final confirmed = status == TxStatus.confirmed;
    final replaced = status == TxStatus.replaced;
    final color = statusUnknown
        ? WalletColors.text3
        : failed
        ? WalletColors.red
        : replaced
        ? const Color(0xFFF59E0B)
        : confirmed
        ? WalletColors.green
        : WalletColors.accent;
    final icon = statusUnknown
        ? Icons.help_outline_rounded
        : failed
        ? Icons.error_outline_rounded
        : replaced
        ? Icons.swap_horiz_rounded
        : confirmed
        ? Icons.check
        : Icons.schedule_rounded;
    final statusLabel = statusUnknown
        ? l10n.txStatusUnknown
        : failed
        ? l10n.txStatusFailed
        : replaced
        ? l10n.txStatusReplaced
        : confirmed
        ? l10n.txStatusConfirmed
        : l10n.txStatusPending;
    return KtScreen(
      gap: 24,
      bottom: KtPrimaryButton(
        label: l10n.backToHome,
        onPressed: () => context.go('/home'),
      ),
      children: [
        const SizedBox(height: 24),
        Center(
          child: Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Icon(icon, size: 32, color: Colors.white),
              ),
            ),
          ),
        ),
        Column(
          children: [
            Text(
              submissionUnknown ? l10n.txSubmissionUnknown : l10n.txSubmitted,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: WalletColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              transferLabel,
              style: const TextStyle(fontSize: 14, color: WalletColors.text2),
            ),
          ],
        ),
        if (submissionUnknown)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7E8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFD58A)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFFC56A00),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.txSubmissionUnknownMessage,
                    style: const TextStyle(
                      color: Color(0xFF7A4300),
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        KtCard(
          child: Column(
            children: [
              KtDetailRow(label: l10n.txHash, value: hashValue, mono: true),
              const SizedBox(height: 14),
              KeyedSubtree(
                key: const ValueKey('broadcast-confirmations'),
                child: KtDetailRow(
                  label: l10n.confirmations,
                  value: _confirmations?.toString() ?? '--',
                  mono: true,
                ),
              ),
              const SizedBox(height: 14),
              KtDetailRow(
                label: l10n.statusLabel,
                value: statusLabel,
                valueColor: color,
              ),
              const SizedBox(height: 14),
              KtDetailRow(
                label: l10n.txBroadcastTime,
                value: _transaction?.broadcastAt == null
                    ? '--'
                    : _date(_transaction!.broadcastAt!),
              ),
              const SizedBox(height: 14),
              KtDetailRow(
                label: l10n.txLastStatusCheck,
                value: _lastCheckedAt == null
                    ? l10n.txNotCheckedYet
                    : _date(_lastCheckedAt!),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// W15 交易详情. A route without [transactionId] keeps the design-gallery
/// snapshot; real history navigation supplies the local row id and enables
/// EVM speed-up/cancellation only when every persisted signing parameter is
/// available.
class TxDetailScreen extends StatefulWidget {
  const TxDetailScreen({
    super.key,
    this.transactionId,
    this.transaction,
    this.chainRecord,
    this.transferService,
    this.authGate = const LocalTransactionAuthGate(),
    this.tempDirectory,
    this.cardRenderer,
    this.statusService,
    this.pollInterval = const Duration(seconds: 8),
  });

  final String? transactionId;

  /// An on-chain record with no local row behind it — an incoming transfer, or
  /// one sent from another device. Without this the screen fell back to a
  /// hardcoded demo transaction, so every such row opened a fabricated one.
  final ChainTxRecord? chainRecord;

  /// Explicit row injection for deterministic widget tests.
  final Transaction? transaction;
  final LocalTransferService? transferService;
  final TransactionAuthGate authGate;

  /// Injectable seams keep export UI tests deterministic. The production
  /// path renders a real high-resolution card and stages it in the platform
  /// temporary directory before opening the share sheet.
  final Future<Directory> Function()? tempDirectory;
  final Future<Uint8List> Function(TransactionCardData)? cardRenderer;
  final TransactionStatusService? statusService;
  final Duration pollInterval;

  /// Demo tx hash of the displayed transaction (matches the broadcast flow).
  static const _txHash = '8f6d2c…a94e07';

  @override
  State<TxDetailScreen> createState() => _TxDetailScreenState();
}

class _TxDetailScreenState extends State<TxDetailScreen>
    with WidgetsBindingObserver {
  Future<Transaction?>? _transaction;
  String? _activeId;
  bool _submitting = false;
  bool _exportingReceipt = false;
  int? _lastCheckedAt;
  TxCheckOutcome? _lastCheckOutcome;
  TransactionStatusService? _statusService;
  Timer? _statusTimer;

  @override
  void initState() {
    super.initState();
    _activeId = widget.transactionId;
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final prefs = AppPrefsScope.maybeOf(context);
    final networks = NetworkScope.maybeOf(context);
    _statusService ??=
        widget.statusService ??
        TransactionStatusService(
          endpoints: effectiveRpcEndpoints(prefs, networks),
          networkEndpoints: networks == null
              ? null
              : effectiveTransactionRpcEndpoints(prefs, networks),
          gateway: prefsGatewayResolver(prefs, networks),
          onEvmNonceObserved: (transaction, nonce) async {
            await WalletScope.of(context).setTransactionNonceIfAbsentForWallet(
              transaction.walletId,
              transaction.id,
              nonce,
            );
          },
        );
    if (widget.transaction == null && _activeId != null) {
      _transaction ??= _loadTransaction();
    }
  }

  Future<Transaction?> _loadTransaction() async {
    final id = _activeId;
    if (id == null) return null;
    final transaction = await WalletScope.of(context).localTransactionById(id);
    if (transaction != null) {
      _lastCheckedAt = transaction.lastCheckedAt;
      _lastCheckOutcome = transaction.lastCheckOutcome;
      _scheduleStatusCheck(transaction, immediately: true);
    }
    return transaction;
  }

  void _reload([String? id]) {
    if (id != null) _activeId = id;
    setState(() {
      _transaction = _activeId == null ? null : _loadTransaction();
    });
  }

  bool _awaitingConfirmation(Transaction transaction) =>
      transaction.hash != null &&
      (transaction.status == TxStatus.submitted ||
          transaction.status == TxStatus.pending ||
          transaction.status == TxStatus.broadcast);

  void _scheduleStatusCheck(
    Transaction transaction, {
    bool immediately = false,
  }) {
    _statusTimer?.cancel();
    if (!_awaitingConfirmation(transaction)) return;
    _statusTimer = Timer(immediately ? Duration.zero : widget.pollInterval, () {
      _checkStatus(transaction);
    });
  }

  Future<void> _checkStatus(Transaction transaction) async {
    final service = _statusService;
    if (!mounted || service == null || !_awaitingConfirmation(transaction)) {
      return;
    }
    final status = await service.check(transaction);
    if (!mounted) return;
    final checkedAt = DateTime.now().millisecondsSinceEpoch;
    final next = switch (status) {
      ChainTransactionStatus.confirmed => TxStatus.confirmed,
      ChainTransactionStatus.failed => TxStatus.failed,
      ChainTransactionStatus.replaced => TxStatus.replaced,
      ChainTransactionStatus.expired => TxStatus.expired,
      ChainTransactionStatus.pending || ChainTransactionStatus.unknown => null,
    };
    final outcome = switch (status) {
      ChainTransactionStatus.pending => TxCheckOutcome.pending,
      ChainTransactionStatus.unknown => TxCheckOutcome.unknown,
      _ => null,
    };
    final terminal =
        status == ChainTransactionStatus.confirmed ||
        status == ChainTransactionStatus.failed ||
        status == ChainTransactionStatus.replaced ||
        status == ChainTransactionStatus.expired;
    final changed = next != null && next != transaction.status;
    final controller = WalletScope.of(context);
    final persisted = changed ? next : transaction.status;
    var applied = false;
    if (_isEvmCoinName(transaction.coin) &&
        changed &&
        (persisted == TxStatus.confirmed || persisted == TxStatus.failed)) {
      final settlement = await controller.settleEvmTransactionForWallet(
        walletId: transaction.walletId,
        id: transaction.id,
        status: persisted,
        hash: transaction.hash,
        lastCheckedAt: checkedAt,
      );
      applied = settlement.applied;
    } else {
      applied = await controller.updateTransactionStatusForWallet(
        transaction.walletId,
        transaction.id,
        persisted,
        hash: transaction.hash,
        lastCheckedAt: checkedAt,
        lastCheckOutcome: outcome,
        clearLastCheckOutcome: terminal,
        onlyIfLive: true,
        finalityMetricAt: changed && terminal ? checkedAt : null,
      );
    }
    if (!mounted) return;
    if (!applied) {
      _reload();
      return;
    }
    setState(() {
      _lastCheckedAt = checkedAt;
      _lastCheckOutcome = terminal ? null : outcome;
    });
    if (changed) {
      _reload();
      return;
    }
    _scheduleStatusCheck(transaction);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _statusTimer?.cancel();
      return;
    }
    final future = _transaction;
    if (future != null) {
      future.then((transaction) {
        if (transaction != null) _checkStatus(transaction);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusTimer?.cancel();
    super.dispose();
  }

  Chain? _chainFor(Transaction tx) => switch (tx.coin) {
    'eth' => Chain.ethereum,
    'polygon' => Chain.polygon,
    'base' => Chain.base,
    'arbitrum' => Chain.arbitrum,
    'avalanche' => Chain.avalanche,
    'bnb' => Chain.bnb,
    'tron' => Chain.tron,
    'solana' => Chain.solana,
    _ => null,
  };

  bool _canReplace(Transaction tx) {
    final chain = _chainFor(tx);
    final isEvm =
        chain == Chain.ethereum ||
        chain == Chain.polygon ||
        chain == Chain.base ||
        chain == Chain.avalanche ||
        chain == Chain.bnb;
    return isEvm &&
        tx.signMode == SignMode.local &&
        (tx.status == TxStatus.submitted || tx.status == TxStatus.pending) &&
        tx.lastCheckOutcome != TxCheckOutcome.unknown &&
        tx.replacedById == null &&
        // A row with no recorded network (pre-v4 legacy) cannot be safely
        // rebuilt: we do not know which chain instance it was broadcast on.
        tx.networkId != null &&
        tx.nonce != null &&
        tx.maxPriorityFeeRaw != null &&
        tx.maxFeeRaw != null &&
        tx.gasLimitRaw != null;
  }

  /// The network instance the ROW was recorded on — never the currently
  /// active one. A speed-up/cancel must rebuild the transaction for the very
  /// network that carries the pending nonce; using `activeFor(chain)` meant a
  /// Sepolia row could be re-signed and broadcast as a real mainnet
  /// transaction (chainId 1) with the Sepolia recipient after an environment
  /// switch. Returns null when the row's network is unknown to this build.
  Network? _rowNetwork(Transaction tx) {
    final id = tx.networkId;
    if (id == null) return null;
    return NetworkScope.maybeOf(context)?.byId(id);
  }

  /// Whether the row's own network is the one currently selected for its
  /// chain. Replacement requires it: the RPC endpoints, nonce view and fee
  /// oracle all follow the active network.
  bool _rowNetworkIsActive(Transaction tx) {
    final chain = _chainFor(tx);
    final networks = NetworkScope.maybeOf(context);
    if (chain == null || networks == null || tx.networkId == null) return false;
    return networks.activeFor(chain).id == tx.networkId;
  }

  bool _statusEvidenceUnknown(Transaction transaction) =>
      _awaitingConfirmation(transaction) &&
      (_lastCheckOutcome ?? transaction.lastCheckOutcome) ==
          TxCheckOutcome.unknown;

  String _statusLabel(AppLocalizations l10n, Transaction transaction) =>
      _statusEvidenceUnknown(transaction)
      ? l10n.txStatusUnknown
      : switch (transaction.status) {
          TxStatus.submitted => l10n.txStatusSubmitted,
          TxStatus.pending ||
          TxStatus.broadcast ||
          TxStatus.signed ||
          TxStatus.awaitingSig ||
          TxStatus.draft => l10n.txStatusPending,
          TxStatus.confirmed => l10n.txStatusConfirmed,
          TxStatus.failed || TxStatus.expired => l10n.txStatusFailed,
          TxStatus.dropped => l10n.txStatusDropped,
          TxStatus.replaced => l10n.txStatusReplaced,
        };

  Color _statusColor(Transaction transaction) =>
      _statusEvidenceUnknown(transaction)
      ? WalletColors.text3
      : switch (transaction.status) {
          TxStatus.confirmed => WalletColors.green,
          TxStatus.failed ||
          TxStatus.dropped ||
          TxStatus.expired => WalletColors.red,
          TxStatus.replaced => WalletColors.text3,
          _ => WalletColors.accent,
        };

  IconData _statusIcon(Transaction transaction) =>
      _statusEvidenceUnknown(transaction)
      ? Icons.help_outline_rounded
      : switch (transaction.status) {
          TxStatus.confirmed => Icons.check_circle,
          TxStatus.failed ||
          TxStatus.dropped ||
          TxStatus.expired => Icons.error,
          TxStatus.replaced => Icons.swap_horiz_rounded,
          _ => Icons.schedule_rounded,
        };

  String _short(String value) => value.length <= 24
      ? value
      : '${value.substring(0, 12)}…${value.substring(value.length - 10)}';

  (int, String)? _nativeUnit(Transaction tx) {
    final chain = _chainFor(tx);
    if (chain == null) return null;
    final coin = rpcCoinForChain(chain);
    return (BalanceService.decimalsFor[coin]!, BalanceService.symbolFor[coin]!);
  }

  String _displayNativeRaw(String raw, Transaction tx) {
    final unit = _nativeUnit(tx);
    if (unit == null) return '$raw base units';
    final (decimals, symbol) = unit;
    final amount = Amount(
      raw: BigInt.parse(raw),
      decimals: decimals,
      symbol: symbol,
    );
    return '${amount.format(maxFraction: 8)} $symbol';
  }

  String _displayAmount(BuildContext context, Transaction tx) {
    if (tx.operation == TxOperationKind.approvalRevoke) {
      return AppLocalizations.of(context).approvalRevoke;
    }
    final token = _tokenFor(tx);
    final amount = token == null
        ? tx.contract == null
              ? _displayNativeRaw(tx.amountRaw, tx)
              : '${tx.amountRaw} Token (raw)'
        : '${Amount(raw: BigInt.parse(tx.amountRaw), decimals: token.decimals, symbol: token.symbol).format(maxFraction: 8)} ${token.symbol}';
    return tx.direction == TxDirection.outgoing ? '-$amount' : amount;
  }

  TokenInfo? _tokenFor(Transaction tx) {
    final contract = tx.contract;
    final networkId = tx.networkId;
    if (contract == null || networkId == null) return null;
    for (final token
        in builtinTokensByNetworkId[networkId] ?? const <TokenInfo>[]) {
      final matches = contract.startsWith('0x')
          ? token.contract.toLowerCase() == contract.toLowerCase()
          : token.contract == contract;
      if (matches) return token;
    }
    return null;
  }

  String _date(int millis) {
    final value = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${two(value.month)}-${two(value.day)} '
        '${two(value.hour)}:${two(value.minute)}';
  }

  Future<void> _openExplorer(Transaction tx) async {
    final chain = _chainFor(tx);
    final hash = tx.hash;
    if (chain == null || hash == null || hash.isEmpty) return;
    // The explorer of the network the transaction was actually broadcast on;
    // the active one is only a fallback for legacy rows without a network.
    final network =
        _rowNetwork(tx) ?? NetworkScope.of(context).activeFor(chain);
    final url = explorerTxUrl(network, hash);
    if (url == null) return;
    final opened = await ExternalActions.instance.open(Uri.parse(url));
    if (!opened && mounted) {
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context).externalActionFailed),
          ),
        );
    }
  }

  Future<void> _copyHash(String hash) async {
    await Clipboard.setData(ClipboardData(text: hash));
    if (mounted) _showMessage(AppLocalizations.of(context).txHashCopied);
  }

  TransactionCardTone _receiptTone(Transaction transaction) =>
      _statusEvidenceUnknown(transaction)
      ? TransactionCardTone.neutral
      : switch (transaction.status) {
          TxStatus.confirmed => TransactionCardTone.success,
          TxStatus.failed ||
          TxStatus.dropped ||
          TxStatus.expired => TransactionCardTone.failed,
          TxStatus.replaced => TransactionCardTone.neutral,
          _ => TransactionCardTone.pending,
        };

  String _nativeSymbolForChain(Chain chain) => switch (chain) {
    Chain.ethereum || Chain.base || Chain.arbitrum => 'ETH',
    Chain.polygon => 'POL',
    Chain.avalanche => 'AVAX',
    Chain.bnb => 'BNB',
    Chain.tron => 'TRX',
    Chain.solana => 'SOL',
  };

  String _destinationAccountValue(
    BuildContext context,
    Chain chain,
    String address,
  ) {
    final evm = switch (chain) {
      Chain.ethereum ||
      Chain.polygon ||
      Chain.base ||
      Chain.arbitrum ||
      Chain.avalanche ||
      Chain.bnb => true,
      _ => false,
    };
    for (final wallet in WalletScope.of(context).wallets) {
      final local = addressForChain(wallet.addresses, chain);
      final matches = evm
          ? local.toLowerCase() == address.toLowerCase()
          : local == address;
      if (matches) return '${wallet.name}\n$address';
    }
    return address;
  }

  TransactionCardData? _receiptForLive(BuildContext context, Transaction tx) {
    final hash = tx.hash;
    final chain = _chainFor(tx);
    if (hash == null || hash.isEmpty || chain == null) return null;
    final l10n = AppLocalizations.of(context);
    final network =
        _rowNetwork(tx) ?? NetworkScope.of(context).activeFor(chain);
    final explorerUrl = explorerTxUrl(network, hash);
    if (explorerUrl == null) return null;
    final token = _tokenFor(tx);
    final symbol = token?.symbol ?? _nativeSymbolForChain(chain);
    final fields = <TransactionCardField>[
      TransactionCardField(label: l10n.networkRow, value: network.name),
      TransactionCardField(
        label: l10n.fromAddress,
        value: tx.fromAddr,
        mono: true,
      ),
      TransactionCardField(
        label: l10n.recipientAddress,
        value: tx.toAddr,
        mono: true,
      ),
      if (tx.contract != null)
        TransactionCardField(
          label: l10n.contractAddress,
          value: tx.contract!,
          mono: true,
        ),
      if (tx.feeRaw != null)
        TransactionCardField(
          label: l10n.networkFee,
          value: _displayNativeRaw(tx.feeRaw!, tx),
        ),
      if (tx.nonce != null)
        TransactionCardField(
          label: l10n.txNonceLabel,
          value: tx.nonce!,
          mono: true,
        ),
      if (tx.broadcastAt != null)
        TransactionCardField(
          label: l10n.txBroadcastTime,
          value: _date(tx.broadcastAt!),
        ),
      if ((_lastCheckedAt ?? tx.lastCheckedAt) != null)
        TransactionCardField(
          label: l10n.txLastStatusCheck,
          value: _date((_lastCheckedAt ?? tx.lastCheckedAt)!),
        ),
      TransactionCardField(label: l10n.txHash, value: hash, mono: true),
    ];
    return TransactionCardData(
      title: l10n.transactionReceiptTitle,
      amount: _displayAmount(context, tx),
      direction: tx.operation == TxOperationKind.approvalRevoke
          ? l10n.approvalRevoke
          : tx.direction == TxDirection.outgoing
          ? l10n.txSent
          : l10n.txReceived,
      status: _statusLabel(l10n, tx),
      transactionTimeLabel: l10n.transactionReceiptTimeLabel,
      transactionTime: _date(tx.createdAt),
      networkName: network.name,
      isTestnet: network.isTestnet,
      testnetLabel: l10n.testnetBadge,
      explorerUrl: explorerUrl,
      scanLabel: l10n.scanToVerifyOnChain,
      footer: l10n.transactionReceiptFooter,
      fields: fields,
      tone: _receiptTone(tx),
      tokenIconAsset: TokenIcon.assetFor(symbol),
      networkIconAsset: ChainIcon.assetFor(chain),
    );
  }

  TransactionCardData? _receiptForChainRecord(
    BuildContext context,
    ChainTxRecord record,
  ) {
    final l10n = AppLocalizations.of(context);
    final chain = chainOf(record.coin);
    final network = _networkForChainRecord(context, record);
    if (network == null) return null;
    final explorerUrl = explorerTxUrl(network, record.hash);
    if (explorerUrl == null) return null;
    final symbol = record.assetSymbol ?? _nativeSymbolForChain(chain);
    return TransactionCardData(
      title: l10n.transactionReceiptTitle,
      amount: record.amountText ?? '--',
      direction: record.outgoing ? l10n.txSent : l10n.txReceived,
      status: _chainTxStatusLabel(l10n, record.status),
      transactionTimeLabel: l10n.transactionReceiptTimeLabel,
      transactionTime: _date(record.timestamp.millisecondsSinceEpoch),
      networkName: network.name,
      isTestnet: network.isTestnet,
      testnetLabel: l10n.testnetBadge,
      explorerUrl: explorerUrl,
      scanLabel: l10n.scanToVerifyOnChain,
      footer: l10n.transactionReceiptFooter,
      fields: [
        TransactionCardField(label: l10n.networkRow, value: network.name),
        if (record.fromAddress != null)
          TransactionCardField(
            label: l10n.transactionSourceAddress,
            value: record.fromAddress!,
            mono: true,
          ),
        if (record.toAddress != null)
          TransactionCardField(
            label: l10n.transactionDestinationAccount,
            value: _destinationAccountValue(context, chain, record.toAddress!),
            mono: true,
          ),
        if (record.assetContract != null)
          TransactionCardField(
            label: l10n.contractAddress,
            value: record.assetContract!,
            mono: true,
          ),
        TransactionCardField(
          label: l10n.txHash,
          value: record.hash,
          mono: true,
        ),
      ],
      tone: _chainTxCardTone(record.status),
      tokenIconAsset: TokenIcon.assetFor(symbol),
      networkIconAsset: ChainIcon.assetFor(chain),
    );
  }

  Network? _networkForChainRecord(BuildContext context, ChainTxRecord record) {
    final id = record.networkId;
    if (id == null || id.isEmpty) return null;
    final network = NetworkScope.of(context).byId(id);
    if (network == null || network.chain != chainOf(record.coin)) return null;
    return network;
  }

  Future<void> _chooseReceiptExport(TransactionCardData data) async {
    if (_exportingReceipt) return;
    final l10n = AppLocalizations.of(context);
    final action = await showModalBottomSheet<_ReceiptExportAction>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.exportTransactionReceipt,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: WalletColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.exportTransactionReceiptSubtitle,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: WalletColors.text3,
              ),
            ),
            const SizedBox(height: 18),
            _ReceiptActionTile(
              key: const ValueKey('receipt-save-photos'),
              icon: Icons.download_rounded,
              title: l10n.saveReceiptToPhotos,
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ReceiptExportAction.save),
            ),
            const SizedBox(height: 10),
            _ReceiptActionTile(
              key: const ValueKey('receipt-share-image'),
              icon: Icons.ios_share_rounded,
              title: l10n.shareReceiptImage,
              onTap: () =>
                  Navigator.of(sheetContext).pop(_ReceiptExportAction.share),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    await _runReceiptExport(data, action);
  }

  Future<void> _runReceiptExport(
    TransactionCardData data,
    _ReceiptExportAction action,
  ) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    setState(() => _exportingReceipt = true);
    try {
      final png = await (widget.cardRenderer ?? renderTransactionCardPng)(data);
      if (action == _ReceiptExportAction.save) {
        final outcome = await MediaGallery.instance.saveImage(
          png,
          name: 'kt-wallet-transaction',
        );
        if (!mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(switch (outcome) {
              SaveImageOutcome.saved => l10n.transactionReceiptSaved,
              SaveImageOutcome.denied => l10n.transactionReceiptDenied,
              SaveImageOutcome.unsupported => l10n.transactionReceiptUseShare,
              SaveImageOutcome.failed => l10n.transactionReceiptFailed,
            }),
          ),
        );
        return;
      }

      final directory =
          await (widget.tempDirectory?.call() ?? getTemporaryDirectory());
      final file = File('${directory.path}/kt-wallet-transaction.png');
      file.writeAsBytesSync(png, flush: true);
      await ExternalActions.instance.shareFile(
        path: file.path,
        mimeType: 'image/png',
        text: data.explorerUrl,
        subject: l10n.transactionReceiptSubject(data.networkName),
      );
    } on Object {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.transactionReceiptFailed)),
      );
    } finally {
      if (mounted) setState(() => _exportingReceipt = false);
    }
  }

  Future<void> _replace(Transaction original, {required bool cancel}) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => KtConfirmDialog(
        title: l10n.txReplacementConfirmTitle,
        message: cancel ? l10n.txCancelConfirm : l10n.txSpeedUpConfirm,
        cancelLabel: l10n.actionCancel,
        confirmLabel: l10n.actionConfirm,
        icon: cancel ? Icons.cancel_outlined : Icons.bolt_rounded,
        iconColor: cancel ? WalletColors.red : WalletColors.accent,
        destructive: cancel,
        details: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (cancel ? WalletColors.red : WalletColors.accent).withValues(
              alpha: 0.06,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              KtDetailRow(
                label: l10n.txNonceLabel,
                value: original.nonce ?? '—',
                mono: true,
              ),
              const SizedBox(height: 10),
              KtDetailRow(
                label: l10n.amountLabel,
                value: cancel
                    ? '0 ${_nativeUnit(original)!.$2}'
                    : original.operation == TxOperationKind.approvalRevoke
                    ? l10n.approvalRevoke
                    : original.contract != null
                    ? '${original.amountRaw} Token (raw)'
                    : _displayNativeRaw(original.amountRaw, original),
                mono: true,
              ),
            ],
          ),
        ),
      ),
    );
    if (confirmed != true || !mounted) return;

    final authenticated = await widget.authGate.authenticate(
      context,
      method: AppPrefsScope.maybeOf(context)?.authMethod ?? AuthMethod.password,
      reason: cancel ? l10n.txCancelConfirm : l10n.txSpeedUpConfirm,
    );
    if (!authenticated || !mounted) return;

    final controller = WalletScope.of(context);
    final wallet = controller.current;
    final chain = _chainFor(original);
    final networkScope = NetworkScope.maybeOf(context);
    // The ROW's network, not the active one (see [_rowNetwork]).
    final network = _rowNetwork(original);
    final nonce = BigInt.tryParse(original.nonce ?? '');
    final priority = BigInt.tryParse(original.maxPriorityFeeRaw ?? '');
    final maxFee = BigInt.tryParse(original.maxFeeRaw ?? '');
    final gasLimit = BigInt.tryParse(original.gasLimitRaw ?? '');
    if (wallet is! HotWallet ||
        controller.allowsTestBypass ||
        chain == null ||
        network?.evmChainId == null ||
        nonce == null ||
        priority == null ||
        maxFee == null ||
        gasLimit == null) {
      _showMessage(l10n.txReplacementUnavailable);
      return;
    }
    // Refuse rather than silently rebuilding on whatever is selected now: the
    // endpoints, nonce view and fee oracle all follow the ACTIVE network, so a
    // replacement is only meaningful while the row's own network is active.
    final rowNetwork = network!;
    if (!_rowNetworkIsActive(original)) {
      _showMessage(l10n.txReplacementWrongNetwork(rowNetwork.name));
      return;
    }

    setState(() => _submitting = true);
    final prefs = AppPrefsScope.maybeOf(context);
    final service =
        widget.transferService ??
        LocalTransferService(
          endpoints: effectiveRpcEndpoints(prefs, networkScope),
          gateway: prefsGatewayResolver(prefs),
        );
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    final replacementId =
        'replacement_${createdAt}_${cancel ? 'cancel' : 'speed'}';
    var reserved = false;
    var signedHashPersisted = false;
    var broadcastAttempted = false;
    String? localSignedHash;
    String? broadcastHash;
    try {
      final prepared = await service.prepareEvmReplacement(
        chain: chain,
        evmChainId: rowNetwork.evmChainId!,
        from: original.fromAddr,
        recipient: original.toAddr,
        amountRaw: BigInt.parse(original.amountRaw),
        tokenContract: original.contract,
        operation: original.operation == TxOperationKind.approvalRevoke
            ? TxOperation.approvalRevoke
            : null,
        nonce: nonce,
        previousMaxPriorityFeePerGas: priority,
        previousMaxFeePerGas: maxFee,
        previousGasLimit: gasLimit,
        cancel: cancel,
      );
      await controller.reserveOutgoingEvmTransaction(
        id: replacementId,
        coin: prepared.coin,
        // The replacement lives on the SAME network as the row it replaces.
        networkId: rowNetwork.id,
        contract: prepared.tokenContract,
        operation: prepared.operation == TxOperation.approvalRevoke && !cancel
            ? TxOperationKind.approvalRevoke
            : TxOperationKind.transfer,
        from: prepared.from,
        to: prepared.recipient,
        amountRaw: prepared.amountRaw.toString(),
        feeRaw: prepared.maximumFee.toString(),
        signMode: SignMode.local,
        createdAt: createdAt,
        nonce: prepared.nonce.toString(),
        maxPriorityFeeRaw: prepared.maxPriorityFeePerGas.toString(),
        maxFeeRaw: prepared.maxFeePerGas.toString(),
        gasLimitRaw: prepared.gasLimit.toString(),
        replacesId: original.id,
        replacementKind: cancel
            ? TxReplacementKind.cancel
            : TxReplacementKind.speedUp,
      );
      reserved = true;
      final signed = await service.signPreparedEvm(
        wallet: wallet,
        crypto: controller.crypto,
        prepared: prepared,
      );
      localSignedHash = signed.txHash;
      await controller.updateTransactionStatus(
        replacementId,
        TxStatus.submitted,
        hash: signed.txHash,
        broadcastAt: DateTime.now().millisecondsSinceEpoch,
      );
      signedHashPersisted = true;
      broadcastAttempted = true;
      final hash = await service.broadcastSigned(
        prepared.chain,
        signed.signedTx,
        expectedTxHash: signed.txHash,
      );
      broadcastHash = hash;
      final accepted = await controller.recordEvmReplacementBroadcast(
        originalId: original.id,
        replacementId: replacementId,
        hash: hash,
        broadcastAt: DateTime.now().millisecondsSinceEpoch,
      );
      if (!mounted) return;
      _reload(replacementId);
      _showMessage(
        accepted ? l10n.txReplacementSubmitted : l10n.txReplacementRace,
      );
    } on EvmNonceAlreadyConsumed {
      _showMessage(l10n.txNonceAlreadyUsed);
      _reload();
    } on EvmNonceConflict {
      _showMessage(l10n.nonceConflict);
      _reload();
    } on EvmPreflightFailed {
      _showMessage(l10n.transactionSimulationFailed);
    } on LocalTransferUncertainException {
      _reload(replacementId);
      _showMessage(l10n.txSubmissionUnknownMessage);
    } on LocalTransferRejectedException catch (error) {
      if (reserved) {
        try {
          await controller.updateTransactionStatus(
            replacementId,
            TxStatus.failed,
            hash: localSignedHash,
          );
        } catch (_) {
          // Preserve the authoritative rejection reason.
        }
      }
      _reload(replacementId);
      _showMessage(localizedRpcRejection(l10n, error.kind));
    } on LocalTransferUnsupportedException {
      if (reserved) {
        try {
          await controller.updateTransactionStatus(
            replacementId,
            TxStatus.failed,
            hash: localSignedHash,
          );
        } catch (_) {
          // Preserve the unsupported-broadcast reason.
        }
      }
      _reload(replacementId);
      _showMessage(l10n.broadcastUnsupported);
    } on Object {
      if (broadcastHash != null) {
        // Broadcast already succeeded and the replacement row already holds
        // its locally derived hash. Reload it instead of inviting another
        // same-nonce replacement when only the lineage update failed.
        if (mounted) {
          _reload(replacementId);
          _showMessage(l10n.txReplacementSubmitted);
        }
        return;
      }
      if (broadcastAttempted && signedHashPersisted) {
        _reload(replacementId);
        _showMessage(l10n.txSubmissionUnknownMessage);
        return;
      }
      if (reserved) {
        try {
          await controller.updateTransactionStatus(
            replacementId,
            TxStatus.failed,
            hash: signedHashPersisted ? localSignedHash : null,
          );
        } catch (_) {
          // Preserve the original preparation/signing failure. The failed
          // marker is best-effort and no irreversible broadcast occurred.
        }
      }
      if (mounted) _showMessage(l10n.transactionNotSubmitted);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.transaction != null) {
      return _buildLive(context, widget.transaction!);
    }
    final record = widget.chainRecord;
    if (record != null) return _buildChainOnly(context, record);
    // Scope-absent gallery / goldens only: every real row now arrives with an
    // id or a chain record. Keep the screen fail-closed even when embedded
    // outside GoRouter so a future route cannot expose the visual fixture.
    if (_activeId == null) {
      final controller = WalletScope.maybeOf(context);
      if (controller == null || controller.allowsTestBypass) {
        return _buildDemo(context);
      }
      return KtScreen(
        navBar: KtNavBar(
          title: AppLocalizations.of(context).txDetailTitle,
          onBack: () => Navigator.of(context).maybePop(),
        ),
        children: [
          Center(child: Text(AppLocalizations.of(context).txNotFound)),
        ],
      );
    }
    return FutureBuilder<Transaction?>(
      future: _transaction,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return KtScreen(
            navBar: KtNavBar(
              title: AppLocalizations.of(context).txDetailTitle,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            children: const [Center(child: CircularProgressIndicator())],
          );
        }
        final transaction = snapshot.data;
        if (transaction == null) {
          return KtScreen(
            navBar: KtNavBar(
              title: AppLocalizations.of(context).txDetailTitle,
              onBack: () => Navigator.of(context).maybePop(),
            ),
            children: [
              Center(child: Text(AppLocalizations.of(context).txNotFound)),
            ],
          );
        }
        return _buildLive(context, transaction);
      },
    );
  }

  Widget _buildLive(BuildContext context, Transaction tx) {
    final l10n = AppLocalizations.of(context);
    final statusColor = _statusColor(tx);
    final chain = _chainFor(tx);
    // The row's own network (falling back to its recorded id, then to the
    // active instance for legacy rows) — never relabel a Sepolia transfer
    // "Ethereum" just because mainnet is selected now.
    final networkName =
        _rowNetwork(tx)?.name ??
        tx.networkId ??
        (chain == null
            ? tx.coin
            : NetworkScope.of(context).activeFor(chain).name);
    final receipt = _receiptForLive(context, tx);
    // Replacement is offered only while the row's own network is active.
    final canReplace = _canReplace(tx) && _rowNetworkIsActive(tx);
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(
        title: l10n.txDetailTitle,
        onBack: () => Navigator.of(context).maybePop(),
        trailing: receipt == null ? null : Icons.open_in_new,
        trailingTooltip: l10n.txViewInExplorer,
        onTrailing: receipt == null ? null : () => _openExplorer(tx),
      ),
      bottom: canReplace
          ? Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                KtPrimaryButton(
                  label: l10n.txSpeedUp,
                  icon: Icons.bolt_rounded,
                  onPressed: _submitting
                      ? null
                      : () => _replace(tx, cancel: false),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton.icon(
                    onPressed: _submitting
                        ? null
                        : () => _replace(tx, cancel: true),
                    icon: const Icon(Icons.cancel_outlined),
                    label: Text(l10n.txCancelTransaction),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: WalletColors.red,
                      side: const BorderSide(color: WalletColors.red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : null,
      children: [
        Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(_statusIcon(tx), size: 28, color: statusColor),
            ),
            const SizedBox(height: 10),
            Text(
              _displayAmount(context, tx),
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: WalletColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${_statusLabel(l10n, tx)} · ${_date(tx.createdAt)}',
              style: const TextStyle(fontSize: 13, color: WalletColors.text3),
            ),
          ],
        ),
        KtCard(
          child: Column(
            children: [
              KtDetailRow(label: l10n.networkRow, value: networkName),
              const SizedBox(height: 14),
              KtDetailRow(
                label: tx.operation == TxOperationKind.approvalRevoke
                    ? l10n.approvalSpender
                    : l10n.recipientAddress,
                value: _short(tx.toAddr),
                mono: true,
              ),
              const SizedBox(height: 14),
              KtDetailRow(
                label: l10n.txRawAmountLabel,
                value: tx.amountRaw,
                mono: true,
              ),
              if (tx.feeRaw != null) ...[
                const SizedBox(height: 14),
                KtDetailRow(
                  label: l10n.networkFee,
                  value: _displayNativeRaw(tx.feeRaw!, tx),
                  mono: true,
                ),
              ],
              if (tx.nonce != null) ...[
                const SizedBox(height: 14),
                KtDetailRow(
                  label: l10n.txNonceLabel,
                  value: tx.nonce!,
                  mono: true,
                ),
              ],
              if (tx.hash != null) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: KtDetailRow(
                        label: l10n.txHash,
                        value: _short(tx.hash!),
                        mono: true,
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      key: const ValueKey('copy-transaction-hash'),
                      tooltip: l10n.txCopyHash,
                      onPressed: () => _copyHash(tx.hash!),
                      icon: const Icon(Icons.copy_rounded, size: 19),
                      color: WalletColors.accent,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              KtDetailRow(
                label: l10n.txBroadcastTime,
                value: tx.broadcastAt == null ? '--' : _date(tx.broadcastAt!),
              ),
              const SizedBox(height: 14),
              KtDetailRow(
                label: l10n.txLastStatusCheck,
                value: (_lastCheckedAt ?? tx.lastCheckedAt) == null
                    ? l10n.txNotCheckedYet
                    : _date((_lastCheckedAt ?? tx.lastCheckedAt)!),
              ),
              const SizedBox(height: 14),
              KtDetailRow(
                label: l10n.statusLabel,
                value: _statusLabel(l10n, tx),
                valueColor: statusColor,
              ),
              if (tx.replacesId != null) ...[
                const SizedBox(height: 14),
                KtDetailRow(
                  label: l10n.txReplacesLabel,
                  value: _short(tx.replacesId!),
                  mono: true,
                ),
              ],
              if (tx.replacedById != null) ...[
                const SizedBox(height: 14),
                KtDetailRow(
                  label: tx.status == TxStatus.replaced
                      ? l10n.txReplacedByLabel
                      : l10n.txReplacementPendingLabel,
                  value: _short(tx.replacedById!),
                  mono: true,
                ),
              ],
            ],
          ),
        ),
        if (receipt != null)
          SizedBox(
            width: double.infinity,
            height: 50,
            child: OutlinedButton.icon(
              key: const ValueKey('view-transaction-in-explorer'),
              onPressed: () => _openExplorer(tx),
              icon: const Icon(Icons.open_in_new_rounded, size: 19),
              label: Text(l10n.txViewInExplorer),
              style: OutlinedButton.styleFrom(
                foregroundColor: WalletColors.accent,
                side: BorderSide(
                  color: WalletColors.accent.withValues(alpha: 0.35),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
        if (receipt != null)
          _TransactionReceiptPanel(
            exporting: _exportingReceipt,
            title: l10n.exportTransactionReceipt,
            subtitle: l10n.exportTransactionReceiptSubtitle,
            onTap: () => _chooseReceiptExport(receipt),
          ),
      ],
    );
  }

  /// A transaction this wallet did not broadcast: the chain gave us a hash, a
  /// direction, a time and (usually) an amount, and nothing else. Everything
  /// unknown is left out rather than filled in.
  Widget _buildChainOnly(BuildContext context, ChainTxRecord record) {
    final l10n = AppLocalizations.of(context);
    final network = _networkForChainRecord(context, record);
    final url = network == null ? null : explorerTxUrl(network, record.hash);
    final receipt = _receiptForChainRecord(context, record);
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(
        title: l10n.txDetailTitle,
        onBack: () => Navigator.of(context).maybePop(),
        trailing: url == null ? null : Icons.open_in_new,
        trailingTooltip: l10n.txViewInExplorer,
        onTrailing: url == null
            ? null
            : () async {
                final opened = await ExternalActions.instance.open(
                  Uri.parse(url),
                );
                if (!opened && context.mounted) {
                  ScaffoldMessenger.of(context)
                    ..clearSnackBars()
                    ..showSnackBar(
                      SnackBar(content: Text(l10n.externalActionFailed)),
                    );
                }
              },
      ),
      children: [
        Column(
          children: [
            Icon(
              record.outgoing ? Icons.north_east : Icons.south_west,
              size: 40,
              color: record.outgoing ? WalletColors.text : WalletColors.green,
            ),
            const SizedBox(height: 10),
            Text(
              record.amountText ?? '--',
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: WalletColors.text,
              ),
            ),
            if (!record.assetVerified) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: WalletColors.amber.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: WalletColors.amber.withValues(alpha: 0.32),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      size: 20,
                      color: WalletColors.amber,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        record.impersonatesProtectedSymbol
                            ? l10n.tokenImpersonationWarning(
                                record.assetSymbol!,
                              )
                            : l10n.unverifiedToken,
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.4,
                          fontWeight: FontWeight.w600,
                          color: WalletColors.amber,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              _chainTxStatusLabel(l10n, record.status),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: _chainTxStatusColor(record.status),
              ),
            ),
          ],
        ),
        KtCard(
          child: Column(
            children: [
              KtDetailRow(
                label: l10n.statusLabel,
                value: record.outgoing ? l10n.txSent : l10n.txReceived,
              ),
              const SizedBox(height: 14),
              if (network != null)
                KtDetailRow(label: l10n.networkRow, value: network.name),
              if (record.fromAddress != null) ...[
                const SizedBox(height: 14),
                KtDetailRow(
                  label: l10n.transactionSourceAddress,
                  value: _short(record.fromAddress!),
                  mono: true,
                ),
              ],
              if (record.toAddress != null) ...[
                const SizedBox(height: 14),
                KtDetailRow(
                  label: l10n.transactionDestinationAccount,
                  value: _destinationAccountValue(
                    context,
                    chainOf(record.coin),
                    record.toAddress!,
                  ),
                  mono: true,
                ),
              ],
              if (record.assetContract != null) ...[
                const SizedBox(height: 14),
                KtDetailRow(
                  label: l10n.contractAddress,
                  value: record.assetContract!,
                  mono: true,
                ),
              ],
              const SizedBox(height: 14),
              KtDetailRow(
                label: l10n.txTimeLabel,
                value: _date(record.timestamp.millisecondsSinceEpoch),
              ),
              const SizedBox(height: 14),
              KtDetailRow(
                label: l10n.txHash,
                value: _short(record.hash),
                mono: true,
              ),
            ],
          ),
        ),
        if (receipt != null)
          _TransactionReceiptPanel(
            exporting: _exportingReceipt,
            title: l10n.exportTransactionReceipt,
            subtitle: l10n.exportTransactionReceiptSubtitle,
            onTap: () => _chooseReceiptExport(receipt),
          ),
      ],
    );
  }

  Widget _buildDemo(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(
        title: l10n.txDetailTitle,
        onBack: () => Navigator.of(context).maybePop(),
        trailing: Icons.open_in_new,
        trailingTooltip: l10n.txViewInExplorer,
        onTrailing: () async {
          // Explorer follows the ACTIVE tron network (the displayed demo tx
          // is a TRON transfer): Nile's tronscan under the testnet
          // environment, tronscan.org on mainnet — identical to the previous
          // hardcoded link when no override is active.
          final opened = await ExternalActions.instance.open(
            Uri.parse(
              explorerTxUrl(
                NetworkScope.of(context).activeFor(Chain.tron),
                TxDetailScreen._txHash,
              )!,
            ),
          );
          if (!opened && context.mounted) {
            ScaffoldMessenger.of(context)
              ..clearSnackBars()
              ..showSnackBar(
                SnackBar(content: Text(l10n.externalActionFailed)),
              );
          }
        },
      ),
      children: [
        Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: WalletColors.green.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle,
                size: 28,
                color: WalletColors.green,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '-120.00 USDT',
              style: TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.5,
                color: WalletColors.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${l10n.confirmedPrefix} · ${l10n.dateToday} 14:38',
              style: const TextStyle(fontSize: 13, color: WalletColors.text3),
            ),
          ],
        ),
        KtCard(
          child: Column(
            children: [
              KtDetailRow(label: l10n.networkRow, value: 'TRON · TRC-20'),
              const SizedBox(height: 14),
              KtDetailRow(
                label: l10n.recipientAddress,
                value: 'TWd4qCEU…nMxR38uQz',
                mono: true,
              ),
              const SizedBox(height: 14),
              KtDetailRow(label: l10n.networkFee, value: '13.72 TRX（\$1.91）'),
              const SizedBox(height: 14),
              KtDetailRow(label: l10n.confirmations, value: '19 / 19'),
              const SizedBox(height: 14),
              KtDetailRow(
                label: l10n.requestId,
                value: 'REQ-7F3A2C',
                mono: true,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _ReceiptExportAction { save, share }

class _TransactionReceiptPanel extends StatelessWidget {
  const _TransactionReceiptPanel({
    required this.exporting,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool exporting;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    key: const ValueKey('transaction-export-receipt'),
    color: WalletColors.surface,
    borderRadius: BorderRadius.circular(18),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: exporting ? null : onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF5578FF), Color(0xFF3155DD)],
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              child: exporting
                  ? const Padding(
                      padding: EdgeInsets.all(13),
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(
                      Icons.qr_code_2_rounded,
                      size: 24,
                      color: Colors.white,
                    ),
            ),
            const SizedBox(width: 13),
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
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: WalletColors.text3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 15,
              color: WalletColors.text3,
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReceiptActionTile extends StatelessWidget {
  const _ReceiptActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: WalletColors.bg,
    borderRadius: BorderRadius.circular(16),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: WalletColors.accent.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 21, color: WalletColors.accent),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: WalletColors.text,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: WalletColors.text3),
          ],
        ),
      ),
    ),
  );
}

/// W30 转账身份验证 (bottom sheet). Production submits through native Wallet
/// Core, whose protected key access supplies the device authentication prompt.
/// An injected [BiometricAuth] keeps widget tests deterministic.
class InvalidTransferState extends StatelessWidget {
  const InvalidTransferState({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      backgroundColor: WalletColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 48, 24, 24),
          child: Column(
            children: [
              const Spacer(),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: WalletColors.red.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.shield_outlined,
                  size: 34,
                  color: WalletColors.red,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                l10n.signRequestBuildFailed,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.55,
                  fontWeight: FontWeight.w600,
                  color: WalletColors.text,
                ),
              ),
              const Spacer(),
              KtPrimaryButton(
                label: l10n.backToHome,
                onPressed: () => context.go('/home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TransferAuthSheet extends StatelessWidget {
  const TransferAuthSheet({super.key, this.auth, this.transferService});

  /// Injectable authenticator; defaults to [BiometricAuth.instance].
  final BiometricAuth? auth;
  final LocalTransferService? transferService;

  Future<void> _faceId(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final session = TransferSessionScope.maybeOf(context);
    final controller = WalletScope.of(context);
    // A real transfer is authenticated by the native CoreCrypto operation
    // that releases the key for signing. Running local_auth first would show
    // two consecutive system prompts while only the second protects the key.
    // Gallery/test flows still use the injectable facade.
    if (auth == null &&
        session?.draft != null &&
        !controller.allowsTestBypass) {
      await _submitLive(context);
      return;
    }
    final outcome = await (auth ?? BiometricAuth.instance).authenticate(
      reason: l10n.authToConfirmTransfer,
    );
    if (!context.mounted) return;
    switch (outcome) {
      case BiometricOutcome.success:
        await _submitLive(context);
      case BiometricOutcome.failure:
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(l10n.biometricFailedRetry)));
      case BiometricOutcome.unavailable:
        ScaffoldMessenger.of(context)
          ..clearSnackBars()
          ..showSnackBar(SnackBar(content: Text(l10n.biometricUnavailable)));
    }
  }

  Future<void> _usePin(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final pin = WalletPin.instance;
    if (!await pin.isSet()) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(l10n.biometricUnavailable)));
      return;
    }
    if (!context.mounted) return;
    final verified = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WalletColors.surface,
      builder: (_) => _TransferPinSheet(pin: pin),
    );
    if (verified == true && context.mounted) {
      await _submitLive(context);
    }
  }

  Future<void> _submitLive(BuildContext context) async {
    final session = TransferSessionScope.maybeOf(context);
    final draft = session?.draft;
    final controller = WalletScope.of(context);
    final wallet = controller.current;
    // Standalone gallery fixtures retain their navigation-only behavior.
    if (controller.allowsTestBypass) {
      if (context.mounted) context.go('/broadcast-result');
      return;
    }
    // A route/deep-link without the in-memory draft cannot prove what the user
    // confirmed. Do not sign, broadcast, or render a fabricated success.
    if (draft == null || wallet is! HotWallet) {
      if (context.mounted) context.go('/home');
      return;
    }
    final networkScope = NetworkScope.maybeOf(context);
    final network = networkScope?.activeFor(draft.chain);
    final chainId = network?.evmChainId;
    final isEvm = switch (draft.chain) {
      Chain.ethereum ||
      Chain.polygon ||
      Chain.base ||
      Chain.arbitrum ||
      Chain.avalanche ||
      Chain.bnb => true,
      Chain.tron || Chain.solana => false,
    };
    if (network == null) {
      _showTransferError(
        context,
        AppLocalizations.of(
          context,
        ).transferNetworkUnavailable(draft.chain.name),
      );
      return;
    }
    if (isEvm && chainId == null) {
      _showTransferError(
        context,
        AppLocalizations.of(context).transferChainIdUnavailable,
      );
      return;
    }
    final prefs = AppPrefsScope.maybeOf(context);
    final service =
        transferService ??
        LocalTransferService(
          endpoints: effectiveRpcEndpoints(prefs, networkScope),
          gateway: prefsGatewayResolver(prefs),
        );
    final createdAt = DateTime.now().millisecondsSinceEpoch;
    final id = session!.localTransactionId ??= 'local_$createdAt';
    final coin = rpcCoinForChain(draft.chain);
    final from = addressForChain(wallet.addresses, draft.chain);
    var reserved = false;
    var signedHashPersisted = false;
    var broadcastAttempted = false;
    String? localSignedHash;
    String? broadcastHash;
    try {
      final String hash;
      if (isEvm) {
        final approved = session.validEvmQuote(
          forDraft: draft,
          networkId: network.id,
          evmChainId: chainId!,
          from: from,
        );
        if (approved == null) {
          if (context.mounted) {
            context.go('/confirm-hot');
          }
          return;
        }
        await controller.reserveOutgoingEvmTransaction(
          id: id,
          coin: approved.coin,
          networkId: network.id,
          contract: approved.tokenContract,
          operation: approved.operation == TxOperation.approvalRevoke
              ? TxOperationKind.approvalRevoke
              : TxOperationKind.transfer,
          from: approved.from,
          to: approved.recipient,
          amountRaw: approved.amountRaw.toString(),
          feeRaw: approved.maximumFee.toString(),
          signMode: SignMode.local,
          createdAt: createdAt,
          nonce: approved.nonce.toString(),
          maxPriorityFeeRaw: approved.maxPriorityFeePerGas.toString(),
          maxFeeRaw: approved.maxFeePerGas.toString(),
          gasLimitRaw: approved.gasLimit.toString(),
        );
        reserved = true;
        final signed = await service.signPreparedEvm(
          wallet: wallet,
          crypto: controller.crypto,
          prepared: approved,
        );
        localSignedHash = signed.txHash;
        await controller.updateTransactionStatus(
          id,
          TxStatus.submitted,
          hash: signed.txHash,
          broadcastAt: DateTime.now().millisecondsSinceEpoch,
        );
        signedHashPersisted = true;
        broadcastAttempted = true;
        hash = await service.broadcastSigned(
          draft.chain,
          signed.signedTx,
          expectedTxHash: signed.txHash,
        );
        broadcastHash = hash;
        await controller.updateTransactionStatus(
          id,
          TxStatus.pending,
          hash: hash,
          broadcastAt: DateTime.now().millisecondsSinceEpoch,
        );
      } else {
        if (draft.chain == Chain.tron) {
          final approved = session.validTronQuote(
            forDraft: draft,
            networkId: network.id,
            from: from,
          );
          if (approved == null) {
            if (context.mounted) context.go('/confirm-hot');
            return;
          }
          await controller.saveOutgoingTransaction(
            id: id,
            coin: coin,
            networkId: network.id,
            contract: draft.tokenContract,
            operation: draft.operation == TxOperation.approvalRevoke
                ? TxOperationKind.approvalRevoke
                : TxOperationKind.transfer,
            from: from,
            to: draft.recipient,
            amountRaw: draft.amount.raw.toString(),
            feeRaw: approved.maximumFeeSun.toString(),
            status: TxStatus.submitted,
            signMode: SignMode.local,
            createdAt: createdAt,
            referenceBlockHeight: approved.referenceBlockHeight,
            expiresAt: approved.expiresAt,
          );
          reserved = true;
          session
            ..referenceBlockHeight = approved.referenceBlockHeight
            ..expiresAt = approved.expiresAt;
          final signed = await service.signPreparedTron(
            wallet: wallet,
            crypto: controller.crypto,
            prepared: approved,
            expectedNetworkIdentity: network.networkIdentity,
          );
          localSignedHash = signed.txHash;
          await controller.updateTransactionStatus(
            id,
            TxStatus.submitted,
            hash: signed.txHash,
            broadcastAt: DateTime.now().millisecondsSinceEpoch,
          );
          signedHashPersisted = true;
          broadcastAttempted = true;
          hash = await service.broadcastSigned(
            Chain.tron,
            signed.signedTx,
            expectedTxHash: signed.txHash,
          );
          broadcastHash = hash;
        } else {
          final approved = session.validSolanaQuote(
            forDraft: draft,
            networkId: network.id,
            from: from,
          );
          if (approved == null) {
            if (context.mounted) context.go('/confirm-hot');
            return;
          }
          await controller.saveOutgoingTransaction(
            id: id,
            coin: coin,
            networkId: network.id,
            contract: draft.tokenContract,
            operation: TxOperationKind.transfer,
            from: from,
            to: draft.recipient,
            amountRaw: draft.amount.raw.toString(),
            feeRaw: approved.networkFeeLamports.toString(),
            status: TxStatus.submitted,
            signMode: SignMode.local,
            createdAt: createdAt,
            lastValidBlockHeight: approved.lastValidBlockHeight,
          );
          reserved = true;
          session.lastValidBlockHeight = approved.lastValidBlockHeight;
          final signed = await service.signPreparedSolana(
            wallet: wallet,
            crypto: controller.crypto,
            prepared: approved,
            expectedNetworkIdentity: network.networkIdentity,
          );
          localSignedHash = signed.txHash;
          await controller.updateTransactionStatus(
            id,
            TxStatus.submitted,
            hash: signed.txHash,
            broadcastAt: DateTime.now().millisecondsSinceEpoch,
          );
          signedHashPersisted = true;
          broadcastAttempted = true;
          hash = await service.broadcastSigned(
            Chain.solana,
            signed.signedTx,
            expectedTxHash: signed.txHash,
          );
          broadcastHash = hash;
        }
        await controller.updateTransactionStatus(
          id,
          TxStatus.pending,
          hash: hash,
          broadcastAt: DateTime.now().millisecondsSinceEpoch,
        );
      }
      if (draft.operation != TxOperation.approvalRevoke) {
        await controller.saveIncomingForLocalWallets(
          coin: coin,
          networkId: network.id,
          contract: draft.tokenContract,
          from: from,
          to: draft.recipient,
          amountRaw: draft.amount.raw.toString(),
          hash: hash,
          createdAt: createdAt,
          broadcastAt: DateTime.now().millisecondsSinceEpoch,
          referenceBlockHeight: session.referenceBlockHeight,
          expiresAt: session.expiresAt,
          lastValidBlockHeight: session.lastValidBlockHeight,
        );
      }
      session
        ..broadcastTxHash = hash
        ..broadcastOutcomeUnknown = false;
      if (context.mounted) context.go('/broadcast-result');
    } on EvmNonceConflict {
      if (context.mounted) {
        _showTransferError(context, AppLocalizations.of(context).nonceConflict);
      }
    } on EvmPreflightFailed {
      if (context.mounted) {
        _showTransferError(
          context,
          AppLocalizations.of(context).transactionSimulationFailed,
        );
      }
    } on LocalTransferUncertainException {
      // The single network write may have succeeded. The durable local hash
      // is the only safe recovery key; navigate to reconciliation and never
      // expose the auth button as an invitation to submit the same action.
      if (signedHashPersisted && localSignedHash != null) {
        session
          ..broadcastTxHash = localSignedHash
          ..broadcastOutcomeUnknown = true;
        if (context.mounted) context.go('/broadcast-result');
      } else if (context.mounted) {
        _showTransferError(
          context,
          AppLocalizations.of(context).txSubmissionUnknownMessage,
        );
      }
    } on LocalTransferRejectedException catch (error) {
      if (reserved) {
        try {
          await controller.updateTransactionStatus(
            id,
            TxStatus.failed,
            hash: localSignedHash,
          );
        } catch (_) {
          // Preserve the authoritative node rejection in the UI.
        }
      }
      if (context.mounted) {
        _showTransferError(
          context,
          localizedRpcRejection(AppLocalizations.of(context), error.kind),
        );
      }
    } on LocalTransferUnsupportedException {
      if (reserved) {
        try {
          await controller.updateTransactionStatus(
            id,
            TxStatus.failed,
            hash: localSignedHash,
          );
        } catch (_) {
          // Preserve the unsupported-broadcast reason in the UI.
        }
      }
      if (context.mounted) {
        _showTransferError(
          context,
          AppLocalizations.of(context).broadcastUnsupported,
        );
      }
    } on Object {
      if (broadcastHash != null) {
        // The irreversible boundary succeeded and the pre-broadcast row with
        // its local hash is already durable. Do not invite a duplicate send
        // merely because the best-effort pending/mirror update failed.
        session
          ..broadcastTxHash = broadcastHash
          ..broadcastOutcomeUnknown = false;
        if (context.mounted) context.go('/broadcast-result');
        return;
      }
      // A transport exception after the locally derived hash was persisted
      // does not prove rejection: the node may have accepted the bytes before
      // its response was lost. Keep `submitted` so restart polling resolves
      // the authoritative chain outcome.
      if (broadcastAttempted && localSignedHash != null) {
        session
          ..broadcastTxHash = localSignedHash
          ..broadcastOutcomeUnknown = true;
        if (context.mounted) context.go('/broadcast-result');
        return;
      }
      if (reserved) {
        try {
          await controller.updateTransactionStatus(
            id,
            TxStatus.failed,
            hash: signedHashPersisted ? localSignedHash : null,
          );
        } catch (_) {
          // Keep the original persistence/signing error. No broadcast was
          // attempted before a signed hash became durable.
        }
      }
      if (context.mounted) {
        _showTransferError(
          context,
          AppLocalizations.of(context).transactionNotSubmitted,
        );
      }
    }
  }

  void _showTransferError(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final controller = WalletScope.of(context);
    final draft = TransferSessionScope.maybeOf(context)?.draft;
    if (!controller.allowsTestBypass &&
        (draft == null || controller.current is! HotWallet)) {
      return const InvalidTransferState();
    }
    final passwordFirst =
        AppPrefsScope.maybeOf(context)?.authMethod == AuthMethod.password;
    return Scaffold(
      backgroundColor: WalletColors.text.withValues(alpha: 0.5),
      body: Semantics(
        button: true,
        label: MaterialLocalizations.of(context).modalBarrierDismissLabel,
        child: GestureDetector(
          // Tapping the dimmed scrim dismisses the auth sheet (opaque so the
          // unpainted region above the card still hit-tests here); the inner
          // detector absorbs taps on the card itself.
          behavior: HitTestBehavior.opaque,
          onTap: () => Navigator.of(context).maybePop(),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: GestureDetector(
              excludeFromSemantics: true,
              onTap: () {},
              child: Container(
                width: double.infinity,
                decoration: const BoxDecoration(
                  color: WalletColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                child: SafeArea(
                  top: false,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(context).height * 0.92,
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: WalletColors.border,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Container(
                            width: 88,
                            height: 88,
                            decoration: BoxDecoration(
                              color: WalletColors.accent.withValues(
                                alpha: 0.06,
                              ),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              passwordFirst
                                  ? Icons.password_rounded
                                  : Icons.face,
                              size: 44,
                              color: WalletColors.accent,
                            ),
                          ),
                          const SizedBox(height: 20),
                          Semantics(
                            header: true,
                            child: Text(
                              l10n.authToConfirmTransfer,
                              style: const TextStyle(
                                fontSize: 19,
                                fontWeight: FontWeight.w700,
                                color: WalletColors.text,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.authEveryTransfer,
                            style: const TextStyle(
                              fontSize: 13,
                              color: WalletColors.text2,
                            ),
                          ),
                          const SizedBox(height: 20),
                          KtPrimaryButton(
                            label: passwordFirst
                                ? l10n.authPassword
                                : l10n.useFaceId,
                            onPressed: () => passwordFirst
                                ? _usePin(context)
                                : _faceId(context),
                          ),
                          const SizedBox(height: 12),
                          TextButton(
                            onPressed: () => passwordFirst
                                ? _faceId(context)
                                : _usePin(context),
                            style: TextButton.styleFrom(
                              foregroundColor: WalletColors.text2,
                              minimumSize: const Size(48, 48),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              textStyle: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            child: Text(
                              passwordFirst
                                  ? l10n.authBiometrics
                                  : l10n.usePasscode,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TransferPinSheet extends StatefulWidget {
  const _TransferPinSheet({required this.pin});

  final WalletPin pin;

  @override
  State<_TransferPinSheet> createState() => _TransferPinSheetState();
}

class _TransferPinSheetState extends State<_TransferPinSheet> {
  String _entry = '';
  String? _error;
  bool _busy = false;

  Future<void> _key(String key) async {
    if (_busy) return;
    if (key == 'del') {
      if (_entry.isNotEmpty) {
        setState(() {
          _entry = _entry.substring(0, _entry.length - 1);
          _error = null;
        });
      }
      return;
    }
    if (_entry.length >= 6) return;
    setState(() {
      _entry += key;
      _error = null;
    });
    if (_entry.length != 6) return;
    setState(() => _busy = true);
    final verdict = await widget.pin.verify(_entry);
    if (!mounted) return;
    if (verdict.isOk) {
      Navigator.of(context).pop(true);
      return;
    }
    final l10n = AppLocalizations.of(context);
    setState(() {
      _entry = '';
      _busy = false;
      _error = verdict.isLocked
          ? l10n.pinLockedRetry(verdict.lockRemaining!.inSeconds + 1)
          : l10n.pinIncorrect;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          20,
          24,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.usePasscode,
              style: const TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w700,
                color: WalletColors.text,
              ),
            ),
            const SizedBox(height: 18),
            PinDots(filled: _entry.length),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: WalletColors.red),
              ),
            ],
            const SizedBox(height: 18),
            PinPad(onKey: _key),
          ],
        ),
      ),
    );
  }
}

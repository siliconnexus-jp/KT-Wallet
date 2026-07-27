import 'package:chains/chains.dart';
import 'package:core_crypto/core_crypto.dart' show Coin;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:ui_kit/ui_kit.dart';
import 'package:wallet_data/wallet_data.dart' show Contact, CustomToken;

import '../../l10n/app_localizations.dart';
import '../market/balance_service.dart' show defaultRpcEndpointFor;
import '../market/gateway_client.dart' show GatewayClient;
import '../market/rpc_health.dart';
import '../market/token_balance_service.dart'
    show
        isKnownOfficialTokenIdentity,
        isProtectedTokenSymbol,
        officialBusdEthereumContract,
        usdcSolanaToken,
        usdtEthToken,
        usdtTronToken;
import '../security/biometric_auth.dart';
import '../security/wallet_pin.dart';
import '../widgets/pin_pad.dart';
import '../widgets/rpc_probe.dart';
import '../widgets/token_icon.dart';
import '../state/app_prefs.dart';
import '../state/networks.dart';
import '../state/locale_controller.dart';
import '../state/wallet_controller.dart';
import '../state/wallet_scope.dart';
import '../wallets/wallet_model.dart';

/// Display name + badge color per validated chain (address book rows).
const _chainTags = [
  (Chain.ethereum, 'Ethereum', ChainColors.ethereum),
  (Chain.polygon, 'Polygon', ChainColors.polygon),
  (Chain.base, 'Base', ChainColors.base),
  (Chain.arbitrum, 'Arbitrum', ChainColors.arbitrum),
  (Chain.avalanche, 'Avalanche', ChainColors.avalanche),
  (Chain.tron, 'TRON', ChainColors.tron),
  (Chain.solana, 'Solana', ChainColors.solana),
];

String _abbrevAddress(String a) =>
    a.length <= 18 ? a : '${a.substring(0, 8)}…${a.substring(a.length - 8)}';

/// Bottom-sheet form field matching the app's card inputs.
Widget _sheetField(
  TextEditingController controller, {
  required String label,
  bool mono = false,
  VoidCallback? onChanged,
}) => Column(
  crossAxisAlignment: CrossAxisAlignment.start,
  children: [
    Text(
      label,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: WalletColors.text2,
      ),
    ),
    const SizedBox(height: 8),
    Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: WalletColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WalletColors.border),
      ),
      child: TextField(
        controller: controller,
        onChanged: (_) => onChanged?.call(),
        autocorrect: false,
        enableSuggestions: false,
        style: TextStyle(
          fontSize: 14,
          fontFamily: mono ? KtFonts.mono : KtFonts.ui,
          color: WalletColors.text,
        ),
        decoration: const InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
        ),
      ),
    ),
  ],
);

Widget _switch(bool on, {VoidCallback? onTap}) => GestureDetector(
  behavior: HitTestBehavior.opaque,
  onTap: onTap,
  child: AnimatedContainer(
    duration: const Duration(milliseconds: 160),
    curve: Curves.easeOut,
    width: 44,
    height: 26,
    padding: const EdgeInsets.all(2),
    decoration: BoxDecoration(
      color: on ? WalletColors.accent : const Color(0xFFE1E4EA),
      borderRadius: BorderRadius.circular(13),
    ),
    child: AnimatedAlign(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      alignment: on ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    ),
  ),
);

/// Native display name for each supported language (shown in its own script,
/// the platform convention). "System" is localized.
String _languageLabel(AppLocalizations l10n, Locale? locale) {
  switch (locale?.languageCode) {
    case 'zh':
      return '简体中文';
    case 'en':
      return 'English';
    case 'ja':
      return '日本語';
    default:
      return l10n.languageSystem;
  }
}

/// W16 地址管理.
class AddressBookScreen extends StatefulWidget {
  const AddressBookScreen({super.key});
  @override
  State<AddressBookScreen> createState() => _AddressBookScreenState();
}

class _AddressBookScreenState extends State<AddressBookScreen> {
  String _query = '';

  /// Contacts rendered by this screen, loaded from (and mutated through) the
  /// [WalletController]: drift-persisted in the real app, in-memory in the
  /// gallery/goldens (no store).
  List<Contact> _contacts = const [];
  WalletController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = WalletScope.of(context);
    if (identical(controller, _controller)) return;
    _controller = controller;
    _load(controller);
  }

  Future<void> _load(WalletController controller) async {
    var contacts = await controller.loadContacts();
    if (contacts.isEmpty && !controller.hasStore) {
      // No-store fallback (gallery/goldens/tests): seed the classic demo rows
      // in-memory so the screen renders exactly like the recorded designs. The
      // real app persists these same rows on first run (see main._seedFirstRun).
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      for (final (name, address, chain) in [
        ('Alice', '0x71c8B2…9F3dA24', Chain.ethereum),
        (l10n.contactBobExchange, 'TWd4qCEU…nMxR38uQz', Chain.tron),
        (l10n.contactColdBackup, '0x8f3C2a…7E19bE1', Chain.polygon),
        ('Dana', '6yKp…Vr2W', Chain.solana),
      ]) {
        await controller.addContact(
          name: name,
          address: address,
          chain: chain.name,
        );
      }
      contacts = controller.contacts;
    }
    if (mounted) setState(() => _contacts = contacts);
  }

  /// Display fields for a stored contact: avatar initial, chain tag + color.
  (String, String, String, String, Color) _display(Contact c) {
    final tag = _chainTags.where((t) => t.$1.name == c.chain).firstOrNull;
    return (
      c.name.characters.first.toUpperCase(),
      c.name,
      _abbrevAddress(c.address),
      tag?.$2 ?? c.chain,
      tag?.$3 ?? WalletColors.text3,
    );
  }

  Future<void> _addContact() => _contactSheet();

  /// "+" / edit bottom sheet: name + address; the address must validate
  /// against one of the supported chains, whose tag/color the row inherits.
  ///
  /// With [existing] the sheet edits that contact in place instead of adding
  /// one — a typo in a name or address used to mean delete and re-enter.
  Future<void> _contactSheet({Contact? existing}) async {
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController(text: existing?.name ?? '');
    final addrController = TextEditingController(text: existing?.address ?? '');
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
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
                  Text(
                    existing == null
                        ? l10n.addContactTitle
                        : l10n.editContactTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: WalletColors.text,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sheetField(
                    nameController,
                    label: l10n.nameLabel,
                    onChanged: () => setSheetState(() {}),
                  ),
                  const SizedBox(height: 14),
                  _sheetField(
                    addrController,
                    label: l10n.addressLabel,
                    mono: true,
                    onChanged: () => setSheetState(() {}),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 10),
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
                            error!,
                            style: const TextStyle(
                              fontSize: 12,
                              color: WalletColors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 18),
                  KtPrimaryButton(
                    label: l10n.actionSave,
                    onPressed:
                        nameController.text.trim().isEmpty ||
                            addrController.text.trim().isEmpty
                        ? null
                        : () async {
                            final name = nameController.text.trim();
                            final addr = addrController.text.trim();
                            final match = _chainTags
                                .where(
                                  (t) => Addresses.validate(t.$1, addr).isValid,
                                )
                                .firstOrNull;
                            if (match == null) {
                              setSheetState(
                                () => error = l10n.invalidChainAddress,
                              );
                              return;
                            }
                            final controller = _controller!;
                            final navigator = Navigator.of(ctx);
                            if (existing == null) {
                              await controller.addContact(
                                name: name,
                                address: addr,
                                chain: match.$1.name,
                              );
                            } else {
                              await controller.updateContact(
                                existing.id,
                                name: name,
                                address: addr,
                                chain: match.$1.name,
                              );
                            }
                            if (mounted) {
                              setState(() => _contacts = controller.contacts);
                            }
                            navigator.pop();
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // Not disposed here: the sheet's exit animation still holds the fields.
  }

  /// "⋮" menu on a contact row: copy the address, edit the contact, or delete
  /// it (with confirmation).
  Future<void> _contactMenu(Contact contact) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
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
                    contact.name,
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
            ListTile(
              leading: const Icon(
                Icons.copy,
                size: 20,
                color: WalletColors.accent,
              ),
              title: Text(
                l10n.copyAddress,
                style: const TextStyle(fontSize: 15, color: WalletColors.text),
              ),
              onTap: () {
                Clipboard.setData(ClipboardData(text: contact.address));
                Navigator.of(ctx).pop();
                messenger
                  ..clearSnackBars()
                  ..showSnackBar(SnackBar(content: Text(l10n.addressCopied)));
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.edit_outlined,
                size: 20,
                color: WalletColors.accent,
              ),
              title: Text(
                l10n.actionEdit,
                style: const TextStyle(fontSize: 15, color: WalletColors.text),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _contactSheet(existing: contact);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline,
                size: 20,
                color: WalletColors.red,
              ),
              title: Text(
                l10n.actionDelete,
                style: const TextStyle(fontSize: 15, color: WalletColors.red),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                _confirmDeleteContact(contact);
              },
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Confirmation + persisted removal. Reuses the generic "removes the local
  /// record only" delete copy (deleteWalletConfirm) — no chain state involved.
  Future<void> _confirmDeleteContact(Contact contact) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => KtConfirmDialog(
        title: l10n.actionDelete,
        message: l10n.deleteWalletConfirm(contact.name),
        cancelLabel: l10n.actionCancel,
        confirmLabel: l10n.actionDelete,
        icon: Icons.person_remove_outlined,
        iconColor: WalletColors.red,
        destructive: true,
      ),
    );
    if (ok == true && mounted) {
      final controller = _controller!;
      await controller.removeContact(contact.id);
      if (mounted) setState(() => _contacts = controller.contacts);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty
        ? _contacts
        : _contacts.where((c) {
            final d = _display(c);
            return d.$2.toLowerCase().contains(q) ||
                d.$3.toLowerCase().contains(q) ||
                d.$4.toLowerCase().contains(q);
          }).toList();
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(
        title: l10n.addressBookTitle,
        onBack: () => Navigator.of(context).maybePop(),
        trailing: Icons.add,
        onTrailing: _addContact,
      ),
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: WalletColors.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.search, size: 18, color: WalletColors.text3),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  onChanged: (v) => setState(() => _query = v),
                  style: const TextStyle(
                    fontSize: 14,
                    color: WalletColors.text,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: l10n.searchNameOrAddress,
                    hintStyle: const TextStyle(
                      fontSize: 14,
                      color: WalletColors.text3,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                // An empty address book is not a failed search: on a fresh
                // install nothing has been typed yet, and "no matching
                // contacts" reads as if the app lost something.
                q.isEmpty ? l10n.contactsEmpty : l10n.noMatchingContacts,
                style: const TextStyle(fontSize: 14, color: WalletColors.text3),
              ),
            ),
          )
        else
          KtCard(
            child: Column(
              children: [
                for (var i = 0; i < results.length; i++) ...[
                  if (i > 0) const SizedBox(height: 16),
                  Builder(
                    builder: (context) {
                      final d = _display(results[i]);
                      return Row(
                        children: [
                          KtAvatar(
                            color: const Color(0xFFF2F4F7),
                            initial: d.$1,
                            size: 40,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      d.$2,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: WalletColors.text,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    NetworkBadge(label: d.$4, dotColor: d.$5),
                                  ],
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  d.$3,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontFamily: KtFonts.mono,
                                    color: WalletColors.text3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _contactMenu(results[i]),
                            child: const Icon(
                              Icons.more_vert,
                              size: 18,
                              color: WalletColors.text3,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// W17 Token 管理.
class TokenManageScreen extends StatefulWidget {
  const TokenManageScreen({super.key});
  @override
  State<TokenManageScreen> createState() => _TokenManageScreenState();
}

class _TokenManageScreenState extends State<TokenManageScreen> {
  /// Brand fallback (icon color + glyph) per known symbol; unknown symbols get
  /// the neutral slate + first letter, exactly like the old hardcoded rows.
  static const _brand = <String, (Color, String)>{
    'USDT': (Color(0xFF26A17B), '₮'),
    'USDC': (Color(0xFF2775CA), r'$'),
    'BUSD': (Color(0xFFF0B90B), 'B'),
    'UNI': (Color(0xFFFF007A), 'U'),
  };

  /// Tokens rendered by this screen, loaded from (and mutated through) the
  /// [WalletController]: drift-persisted in the real app, in-memory in the
  /// gallery/goldens (no store).
  List<CustomToken> _tokens = const [];
  WalletController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = WalletScope.of(context);
    if (identical(controller, _controller)) return;
    _controller = controller;
    _load(controller);
  }

  Future<void> _load(WalletController controller) async {
    var tokens = await controller.loadTokens();
    if (tokens.isEmpty && !controller.hasStore) {
      // No-store fallback (gallery/goldens/tests): seed the classic demo rows
      // in-memory. The real app persists these same rows on first run (see
      // main._seedFirstRun).
      for (final (symbol, name, network, contract, enabled) in [
        ('USDT', 'Tether USD', 'TRON · TRC-20', usdtTronToken.contract, true),
        (
          'USDT',
          'Tether USD',
          'Ethereum · ERC-20',
          usdtEthToken.contract,
          true,
        ),
        ('USDC', 'USD Coin', 'Solana · SPL', usdcSolanaToken.contract, true),
        (
          'BUSD',
          'Binance USD',
          'Ethereum · ERC-20',
          officialBusdEthereumContract,
          false,
        ),
        ('UNI', 'Uniswap', 'Ethereum · ERC-20', null, false),
      ]) {
        await controller.addToken(
          symbol: symbol,
          name: name,
          contract: contract,
          network: network,
          enabled: enabled,
        );
      }
      tokens = controller.tokens;
    }
    if (mounted) setState(() => _tokens = tokens);
  }

  Future<void> _toggle(CustomToken token) async {
    final controller = _controller!;
    await controller.setTokenEnabled(token.id, !token.enabled);
    if (mounted) setState(() => _tokens = controller.tokens);
  }

  /// "+" bottom sheet: symbol + name + contract address; a saved token is
  /// appended to the in-memory list as an enabled row.
  Future<void> _addToken() async {
    final l10n = AppLocalizations.of(context);
    final symbolController = TextEditingController();
    final nameController = TextEditingController();
    final contractController = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
          ),
          child: SafeArea(
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
                  Text(
                    l10n.addTokenTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: WalletColors.text,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sheetField(
                    symbolController,
                    label: l10n.tokenSymbolLabel,
                    onChanged: () => setSheetState(() {}),
                  ),
                  const SizedBox(height: 14),
                  _sheetField(
                    nameController,
                    label: l10n.nameLabel,
                    onChanged: () => setSheetState(() {}),
                  ),
                  const SizedBox(height: 14),
                  _sheetField(
                    contractController,
                    label: l10n.contractAddress,
                    mono: true,
                    onChanged: () => setSheetState(() {}),
                  ),
                  if (isProtectedTokenSymbol(symbolController.text.trim()) &&
                      !isKnownOfficialTokenIdentity(
                        symbolController.text.trim(),
                        contractController.text.trim(),
                      )) ...[
                    const SizedBox(height: 12),
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
                              l10n.tokenImpersonationWarning(
                                symbolController.text.trim().toUpperCase(),
                              ),
                              style: const TextStyle(
                                fontSize: 12,
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
                  const SizedBox(height: 18),
                  KtPrimaryButton(
                    label: l10n.actionSave,
                    onPressed:
                        symbolController.text.trim().isEmpty ||
                            nameController.text.trim().isEmpty
                        ? null
                        : () async {
                            final symbol = symbolController.text
                                .trim()
                                .toUpperCase();
                            final name = nameController.text.trim();
                            final contract = contractController.text.trim();
                            final sub = contract.isEmpty
                                ? name
                                : '$name · ${_abbrevAddress(contract)}';
                            final controller = _controller!;
                            final navigator = Navigator.of(ctx);
                            await controller.addToken(
                              symbol: symbol,
                              name: name,
                              contract: contract.isEmpty ? null : contract,
                              network: sub,
                            );
                            if (mounted) {
                              setState(() => _tokens = controller.tokens);
                            }
                            navigator.pop();
                          },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    // Not disposed here: the sheet's exit animation still holds the fields.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(
        title: l10n.tokenManageTitle,
        onBack: () => Navigator.of(context).maybePop(),
        trailing: Icons.add,
        onTrailing: _addToken,
      ),
      children: [
        // With no tokens the card used to render as a bare empty pill that
        // read like a broken search field. Say what the screen is instead.
        if (_tokens.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                l10n.tokensEmpty,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: WalletColors.text3),
              ),
            ),
          )
        else
          KtCard(
            child: Column(
              children: [
                for (var i = 0; i < _tokens.length; i++) ...[
                  if (i > 0) const SizedBox(height: 14),
                  Builder(
                    builder: (context) {
                      final token = _tokens[i];
                      final identityWarning =
                          isProtectedTokenSymbol(token.symbol) &&
                          !isKnownOfficialTokenIdentity(
                            token.symbol,
                            token.contract,
                          );
                      final (color, initial) =
                          _brand[token.symbol] ??
                          (
                            const Color(0xFF64748B),
                            token.symbol.characters.first,
                          );
                      return Row(
                        children: [
                          TokenIcon(
                            symbol: token.symbol,
                            size: 36,
                            fallbackColor: color,
                            fallbackInitial: initial,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  token.symbol,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: WalletColors.text,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  token.network,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: WalletColors.text3,
                                  ),
                                ),
                                if (identityWarning) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.tokenImpersonationWarning(
                                      token.symbol,
                                    ),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.35,
                                      fontWeight: FontWeight.w600,
                                      color: WalletColors.amber,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          _switch(token.enabled, onTap: () => _toggle(token)),
                        ],
                      );
                    },
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

/// W18 网络设置. Live: tapping a network's RPC row opens a sheet to edit the
/// node URL. Under an [AppPrefsScope] (production) the edit reads/writes the
/// persisted per-chain override ('rpc.eth' …, null → built-in default) and
/// offers a reset-to-default action; without a scope (gallery / goldens /
/// plain widget tests) it keeps the original in-memory demo state and demo
/// hostnames byte-for-byte.
///
/// Under a scope, an OPTIONAL gateway card renders above the per-chain rows:
/// the effective `gateway.url` (the KT production Gateway by default; blank =
/// direct mode), an edit sheet like the RPC rows, and a test-connection action
/// (`kt_health` → snackbar). The card is scope-only, so the scope-absent
/// gallery/golden rendering is unchanged.
class NetworkSettingsScreen extends StatefulWidget {
  const NetworkSettingsScreen({
    super.key,
    this.gatewayTestClient,
    this.probeClient,
    this.healthClient,
  });

  /// Injectable http client for the gateway test-connection call (tests);
  /// null in production (the [GatewayClient] creates its own).
  final http.Client? gatewayTestClient;

  /// Injectable http client for the add-network RPC probe (tests); null in
  /// production (the [RpcProbe] creates and closes its own).
  final http.Client? probeClient;

  /// Injectable http client for the per-row RPC health probes. Separate from
  /// [probeClient] on purpose: the add-network form's tests assert the exact
  /// requests IT makes, and the health badges must not show up in that count.
  final http.Client? healthClient;

  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
  /// Per-network RPC node override chosen in this session (scope-absent demo
  /// fallback only).
  final _rpcOverrides = <String, String>{};

  /// True while a gateway test-connection call is in flight.
  bool _testingGateway = false;

  /// Measured RPC round-trip per active network. Only built under a
  /// [NetworkScope] — the gallery / goldens have no networks to probe and must
  /// stay deterministic, so they render '—' instead of a made-up figure.
  RpcHealthController? _health;

  @override
  void dispose() {
    _health?.dispose();
    super.dispose();
  }

  RpcHealthController _healthController() => _health ??= RpcHealthController(
    probe: widget.healthClient == null
        ? null
        : RpcProbe(client: widget.healthClient),
  )..addListener(_onHealthChanged);

  void _onHealthChanged() {
    if (mounted) setState(() {});
  }

  /// The badge on an RPC row: measured latency, or an honest unknown.
  ///
  /// Kicks the measurement off from the build (post-frame — the controller
  /// notifies synchronously) and de-duplicates per network id, so a rebuild
  /// storm cannot turn into a probe storm.
  Widget _healthBadge(
    AppLocalizations l10n,
    NetworkController? net,
    Coin coin,
    String rpcUrl,
  ) {
    if (net == null) return _badge(l10n.rpcNotMeasured, WalletColors.text3);
    final network = net.activeFor(_chainOfCoin(coin));
    final health = _healthController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      health.measure(
        networkId: network.id,
        chain: network.chain,
        rpcUrl: rpcUrl,
      );
    });
    return switch (health.healthOf(network.id)) {
      RpcHealthProbing() => _badge(l10n.rpcMeasuring, WalletColors.text3),
      RpcHealthOk(:final millis) => _badge('$millis ms', WalletColors.green),
      RpcHealthDown() => _badge(l10n.rpcUnreachable, WalletColors.red),
    };
  }

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: color),
    ),
  );

  static Chain _chainOfCoin(Coin coin) => switch (coin) {
    Coin.eth => Chain.ethereum,
    Coin.polygon => Chain.polygon,
    Coin.base => Chain.base,
    Coin.arbitrum => Chain.arbitrum,
    Coin.avalanche => Chain.avalanche,
    Coin.tron => Chain.tron,
    Coin.solana => Chain.solana,
  };

  /// Edit sheet for the gateway URL, mirroring the RPC row sheet. Saving a
  /// blank value selects direct mode; reset restores the production Gateway.
  Future<void> _editGateway(AppPrefsController prefs) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: prefs.gatewayUrl ?? '');
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
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
                Text(
                  l10n.gatewayTitle,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: WalletColors.text,
                  ),
                ),
                const SizedBox(height: 16),
                _sheetField(controller, label: l10n.gatewayTitle, mono: true),
                const SizedBox(height: 18),
                KtPrimaryButton(
                  label: l10n.actionSave,
                  onPressed: () {
                    // Blank explicitly selects direct mode.
                    prefs.setGatewayUrl(controller.text);
                    Navigator.of(ctx).pop();
                  },
                ),
                const SizedBox(height: 8),
                Center(
                  child: TextButton(
                    onPressed: () {
                      prefs.setGatewayUrl(AppPrefsController.defaultGatewayUrl);
                      Navigator.of(ctx).pop();
                    },
                    child: Text(
                      l10n.networkResetDefault,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: WalletColors.text2,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Not disposed here: the sheet's exit animation still holds the field.
  }

  /// `kt_health` against the saved gateway URL; the outcome lands in a
  /// success/failure snackbar. [GatewayClient.health] never throws.
  Future<void> _testGateway(String url) async {
    if (_testingGateway) return;
    setState(() => _testingGateway = true);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final client = GatewayClient(
      baseUrl: url,
      client: widget.gatewayTestClient,
    );
    final ok = await client.health();
    if (widget.gatewayTestClient == null) client.close();
    if (!mounted) return;
    setState(() => _testingGateway = false);
    messenger.showSnackBar(
      SnackBar(content: Text(ok ? l10n.gatewayTestOk : l10n.gatewayTestFail)),
    );
  }

  /// The gateway card (scope-only, so goldens keep the scope-absent bytes).
  Widget _gatewayCard(AppLocalizations l10n, AppPrefsController prefs) {
    final url = prefs.gatewayUrl;
    return KtCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.gatewayTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: WalletColors.text,
                  ),
                ),
              ),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: url == null ? null : () => _testGateway(url),
                child: Text(
                  l10n.gatewayTest,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: url == null
                        ? WalletColors.text3
                        : WalletColors.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            l10n.gatewayDesc,
            style: const TextStyle(fontSize: 12, color: WalletColors.text3),
          ),
          const SizedBox(height: 12),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _editGateway(prefs),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    url ?? l10n.gatewayNotSet,
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: url == null ? null : KtFonts.mono,
                      color: url == null
                          ? WalletColors.text3
                          : WalletColors.text,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: WalletColors.text3,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- multi-network management (NetworkScope-only, so the scope-absent
  // gallery/golden rendering stays byte-for-byte) ---------------------------

  /// What the current environment profile alone would dictate for [chain]
  /// (each family has exactly one built-in mainnet and one built-in testnet,
  /// asserted by the foundation tests).
  Network _profileDefault(NetworkController net, Chain chain) =>
      builtinNetworks.firstWhere(
        (n) =>
            n.chain == chain &&
            n.isTestnet == (net.environment == NetworkEnvironment.testnet),
      );

  /// 网络环境 card: the mainnet/testnet environment switch.
  Widget _envCard(AppLocalizations l10n, NetworkController net) => KtCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.networkEnvironment,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: WalletColors.text,
          ),
        ),
        const SizedBox(height: 12),
        KtSegmented(
          options: [l10n.envMainnet, l10n.envTestnet],
          selected: net.environment == NetworkEnvironment.testnet ? 1 : 0,
          // Foundation behavior: an explicit environment switch clears the
          // per-chain overrides ("everything mainnet/testnet" wins).
          onChanged: (i) => net.setEnvironment(
            i == 1 ? NetworkEnvironment.testnet : NetworkEnvironment.mainnet,
          ),
        ),
      ],
    ),
  );

  /// Small amber dot marking a testnet instance.
  static Widget _testnetDot() => Container(
    width: 6,
    height: 6,
    decoration: const BoxDecoration(
      color: WalletColors.amber,
      shape: BoxShape.circle,
    ),
  );

  /// 逐链网络 card: one row per chain family showing the ACTIVE network name;
  /// tapping opens the per-family picker, "+" opens the add-network form.
  Widget _perChainCard(AppLocalizations l10n, NetworkController net) => KtCard(
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                l10n.perChainNetwork,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: WalletColors.text,
                ),
              ),
            ),
            GestureDetector(
              key: const ValueKey('add-network'),
              behavior: HitTestBehavior.opaque,
              onTap: () => _addNetworkSheet(net),
              child: const Icon(
                Icons.add,
                size: 18,
                color: WalletColors.accent,
              ),
            ),
          ],
        ),
        for (final (chain, label, color) in _chainTags) ...[
          const SizedBox(height: 14),
          Builder(
            builder: (context) {
              final active = net.activeFor(chain);
              return GestureDetector(
                key: ValueKey('net-row-${chain.name}'),
                behavior: HitTestBehavior.opaque,
                onTap: () => _pickNetwork(net, chain, label),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: WalletColors.text,
                        ),
                      ),
                    ),
                    if (active.isTestnet) ...[
                      _testnetDot(),
                      const SizedBox(width: 6),
                    ],
                    Text(
                      active.name,
                      style: const TextStyle(
                        fontSize: 13,
                        color: WalletColors.text2,
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: WalletColors.text3,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ],
    ),
  );

  /// Per-family picker sheet: built-ins + customs, testnets with an amber dot,
  /// the active one checked, custom rows with a delete affordance.
  ///
  /// Selecting the network the environment profile already dictates CLEARS the
  /// override instead of pinning it: a pin to "what the profile says anyway"
  /// would silently survive a later environment switch and betray it.
  Future<void> _pickNetwork(
    NetworkController net,
    Chain chain,
    String familyLabel,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
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
                      familyLabel,
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
              for (final n in net.networksFor(chain))
                ListTile(
                  key: ValueKey('net-opt-${n.id}'),
                  leading: n.isTestnet
                      ? _testnetDot()
                      : Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: WalletColors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                  title: Text(
                    n.name,
                    style: const TextStyle(
                      fontSize: 15,
                      color: WalletColors.text,
                    ),
                  ),
                  subtitle: Text(
                    n.rpcUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      fontFamily: KtFonts.mono,
                      color: WalletColors.text3,
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Built-ins show no delete; custom networks do.
                      if (!n.builtin)
                        GestureDetector(
                          key: ValueKey('net-del-${n.id}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () async {
                            await _confirmDeleteNetwork(ctx, net, n);
                            setSheetState(() {});
                          },
                          child: const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: WalletColors.red,
                            ),
                          ),
                        ),
                      if (net.activeFor(chain).id == n.id)
                        const Icon(
                          Icons.check,
                          size: 20,
                          color: WalletColors.accent,
                        ),
                    ],
                  ),
                  onTap: () {
                    // Picking the profile default = clearing the pin.
                    net.setOverride(
                      chain,
                      n.id == _profileDefault(net, chain).id ? null : n.id,
                    );
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

  /// Delete confirmation. When the network is currently active for some chain
  /// the dialog says so (networkInUse) but still allows deletion — the
  /// foundation drops the override and falls back to the environment profile.
  Future<void> _confirmDeleteNetwork(
    BuildContext sheetCtx,
    NetworkController net,
    Network n,
  ) async {
    final l10n = AppLocalizations.of(context);
    final inUse = Chain.values.any((c) => net.activeFor(c).id == n.id);
    final ok = await showDialog<bool>(
      context: sheetCtx,
      builder: (_) => KtConfirmDialog(
        title: l10n.deleteNetwork,
        message: inUse ? '${n.name}\n${l10n.networkInUse}' : n.name,
        cancelLabel: l10n.actionCancel,
        confirmLabel: l10n.actionDelete,
        icon: Icons.delete_outline_rounded,
        iconColor: WalletColors.red,
        destructive: true,
      ),
    );
    if (ok == true) await net.removeCustom(n.id);
  }

  /// 添加网络 sheet: family picker + name/RPC/symbol (+ chainId for EVM
  /// families, explorer optional). Saving PROBES the RPC first — nothing is
  /// persisted until the endpoint answered once (and, for EVM, reported the
  /// typed chain id).
  Future<void> _addNetworkSheet(NetworkController net) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final nameController = TextEditingController();
    final rpcController = TextEditingController();
    final symbolController = TextEditingController();
    final chainIdController = TextEditingController();
    final explorerController = TextEditingController();
    var family = 0; // index into _chainTags
    var probing = false;
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final chain = _chainTags[family].$1;
          final isEvm = chain == Chain.ethereum || chain == Chain.polygon;
          final typedChainId = int.tryParse(chainIdController.text.trim());
          final complete =
              nameController.text.trim().isNotEmpty &&
              rpcController.text.trim().isNotEmpty &&
              symbolController.text.trim().isNotEmpty &&
              (!isEvm || typedChainId != null);
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SafeArea(
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
                      Text(
                        l10n.addNetwork,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: WalletColors.text,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.chainFamilyLabel,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: WalletColors.text2,
                        ),
                      ),
                      const SizedBox(height: 8),
                      KtSegmented(
                        // Seven chain names do not fit an even split; they
                        // wrapped mid-word ("Ethere/um"). Natural width in a
                        // horizontal scroll instead.
                        scrollable: true,
                        options: [for (final t in _chainTags) t.$2],
                        selected: family,
                        onChanged: probing
                            ? null
                            : (i) => setSheetState(() => family = i),
                      ),
                      const SizedBox(height: 14),
                      _sheetField(
                        nameController,
                        label: l10n.networkNameLabel,
                        onChanged: () => setSheetState(() {}),
                      ),
                      const SizedBox(height: 14),
                      _sheetField(
                        rpcController,
                        label: l10n.rpcNode,
                        mono: true,
                        onChanged: () => setSheetState(() {}),
                      ),
                      const SizedBox(height: 14),
                      _sheetField(
                        symbolController,
                        label: l10n.symbolLabel,
                        onChanged: () => setSheetState(() {}),
                      ),
                      if (isEvm) ...[
                        const SizedBox(height: 14),
                        _sheetField(
                          chainIdController,
                          label: l10n.chainIdLabel,
                          mono: true,
                          onChanged: () => setSheetState(() {}),
                        ),
                      ],
                      const SizedBox(height: 14),
                      _sheetField(
                        explorerController,
                        label: l10n.explorerLabel,
                        mono: true,
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 10),
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
                                error!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: WalletColors.red,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 18),
                      KtPrimaryButton(
                        label: probing ? l10n.probeChecking : l10n.actionSave,
                        onPressed: !complete || probing
                            ? null
                            : () async {
                                setSheetState(() {
                                  probing = true;
                                  error = null;
                                });
                                final probe = RpcProbe(
                                  client: widget.probeClient,
                                );
                                final result = await probe.probe(
                                  chain: chain,
                                  rpcUrl: rpcController.text.trim(),
                                  expectedChainId: isEvm ? typedChainId : null,
                                );
                                if (widget.probeClient == null) probe.close();
                                if (!ctx.mounted) return;
                                switch (result) {
                                  case RpcProbeOk():
                                    final explorer = explorerController.text
                                        .trim();
                                    await net.addCustom(
                                      chain: chain,
                                      name: nameController.text.trim(),
                                      rpcUrl: rpcController.text.trim(),
                                      symbol: symbolController.text
                                          .trim()
                                          .toUpperCase(),
                                      evmChainId: isEvm ? typedChainId : null,
                                      explorerUrl: explorer.isEmpty
                                          ? null
                                          : explorer,
                                    );
                                    if (!ctx.mounted) return;
                                    Navigator.of(ctx).pop();
                                    messenger
                                      ..clearSnackBars()
                                      ..showSnackBar(
                                        SnackBar(
                                          content: Text(l10n.probeOkSave),
                                        ),
                                      );
                                  case RpcProbeChainIdMismatch(:final actual):
                                    // The node's actual id, decimal, inline; the
                                    // sheet stays open for correction.
                                    setSheetState(() {
                                      probing = false;
                                      error = l10n.chainIdMismatch(actual);
                                    });
                                  case RpcProbeFailure():
                                    setSheetState(() {
                                      probing = false;
                                      error = l10n.rpcProbeFailed;
                                    });
                                }
                              },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    // Not disposed here: the sheet's exit animation still holds the fields.
  }

  Future<void> _editRpc(
    AppPrefsController? prefs,
    Coin coin,
    String name,
    String rpc,
  ) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: rpc);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
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
                Text(
                  name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: WalletColors.text,
                  ),
                ),
                const SizedBox(height: 16),
                _sheetField(controller, label: l10n.rpcNode, mono: true),
                const SizedBox(height: 18),
                KtPrimaryButton(
                  label: l10n.actionSave,
                  onPressed: () {
                    final value = controller.text.trim();
                    if (value.isNotEmpty) {
                      if (prefs != null) {
                        // Saving the default back counts as "no override".
                        prefs.setRpcOverride(
                          coin,
                          value == defaultRpcEndpointFor(coin) ? null : value,
                        );
                      } else {
                        setState(() => _rpcOverrides[name] = value);
                      }
                    }
                    Navigator.of(ctx).pop();
                  },
                ),
                if (prefs != null) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        prefs.setRpcOverride(coin, null);
                        Navigator.of(ctx).pop();
                      },
                      child: Text(
                        l10n.networkResetDefault,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: WalletColors.text2,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
    // Not disposed here: the sheet's exit animation still holds the field.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Rebuilds on preference changes (the InheritedNotifier dependency), so a
    // saved or reset override updates the effective URL rows immediately.
    final prefs = AppPrefsScope.maybeOf(context);
    // Multi-network management is NetworkScope-only (maybeOf registers the
    // rebuild dependency); scope-absent (gallery / goldens) renders exactly
    // the pre-feature screen.
    final net = NetworkScope.maybeOf(context);
    // Rows carry identity only. Latency/health used to be string literals
    // here ('86 ms', '112 ms', '64 ms', and a permanent Timeout for Solana) —
    // numbers the app had never measured. They now come from _health.
    final nets = <(Color, Coin, String, String)>[
      (ChainColors.ethereum, Coin.eth, 'Ethereum', 'eth-mainnet.g.alchemy.com'),
      (ChainColors.polygon, Coin.polygon, 'Polygon', 'polygon-rpc.com'),
      if (net != null) ...[
        (ChainColors.base, Coin.base, 'Base', 'mainnet.base.org'),
        (
          ChainColors.arbitrum,
          Coin.arbitrum,
          'Arbitrum',
          'arb1.arbitrum.io/rpc',
        ),
        (
          ChainColors.avalanche,
          Coin.avalanche,
          'Avalanche',
          'api.avax.network/ext/bc/C/rpc',
        ),
      ],
      (ChainColors.tron, Coin.tron, 'TRON', 'api.trongrid.io'),
      (
        ChainColors.solana,
        Coin.solana,
        'Solana',
        'api.mainnet-beta.solana.com',
      ),
    ];
    // The URL shown and edited per row: the persisted effective endpoint in
    // live mode, the demo hostname (plus session-local edits) otherwise.
    String effectiveRpc(Coin coin, String name, String demo) {
      if (prefs == null) return _rpcOverrides[name] ?? demo;
      final override = prefs.rpcOverride(coin);
      if (override != null) return override;
      final chain = switch (coin) {
        Coin.eth => Chain.ethereum,
        Coin.polygon => Chain.polygon,
        Coin.base => Chain.base,
        Coin.arbitrum => Chain.arbitrum,
        Coin.avalanche => Chain.avalanche,
        Coin.tron => Chain.tron,
        Coin.solana => Chain.solana,
      };
      return net?.activeFor(chain).rpcUrl ?? defaultRpcEndpointFor(coin);
    }

    return KtScreen(
      gap: 16,
      navBar: KtNavBar(
        title: l10n.networkSettingsTitle,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      children: [
        // Optional gateway card, above the per-chain rows. Live-scope only:
        // the scope-absent (gallery / goldens) rendering stays byte-for-byte.
        if (prefs != null) _gatewayCard(l10n, prefs),
        // Environment switch + per-family active-network picker, under the
        // gateway card and above the RPC latency rows (NetworkScope-only).
        if (net != null) ...[_envCard(l10n, net), _perChainCard(l10n, net)],
        for (final (color, coin, name, rpc) in nets)
          KtCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: WalletColors.text,
                        ),
                      ),
                    ),
                    _healthBadge(
                      l10n,
                      net,
                      coin,
                      effectiveRpc(coin, name, rpc),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _editRpc(
                    prefs,
                    coin,
                    name,
                    effectiveRpc(coin, name, rpc),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              l10n.rpcNode,
                              style: const TextStyle(
                                fontSize: 12,
                                color: WalletColors.text3,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              effectiveRpc(coin, name, rpc),
                              style: const TextStyle(
                                fontSize: 12,
                                fontFamily: KtFonts.mono,
                                color: WalletColors.text,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: WalletColors.text3,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// W19 安全设置.
class SecuritySettingsScreen extends StatefulWidget {
  const SecuritySettingsScreen({super.key});
  @override
  State<SecuritySettingsScreen> createState() => _SecuritySettingsScreenState();
}

class _SecuritySettingsScreenState extends State<SecuritySettingsScreen> {
  /// The app-wide controller, when one is in scope.
  ///
  /// This screen used to own a second [AppPrefsController] over the same
  /// SharedPreferences keys. Writes persisted, so the value came back after a
  /// restart — but the controller the rest of the app listens to never heard
  /// about them, which is what made 隐私模式 look like it did nothing: the
  /// home balances stayed masked (or unmasked) until the next cold start.
  AppPrefsController? _shared;

  /// Fallback for the design gallery and goldens, where no scope is mounted.
  /// Owned here, unlike [_shared].
  AppPrefsController? _fallback;

  AppPrefsController get _prefs => _shared ?? _fallback!;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Registers the dependency too: a change from anywhere rebuilds this
    // screen, so the switches stay in step without a listener of their own.
    _shared = AppPrefsScope.maybeOf(context);
    if (_shared == null && _fallback == null) {
      _fallback = AppPrefsController()
        ..addListener(_onPrefsChanged)
        ..load();
    }
  }

  @override
  void dispose() {
    _fallback?.removeListener(_onPrefsChanged);
    _fallback?.dispose();
    super.dispose();
  }

  void _onPrefsChanged() {
    if (mounted) setState(() {});
  }

  /// Shared option-list bottom sheet (same visual pattern as the language
  /// picker): [labels] with the [selected] index checked; returns the tapped
  /// index via [onSelect].
  Future<void> _pickOption({
    required String title,
    required List<String> labels,
    required int selected,
    required ValueChanged<int> onSelect,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
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
                    title,
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
            for (var i = 0; i < labels.length; i++)
              ListTile(
                title: Text(
                  labels[i],
                  style: const TextStyle(
                    fontSize: 15,
                    color: WalletColors.text,
                  ),
                ),
                trailing: i == selected
                    ? const Icon(
                        Icons.check,
                        size: 20,
                        color: WalletColors.accent,
                      )
                    : null,
                onTap: () {
                  onSelect(i);
                  Navigator.of(ctx).pop();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// App-lock switch. Turning it ON with no PIN enrolled first walks through
  /// the set-PIN sheet (the gate needs a fallback for devices without
  /// biometrics); turning it OFF demands proof — a biometric success or the
  /// current PIN.
  Future<void> _toggleAppLock() async {
    final pin = WalletPin.instance;
    final auth = BiometricAuth.instance;
    if (!_prefs.appLock) {
      // Turning ON: enroll a PIN first when none exists yet.
      if (!await pin.isSet()) {
        if (!mounted) return;
        final enrolled = await showModalBottomSheet<bool>(
          context: context,
          backgroundColor: WalletColors.surface,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => _SetPinSheet(pin: pin),
        );
        if (enrolled != true) return; // sheet dismissed: leave the lock off
      }
      await _prefs.setAppLock(true);
      return;
    }
    // Turning OFF. Legacy state (lock on, nothing ever enrolled): there is
    // nothing to verify against, so the switch just flips.
    if (!await pin.isSet()) {
      await _prefs.setAppLock(false);
      return;
    }
    if (!mounted) return;
    var verified = false;
    if (await auth.canAuthenticate()) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context);
      verified =
          await auth.authenticate(reason: l10n.appLock) ==
          BiometricOutcome.success;
    }
    if (!verified) {
      // Same order as the gate: biometrics first, PIN numpad as the fallback.
      if (!mounted) return;
      final ok = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: WalletColors.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => _VerifyPinSheet(pin: pin),
      );
      verified = ok == true;
    }
    if (verified) await _prefs.setAppLock(false);
  }

  String _autoLockLabel(AppLocalizations l10n, int minutes) => minutes == 0
      ? l10n.autoLockImmediate
      : l10n.autoLockMinutesLabel(minutes);

  Future<void> _pickFiat() async {
    final l10n = AppLocalizations.of(context);
    await _pickOption(
      title: l10n.fiatUnit,
      labels: AppPrefsController.fiatOptions,
      selected: AppPrefsController.fiatOptions.indexOf(_prefs.fiat),
      onSelect: (i) => _prefs.setFiat(AppPrefsController.fiatOptions[i]),
    );
  }

  Future<void> _pickAutoLock() async {
    final l10n = AppLocalizations.of(context);
    await _pickOption(
      title: l10n.autoLock,
      labels: [
        for (final m in AppPrefsController.autoLockOptions)
          _autoLockLabel(l10n, m),
      ],
      selected: AppPrefsController.autoLockOptions.indexOf(
        _prefs.autoLockMinutes,
      ),
      onSelect: (i) =>
          _prefs.setAutoLockMinutes(AppPrefsController.autoLockOptions[i]),
    );
  }

  Future<void> _pickAuthMethod() async {
    final l10n = AppLocalizations.of(context);
    AuthMethod? selectedMethod;
    await _pickOption(
      title: l10n.authMethod,
      labels: [l10n.authBiometrics, l10n.authPassword],
      selected: _prefs.authMethod == AuthMethod.biometrics ? 0 : 1,
      onSelect: (index) {
        selectedMethod = index == 0
            ? AuthMethod.biometrics
            : AuthMethod.password;
      },
    );
    final method = selectedMethod;
    if (method == null || !mounted) return;
    if (method == AuthMethod.password && !await WalletPin.instance.isSet()) {
      if (!mounted) return;
      final enrolled = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: WalletColors.surface,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => _SetPinSheet(pin: WalletPin.instance),
      );
      if (enrolled != true) return;
    }
    await _prefs.setAuthMethod(method);
  }

  /// Danger row: deletes the first watch wallet after confirmation (a watch
  /// wallet holds only public addresses, so this never touches key material).
  Future<void> _deleteWatchWallet() async {
    final l10n = AppLocalizations.of(context);
    final controller = WalletScope.of(context);
    final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
    final watch = controller.wallets.whereType<WatchWallet>().firstOrNull;
    if (watch == null) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.noWatchWallet)));
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => KtConfirmDialog(
        title: l10n.deleteWalletTitle,
        message: l10n.deleteWalletConfirm(watch.name),
        cancelLabel: l10n.actionCancel,
        confirmLabel: l10n.actionDelete,
        icon: Icons.delete_outline_rounded,
        iconColor: WalletColors.red,
        destructive: true,
      ),
    );
    if (ok == true && mounted) {
      await controller.remove(watch.id);
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.deletedWallet(watch.name))),
      );
    }
  }

  Future<void> _pickLanguage() async {
    final l10n = AppLocalizations.of(context);
    final controller = LocaleScope.of(context);
    final current = controller.locale?.languageCode;
    final options = <(String, Locale?)>[
      (l10n.languageSystem, null),
      ('简体中文', const Locale('zh')),
      ('English', const Locale('en')),
      ('日本語', const Locale('ja')),
    ];
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
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
                    l10n.displayLanguage,
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
            for (final (label, locale) in options)
              ListTile(
                title: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    color: WalletColors.text,
                  ),
                ),
                trailing: (locale?.languageCode == current)
                    ? const Icon(
                        Icons.check,
                        size: 20,
                        color: WalletColors.accent,
                      )
                    : null,
                onTap: () {
                  controller.setLocale(locale);
                  Navigator.of(ctx).pop();
                },
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  /// Confirms leaving wallet mode; on confirm the combined installer returns
  /// to the device-mode picker. Only reachable when a [DeviceModeScope] is
  /// present (i.e. running inside the single-installer app).
  Future<void> _confirmDeviceModeSwitch(DeviceModeScope scope) async {
    final l10n = AppLocalizations.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => KtConfirmDialog(
        title: l10n.deviceModeSwitchTitle,
        message: l10n.deviceModeSwitchDesc,
        cancelLabel: l10n.actionCancel,
        confirmLabel: l10n.actionConfirm,
        icon: Icons.phonelink_setup_rounded,
      ),
    );
    if (confirmed == true) scope.exitMode();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final localeController = LocaleScope.of(context);
    final modeScope = DeviceModeScope.maybeOf(context);
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(
        title: l10n.settingsSecurity,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      children: [
        Text(
          l10n.accessControl,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: WalletColors.text2,
          ),
        ),
        KtCard(
          child: Column(
            children: [
              _row(
                Icons.lock_outline,
                l10n.appLock,
                l10n.appLockDesc,
                _switch(_prefs.appLock, onTap: _toggleAppLock),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _pickAuthMethod,
                child: _row(
                  _prefs.authMethod == AuthMethod.biometrics
                      ? Icons.face_outlined
                      : Icons.password_rounded,
                  l10n.authMethod,
                  l10n.authMethodDesc,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Shrinkable: a long localized value (Japanese runs
                      // longest) must ellipsize rather than overflow the row.
                      Flexible(
                        child: Text(
                          _prefs.authMethod == AuthMethod.biometrics
                              ? l10n.authBiometrics
                              : l10n.authPassword,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: WalletColors.text2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: WalletColors.text3,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _pickAutoLock,
                child: _row(
                  Icons.timer_outlined,
                  l10n.autoLock,
                  l10n.autoLockDesc,
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          _autoLockLabel(l10n, _prefs.autoLockMinutes),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: WalletColors.text2,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: WalletColors.text3,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              _row(
                Icons.visibility_off_outlined,
                l10n.privacyMode,
                l10n.privacyModeDesc,
                _switch(
                  _prefs.privacyMode,
                  onTap: () => _prefs.setPrivacyMode(!_prefs.privacyMode),
                ),
              ),
              // Watch wallets hold no key material, so there is nothing to
              // seal — offering the row would only lead to a dead end.
              if (WalletScope.of(context).current is HotWallet) ...[
                const SizedBox(height: 16),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => context.push('/backup'),
                  child: _row(
                    Icons.cloud_upload_outlined,
                    l10n.backupEncryptedRow,
                    l10n.backupEncryptedRowDesc,
                    const Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: WalletColors.text3,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        Text(
          l10n.dataSection,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
            color: WalletColors.text2,
          ),
        ),
        KtCard(
          child: Column(
            children: [
              _SimpleRow(
                Icons.attach_money,
                l10n.fiatUnit,
                _prefs.fiat,
                onTap: _pickFiat,
              ),
              const SizedBox(height: 16),
              _SimpleRow(
                Icons.language,
                l10n.displayLanguage,
                _languageLabel(l10n, localeController.locale),
                onTap: _pickLanguage,
              ),
              // Only in the combined single-installer app: switch back to the
              // device-mode picker. Hidden in standalone/test setups.
              if (modeScope != null) ...[
                const SizedBox(height: 16),
                _SimpleRow(
                  Icons.devices_outlined,
                  l10n.deviceMode,
                  l10n.modeWalletTitle,
                  onTap: () => _confirmDeviceModeSwitch(modeScope),
                ),
              ],
            ],
          ),
        ),
        KtCard(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _deleteWatchWallet,
            child: _row(
              Icons.delete_outline,
              l10n.deleteWatchWallet,
              l10n.deleteWatchWalletDesc,
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: WalletColors.text3,
              ),
              danger: true,
            ),
          ),
        ),
      ],
    );
  }

  static Widget _row(
    IconData icon,
    String label,
    String sub,
    Widget trailing, {
    bool danger = false,
  }) => Row(
    children: [
      Icon(
        icon,
        size: 19,
        color: danger ? WalletColors.red : WalletColors.text2,
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: danger ? WalletColors.red : WalletColors.text,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              sub,
              style: const TextStyle(fontSize: 12, color: WalletColors.text3),
            ),
          ],
        ),
      ),
      // Without this the description ran straight into the trailing value.
      // Latin copy happened to be short enough to hide it; the Japanese
      // strings fill the line and the two collide.
      const SizedBox(width: 12),
      // Flexible so a long localized value can ellipsize instead of
      // overflowing, Align so it still sits on the card's right edge:
      // a bare Flexible splits the row 1:1 with the Expanded label and
      // parks every switch and chevron at the midpoint.
      Flexible(
        child: Align(alignment: Alignment.centerRight, child: trailing),
      ),
    ],
  );
}

class _SimpleRow extends StatelessWidget {
  const _SimpleRow(this.icon, this.label, this.value, {this.onTap});
  final IconData icon;
  final String label, value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Row(
      children: [
        Icon(icon, size: 19, color: WalletColors.text2),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: WalletColors.text,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(fontSize: 13, color: WalletColors.text2),
        ),
        const Icon(Icons.chevron_right, size: 16, color: WalletColors.text3),
      ],
    ),
  );
}

/// Set-PIN bottom sheet (enrollment for the app-lock fallback). Two-phase,
/// mirroring cold_signer's C14 interaction: enter 6 digits, re-enter to
/// confirm; a mismatch shows an inline error and starts over. Pops `true`
/// once the PIN is enrolled.
class _SetPinSheet extends StatefulWidget {
  const _SetPinSheet({required this.pin});

  final WalletPin pin;

  @override
  State<_SetPinSheet> createState() => _SetPinSheetState();
}

class _SetPinSheetState extends State<_SetPinSheet> {
  String _entry = '';
  String? _first; // the first pass, once 6 digits entered
  String? _error;
  bool _saving = false;

  Future<void> _onKey(String k) async {
    if (_saving) return;
    if (k == 'del') {
      if (_entry.isNotEmpty) {
        setState(() => _entry = _entry.substring(0, _entry.length - 1));
      }
      return;
    }
    if (_entry.length >= 6) return;
    setState(() {
      _entry += k;
      _error = null;
    });
    if (_entry.length < 6) return;

    if (_first == null) {
      // First pass done; ask for confirmation.
      setState(() {
        _first = _entry;
        _entry = '';
      });
    } else if (_entry == _first) {
      setState(() => _saving = true);
      await widget.pin.setPin(_entry);
      if (mounted) Navigator.of(context).pop(true);
    } else {
      final l10n = AppLocalizations.of(context);
      setState(() {
        _first = null;
        _entry = '';
        _error = l10n.pinMismatch;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final confirming = _first != null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
            const SizedBox(height: 16),
            Text(
              confirming ? l10n.setPinConfirmPrompt : l10n.setPinPrompt,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: WalletColors.text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.setPinDesc,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                height: 1.5,
                color: WalletColors.text3,
              ),
            ),
            const SizedBox(height: 14),
            PinDots(filled: _entry.length),
            SizedBox(
              height: 32,
              child: Center(
                child: _error == null
                    ? null
                    : Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: WalletColors.red,
                        ),
                      ),
              ),
            ),
            PinPad(onKey: _onKey),
          ],
        ),
      ),
    );
  }
}

/// Verify-PIN bottom sheet (guards switching the app lock off). Verifies the
/// entry against [WalletPin] — wrong-PIN and lockout messages inline — and
/// pops `true` on success.
class _VerifyPinSheet extends StatefulWidget {
  const _VerifyPinSheet({required this.pin});

  final WalletPin pin;

  @override
  State<_VerifyPinSheet> createState() => _VerifyPinSheetState();
}

class _VerifyPinSheetState extends State<_VerifyPinSheet> {
  String _entry = '';
  String? _error;
  bool _verifying = false;

  Future<void> _onKey(String k) async {
    if (_verifying) return;
    if (k == 'del') {
      if (_entry.isNotEmpty) {
        setState(() => _entry = _entry.substring(0, _entry.length - 1));
      }
      return;
    }
    if (_entry.length >= 6) return;
    setState(() {
      _entry += k;
      _error = null;
    });
    if (_entry.length < 6) return;

    final l10n = AppLocalizations.of(context);
    setState(() => _verifying = true);
    final verdict = await widget.pin.verify(_entry);
    if (!mounted) return;
    if (verdict.isOk) {
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _entry = '';
      _verifying = false;
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
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
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
            const SizedBox(height: 16),
            Text(
              l10n.enterPinToDisable,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: WalletColors.text,
              ),
            ),
            const SizedBox(height: 18),
            PinDots(filled: _entry.length),
            SizedBox(
              height: 32,
              child: Center(
                child: _error == null
                    ? null
                    : Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 13,
                          color: WalletColors.red,
                        ),
                      ),
              ),
            ),
            PinPad(onKey: _onKey),
          ],
        ),
      ),
    );
  }
}

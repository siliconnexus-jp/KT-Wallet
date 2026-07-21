import 'package:chains/chains.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui_kit/ui_kit.dart';
import 'package:wallet_data/wallet_data.dart' show Contact, CustomToken;

import '../../l10n/app_localizations.dart';
import '../widgets/token_icon.dart';
import '../state/app_prefs.dart';
import '../state/locale_controller.dart';
import '../state/wallet_controller.dart';
import '../state/wallet_scope.dart';
import '../wallets/wallet_model.dart';

/// Display name + badge color per validated chain (address book rows).
const _chainTags = [
  (Chain.ethereum, 'Ethereum', ChainColors.ethereum),
  (Chain.polygon, 'Polygon', ChainColors.polygon),
  (Chain.tron, 'TRON', ChainColors.tron),
  (Chain.solana, 'Solana', ChainColors.solana),
];

String _abbrevAddress(String a) => a.length <= 18 ? a : '${a.substring(0, 8)}…${a.substring(a.length - 8)}';

/// Bottom-sheet form field matching the app's card inputs.
Widget _sheetField(TextEditingController controller, {required String label, bool mono = false, VoidCallback? onChanged}) =>
    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: WalletColors.text2)),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: WalletColors.bg, borderRadius: BorderRadius.circular(12), border: Border.all(color: WalletColors.border)),
        child: TextField(
          controller: controller,
          onChanged: (_) => onChanged?.call(),
          autocorrect: false,
          enableSuggestions: false,
          style: TextStyle(fontSize: 14, fontFamily: mono ? KtFonts.mono : KtFonts.ui, color: WalletColors.text),
          decoration: const InputDecoration(isCollapsed: true, border: InputBorder.none),
        ),
      ),
    ]);

Widget _switch(bool on, {VoidCallback? onTap}) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        width: 44, height: 26,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: on ? WalletColors.accent : const Color(0xFFE1E4EA), borderRadius: BorderRadius.circular(13)),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          alignment: on ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(width: 22, height: 22, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
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
        await controller.addContact(name: name, address: address, chain: chain.name);
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

  /// "+" bottom sheet: name + address; the address must validate against one
  /// of the supported chains, whose tag/color the new row inherits.
  Future<void> _addContact() async {
    final l10n = AppLocalizations.of(context);
    final nameController = TextEditingController();
    final addrController = TextEditingController();
    String? error;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: WalletColors.border, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text(l10n.addContactTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: WalletColors.text)),
                const SizedBox(height: 16),
                _sheetField(nameController, label: l10n.nameLabel, onChanged: () => setSheetState(() {})),
                const SizedBox(height: 14),
                _sheetField(addrController, label: l10n.addressLabel, mono: true, onChanged: () => setSheetState(() {})),
                if (error != null) ...[
                  const SizedBox(height: 10),
                  Row(children: [
                    const Icon(Icons.error_outline, size: 14, color: WalletColors.red),
                    const SizedBox(width: 6),
                    Expanded(child: Text(error!, style: const TextStyle(fontSize: 12, color: WalletColors.red))),
                  ]),
                ],
                const SizedBox(height: 18),
                KtPrimaryButton(
                  label: l10n.actionSave,
                  onPressed: nameController.text.trim().isEmpty || addrController.text.trim().isEmpty
                      ? null
                      : () async {
                          final name = nameController.text.trim();
                          final addr = addrController.text.trim();
                          final match = _chainTags.where((t) => Addresses.validate(t.$1, addr).isValid).firstOrNull;
                          if (match == null) {
                            setSheetState(() => error = l10n.invalidChainAddress);
                            return;
                          }
                          final controller = _controller!;
                          final navigator = Navigator.of(ctx);
                          await controller.addContact(name: name, address: addr, chain: match.$1.name);
                          if (mounted) setState(() => _contacts = controller.contacts);
                          navigator.pop();
                        },
                ),
              ]),
            ),
          ),
        ),
      ),
    );
    // Not disposed here: the sheet's exit animation still holds the fields.
  }

  /// "⋮" menu on a contact row: copy the contact's address, or delete the
  /// contact (with confirmation).
  Future<void> _contactMenu(Contact contact) async {
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
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
              Text(contact.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: WalletColors.text)),
            ]),
          ),
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(Icons.copy, size: 20, color: WalletColors.accent),
            title: Text(l10n.copyAddress, style: const TextStyle(fontSize: 15, color: WalletColors.text)),
            onTap: () {
              Clipboard.setData(ClipboardData(text: contact.address));
              Navigator.of(ctx).pop();
              messenger
                ..clearSnackBars()
                ..showSnackBar(SnackBar(content: Text(l10n.addressCopied)));
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_outline, size: 20, color: WalletColors.red),
            title: Text(l10n.actionDelete, style: const TextStyle(fontSize: 15, color: WalletColors.red)),
            onTap: () {
              Navigator.of(ctx).pop();
              _confirmDeleteContact(contact);
            },
          ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  /// Confirmation + persisted removal. Reuses the generic "removes the local
  /// record only" delete copy (deleteWalletConfirm) — no chain state involved.
  Future<void> _confirmDeleteContact(Contact contact) async {
    final l10n = AppLocalizations.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.actionDelete),
        content: Text(l10n.deleteWalletConfirm(contact.name)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.actionCancel)),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.actionDelete, style: const TextStyle(color: WalletColors.red)),
          ),
        ],
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
            return d.$2.toLowerCase().contains(q) || d.$3.toLowerCase().contains(q) || d.$4.toLowerCase().contains(q);
          }).toList();
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: l10n.addressBookTitle, onBack: () => Navigator.of(context).maybePop(), trailing: Icons.add, onTrailing: _addContact),
      children: [
        Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(color: WalletColors.surface, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            const Icon(Icons.search, size: 18, color: WalletColors.text3),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(fontSize: 14, color: WalletColors.text),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: l10n.searchNameOrAddress,
                  hintStyle: const TextStyle(fontSize: 14, color: WalletColors.text3),
                ),
              ),
            ),
          ]),
        ),
        if (results.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Center(child: Text(l10n.noMatchingContacts, style: const TextStyle(fontSize: 14, color: WalletColors.text3))),
          )
        else
          KtCard(
            child: Column(children: [
              for (var i = 0; i < results.length; i++) ...[
                if (i > 0) const SizedBox(height: 16),
                Builder(builder: (context) {
                  final d = _display(results[i]);
                  return Row(children: [
                    KtAvatar(color: const Color(0xFFF2F4F7), initial: d.$1, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(d.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: WalletColors.text)),
                          const SizedBox(width: 8),
                          NetworkBadge(label: d.$4, dotColor: d.$5),
                        ]),
                        const SizedBox(height: 3),
                        Text(d.$3, style: const TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: WalletColors.text3)),
                      ]),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _contactMenu(results[i]),
                      child: const Icon(Icons.more_vert, size: 18, color: WalletColors.text3),
                    ),
                  ]);
                }),
              ],
            ]),
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
      for (final (symbol, name, network, enabled) in [
        ('USDT', 'Tether USD', 'TRON · TRC-20', true),
        ('USDT', 'Tether USD', 'Ethereum · ERC-20', true),
        ('USDC', 'USD Coin', 'Solana · SPL', true),
        ('BUSD', 'Binance USD', 'Ethereum · ERC-20', false),
        ('UNI', 'Uniswap', 'Ethereum · ERC-20', false),
      ]) {
        await controller.addToken(symbol: symbol, name: name, network: network, enabled: enabled);
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: WalletColors.border, borderRadius: BorderRadius.circular(2)))),
                const SizedBox(height: 16),
                Text(l10n.addTokenTitle, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: WalletColors.text)),
                const SizedBox(height: 16),
                _sheetField(symbolController, label: l10n.tokenSymbolLabel, onChanged: () => setSheetState(() {})),
                const SizedBox(height: 14),
                _sheetField(nameController, label: l10n.nameLabel, onChanged: () => setSheetState(() {})),
                const SizedBox(height: 14),
                _sheetField(contractController, label: l10n.contractAddress, mono: true, onChanged: () => setSheetState(() {})),
                const SizedBox(height: 18),
                KtPrimaryButton(
                  label: l10n.actionSave,
                  onPressed: symbolController.text.trim().isEmpty || nameController.text.trim().isEmpty
                      ? null
                      : () async {
                          final symbol = symbolController.text.trim().toUpperCase();
                          final name = nameController.text.trim();
                          final contract = contractController.text.trim();
                          final sub = contract.isEmpty ? name : '$name · ${_abbrevAddress(contract)}';
                          final controller = _controller!;
                          final navigator = Navigator.of(ctx);
                          await controller.addToken(
                            symbol: symbol,
                            name: name,
                            contract: contract.isEmpty ? null : contract,
                            network: sub,
                          );
                          if (mounted) setState(() => _tokens = controller.tokens);
                          navigator.pop();
                        },
                ),
              ]),
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
      navBar: KtNavBar(title: l10n.tokenManageTitle, onBack: () => Navigator.of(context).maybePop(), trailing: Icons.add, onTrailing: _addToken),
      children: [
        KtCard(
          child: Column(children: [
            for (var i = 0; i < _tokens.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              Builder(builder: (context) {
                final token = _tokens[i];
                final (color, initial) = _brand[token.symbol] ??
                    (const Color(0xFF64748B), token.symbol.characters.first);
                return Row(children: [
                  TokenIcon(symbol: token.symbol, size: 36, fallbackColor: color, fallbackInitial: initial),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(token.symbol, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: WalletColors.text)),
                      const SizedBox(height: 3),
                      Text(token.network, style: const TextStyle(fontSize: 12, color: WalletColors.text3)),
                    ]),
                  ),
                  _switch(token.enabled, onTap: () => _toggle(token)),
                ]);
              }),
            ],
          ]),
        ),
      ],
    );
  }
}

/// W18 网络设置. Live: tapping a network's RPC row opens a sheet to edit the
/// node URL (in-memory demo state, like the token/contact lists).
class NetworkSettingsScreen extends StatefulWidget {
  const NetworkSettingsScreen({super.key});
  @override
  State<NetworkSettingsScreen> createState() => _NetworkSettingsScreenState();
}

class _NetworkSettingsScreenState extends State<NetworkSettingsScreen> {
  /// Per-network RPC node override chosen in this session.
  final _rpcOverrides = <String, String>{};

  Future<void> _editRpc(String name, String rpc) async {
    final l10n = AppLocalizations.of(context);
    final controller = TextEditingController(text: rpc);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: WalletColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Center(child: Container(width: 36, height: 4, decoration: BoxDecoration(color: WalletColors.border, borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              Text(name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: WalletColors.text)),
              const SizedBox(height: 16),
              _sheetField(controller, label: l10n.rpcNode, mono: true),
              const SizedBox(height: 18),
              KtPrimaryButton(
                label: l10n.actionSave,
                onPressed: () {
                  final value = controller.text.trim();
                  if (value.isNotEmpty) setState(() => _rpcOverrides[name] = value);
                  Navigator.of(ctx).pop();
                },
              ),
            ]),
          ),
        ),
      ),
    );
    // Not disposed here: the sheet's exit animation still holds the field.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final nets = <(Color, String, String, String, bool)>[
      (ChainColors.ethereum, 'Ethereum', 'eth-mainnet.g.alchemy.com', '86 ms', true),
      (ChainColors.polygon, 'Polygon', 'polygon-rpc.com', '112 ms', true),
      (ChainColors.tron, 'TRON', 'api.trongrid.io', '64 ms', true),
      (ChainColors.solana, 'Solana', 'api.mainnet-beta.solana.com', l10n.rpcTimeout, false),
    ];
    return KtScreen(
      gap: 16,
      navBar: KtNavBar(title: l10n.networkSettingsTitle, onBack: () => Navigator.of(context).maybePop()),
      children: [
        for (final (color, name, rpc, ms, ok) in nets)
          KtCard(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
                const SizedBox(width: 8),
                Expanded(child: Text(name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: WalletColors.text))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(color: (ok ? WalletColors.green : WalletColors.red).withValues(alpha: 0.08), borderRadius: BorderRadius.circular(999)),
                  child: Text(ms, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: ok ? WalletColors.green : WalletColors.red)),
                ),
              ]),
              const SizedBox(height: 12),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _editRpc(name, _rpcOverrides[name] ?? rpc),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(l10n.rpcNode, style: const TextStyle(fontSize: 12, color: WalletColors.text3)),
                      const SizedBox(height: 2),
                      Text(_rpcOverrides[name] ?? rpc, style: const TextStyle(fontSize: 12, fontFamily: KtFonts.mono, color: WalletColors.text)),
                    ]),
                  ),
                  const Icon(Icons.chevron_right, size: 16, color: WalletColors.text3),
                ]),
              ),
            ]),
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
  /// Screen-local prefs controller; values are persisted (SharedPreferences)
  /// so they survive leaving the screen and app restarts.
  final _prefs = AppPrefsController();

  @override
  void initState() {
    super.initState();
    _prefs.addListener(_onPrefsChanged);
    _prefs.load();
  }

  @override
  void dispose() {
    _prefs.removeListener(_onPrefsChanged);
    _prefs.dispose();
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: WalletColors.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: WalletColors.text)),
            ]),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < labels.length; i++)
            ListTile(
              title: Text(labels[i], style: const TextStyle(fontSize: 15, color: WalletColors.text)),
              trailing: i == selected ? const Icon(Icons.check, size: 20, color: WalletColors.accent) : null,
              onTap: () {
                onSelect(i);
                Navigator.of(ctx).pop();
              },
            ),
          const SizedBox(height: 12),
        ]),
      ),
    );
  }

  String _autoLockLabel(AppLocalizations l10n, int minutes) =>
      minutes == 0 ? l10n.autoLockImmediate : l10n.autoLockMinutesLabel(minutes);

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
      labels: [for (final m in AppPrefsController.autoLockOptions) _autoLockLabel(l10n, m)],
      selected: AppPrefsController.autoLockOptions.indexOf(_prefs.autoLockMinutes),
      onSelect: (i) => _prefs.setAutoLockMinutes(AppPrefsController.autoLockOptions[i]),
    );
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
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteWalletTitle),
        content: Text(l10n.deleteWalletConfirm(watch.name)),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(l10n.actionCancel)),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.actionDelete, style: const TextStyle(color: WalletColors.red)),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      controller.remove(watch.id);
      messenger.showSnackBar(SnackBar(content: Text(l10n.deletedWallet(watch.name))));
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
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 36, height: 4, decoration: BoxDecoration(color: WalletColors.border, borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(children: [
              Text(l10n.displayLanguage, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: WalletColors.text)),
            ]),
          ),
          const SizedBox(height: 8),
          for (final (label, locale) in options)
            ListTile(
              title: Text(label, style: const TextStyle(fontSize: 15, color: WalletColors.text)),
              trailing: (locale?.languageCode == current)
                  ? const Icon(Icons.check, size: 20, color: WalletColors.accent)
                  : null,
              onTap: () {
                controller.setLocale(locale);
                Navigator.of(ctx).pop();
              },
            ),
          const SizedBox(height: 12),
        ]),
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
      builder: (ctx) => AlertDialog(
        backgroundColor: WalletColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(l10n.deviceModeSwitchTitle, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: WalletColors.text)),
        content: Text(l10n.deviceModeSwitchDesc, style: const TextStyle(fontSize: 14, height: 1.5, color: WalletColors.text2)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.actionCancel, style: const TextStyle(color: WalletColors.text2)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.actionConfirm, style: const TextStyle(color: WalletColors.accent)),
          ),
        ],
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
      navBar: KtNavBar(title: l10n.settingsSecurity, onBack: () => Navigator.of(context).maybePop()),
      children: [
        Text(l10n.accessControl, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: WalletColors.text2)),
        KtCard(
          child: Column(children: [
            _row(Icons.lock_outline, l10n.appLock, l10n.appLockDesc, _switch(_prefs.appLock, onTap: () => _prefs.setAppLock(!_prefs.appLock))),
            const SizedBox(height: 16),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _pickAutoLock,
              child: _row(Icons.timer_outlined, l10n.autoLock, l10n.autoLockDesc, Row(mainAxisSize: MainAxisSize.min, children: [Text(_autoLockLabel(l10n, _prefs.autoLockMinutes), style: const TextStyle(fontSize: 13, color: WalletColors.text2)), const Icon(Icons.chevron_right, size: 16, color: WalletColors.text3)])),
            ),
            const SizedBox(height: 16),
            _row(Icons.visibility_off_outlined, l10n.privacyMode, l10n.privacyModeDesc, _switch(_prefs.privacyMode, onTap: () => _prefs.setPrivacyMode(!_prefs.privacyMode))),
          ]),
        ),
        Text(l10n.dataSection, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: WalletColors.text2)),
        KtCard(
          child: Column(children: [
            _SimpleRow(Icons.attach_money, l10n.fiatUnit, _prefs.fiat, onTap: _pickFiat),
            const SizedBox(height: 16),
            _SimpleRow(Icons.language, l10n.displayLanguage, _languageLabel(l10n, localeController.locale), onTap: _pickLanguage),
            // Only in the combined single-installer app: switch back to the
            // device-mode picker. Hidden in standalone/test setups.
            if (modeScope != null) ...[
              const SizedBox(height: 16),
              _SimpleRow(Icons.devices_outlined, l10n.deviceMode, l10n.modeWalletTitle, onTap: () => _confirmDeviceModeSwitch(modeScope)),
            ],
          ]),
        ),
        KtCard(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _deleteWatchWallet,
            child: _row(Icons.delete_outline, l10n.deleteWatchWallet, l10n.deleteWatchWalletDesc, const Icon(Icons.chevron_right, size: 16, color: WalletColors.text3), danger: true),
          ),
        ),
      ],
    );
  }

  static Widget _row(IconData icon, String label, String sub, Widget trailing, {bool danger = false}) => Row(children: [
        Icon(icon, size: 19, color: danger ? WalletColors.red : WalletColors.text2),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: danger ? WalletColors.red : WalletColors.text)),
            const SizedBox(height: 2),
            Text(sub, style: const TextStyle(fontSize: 12, color: WalletColors.text3)),
          ]),
        ),
        trailing,
      ]);
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
        child: Row(children: [
          Icon(icon, size: 19, color: WalletColors.text2),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: WalletColors.text))),
          Text(value, style: const TextStyle(fontSize: 13, color: WalletColors.text2)),
          const Icon(Icons.chevron_right, size: 16, color: WalletColors.text3),
        ]),
      );
}

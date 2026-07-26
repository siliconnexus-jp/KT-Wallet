import 'package:drift/drift.dart';

/// Persistence schema for the online app (detailed-design.md §5.1).
///
/// Money is stored as decimal STRING (BigInt base units), never a numeric
/// column — no float precision loss. All per-wallet business tables carry a
/// `walletId` and are only reached through a wallet-scoped repository.
///
/// NOTE ON CASCADE: `.references(Wallets, #id)` documents the relationship but
/// drift does not emit a SQL FOREIGN KEY clause for these tables in this build
/// config, so there is NO database-level ON DELETE CASCADE. Child cleanup is
/// done explicitly and transactionally by `WalletsRepository.deleteWallet` —
/// that manual cascade is authoritative and must delete children before the
/// parent wallet row.

enum WalletType { hot, watch }

enum TxDirection { incoming, outgoing }

enum TxStatus {
  draft,
  awaitingSig,
  signed,
  broadcast,
  confirmed,
  failed,
  expired,

  /// Accepted by the app for submission, before a node has answered.
  submitted,

  /// Accepted by a node but not yet confirmed on-chain.
  pending,

  /// No longer visible to the network after the pending timeout.
  dropped,

  /// Superseded by another transaction using the same EVM nonce.
  replaced,
}

enum SignMode { local, airgap }

enum TxReplacementKind { speedUp, cancel }

class Wallets extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 64)();
  IntColumn get type => intEnum<WalletType>()();
  IntColumn get avatarColor => integer()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  BoolColumn get backedUp => boolean().withDefault(const Constant(false))();
  TextColumn get coldWalletId => text().nullable()();
  IntColumn get protocolVer => integer().nullable()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class Accounts extends Table {
  TextColumn get walletId => text().references(Wallets, #id)();
  TextColumn get coin => text()();
  TextColumn get address => text()();
  TextColumn get derivationPath => text()();
  IntColumn get accountIndex => integer()();

  @override
  Set<Column> get primaryKey => {walletId, coin};
}

class Tokens extends Table {
  TextColumn get walletId => text().references(Wallets, #id)();
  TextColumn get coin => text()();
  TextColumn get contract => text().withDefault(const Constant(''))();
  TextColumn get symbol => text()();
  IntColumn get decimals => integer()();
  TextColumn get name => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  BoolColumn get trusted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {walletId, coin, contract};
}

class Balances extends Table {
  TextColumn get walletId => text().references(Wallets, #id)();
  TextColumn get coin => text()();
  TextColumn get contract => text().withDefault(const Constant(''))();

  /// BigInt base units, decimal string.
  TextColumn get raw => text()();
  RealColumn get fiat => real().nullable()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {walletId, coin, contract};
}

class Transactions extends Table {
  TextColumn get id => text()();
  TextColumn get walletId => text().references(Wallets, #id)();
  TextColumn get reqId => text().nullable()();
  TextColumn get coin => text()();
  TextColumn get contract => text().nullable()();
  IntColumn get direction => intEnum<TxDirection>()();
  TextColumn get fromAddr => text()();
  TextColumn get toAddr => text()();
  TextColumn get amountRaw => text()();
  TextColumn get feeRaw => text().nullable()();
  TextColumn get hash => text().nullable()();
  IntColumn get status => intEnum<TxStatus>()();
  IntColumn get signMode => intEnum<SignMode>()();
  TextColumn get memo => text().nullable()();
  IntColumn get createdAt => integer()();
  IntColumn get broadcastAt => integer().nullable()();

  /// EVM replacement metadata. Quantities remain decimal strings so nonce and
  /// fees never lose precision. They are null for TRON, Solana and legacy rows.
  TextColumn get nonce => text().nullable()();
  TextColumn get maxPriorityFeeRaw => text().nullable()();
  TextColumn get maxFeeRaw => text().nullable()();
  TextColumn get gasLimitRaw => text().nullable()();

  /// Replacement lineage. A successfully accepted replacement sets the
  /// original row's [replacedById]; the new row points back with [replacesId].
  TextColumn get replacesId => text().nullable()();
  TextColumn get replacedById => text().nullable()();
  IntColumn get replacementKind => intEnum<TxReplacementKind>().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class AddressBook extends Table {
  TextColumn get id => text()();
  TextColumn get walletId => text().references(Wallets, #id)();
  TextColumn get name => text()();
  TextColumn get address => text()();
  TextColumn get coin => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

class SignRequests extends Table {
  TextColumn get reqId => text()();
  TextColumn get walletId => text().references(Wallets, #id)();
  TextColumn get coin => text()();
  BlobColumn get rawTx => blob()();
  IntColumn get expiresAt => integer()();
  TextColumn get status => text()();

  @override
  Set<Column> get primaryKey => {reqId};
}

/// Global (cross-wallet) address-book contacts (Settings → 地址管理). Unlike
/// [AddressBook] these are not scoped to a wallet: the address book screen is
/// an app-level surface. Added in schema v2.
class Contacts extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().withLength(min: 1, max: 64)();
  TextColumn get address => text()();

  /// Canonical chain tag (e.g. 'ethereum', 'tron'). Stored as text because
  /// wallet_data has no dependency on the chains package's enum.
  TextColumn get chain => text()();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Global custom-token registry (Settings → Token 管理): the user-managed
/// show/hide token list, independent of any wallet. Added in schema v2.
class CustomTokens extends Table {
  TextColumn get id => text()();
  TextColumn get symbol => text()();
  TextColumn get name => text()();
  TextColumn get contract => text().nullable()();

  /// Display label for where the token lives (e.g. 'TRON · TRC-20').
  TextColumn get network => text()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Global settings (not per-wallet).
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Per-wallet settings.
class WalletSettings extends Table {
  TextColumn get walletId => text().references(Wallets, #id)();
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {walletId, key};
}

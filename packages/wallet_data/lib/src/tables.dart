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

/// Semantic operation represented by a transaction row. Keeping this
/// separate from `amountRaw` prevents an ERC-20 `approve(spender, 0)` revoke
/// from being rendered or exported as a zero-value token transfer.
enum TxOperationKind { transfer, approvalRevoke }

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

/// Result of the latest hash-specific, chain-authoritative status lookup for
/// a transaction that is still locally live.
///
/// This is deliberately separate from [TxStatus]: an unavailable RPC or a
/// node that no longer remembers a hash must not terminally fail/drop a
/// transaction, but the UI must also not keep claiming that it is definitely
/// pending. A later successful lookup can move this evidence back to
/// [pending] or settle the transaction normally.
enum TxCheckOutcome { pending, unknown }

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

  /// NETWORK DIMENSION (schema v4). The app-level network id
  /// ('eth-mainnet', 'eth-sepolia', 'tron-nile', 'custom-1712…'), NOT the EVM
  /// chain id, because:
  ///
  /// * a chain id is null for TRON and Solana, whose testnets (Nile, Devnet)
  ///   are just as selectable and just as dangerous to confuse;
  /// * user-added custom networks may reuse or omit a chain id, so it is not
  ///   a unique key, while the network id is the app's stable identity and
  ///   maps 1:1 onto `NetworkController.byId` / `activeFor(chain).id`.
  ///
  /// [coin] stays the protocol family; this column says WHICH instance of it.
  /// Nullable only for rows the v4 backfill could not attribute; every write
  /// since v4 sets it. A null here is treated as "unknown network", which
  /// disables replacement rather than guessing.
  TextColumn get networkId => text().nullable()();
  TextColumn get contract => text().nullable()();
  IntColumn get operation => intEnum<TxOperationKind>().withDefault(
    Constant(TxOperationKind.transfer.index),
  )();
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

  /// Epoch milliseconds of the latest hash-specific status lookup attempted
  /// against the Gateway or an active chain RPC. This is diagnostic evidence,
  /// not a finality signal: a recent lookup may still have returned unknown.
  IntColumn get lastCheckedAt => integer().nullable()();

  /// What the latest hash-specific lookup actually proved. Null means no
  /// lookup result has been recorded (or the transaction is terminal).
  IntColumn get lastCheckOutcome => intEnum<TxCheckOutcome>().nullable()();

  /// Chain-authoritative validity metadata. These values are captured from
  /// the same RPC response used to construct the signed transaction:
  ///
  /// * TRON stores the TAPOS reference block height and epoch-ms expiration.
  /// * Solana stores the `lastValidBlockHeight` paired with its recent
  ///   blockhash.
  ///
  /// They stay null for EVM and legacy rows. A status poller may mark a
  /// missing transaction `expired` only after the active canonical chain has
  /// advanced beyond the corresponding persisted boundary.
  IntColumn get referenceBlockHeight => integer().nullable()();
  IntColumn get expiresAt => integer().nullable()();
  IntColumn get lastValidBlockHeight => integer().nullable()();

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

/// Privacy-minimal transaction-finality samples committed in the same SQLite
/// transaction as the terminal status they describe.
///
/// The table deliberately contains no wallet id, address, transaction hash,
/// amount, network, error text or event timestamp. An auto-increment sequence
/// only preserves local ordering while the repository keeps the newest 100
/// rows. This makes SQLite the single durable source for finality metrics and
/// removes the crash window created by copying them to SharedPreferences.
class FinalityMetrics extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get durationMs => integer()();
  BoolColumn get success => boolean()();
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

  /// Exact network instance selected when the user added the token.
  ///
  /// Older rows are null because the original token form stored only a
  /// human-readable label. Callers must not guess a network from that label:
  /// the same contract address can identify unrelated tokens on two EVM
  /// chains.
  TextColumn get networkId => text().nullable()();
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

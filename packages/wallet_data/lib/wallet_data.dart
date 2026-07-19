/// KT Wallet online-app persistence: drift schema + per-wallet-scoped
/// repositories. See detailed-design.md §5.
///
/// USAGE CONTRACT: application code must go through [WalletsRepository] and its
/// [WalletRepository] scopes for all business-table access. The [WalletDatabase]
/// handle is exported only so the app can construct a repository
/// (`WalletsRepository(db)`) and manage the connection lifecycle; its raw
/// `select`/`into`/`delete`/`customStatement` surface bypasses per-wallet
/// isolation (INV-11) and must not be used for business queries. Enforced by
/// convention + review (a lint rule banning direct table access outside this
/// package is a P8 hardening item).
library;

export 'src/database.dart';
export 'src/repositories.dart';
export 'src/tables.dart'
    show WalletType, TxDirection, TxStatus, SignMode;

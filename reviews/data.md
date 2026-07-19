# Review: P4 wallet_data (data layer)

Module: `packages/wallet_data` (drift schema + per-wallet-scoped repositories).
Reviewer: AI code review (Explore agent) + author reconciliation.
Design refs: detailed-design.md §5.1, §8.11.

## Test status

- `dart test` → 13 passing (per-wallet isolation across transactions / address
  book / token visibility / settings; forced-scope on foreign walletId; delete
  cascade; count; newest-first ordering; large-BigInt-as-text round-trip;
  schema/table-set integrity; concurrent cross-wallet writes).
- `dart analyze` → clean. Generated `database.g.dart` committed; CI regenerates.
- Fully verifiable here (drift + in-memory sqlite3).

## Findings & disposition

### Blocking — FIXED

- **Release-build cross-wallet write via `companion.walletId`** — the scoped
  write methods (`upsertAccount/Transaction/Token/Balance`, `addContact`)
  guarded a foreign walletId only with `assert(...)`, which is stripped in
  release/profile builds, then inserted the caller's companion as-is. A caller
  could write wallet B's row through `wallets.scoped('A')` in the build that
  ships. FIXED: each method now forces the scope's id via
  `companion.copyWith(walletId: Value(walletId))` — isolation holds regardless
  of build mode. New test "scope forces walletId even if the caller passes a
  foreign one" pins it. (`putSetting` already built the companion from the
  scope and needed no change.)

### Minor — FIXED / addressed

- **FK cascade not actually enforced** — investigation showed drift emits NO
  SQL `FOREIGN KEY` clause for these tables in this build config (only CHECK
  constraints), so a DB-level `ON DELETE CASCADE` never fires (and
  `foreign_keys=ON` is confirmed at runtime). The non-functional
  `onDelete: KeyAction.cascade` annotations were removed to avoid implying a
  guarantee that doesn't exist. The schema now documents that
  `WalletsRepository.deleteWallet`'s explicit, transactional child-deletion is
  the authoritative cascade, and a test pins that contract.
- **`count()` loaded all rows** — replaced with a `SELECT COUNT(*)`
  (`selectOnly` + `id.count()`).
- **Full `WalletDatabase` re-exported (unscoped table access)** — the handle
  must be exported so the app can construct `WalletsRepository(db)` and manage
  the connection, but its raw `select/into/delete/customStatement` surface
  bypasses isolation. Documented a hard USAGE CONTRACT in `wallet_data.dart`;
  a custom lint banning direct table access outside the package is queued as a
  **P8 hardening item**.

### Confirmed correct (agent, no violation)

- Scope coverage: every `WalletRepository` read/mutate binds the instance
  `walletId`; none takes an overriding walletId parameter.
- `deleteWallet` cascade completeness: all seven per-wallet tables + the wallet
  row, in a transaction, child-before-parent; global `Settings` excluded.
- Money columns: all base-unit amounts are TEXT (BigInt string); only
  `balances.fiat` is REAL (the allowed estimate).
- Ordering (newest-first), `enabledOnly` token filter, and per-wallet settings
  key scoping (`{walletId, key}` PK) all correct.

## Invariant checklist (DD §8.11)

| # | Invariant | Status |
|---|-----------|--------|
| 11 | Every business query bound to walletId; no cross-wallet read/write | PASS — reads scoped; writes force scope id in all build modes; only `WalletsRepository` crosses wallets |

## Gate decision

Auto-continue gate (no user stop). Blocking finding fixed and pinned by test;
minors fixed or documented with a P8 follow-up. 13 tests green, analyze clean.
Proceeding to P5 (Cold Signer app).

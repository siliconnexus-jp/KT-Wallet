# wallet_data

Drift/SQLite persistence for the online KT Wallet app. It stores public wallet
metadata, accounts, balances, contacts, custom tokens, signing requests, and
transaction lifecycle state. Private keys and mnemonics do not belong in this
database.

```dart
final database = WalletDatabase(queryExecutor);
final wallets = WalletsRepository(database);
final current = wallets.scoped('wallet-id');
final pending = await current.transactions(
  networkIds: {'eth-sepolia'},
);
```

## Invariants

- `WalletRepository` is permanently scoped to one wallet ID and overwrites a
  caller-supplied foreign wallet ID on writes.
- transaction queries can be restricted by network instance so mainnet and
  testnet rows never merge;
- EVM nonce reservation is atomic per wallet, network, sender, and nonce;
- replacement lineage and `pending/unknown/confirmed/failed/dropped` evidence
  survive restart;
- wallet deletion cascades all wallet-scoped public state.

Schema changes require a migration, preservation tests from every supported
version, and an updated schema-version comment. Host apps must apply platform
file protection and backup exclusion; this package cannot enforce OS storage
policy itself.

Run `dart run build_runner build --delete-conflicting-outputs` after table
changes and `dart test` before committing generated code. Licensed under
MPL-2.0; see `LICENSE`.

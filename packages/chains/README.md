# chains

Chain primitives shared by KT Wallet and KT Cold Signer. The package supports
Ethereum-compatible networks, TRON, and Solana without depending on app UI or
storage.

## Capabilities

- strict address validation and exact decimal/base-unit conversion;
- EIP-1559, TRON protobuf, and Solana message construction/parsing;
- native transfers, ERC-20/TRC-20/SPL transfers, EVM approval revocation, and
  Solana Associated Token Account binding;
- canonical signed-transaction verification and sender/fee-payer recovery,
  including EVM/TRON high-s rejection and full original-request byte/field
  equality;
- typed EVM, TRON, and Solana RPC clients over caller-provided transports;
- canonical derivation-path declarations for every supported chain.

```dart
import 'package:chains/chains.dart';

final validation = Addresses.validate(
  Chain.ethereum,
  '0x1111111111111111111111111111111111111111',
);
if (!validation.isValid) throw StateError('invalid recipient');

final amount = Amount.parse('1.25', decimals: 6);
assert(amount.raw == BigInt.from(1_250_000));
```

Import `package:chains/rpc.dart` only in the online wallet or Gateway-facing
code. KT Cold Signer deliberately bans that library through the repository
dependency firewall.

## Security boundary

Transaction previews must be produced by the parsers in this package, never
from QR summary text. A successful parse is not permission to broadcast:
network identity, live fees, balance, simulation, user authentication, native
signing, canonical wire decoding, signer recovery, and post-signature
byte/field equality are separate fail-closed gates.

Run `dart test` from this package directory. Licensed under MPL-2.0; see
`LICENSE`.

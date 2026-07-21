# Real-signing recon (P1-4 groundwork)

Recorded 2026-07-21 after wiring real crypto (derive) on iOS. This documents
exactly what stands between the app and REAL transaction signing, so the
implementation round can execute without re-discovery.

## Current bridge state (fail-closed by design)

`packages/core_crypto/ios/.../WalletCoreBridge.swift` — `sign(entropy, coin,
signingInput)` deliberately throws `SIGN_FAILED`:

> IMPORTANT (must be completed + verified on device — P1-4 DoD): `chains`
> builds the SigningInput WITHOUT a private key; the derived key must be
> injected into the per-chain SigningInput proto here before `AnySigner.sign`.

So real signing = (A) Dart builds per-chain wallet-core `SigningInput`
protobufs (no key material), (B) Swift deserializes, injects the derived
private key, runs `AnySigner.sign`, returns `signedTx` + `txHash` from the
per-chain `SigningOutput`.

## SigningInput field maps (wallet-core master, fetched 2026-07-21)

### Ethereum.proto → TW.Ethereum.Proto.SigningInput
| field | # | type | notes |
|---|---|---|---|
| chain_id | 1 | bytes | big-endian minimal |
| nonce | 2 | bytes | big-endian minimal |
| tx_mode | 3 | enum | `Enveloped` for EIP-1559 |
| gas_limit | 5 | bytes | |
| max_inclusion_fee_per_gas | 6 | bytes | priority fee |
| max_fee_per_gas | 7 | bytes | |
| to_address | 8 | string | checksummed hex |
| private_key | 9 | bytes | **Swift-injected only** |
| transaction | 10 | msg | `.transfer{amount=1,data=2}` or `.erc20_transfer{to=1,amount=2}` |

Output: `SigningOutput.encoded` = signed typed tx; txHash = keccak256(encoded)
(compute with our chains keccak; wallet-core also exposes Hash.keccak256).

### Tron.proto → TW.Tron.Proto.SigningInput
| field | # | type | notes |
|---|---|---|---|
| transaction | 1 | msg | structured raw_data |
| private_key | 2 | bytes | Swift-injected |
| raw_json | 3 | string | **preferred path**: node-style JSON with txID + raw_data(+_hex); when set, `transaction` is ignored and the library verifies the hash itself |

Our own `chains` TRON raw_data encoder (in flight) produces raw_data_hex +
txID — feed them through `raw_json` so wallet-core cross-verifies OUR
serialization against OUR hash. Output: `SigningOutput.id` is the txid.

### Solana.proto → TW.Solana.Proto.SigningInput
| field | # | type | notes |
|---|---|---|---|
| private_key | 1 | bytes | Swift-injected |
| recent_blockhash | 2 | string | base58 |
| v0_msg | 3 | bool | false = legacy |
| transfer_transaction | 4 | msg | `Transfer{recipient=1,value=2,...}` (verify sub-fields at impl time) |

Output: `SigningOutput.encoded` (base58 tx for broadcast).

## Implementation checklist

**Swift (core_crypto/ios, ~80 lines)**
1. `case "eth","polygon"`: `EthereumSigningInput(serializedBytes:)` →
   `input.privateKey = wallet.getKeyForCoin(.ethereum).data` →
   `AnySigner.sign` → `(output.encoded, keccak256 hex)`.
2. `case "tron"`: TronSigningInput, key for `.tron`, txHash = `output.id`.
3. `case "solana"`: SolanaSigningInput, key for `.solana`, encoded is the
   broadcastable payload; txHash = first signature (base58).
4. Keep the AuthGate wrap and fail-closed error mapping as-is.

**Dart (kt_wallet or chains)**
- Reuse the protobuf writer landing with the TRON encoder to emit the three
  SigningInput shapes (never with field 9/2/1 private_key — enforced by
  construction). Replace `signingInput` sent over the MethodChannel; today's
  `rawTx` (EIP-1559 unsigned / TRON raw_data / Solana message) stays in the
  airgap payload for signer display+hash purposes.

**Verification (iOS simulator integration test)**
- Determinism: same wallet + same input → identical signedTx.
- Structure: EVM output starts 0x02 and parses as RLP list; TRON output.id
  equals OUR independently computed sha256(raw_data); Solana encoded
  base58-decodes with signature count 1.
- The TRON raw_json path makes wallet-core itself assert our serialization
  (it rejects mismatched txID) — the strongest cross-check available without
  a second signer implementation.

## Non-goals until then
Broadcast of real signatures (pipe already gated on the SIGNED-V1 demo
prefix), Android (blocked on wallet-core credential), testnet funds.

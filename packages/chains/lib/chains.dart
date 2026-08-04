/// Chain adapters CORE: money type, address validation, transaction
/// preview/builder parameters and crypto primitives. Pure Dart, safe for BOTH
/// apps. RPC clients live in the separate `package:chains/rpc.dart` entrypoint
/// which the offline signer must NOT import (dependency firewall, tech-plan §4).
library;

export 'src/address.dart';
export 'src/amount.dart';
export 'src/base58.dart' show base58Decode, base58Encode, Base58Error;
export 'src/derivation_paths.dart';
export 'src/evm_abi.dart';
export 'src/evm_tx.dart';
export 'src/keccak.dart' show keccak256;
export 'src/rlp.dart';
export 'src/sha256.dart' show sha256;
export 'src/signature_verifier.dart';
export 'src/strict_json.dart' show decodeJsonWithUniqueObjectMembers;
export 'src/solana_tx.dart';
export 'src/transaction_parser.dart';
export 'src/tron_tx.dart';
export 'src/tx_preview.dart';

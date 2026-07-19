/// AIRGAP-V1: animated-QR transport for account export, unsigned transactions
/// and signed results between KT Wallet and Cold Signer.
///
/// See detailed-design.md §3 for the wire format, state machine and anti-replay
/// rules. Pure Dart, shared by both apps.
library;

export 'src/aggregator.dart';
export 'src/cbor.dart';
export 'src/crc32.dart';
export 'src/fragmenter.dart';
export 'src/payload.dart';
export 'src/validator.dart';

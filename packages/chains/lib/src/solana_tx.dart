import 'dart:typed_data';

import 'base58.dart';

/// Solana LEGACY message serialization — the exact bytes an offline signer
/// ed25519-signs, so the air-gap payload carries a genuine sign-ready
/// message instead of a summary (mirroring `Eip1559Tx` for EVM chains).
///
/// Layout per the Solana transaction spec:
/// `header(3 bytes) || compact-u16 key count || 32-byte keys ||
///  recentBlockhash(32) || compact-u16 ix count || instructions`,
/// where each instruction is `programIdIndex(u8) || compact-u16 account
/// count || account indices || compact-u16 data length || data`.
///
/// Versioned (v0) messages, address-lookup tables and multi-signer
/// transactions are out of scope: V1 only builds single-signer native SOL
/// and SPL-token transfers, which legacy messages cover completely.

/// System Program id (native SOL transfers).
const String solanaSystemProgram = '11111111111111111111111111111111';

/// SPL Token Program id.
const String solanaTokenProgram =
    'TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA';

final BigInt _u64Max = (BigInt.one << 64) - BigInt.one;

/// One compiled instruction: indices into the message's account-key table
/// plus opaque program data.
class SolanaInstruction {
  SolanaInstruction({
    required this.programIdIndex,
    required List<int> accountIndices,
    required Uint8List data,
  })  : accountIndices = Uint8List.fromList(accountIndices),
        data = Uint8List.fromList(data) {
    if (programIdIndex < 0 || programIdIndex > 0xff) {
      throw ArgumentError('programIdIndex must fit a u8: $programIdIndex');
    }
    for (final i in accountIndices) {
      if (i < 0 || i > 0xff) {
        throw ArgumentError('account index must fit a u8: $i');
      }
    }
  }

  /// Index of the program id in the message account keys.
  final int programIdIndex;

  /// Indices of the instruction's accounts in the message account keys.
  final Uint8List accountIndices;

  /// Program-specific instruction data.
  final Uint8List data;
}

/// A legacy Solana message: header, account keys, recent blockhash and
/// compiled instructions.
class SolanaMessage {
  SolanaMessage({
    required this.numRequiredSignatures,
    required this.numReadonlySignedAccounts,
    required this.numReadonlyUnsignedAccounts,
    required List<Uint8List> accountKeys,
    required Uint8List recentBlockhash,
    required List<SolanaInstruction> instructions,
  })  : accountKeys = List.unmodifiable(
            [for (final k in accountKeys) Uint8List.fromList(k)]),
        recentBlockhash = Uint8List.fromList(recentBlockhash),
        instructions = List.unmodifiable(instructions) {
    if (numRequiredSignatures < 1 || numRequiredSignatures > 0xff) {
      throw ArgumentError(
          'numRequiredSignatures out of range: $numRequiredSignatures');
    }
    if (numReadonlySignedAccounts < 0 ||
        numReadonlySignedAccounts >= numRequiredSignatures) {
      throw ArgumentError('numReadonlySignedAccounts must be >= 0 and leave '
          'at least one writable signer (the fee payer)');
    }
    if (numReadonlyUnsignedAccounts < 0 ||
        numRequiredSignatures + numReadonlyUnsignedAccounts >
            accountKeys.length) {
      throw ArgumentError('header counts exceed ${accountKeys.length} keys');
    }
    for (final key in accountKeys) {
      if (key.length != 32) {
        throw ArgumentError('account key must be 32 bytes, got ${key.length}');
      }
    }
    if (recentBlockhash.length != 32) {
      throw ArgumentError(
          'recentBlockhash must be 32 bytes, got ${recentBlockhash.length}');
    }
    for (final ix in instructions) {
      if (ix.programIdIndex >= accountKeys.length) {
        throw ArgumentError(
            'programIdIndex ${ix.programIdIndex} out of key range');
      }
      for (final i in ix.accountIndices) {
        if (i >= accountKeys.length) {
          throw ArgumentError('account index $i out of key range');
        }
      }
    }
  }

  /// Builds the message for a native SOL transfer: System Program
  /// instruction 2 (Transfer), data = `u32 LE 2 || u64 LE lamports`.
  ///
  /// Account order per the spec: [from] is the writable fee-payer signer
  /// (index 0), [to] the writable non-signer (index 1), and the System
  /// Program the readonly non-signer (index 2) — header (1, 0, 1).
  factory SolanaMessage.systemTransfer({
    required String from,
    required String to,
    required BigInt lamports,
    required String recentBlockhash,
  }) {
    final data = BytesBuilder()
      ..add(_u32le(2)) // SystemInstruction::Transfer
      ..add(_u64le(lamports, 'lamports'));
    return SolanaMessage(
      numRequiredSignatures: 1,
      numReadonlySignedAccounts: 0,
      numReadonlyUnsignedAccounts: 1,
      accountKeys: [
        pubkeyBytes(from),
        pubkeyBytes(to),
        pubkeyBytes(solanaSystemProgram),
      ],
      recentBlockhash: pubkeyBytes(recentBlockhash),
      instructions: [
        SolanaInstruction(
          programIdIndex: 2,
          accountIndices: const [0, 1],
          data: data.toBytes(),
        ),
      ],
    );
  }

  /// Builds the message for an SPL-token transfer: Token Program
  /// instruction 3 (Transfer), data = `u8 3 || u64 LE amount`, accounts
  /// [source (writable), destination (writable), owner (signer)].
  ///
  /// [source] and [destination] are explicit token accounts. Deriving the
  /// associated token account from a wallet address needs the sha256-based
  /// PDA search with ed25519 off-curve checks — out of scope for V1, so
  /// callers resolve token accounts (e.g. via RPC) and pass them in.
  ///
  /// Key table: [owner] is the writable fee-payer signer (index 0), the
  /// two token accounts are writable non-signers (indices 1, 2) and the
  /// Token Program is the readonly non-signer (index 3) — header (1, 0, 1).
  factory SolanaMessage.splTransfer({
    required String source,
    required String destination,
    required String owner,
    required BigInt amount,
    required String recentBlockhash,
  }) {
    final data = BytesBuilder()
      ..addByte(3) // TokenInstruction::Transfer
      ..add(_u64le(amount, 'amount'));
    return SolanaMessage(
      numRequiredSignatures: 1,
      numReadonlySignedAccounts: 0,
      numReadonlyUnsignedAccounts: 1,
      accountKeys: [
        pubkeyBytes(owner),
        pubkeyBytes(source),
        pubkeyBytes(destination),
        pubkeyBytes(solanaTokenProgram),
      ],
      recentBlockhash: pubkeyBytes(recentBlockhash),
      instructions: [
        SolanaInstruction(
          programIdIndex: 3,
          accountIndices: const [1, 2, 0], // source, destination, owner
          data: data.toBytes(),
        ),
      ],
    );
  }

  final int numRequiredSignatures;
  final int numReadonlySignedAccounts;
  final int numReadonlyUnsignedAccounts;

  /// 32-byte public keys: signers first (writable then readonly), then
  /// writable non-signers, then readonly non-signers.
  final List<Uint8List> accountKeys;

  final Uint8List recentBlockhash;
  final List<SolanaInstruction> instructions;

  /// Decodes a base58 pubkey (or blockhash) and requires exactly 32 bytes,
  /// so a truncated or wrong-network paste can never reach the wire.
  static Uint8List pubkeyBytes(String base58) {
    final Uint8List bytes;
    try {
      bytes = base58Decode(base58);
    } on Base58Error catch (e) {
      throw ArgumentError('invalid base58 pubkey: ${e.message}');
    }
    if (bytes.length != 32) {
      throw ArgumentError(
          'pubkey must decode to 32 bytes, got ${bytes.length}: $base58');
    }
    return bytes;
  }

  /// Encodes a length as compact-u16 (shortvec) per the Solana spec: seven
  /// value bits per byte, little-endian groups, high bit = continuation.
  static Uint8List encodeCompactU16(int value) {
    if (value < 0 || value > 0xffff) {
      throw ArgumentError('compact-u16 out of range: $value');
    }
    final out = <int>[];
    var v = value;
    while (true) {
      final elem = v & 0x7f;
      v >>= 7;
      if (v == 0) {
        out.add(elem);
        return Uint8List.fromList(out);
      }
      out.add(elem | 0x80);
    }
  }

  /// Serializes the legacy message. A signed transaction on the wire is
  /// `compact-u16 signature count || 64-byte signatures || serialize()`.
  Uint8List serialize() {
    final out = BytesBuilder()
      ..addByte(numRequiredSignatures)
      ..addByte(numReadonlySignedAccounts)
      ..addByte(numReadonlyUnsignedAccounts)
      ..add(encodeCompactU16(accountKeys.length));
    for (final key in accountKeys) {
      out.add(key);
    }
    out
      ..add(recentBlockhash)
      ..add(encodeCompactU16(instructions.length));
    for (final ix in instructions) {
      out
        ..addByte(ix.programIdIndex)
        ..add(encodeCompactU16(ix.accountIndices.length))
        ..add(ix.accountIndices)
        ..add(encodeCompactU16(ix.data.length))
        ..add(ix.data);
    }
    return out.toBytes();
  }

  /// The bytes the signer's ed25519 key signs — exactly [serialize], with
  /// no hashing step (unlike EVM's keccak256 pre-hash).
  Uint8List get signingBytes => serialize();

  static Uint8List _u32le(int value) {
    final out = Uint8List(4);
    ByteData.view(out.buffer).setUint32(0, value, Endian.little);
    return out;
  }

  static Uint8List _u64le(BigInt value, String name) {
    if (value < BigInt.zero || value > _u64Max) {
      throw ArgumentError('$name must fit an unsigned 64-bit int: $value');
    }
    final out = Uint8List(8);
    var v = value;
    final mask = BigInt.from(0xff);
    for (var i = 0; i < 8; i++) {
      out[i] = (v & mask).toInt();
      v >>= 8;
    }
    return out;
  }
}

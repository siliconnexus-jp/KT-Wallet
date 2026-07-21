import 'dart:typed_data';

import 'address.dart';
import 'base58.dart';
import 'sha256.dart';
import 'tx_preview.dart';

/// TRON unsigned transaction: the `Transaction.raw` protobuf bytes that the
/// offline signer hashes (`txID == sha256(raw_data)`) and signs, and that
/// `wallet/broadcasttransaction` expects back together with the signature.
///
/// Field numbers and structure come from TRON's protocol definitions,
/// fetched 2026-07-21 from
/// https://raw.githubusercontent.com/tronprotocol/protocol/master/core/Tron.proto
/// and core/contract/{balance_contract,smart_contract}.proto — cited inline
/// below. The encoding is locked against real mainnet transactions in
/// tron_tx_test.dart (byte-identical raw_data_hex + txID reproduction).

// ---------------------------------------------------------------------------
// Minimal protobuf wire-format writer
// ---------------------------------------------------------------------------

/// Minimal protobuf (proto3) wire-format writer — only what TRON `raw_data`
/// encoding needs: varints, field tags, and length-delimited fields
/// (bytes / UTF-8 strings / embedded messages). Fields must be written in
/// ascending field-number order to match java-tron's canonical serialization
/// (verified byte-identical against on-chain transactions).
final class ProtoWriter {
  final BytesBuilder _out = BytesBuilder();

  /// Encodes a non-negative integer as a base-128 varint (protobuf spec:
  /// 7 bits per byte, LSB group first, high bit = continuation).
  static Uint8List varint(int value) {
    if (value < 0) {
      // TRON raw_data only ever carries non-negative int64s (timestamps,
      // amounts, fee limits); a negative here is a caller bug, and encoding
      // it would require the 10-byte two's-complement form.
      throw ArgumentError('varint value must be non-negative: $value');
    }
    final out = BytesBuilder();
    var v = value;
    while (v > 0x7F) {
      out.addByte((v & 0x7F) | 0x80);
      v >>= 7;
    }
    out.addByte(v);
    return out.toBytes();
  }

  /// Field tag: `(fieldNumber << 3) | wireType` (protobuf encoding spec).
  /// Wire type 0 = varint, 2 = length-delimited.
  static int tag(int fieldNumber, int wireType) =>
      (fieldNumber << 3) | wireType;

  /// Writes a varint (wire type 0) field.
  void writeVarint(int fieldNumber, int value) {
    _out.add(varint(tag(fieldNumber, 0)));
    _out.add(varint(value));
  }

  /// Writes a length-delimited (wire type 2) field: bytes or an embedded
  /// message's encoded bytes.
  void writeBytes(int fieldNumber, List<int> bytes) {
    _out.add(varint(tag(fieldNumber, 2)));
    _out.add(varint(bytes.length));
    _out.add(bytes);
  }

  /// Writes a length-delimited string field (UTF-8; TRON type_urls are ASCII).
  void writeString(int fieldNumber, String value) =>
      writeBytes(fieldNumber, value.codeUnits);

  Uint8List toBytes() => _out.toBytes();
}

// ---------------------------------------------------------------------------
// Contracts
// ---------------------------------------------------------------------------

/// One contract inside `Transaction.raw.contract` — V1 builds exactly one:
/// a TRX transfer or a TRC-20 `transfer(address,uint256)` call.
sealed class TronContract {
  /// `Transaction.Contract.ContractType` enum value (Tron.proto).
  int get typeCode;

  /// `google.protobuf.Any.type_url` for the parameter payload.
  String get typeUrl;

  /// Encodes the contract-specific parameter message (the `Any.value` bytes).
  Uint8List encodeValue();
}

/// TRX native transfer. Fields per balance_contract.proto:
/// ```proto
/// message TransferContract {
///   bytes owner_address = 1;
///   bytes to_address = 2;
///   int64 amount = 3;
/// }
/// ```
final class TransferContract implements TronContract {
  TransferContract({
    required Uint8List ownerAddress,
    required Uint8List toAddress,
    required this.amount,
  })  : ownerAddress = _checkRawAddress(ownerAddress, 'ownerAddress'),
        toAddress = _checkRawAddress(toAddress, 'toAddress') {
    _checkInt64(amount, 'amount');
  }

  /// Raw 21-byte 0x41-prefixed sender address (base58check-decoded).
  final Uint8List ownerAddress;

  /// Raw 21-byte 0x41-prefixed recipient address.
  final Uint8List toAddress;

  /// Amount in SUN (1 TRX = 1e6 SUN).
  final BigInt amount;

  /// `ContractType.TransferContract = 1` (Tron.proto).
  @override
  int get typeCode => 1;

  @override
  String get typeUrl => 'type.googleapis.com/protocol.TransferContract';

  @override
  Uint8List encodeValue() {
    final w = ProtoWriter()
      ..writeBytes(1, ownerAddress) // owner_address = 1
      ..writeBytes(2, toAddress) // to_address = 2
      ..writeVarint(3, amount.toInt()); // amount = 3
    return w.toBytes();
  }
}

/// Smart-contract call (TRC-20 transfer). Fields per smart_contract.proto:
/// ```proto
/// message TriggerSmartContract {
///   bytes owner_address = 1;
///   bytes contract_address = 2;
///   int64 call_value = 3;
///   bytes data = 4;
///   int64 call_token_value = 5;
///   int64 token_id = 6;
/// }
/// ```
/// V1 only builds plain TRC-20 transfers: `call_value`, `call_token_value`
/// and `token_id` stay at their proto3 defaults (0) and are omitted from the
/// wire, matching how wallets encode USDT transfers on mainnet.
final class TriggerSmartContract implements TronContract {
  TriggerSmartContract({
    required Uint8List ownerAddress,
    required Uint8List contractAddress,
    required Uint8List data,
  })  : ownerAddress = _checkRawAddress(ownerAddress, 'ownerAddress'),
        contractAddress = _checkRawAddress(contractAddress, 'contractAddress'),
        data = Uint8List.fromList(data);

  /// Raw 21-byte 0x41-prefixed caller address.
  final Uint8List ownerAddress;

  /// Raw 21-byte 0x41-prefixed contract address (e.g. USDT).
  final Uint8List contractAddress;

  /// ABI calldata (selector + arguments); see [Trc20.transferCalldata].
  final Uint8List data;

  /// `ContractType.TriggerSmartContract = 31` (Tron.proto).
  @override
  int get typeCode => 31;

  @override
  String get typeUrl => 'type.googleapis.com/protocol.TriggerSmartContract';

  @override
  Uint8List encodeValue() {
    final w = ProtoWriter()
      ..writeBytes(1, ownerAddress) // owner_address = 1
      ..writeBytes(2, contractAddress) // contract_address = 2
      ..writeBytes(4, data); // data = 4 (call_value=3 omitted, default 0)
    return w.toBytes();
  }
}

// ---------------------------------------------------------------------------
// raw_data
// ---------------------------------------------------------------------------

/// TRON `Transaction.raw` in its unsigned form — the exact bytes the offline
/// signer hashes and signs, mirroring [Eip1559Tx] for EVM chains
/// (detailed-design.md §4.2). Relevant fields per Tron.proto:
/// ```proto
/// message raw {
///   bytes ref_block_bytes = 1;
///   int64 ref_block_num = 3;   // not set by wallets; TRON uses bytes+hash
///   bytes ref_block_hash = 4;
///   int64 expiration = 8;
///   repeated Contract contract = 11;
///   int64 timestamp = 14;
///   int64 fee_limit = 18;
/// }
/// ```
/// and the contract wrapper:
/// ```proto
/// message Contract {
///   ContractType type = 1;
///   google.protobuf.Any parameter = 2;  // Any: string type_url=1, bytes value=2
/// }
/// ```
class TronRawTx {
  TronRawTx({
    required Uint8List refBlockBytes,
    required Uint8List refBlockHash,
    required this.expiration,
    required this.timestamp,
    required this.contract,
    this.feeLimit,
  })  : refBlockBytes = Uint8List.fromList(refBlockBytes),
        refBlockHash = Uint8List.fromList(refBlockHash) {
    if (refBlockBytes.length != 2) {
      throw ArgumentError(
          'refBlockBytes must be 2 bytes, got ${refBlockBytes.length}');
    }
    if (refBlockHash.length != 8) {
      throw ArgumentError(
          'refBlockHash must be 8 bytes, got ${refBlockHash.length}');
    }
    if (expiration < 0 || timestamp < 0) {
      throw ArgumentError('expiration and timestamp must be non-negative');
    }
    final fee = feeLimit;
    if (fee != null && fee <= 0) {
      throw ArgumentError('feeLimit must be positive when set: $fee');
    }
  }

  /// Builds the unsigned raw_data for a [TransferIntent]: a native transfer
  /// becomes a [TransferContract] in SUN; a token transfer becomes a
  /// [TriggerSmartContract] calling `transfer(address,uint256)` on the token
  /// (and then [feeLimit] is required — TriggerSmartContract burns energy).
  /// The caller supplies [refBlockBytes]/[refBlockHash]/timestamps: they come
  /// from the chain (`wallet/getnowblock`) at build time.
  factory TronRawTx.forTransfer(
    TransferIntent intent, {
    required Uint8List refBlockBytes,
    required Uint8List refBlockHash,
    required int expiration,
    required int timestamp,
    int? feeLimit,
  }) {
    if (intent.chain != Chain.tron) {
      throw ArgumentError('not a TRON transfer: ${intent.chain}');
    }
    final owner = addressBytes(intent.from);
    switch (intent.operation) {
      case TxOperation.nativeTransfer:
        return TronRawTx(
          refBlockBytes: refBlockBytes,
          refBlockHash: refBlockHash,
          expiration: expiration,
          timestamp: timestamp,
          feeLimit: feeLimit,
          contract: TransferContract(
            ownerAddress: owner,
            toAddress: addressBytes(intent.to),
            amount: intent.amount.raw,
          ),
        );
      case TxOperation.tokenTransfer:
        if (feeLimit == null) {
          throw ArgumentError('TRC-20 transfer requires a feeLimit');
        }
        return TronRawTx(
          refBlockBytes: refBlockBytes,
          refBlockHash: refBlockHash,
          expiration: expiration,
          timestamp: timestamp,
          feeLimit: feeLimit,
          contract: TriggerSmartContract(
            ownerAddress: owner,
            contractAddress: addressBytes(intent.tokenContract!),
            data: Trc20.transferCalldata(
              to: intent.to,
              amount: intent.amount.raw,
            ),
          ),
        );
    }
  }

  /// `ref_block_bytes`: bytes 6..8 of the reference block height (2 bytes).
  final Uint8List refBlockBytes;

  /// `ref_block_hash`: bytes 8..16 of the reference block ID (8 bytes).
  final Uint8List refBlockHash;

  /// `expiration` in epoch milliseconds.
  final int expiration;

  /// `timestamp` in epoch milliseconds.
  final int timestamp;

  /// `fee_limit` in SUN; only meaningful for [TriggerSmartContract] and
  /// omitted from the wire when null (proto3 default).
  final int? feeLimit;

  /// The single contract (`raw.contract` is repeated in the proto but the
  /// chain only supports size = 1).
  final TronContract contract;

  /// Decodes a base58check TRON address ("T...") into its raw 21-byte
  /// 0x41-prefixed wire form, running it through [Addresses.validate] first
  /// so a bad checksum or wrong-network paste can never reach the wire.
  static Uint8List addressBytes(String address) {
    final v = Addresses.validate(Chain.tron, address);
    if (!v.isValid) {
      throw ArgumentError('invalid TRON address: ${v.reason}');
    }
    // 25 decoded bytes = 21-byte payload (0x41 + 20) + 4-byte checksum;
    // the checksum was verified by Addresses.validate above.
    return Uint8List.sublistView(base58Decode(v.normalized!), 0, 21);
  }

  /// Serializes `Transaction.raw` in canonical (ascending field number)
  /// order — the exact bytes whose sha256 is the txID. Verified
  /// byte-identical against mainnet raw_data_hex in tron_tx_test.dart.
  Uint8List encodeRawData() {
    // Contract wrapper: type = 1 (enum varint), parameter = 2 (Any).
    final any = ProtoWriter()
      ..writeString(1, contract.typeUrl) // Any.type_url = 1
      ..writeBytes(2, contract.encodeValue()); // Any.value = 2
    final contractMsg = ProtoWriter()
      ..writeVarint(1, contract.typeCode) // Contract.type = 1
      ..writeBytes(2, any.toBytes()); // Contract.parameter = 2

    final raw = ProtoWriter()
      ..writeBytes(1, refBlockBytes) // ref_block_bytes = 1
      ..writeBytes(4, refBlockHash) // ref_block_hash = 4
      ..writeVarint(8, expiration) // expiration = 8
      ..writeBytes(11, contractMsg.toBytes()) // contract = 11
      ..writeVarint(14, timestamp); // timestamp = 14
    final fee = feeLimit;
    if (fee != null) {
      raw.writeVarint(18, fee); // fee_limit = 18
    }
    return raw.toBytes();
  }

  /// The transaction ID: hex `sha256(raw_data)` — also the digest the
  /// signer's secp256k1 key signs.
  String txId() => signingHash()
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  /// The digest the signer's secp256k1 key actually signs:
  /// `sha256(encodeRawData())`.
  Uint8List signingHash() => sha256(encodeRawData());
}

// ---------------------------------------------------------------------------
// TRC-20 calldata
// ---------------------------------------------------------------------------

/// Minimal ABI encoding for the only TRON contract call V1 builds: TRC-20
/// `transfer(address,uint256)` — same selector as ERC-20 (0xa9059cbb), but
/// the recipient argument is a TRON base58check address.
abstract final class Trc20 {
  /// 4-byte selector of `transfer(address,uint256)` = 0xa9059cbb.
  static Uint8List get transferSelector =>
      Uint8List.fromList(const [0xa9, 0x05, 0x9c, 0xbb]);

  /// Builds the 68-byte calldata for a TRC-20 transfer. [to] is a
  /// base58check TRON address; [amount] the raw token amount in base units.
  ///
  /// The address word follows the TronWeb convention: the 21-byte raw
  /// address MINUS its 0x41 network prefix, left-padded with 12 zero bytes
  /// (the TVM decodes `address` from the low 20 bytes). Some wallets instead
  /// keep the 0x41 inside the word (11 zero bytes + 21 bytes) — seen on
  /// mainnet, e.g. tx b4856499cb5406a3... in tron_tx_test.dart — and the TVM
  /// accepts both because the extra byte is above the uint160 mask.
  static Uint8List transferCalldata({
    required String to,
    required BigInt amount,
  }) {
    if (amount < BigInt.zero) {
      throw ArgumentError('amount must be non-negative');
    }
    if (amount >= (BigInt.one << 256)) {
      throw ArgumentError('amount exceeds uint256');
    }
    final raw = TronRawTx.addressBytes(to); // 21 bytes, 0x41-prefixed
    final out = BytesBuilder();
    out.add(transferSelector);
    out.add(Uint8List(12)); // pad address to a 32-byte word
    out.add(Uint8List.sublistView(raw, 1)); // 20-byte body, 0x41 stripped
    // uint256 big-endian, left-padded to 32 bytes.
    final word = Uint8List(32);
    var x = amount;
    final mask = BigInt.from(0xFF);
    for (var i = 31; i >= 0 && x > BigInt.zero; i--) {
      word[i] = (x & mask).toInt();
      x = x >> 8;
    }
    out.add(word);
    return out.toBytes();
  }
}

// ---------------------------------------------------------------------------
// Shared checks
// ---------------------------------------------------------------------------

Uint8List _checkRawAddress(Uint8List address, String name) {
  if (address.length != 21 || address[0] != 0x41) {
    throw ArgumentError(
        '$name must be a raw 21-byte 0x41-prefixed TRON address');
  }
  return Uint8List.fromList(address);
}

void _checkInt64(BigInt value, String name) {
  if (value < BigInt.zero) {
    throw ArgumentError('$name must be non-negative: $value');
  }
  if (value >= (BigInt.one << 63)) {
    throw ArgumentError('$name exceeds int64: $value');
  }
}

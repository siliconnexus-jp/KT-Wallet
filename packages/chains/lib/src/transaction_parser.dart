import 'dart:typed_data';

import 'address.dart';
import 'base58.dart';
import 'evm_tx.dart';
import 'sha256.dart';
import 'solana_tx.dart';
import 'tx_preview.dart';

class ParsedUnsignedTransfer {
  const ParsedUnsignedTransfer({
    required this.chain,
    required this.operation,
    required this.to,
    required this.amountRaw,
    this.from,
    this.tokenContract,
    this.networkId,
    this.maxFeeRaw,
    this.nonce,
    this.maxPriorityFeePerGas,
    this.maxFeePerGas,
    this.gasLimit,
  });

  final Chain chain;
  final TxOperation operation;
  final String? from;
  final String to;
  final BigInt amountRaw;
  final String? tokenContract;
  final BigInt? networkId;
  final BigInt? maxFeeRaw;
  final BigInt? nonce;
  final BigInt? maxPriorityFeePerGas;
  final BigInt? maxFeePerGas;
  final BigInt? gasLimit;
}

/// Parses only the exact transaction families KT Wallet can build. It throws
/// on unknown programs/contracts or malformed bytes so the offline signer
/// never falls back to the untrusted QR summary.
ParsedUnsignedTransfer parseUnsignedTransfer(Chain chain, Uint8List rawTx) =>
    switch (chain) {
      Chain.ethereum ||
      Chain.polygon ||
      Chain.base ||
      Chain.arbitrum ||
      Chain.avalanche ||
      Chain.bnb => _parseEvm(chain, rawTx),
      Chain.tron => _parseTron(rawTx),
      Chain.solana => _parseSolana(rawTx),
    };

ParsedUnsignedTransfer _parseEvm(Chain chain, Uint8List raw) {
  if (raw.isEmpty || raw.first != 0x02) {
    throw const FormatException('expected EIP-1559 transaction');
  }
  final fields = _decodeRlpList(raw, 1);
  if (fields.length != 9 || fields[8].isList != true) {
    throw const FormatException('invalid EIP-1559 fields');
  }
  final chainId = _bigInt(fields[0].payload);
  final nonce = _bigInt(fields[1].payload);
  final maxPriorityFeePerGas = _bigInt(fields[2].payload);
  final maxFeePerGas = _bigInt(fields[3].payload);
  final gasLimit = _bigInt(fields[4].payload);
  final destination = fields[5].payload;
  final value = _bigInt(fields[6].payload);
  final data = fields[7].payload;
  if (destination.length != 20) {
    throw const FormatException('contract creation is unsupported');
  }
  // Re-encode the exact V1 family and require byte equality. This rejects
  // non-canonical RLP, list-typed scalar/byte fields, leading-zero integers,
  // and any non-empty access list before an offline signer displays or signs
  // a transaction whose hidden wire meaning differs from the preview.
  final Uint8List canonical;
  try {
    canonical = Eip1559Tx(
      chainId: chainId,
      nonce: nonce,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      maxFeePerGas: maxFeePerGas,
      gasLimit: gasLimit,
      to: destination,
      value: value,
      data: data,
    ).encodeUnsigned();
  } on Object {
    throw const FormatException('invalid EIP-1559 scalar values');
  }
  if (!_same(canonical, raw)) {
    throw const FormatException('non-canonical EIP-1559 transaction');
  }
  final to = '0x${_hex(destination)}';
  if (data.isEmpty) {
    return ParsedUnsignedTransfer(
      chain: chain,
      operation: TxOperation.nativeTransfer,
      to: to,
      amountRaw: value,
      networkId: chainId,
      maxFeeRaw: maxFeePerGas * gasLimit,
      nonce: nonce,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      maxFeePerGas: maxFeePerGas,
      gasLimit: gasLimit,
    );
  }
  if (value != BigInt.zero || data.length != 68) {
    throw const FormatException('unsupported EVM contract call');
  }
  if (data.sublist(4, 16).any((byte) => byte != 0)) {
    throw const FormatException('invalid ERC-20 address word');
  }
  if (_same(data.sublist(0, 4), const [0xa9, 0x05, 0x9c, 0xbb])) {
    return ParsedUnsignedTransfer(
      chain: chain,
      operation: TxOperation.tokenTransfer,
      to: '0x${_hex(data.sublist(16, 36))}',
      amountRaw: _bigInt(data.sublist(36, 68)),
      tokenContract: to,
      networkId: chainId,
      maxFeeRaw: maxFeePerGas * gasLimit,
      nonce: nonce,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      maxFeePerGas: maxFeePerGas,
      gasLimit: gasLimit,
    );
  }
  if (_same(data.sublist(0, 4), const [0x09, 0x5e, 0xa7, 0xb3])) {
    if (data.sublist(36, 68).any((byte) => byte != 0)) {
      throw const FormatException('non-zero ERC-20 approval is unsupported');
    }
    return ParsedUnsignedTransfer(
      chain: chain,
      operation: TxOperation.approvalRevoke,
      to: '0x${_hex(data.sublist(16, 36))}',
      amountRaw: BigInt.zero,
      tokenContract: to,
      networkId: chainId,
      maxFeeRaw: maxFeePerGas * gasLimit,
      nonce: nonce,
      maxPriorityFeePerGas: maxPriorityFeePerGas,
      maxFeePerGas: maxFeePerGas,
      gasLimit: gasLimit,
    );
  }
  throw const FormatException('unsupported EVM contract call');
}

ParsedUnsignedTransfer _parseTron(Uint8List raw) {
  final root = _proto(raw);
  final contractWrapper = root.bytes(11);
  final feeLimit = root.integerOrNull(18);
  final wrapper = _proto(contractWrapper);
  final type = wrapper.integer(1);
  final any = _proto(wrapper.bytes(2));
  final value = _proto(any.bytes(2));
  final from = _tronAddress(value.bytes(1));
  if (type == 1) {
    return ParsedUnsignedTransfer(
      chain: Chain.tron,
      operation: TxOperation.nativeTransfer,
      from: from,
      to: _tronAddress(value.bytes(2)),
      amountRaw: BigInt.from(value.integer(3)),
      maxFeeRaw: feeLimit == null ? null : BigInt.from(feeLimit),
    );
  }
  if (type != 31) throw const FormatException('unsupported TRON contract');
  final calldata = value.bytes(4);
  if (calldata.length != 68 ||
      !_same(calldata.sublist(0, 4), const [0xa9, 0x05, 0x9c, 0xbb])) {
    throw const FormatException('unsupported TRC-20 call');
  }
  final recipient = Uint8List.fromList([0x41, ...calldata.sublist(16, 36)]);
  return ParsedUnsignedTransfer(
    chain: Chain.tron,
    operation: TxOperation.tokenTransfer,
    from: from,
    to: _tronAddress(recipient),
    amountRaw: _bigInt(calldata.sublist(36, 68)),
    tokenContract: _tronAddress(value.bytes(2)),
    maxFeeRaw: feeLimit == null ? null : BigInt.from(feeLimit),
  );
}

ParsedUnsignedTransfer _parseSolana(Uint8List raw) {
  if (raw.length < 69 || raw[0] != 1 || raw[1] != 0) {
    throw const FormatException('unsupported Solana message header');
  }
  var cursor = 3;
  final keyCount = _shortVec(raw, cursor);
  cursor = keyCount.next;
  if (keyCount.value < 3 || cursor + keyCount.value * 32 + 32 > raw.length) {
    throw const FormatException('invalid Solana account table');
  }
  final keys = <Uint8List>[];
  for (var i = 0; i < keyCount.value; i++) {
    keys.add(Uint8List.sublistView(raw, cursor, cursor + 32));
    cursor += 32;
  }
  cursor += 32; // recent blockhash
  final instructionCount = _shortVec(raw, cursor);
  cursor = instructionCount.next;
  if (instructionCount.value < 1 ||
      instructionCount.value > 2 ||
      cursor >= raw.length) {
    throw const FormatException('unsupported Solana instruction count');
  }
  final instructions =
      <({String program, List<int> accounts, Uint8List data})>[];
  for (var i = 0; i < instructionCount.value; i++) {
    final programIndex = raw[cursor++];
    final accountCount = _shortVec(raw, cursor);
    cursor = accountCount.next;
    if (cursor + accountCount.value > raw.length ||
        programIndex >= keys.length) {
      throw const FormatException('invalid Solana accounts');
    }
    final accounts = raw.sublist(cursor, cursor + accountCount.value);
    if (accounts.any((index) => index >= keys.length)) {
      throw const FormatException('Solana account index out of range');
    }
    cursor += accountCount.value;
    final dataLength = _shortVec(raw, cursor);
    cursor = dataLength.next;
    if (cursor + dataLength.value > raw.length) {
      throw const FormatException('invalid Solana instruction');
    }
    final data = Uint8List.sublistView(raw, cursor, cursor + dataLength.value);
    cursor += dataLength.value;
    instructions.add((
      program: base58Encode(keys[programIndex]),
      accounts: accounts,
      data: data,
    ));
  }
  if (cursor != raw.length) {
    throw const FormatException('trailing Solana instruction bytes');
  }
  final transfer = instructions.last;
  final program = transfer.program;
  final accounts = transfer.accounts;
  final data = transfer.data;
  final from = base58Encode(keys.first);
  if (program == '11111111111111111111111111111111') {
    if (accounts.length != 2 ||
        accounts.first != 0 ||
        data.length != 12 ||
        _u32le(data, 0) != 2) {
      throw const FormatException('unsupported System Program instruction');
    }
    return ParsedUnsignedTransfer(
      chain: Chain.solana,
      operation: TxOperation.nativeTransfer,
      from: from,
      to: base58Encode(keys[accounts[1]]),
      amountRaw: _u64le(data, 4),
    );
  }
  if (instructions.length == 2) {
    final create = instructions.first;
    if (create.program != solanaAssociatedTokenProgram ||
        create.accounts.length != 6 ||
        create.data.length != 1 ||
        create.data.first != 1) {
      throw const FormatException('unsupported ATA create instruction');
    }
  }
  if ((program != solanaTokenProgram && program != solanaToken2022Program) ||
      accounts.length != 4 ||
      accounts.last != 0 ||
      data.length != 10 ||
      data.first != 12) {
    throw const FormatException('unsupported SPL Token instruction');
  }
  var recipient = base58Encode(keys[accounts[2]]);
  if (instructions.length == 2) {
    final create = instructions.first;
    final mint = base58Encode(keys[accounts[1]]);
    final recipientOwner = base58Encode(keys[create.accounts[2]]);
    final destination = base58Encode(keys[accounts[2]]);
    if (create.accounts[0] != 0 ||
        create.accounts[1] != accounts[2] ||
        create.accounts[3] != accounts[1] ||
        base58Encode(keys[create.accounts[4]]) != solanaSystemProgram ||
        base58Encode(keys[create.accounts[5]]) != program ||
        SolanaMessage.associatedTokenAddress(
              owner: recipientOwner,
              mint: mint,
              tokenProgram: program,
            ) !=
            destination) {
      throw const FormatException(
        'ATA create does not match the token transfer',
      );
    }
    recipient = recipientOwner;
  }
  return ParsedUnsignedTransfer(
    chain: Chain.solana,
    operation: TxOperation.tokenTransfer,
    from: from,
    to: recipient,
    amountRaw: _u64le(data, 1),
    tokenContract: base58Encode(keys[accounts[1]]),
  );
}

class _Rlp {
  const _Rlp(this.payload, this.isList, this.next);
  final Uint8List payload;
  final bool isList;
  final int next;
}

List<_Rlp> _decodeRlpList(Uint8List input, int offset) {
  final outer = _readRlp(input, offset);
  if (!outer.isList || outer.next != input.length) {
    throw const FormatException('invalid RLP envelope');
  }
  final fields = <_Rlp>[];
  var cursor = 0;
  while (cursor < outer.payload.length) {
    final field = _readRlp(outer.payload, cursor);
    fields.add(field);
    cursor = field.next;
  }
  return fields;
}

_Rlp _readRlp(Uint8List input, int offset) {
  if (offset >= input.length) throw const FormatException('RLP bounds');
  final prefix = input[offset];
  if (prefix <= 0x7f) {
    return _Rlp(Uint8List.fromList([prefix]), false, offset + 1);
  }
  final isList = prefix >= 0xc0;
  final shortBase = isList ? 0xc0 : 0x80;
  final longBase = isList ? 0xf7 : 0xb7;
  var header = 1;
  int length;
  if (prefix <= longBase) {
    length = prefix - shortBase;
  } else {
    final count = prefix - longBase;
    if (count < 1 || count > 4 || offset + 1 + count > input.length) {
      throw const FormatException('RLP length');
    }
    header += count;
    length = 0;
    for (var i = 0; i < count; i++) {
      length = (length << 8) | input[offset + 1 + i];
    }
  }
  final start = offset + header;
  final end = start + length;
  if (end > input.length) throw const FormatException('RLP bounds');
  return _Rlp(Uint8List.sublistView(input, start, end), isList, end);
}

class _Proto {
  _Proto(this.fields);
  final Map<int, List<Object>> fields;

  int integer(int field) {
    final value = integerOrNull(field);
    if (value == null) throw FormatException('missing protobuf field $field');
    return value;
  }

  int? integerOrNull(int field) {
    final values = fields[field];
    if (values == null || values.length != 1 || values.single is! int) {
      return null;
    }
    return values.single as int;
  }

  Uint8List bytes(int field) {
    final values = fields[field];
    if (values == null || values.length != 1 || values.single is! Uint8List) {
      throw FormatException('missing protobuf bytes $field');
    }
    return values.single as Uint8List;
  }
}

_Proto _proto(Uint8List input) {
  final fields = <int, List<Object>>{};
  var cursor = 0;
  while (cursor < input.length) {
    final tag = _varint(input, cursor);
    cursor = tag.next;
    final number = tag.value >> 3;
    final wire = tag.value & 7;
    if (number == 0) throw const FormatException('invalid protobuf field');
    Object value;
    if (wire == 0) {
      final decoded = _varint(input, cursor);
      cursor = decoded.next;
      value = decoded.value;
    } else if (wire == 2) {
      final length = _varint(input, cursor);
      cursor = length.next;
      final end = cursor + length.value;
      if (end > input.length) throw const FormatException('protobuf bounds');
      value = Uint8List.sublistView(input, cursor, end);
      cursor = end;
    } else {
      throw FormatException('unsupported protobuf wire type $wire');
    }
    fields.putIfAbsent(number, () => []).add(value);
  }
  return _Proto(fields);
}

({int value, int next}) _varint(Uint8List input, int offset) {
  var value = 0;
  var shift = 0;
  var cursor = offset;
  while (cursor < input.length && shift < 64) {
    final byte = input[cursor++];
    value |= (byte & 0x7f) << shift;
    if (byte & 0x80 == 0) {
      if (cursor - offset > 1 && byte == 0) {
        throw const FormatException('non-canonical varint');
      }
      return (value: value, next: cursor);
    }
    shift += 7;
  }
  throw const FormatException('invalid varint');
}

({int value, int next}) _shortVec(Uint8List input, int offset) {
  var value = 0;
  var shift = 0;
  var cursor = offset;
  while (cursor < input.length && shift <= 14) {
    final byte = input[cursor++];
    value |= (byte & 0x7f) << shift;
    if (byte & 0x80 == 0) {
      final count = cursor - offset;
      if ((count > 1 && byte == 0) || (count == 3 && byte > 3)) {
        throw const FormatException('non-canonical shortvec');
      }
      return (value: value, next: cursor);
    }
    shift += 7;
  }
  throw const FormatException('invalid shortvec');
}

String _tronAddress(Uint8List payload) {
  if (payload.length != 21 || payload.first != 0x41) {
    throw const FormatException('invalid TRON address bytes');
  }
  final checksum = sha256(sha256(payload)).sublist(0, 4);
  return base58Encode(Uint8List.fromList([...payload, ...checksum]));
}

BigInt _bigInt(List<int> bytes) {
  var value = BigInt.zero;
  for (final byte in bytes) {
    value = (value << 8) | BigInt.from(byte);
  }
  return value;
}

int _u32le(List<int> bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);

BigInt _u64le(List<int> bytes, int offset) {
  var value = BigInt.zero;
  for (var i = 7; i >= 0; i--) {
    value = (value << 8) | BigInt.from(bytes[offset + i]);
  }
  return value;
}

bool _same(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _hex(List<int> bytes) =>
    bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();

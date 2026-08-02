import 'dart:typed_data';

import 'address.dart';
import 'evm_abi.dart';
import 'keccak.dart';
import 'rlp.dart';
import 'tx_preview.dart';

/// EIP-1559 (type 0x02) transaction in its unsigned form — the exact bytes
/// the offline signer hashes and signs, so the air-gap payload carries a
/// genuine sign-ready transaction instead of a summary (detailed-design.md
/// §4.2). The access list is always empty: V1 only builds plain native,
/// ERC-20 transfers, and the exact zero-allowance approval revocation call.
class Eip1559Tx {
  Eip1559Tx({
    required this.chainId,
    required this.nonce,
    required this.maxPriorityFeePerGas,
    required this.maxFeePerGas,
    required this.gasLimit,
    required Uint8List? to,
    required this.value,
    required Uint8List data,
  }) : to = to == null ? null : Uint8List.fromList(to),
       data = Uint8List.fromList(data) {
    if (chainId <= BigInt.zero) {
      throw ArgumentError('chainId must be positive: $chainId');
    }
    if (nonce < BigInt.zero || gasLimit < BigInt.zero || value < BigInt.zero) {
      throw ArgumentError('nonce, gasLimit and value must be non-negative');
    }
    if (maxPriorityFeePerGas < BigInt.zero || maxFeePerGas < BigInt.zero) {
      throw ArgumentError('fees must be non-negative');
    }
    if (maxPriorityFeePerGas > maxFeePerGas) {
      throw ArgumentError('maxPriorityFeePerGas exceeds maxFeePerGas');
    }
    // Every scalar in a typed Ethereum transaction is a uint256. RLP itself
    // can encode arbitrarily large integers, so relying on the serializer
    // would let a malicious/broken RPC value reach the signing boundary and
    // produce bytes that no conforming EVM node can accept. Fail before a
    // digest is created, just as the ERC-20 ABI encoder already does.
    final uint256Limit = BigInt.one << 256;
    for (final (name, value) in <(String, BigInt)>[
      ('chainId', chainId),
      ('nonce', nonce),
      ('maxPriorityFeePerGas', maxPriorityFeePerGas),
      ('maxFeePerGas', maxFeePerGas),
      ('gasLimit', gasLimit),
      ('value', value),
    ]) {
      if (value >= uint256Limit) {
        throw ArgumentError('$name exceeds uint256: $value');
      }
    }
    if (to != null && to.length != 20) {
      throw ArgumentError('to must be a 20-byte address, got ${to.length}');
    }
  }

  /// Builds the unsigned transaction for a [TransferIntent]: a native
  /// transfer sends [TransferIntent.amount] straight to the recipient with
  /// empty calldata; a token transfer calls `transfer(address,uint256)` on
  /// the contract with zero native value.
  factory Eip1559Tx.forTransfer(
    TransferIntent intent, {
    required BigInt chainId,
    required BigInt nonce,
    required BigInt maxPriorityFeePerGas,
    required BigInt maxFeePerGas,
    required BigInt gasLimit,
  }) {
    if (intent.chain != Chain.ethereum &&
        intent.chain != Chain.polygon &&
        intent.chain != Chain.base &&
        intent.chain != Chain.arbitrum &&
        intent.chain != Chain.avalanche &&
        intent.chain != Chain.bnb) {
      throw ArgumentError('not an EVM chain: ${intent.chain}');
    }
    return switch (intent.operation) {
      TxOperation.nativeTransfer => Eip1559Tx(
        chainId: chainId,
        nonce: nonce,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
        maxFeePerGas: maxFeePerGas,
        gasLimit: gasLimit,
        to: addressBytes(intent.to),
        value: intent.amount.raw,
        data: Uint8List(0),
      ),
      TxOperation.tokenTransfer => Eip1559Tx(
        chainId: chainId,
        nonce: nonce,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
        maxFeePerGas: maxFeePerGas,
        gasLimit: gasLimit,
        to: addressBytes(intent.tokenContract!),
        value: BigInt.zero,
        data: Erc20.transferCalldata(to: intent.to, amount: intent.amount.raw),
      ),
      TxOperation.approvalRevoke => Eip1559Tx(
        chainId: chainId,
        nonce: nonce,
        maxPriorityFeePerGas: maxPriorityFeePerGas,
        maxFeePerGas: maxFeePerGas,
        gasLimit: gasLimit,
        to: addressBytes(intent.tokenContract!),
        value: BigInt.zero,
        data: Erc20.revokeApprovalCalldata(spender: intent.to),
      ),
    };
  }

  /// Transaction envelope type per EIP-2718 (0x02 = EIP-1559).
  static const int txType = 0x02;

  final BigInt chainId;
  final BigInt nonce;
  final BigInt maxPriorityFeePerGas;
  final BigInt maxFeePerGas;
  final BigInt gasLimit;

  /// Recipient (or contract) address bytes; null = contract creation, which
  /// RLP-encodes as the empty byte string.
  final Uint8List? to;

  final BigInt value;
  final Uint8List data;

  /// Decodes a 0x-prefixed EVM address into its 20 bytes, running it through
  /// [Addresses.validate] first so an EIP-55 checksum mismatch or a
  /// wrong-network paste can never reach the wire.
  static Uint8List addressBytes(String address) {
    final v = Addresses.validate(Chain.ethereum, address);
    if (!v.isValid) {
      throw ArgumentError('invalid EVM address: ${v.reason}');
    }
    final hexPart = v.normalized!.substring(2).toLowerCase();
    return Uint8List.fromList([
      for (var i = 0; i < hexPart.length; i += 2)
        int.parse(hexPart.substring(i, i + 2), radix: 16),
    ]);
  }

  /// Unsigned serialization per EIP-1559: `0x02 || rlp([chainId, nonce,
  /// maxPriorityFeePerGas, maxFeePerGas, gasLimit, to, value, data,
  /// accessList])` with the access list fixed empty.
  Uint8List encodeUnsigned() {
    final payload = Rlp.encodeList([
      Rlp.encodeBigInt(chainId),
      Rlp.encodeBigInt(nonce),
      Rlp.encodeBigInt(maxPriorityFeePerGas),
      Rlp.encodeBigInt(maxFeePerGas),
      Rlp.encodeBigInt(gasLimit),
      Rlp.encodeBytes(to ?? Uint8List(0)),
      Rlp.encodeBigInt(value),
      Rlp.encodeBytes(data),
      Rlp.encodeList(const []), // access list, always empty in V1
    ]);
    final out = BytesBuilder();
    out.addByte(txType);
    out.add(payload);
    return out.toBytes();
  }

  /// The digest the signer's secp256k1 key actually signs:
  /// `keccak256(encodeUnsigned())`.
  Uint8List signingHash() => keccak256(encodeUnsigned());
}

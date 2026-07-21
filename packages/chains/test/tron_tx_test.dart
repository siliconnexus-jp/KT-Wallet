import 'dart:typed_data';

import 'package:test/test.dart';

// Imported directly (not via the chains.dart barrel): the barrel export is
// added by the integrating change once this module lands.
import 'package:chains/src/address.dart';
import 'package:chains/src/amount.dart';
import 'package:chains/src/base58.dart';
import 'package:chains/src/sha256.dart';
import 'package:chains/src/tron_tx.dart';
import 'package:chains/src/tx_preview.dart';

String _hex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List _bytes(String hex) => Uint8List.fromList([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]);

// ---------------------------------------------------------------------------
// Golden vectors from TRON mainnet.
//
// Both fetched 2026-07-21 via `POST https://api.trongrid.io/wallet/getnowblock`
// (block 84648450); `raw_data_hex` and `txID` copied verbatim from the node
// response, and sha256(raw_data_hex) == txID re-verified at fetch time.
// ---------------------------------------------------------------------------

/// Vector 1 — plain TRX TransferContract.
/// txID d8ef268b60fbd166db4875bba7ac7d20d44cbd6ab5c9df6a6ff878c36d240d2d
/// owner TVDfpbwC71AbdQoETsFw9LQVeKnTeFLqrv
///   (raw 41d32699f138cdbfbf3bc8cb9c2b68e3e745784b04)
/// to    TMMyc5xhhKVxmJnjrLZEP72X8vrKztuc9Z
///   (raw 417cf7c4ac8e51a8de4cf220c17afc045ce64d72ac)
/// amount 9 SUN, ref_block_bytes a1ee, ref_block_hash f63fb81f0c1ef524,
/// expiration 1784615802000, timestamp 1784615744990, no fee_limit.
const _transferTxId =
    'd8ef268b60fbd166db4875bba7ac7d20d44cbd6ab5c9df6a6ff878c36d240d2d';
const _transferRawDataHex =
    '0a02a1ee2208f63fb81f0c1ef5244090a9909bf8335a65080112610a2d747970652e676f'
    '6f676c65617069732e636f6d2f70726f746f636f6c2e5472616e73666572436f6e747261'
    '637412300a1541d32699f138cdbfbf3bc8cb9c2b68e3e745784b041215417cf7c4ac8e51'
    'a8de4cf220c17afc045ce64d72ac180970deeb8c9bf833';

/// Vector 2 — USDT TriggerSmartContract (TRC-20 transfer of 1000 USDT).
/// txID b4856499cb5406a35be86e5fc49a5e6907daacce7ddd5050322d5b1b29e2b3a4
/// owner TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G
///   (raw 4189cbcb2372e1c2fbc00f24895a406a0c722c89f3)
/// contract TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t (USDT,
///   raw 41a614f803b6fd780986a42c78ec9c7f77e6ded13c)
/// data = a9059cbb + recipient word + amount word (note: this sender's
/// wallet keeps the 0x41 prefix inside the 32-byte address word — 11 zero
/// bytes + 21 bytes — one of the two paddings seen on mainnet).
/// ref block a1ee / f63fb81f0c1ef524, expiration 1784615804989,
/// timestamp 1784615688000, fee_limit 30000000.
const _triggerTxId =
    'b4856499cb5406a35be86e5fc49a5e6907daacce7ddd5050322d5b1b29e2b3a4';
const _triggerData =
    'a9059cbb00000000000000000000004110276c5f76961b98e81de1374ea03ef469cdf4bc'
    '000000000000000000000000000000000000000000000000000000003b9aca00';
const _triggerRawDataHex =
    '0a02a1ee2208f63fb81f0c1ef52440bdc0909bf8335aae01081f12a9010a31747970652e'
    '676f6f676c65617069732e636f6d2f70726f746f636f6c2e54726967676572536d617274'
    '436f6e747261637412740a154189cbcb2372e1c2fbc00f24895a406a0c722c89f3121541'
    'a614f803b6fd780986a42c78ec9c7f77e6ded13c2244$_triggerData'
    '70c0ae899bf83390018087a70e';

void main() {
  group('ProtoWriter varints and tags', () {
    test('varint encodes single-byte values', () {
      expect(ProtoWriter.varint(0), [0x00]);
      expect(ProtoWriter.varint(1), [0x01]);
      expect(ProtoWriter.varint(127), [0x7f]);
    });

    test('varint encodes multi-byte values LSB-group-first', () {
      expect(ProtoWriter.varint(128), [0x80, 0x01]);
      expect(ProtoWriter.varint(300), [0xac, 0x02]);
      // fee_limit 30000000 as it appears in the mainnet trigger vector.
      expect(_hex(ProtoWriter.varint(30000000)), '8087a70e');
      // A real epoch-ms expiration (vector 1).
      expect(_hex(ProtoWriter.varint(1784615802000)), '90a9909bf833');
    });

    test('varint rejects negative values', () {
      expect(() => ProtoWriter.varint(-1), throwsArgumentError);
    });

    test('tags match the raw_data field layout', () {
      expect(ProtoWriter.tag(1, 2), 0x0a); // ref_block_bytes
      expect(ProtoWriter.tag(4, 2), 0x22); // ref_block_hash
      expect(ProtoWriter.tag(8, 0), 0x40); // expiration
      expect(ProtoWriter.tag(11, 2), 0x5a); // contract
      expect(ProtoWriter.tag(14, 0), 0x70); // timestamp
      // fee_limit = 18: tag value 144 spills into a 2-byte varint.
      expect(ProtoWriter.varint(ProtoWriter.tag(18, 0)), [0x90, 0x01]);
    });

    test('length-delimited fields prefix the byte length', () {
      final w = ProtoWriter()..writeBytes(1, _bytes('a1ee'));
      expect(_hex(w.toBytes()), '0a02a1ee');
    });
  });

  group('mainnet golden vectors', () {
    test('TransferContract re-encodes byte-identical and reproduces txID', () {
      final tx = TronRawTx(
        refBlockBytes: _bytes('a1ee'),
        refBlockHash: _bytes('f63fb81f0c1ef524'),
        expiration: 1784615802000,
        timestamp: 1784615744990,
        contract: TransferContract(
          ownerAddress: _bytes('41d32699f138cdbfbf3bc8cb9c2b68e3e745784b04'),
          toAddress: _bytes('417cf7c4ac8e51a8de4cf220c17afc045ce64d72ac'),
          amount: BigInt.from(9),
        ),
      );
      expect(_hex(tx.encodeRawData()), _transferRawDataHex);
      expect(tx.txId(), _transferTxId);
      expect(_hex(tx.signingHash()), _transferTxId);
    });

    test('TriggerSmartContract re-encodes byte-identical and reproduces txID',
        () {
      final tx = TronRawTx(
        refBlockBytes: _bytes('a1ee'),
        refBlockHash: _bytes('f63fb81f0c1ef524'),
        expiration: 1784615804989,
        timestamp: 1784615688000,
        feeLimit: 30000000,
        contract: TriggerSmartContract(
          ownerAddress: _bytes('4189cbcb2372e1c2fbc00f24895a406a0c722c89f3'),
          contractAddress:
              _bytes('41a614f803b6fd780986a42c78ec9c7f77e6ded13c'),
          data: _bytes(_triggerData),
        ),
      );
      expect(_hex(tx.encodeRawData()), _triggerRawDataHex);
      expect(tx.txId(), _triggerTxId);
    });

    test('forTransfer rebuilds vector 1 from base58 addresses', () {
      final tx = TronRawTx.forTransfer(
        TransferIntent(
          chain: Chain.tron,
          operation: TxOperation.nativeTransfer,
          from: 'TVDfpbwC71AbdQoETsFw9LQVeKnTeFLqrv',
          to: 'TMMyc5xhhKVxmJnjrLZEP72X8vrKztuc9Z',
          amount: Amount(raw: BigInt.from(9), decimals: 6, symbol: 'TRX'),
        ),
        refBlockBytes: _bytes('a1ee'),
        refBlockHash: _bytes('f63fb81f0c1ef524'),
        expiration: 1784615802000,
        timestamp: 1784615744990,
      );
      expect(tx.txId(), _transferTxId);
    });
  });

  group('TRC-20 calldata', () {
    test('transferCalldata is selector + padded address + uint256 amount', () {
      // TBSd3Ju3T5URPH3q5C2HqhPG5qewNDuCtR =
      // raw 4110276c5f76961b98e81de1374ea03ef469cdf4bc (vector 2 recipient).
      final data = Trc20.transferCalldata(
        to: 'TBSd3Ju3T5URPH3q5C2HqhPG5qewNDuCtR',
        amount: BigInt.from(1000000000),
      );
      expect(data.length, 68);
      expect(
        _hex(data),
        'a9059cbb'
        // TronWeb padding: 12 zero bytes + 20-byte body (0x41 stripped) —
        // NOT the keep-the-41 variant vector 2's sender used; both decode
        // to the same recipient (address = low 20 bytes of the word).
        '00000000000000000000000010276c5f76961b98e81de1374ea03ef469cdf4bc'
        '000000000000000000000000000000000000000000000000000000003b9aca00',
      );
    });

    test('rejects negative and oversized amounts', () {
      expect(
        () => Trc20.transferCalldata(
          to: 'TBSd3Ju3T5URPH3q5C2HqhPG5qewNDuCtR',
          amount: BigInt.from(-1),
        ),
        throwsArgumentError,
      );
      expect(
        () => Trc20.transferCalldata(
          to: 'TBSd3Ju3T5URPH3q5C2HqhPG5qewNDuCtR',
          amount: BigInt.one << 256,
        ),
        throwsArgumentError,
      );
    });

    test('forTransfer builds a TRC-20 raw_data with our calldata convention',
        () {
      final tx = TronRawTx.forTransfer(
        TransferIntent(
          chain: Chain.tron,
          operation: TxOperation.tokenTransfer,
          from: 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G',
          to: 'TBSd3Ju3T5URPH3q5C2HqhPG5qewNDuCtR',
          amount: Amount(raw: BigInt.from(1000000000), decimals: 6),
          tokenContract: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
          tokenSymbol: 'USDT',
        ),
        refBlockBytes: _bytes('a1ee'),
        refBlockHash: _bytes('f63fb81f0c1ef524'),
        expiration: 1784615804989,
        timestamp: 1784615688000,
        feeLimit: 30000000,
      );
      final contract = tx.contract as TriggerSmartContract;
      expect(_hex(contract.contractAddress),
          '41a614f803b6fd780986a42c78ec9c7f77e6ded13c');
      expect(_hex(contract.data.sublist(0, 4)), 'a9059cbb');
      // Everything outside the address word matches the mainnet vector.
      expect(tx.encodeRawData().length, _bytes(_triggerRawDataHex).length);
    });

    test('forTransfer requires a feeLimit for token transfers', () {
      expect(
        () => TronRawTx.forTransfer(
          TransferIntent(
            chain: Chain.tron,
            operation: TxOperation.tokenTransfer,
            from: 'TNXoiAJ3dct8Fjg4M9fkLFh9S2v9TXc32G',
            to: 'TBSd3Ju3T5URPH3q5C2HqhPG5qewNDuCtR',
            amount: Amount(raw: BigInt.one, decimals: 6),
            tokenContract: 'TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t',
          ),
          refBlockBytes: _bytes('a1ee'),
          refBlockHash: _bytes('f63fb81f0c1ef524'),
          expiration: 1,
          timestamp: 0,
        ),
        throwsArgumentError,
      );
    });

    test('forTransfer rejects non-TRON intents', () {
      expect(
        () => TronRawTx.forTransfer(
          TransferIntent(
            chain: Chain.ethereum,
            operation: TxOperation.nativeTransfer,
            from: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
            to: '0x5aAeb6053F3E94C9b9A09f33669435E7Ef1BeAed',
            amount: Amount(raw: BigInt.one, decimals: 18),
          ),
          refBlockBytes: _bytes('a1ee'),
          refBlockHash: _bytes('f63fb81f0c1ef524'),
          expiration: 1,
          timestamp: 0,
        ),
        throwsArgumentError,
      );
    });
  });

  group('address decode', () {
    test('addressBytes decodes base58check to the 21-byte raw form', () {
      final raw =
          TronRawTx.addressBytes('TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6t');
      expect(raw.length, 21);
      expect(raw[0], 0x41);
      expect(_hex(raw), '41a614f803b6fd780986a42c78ec9c7f77e6ded13c');
    });

    test('raw form roundtrips back to the original base58check string', () {
      const address = 'TVDfpbwC71AbdQoETsFw9LQVeKnTeFLqrv';
      final raw = TronRawTx.addressBytes(address);
      // Base58check re-encode: payload + first 4 bytes of double-sha256.
      final checksum = sha256(sha256(raw)).sublist(0, 4);
      final encoded =
          base58Encode(Uint8List.fromList([...raw, ...checksum]));
      expect(encoded, address);
    });

    test('addressBytes rejects a corrupted checksum', () {
      expect(
        () => TronRawTx.addressBytes('TR7NHqjeKQxGTCi8q8ZY4pL8otSzgjLj6u'),
        throwsArgumentError,
      );
    });
  });

  group('TronRawTx validation', () {
    test('rejects wrong-size block refs and bad raw addresses', () {
      final good = TransferContract(
        ownerAddress: _bytes('41d32699f138cdbfbf3bc8cb9c2b68e3e745784b04'),
        toAddress: _bytes('417cf7c4ac8e51a8de4cf220c17afc045ce64d72ac'),
        amount: BigInt.one,
      );
      expect(
        () => TronRawTx(
          refBlockBytes: _bytes('a1'),
          refBlockHash: _bytes('f63fb81f0c1ef524'),
          expiration: 1,
          timestamp: 0,
          contract: good,
        ),
        throwsArgumentError,
      );
      expect(
        () => TronRawTx(
          refBlockBytes: _bytes('a1ee'),
          refBlockHash: _bytes('f63fb81f0c1ef5'),
          expiration: 1,
          timestamp: 0,
          contract: good,
        ),
        throwsArgumentError,
      );
      // 20-byte (EVM-style) address must be refused: TRON wire form is 21.
      expect(
        () => TransferContract(
          ownerAddress: _bytes('d32699f138cdbfbf3bc8cb9c2b68e3e745784b04'),
          toAddress: _bytes('417cf7c4ac8e51a8de4cf220c17afc045ce64d72ac'),
          amount: BigInt.one,
        ),
        throwsArgumentError,
      );
      expect(
        () => TransferContract(
          ownerAddress: _bytes('41d32699f138cdbfbf3bc8cb9c2b68e3e745784b04'),
          toAddress: _bytes('417cf7c4ac8e51a8de4cf220c17afc045ce64d72ac'),
          amount: BigInt.from(-1),
        ),
        throwsArgumentError,
      );
    });
  });
}

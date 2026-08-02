import Foundation

private func hex(_ data: Data) -> String {
  data.map { String(format: "%02x", $0) }.joined()
}

private let entropy = Data((0x00...0x1F).map(UInt8.init))
private let salt = Data((0x00...0x0F).map(UInt8.init))
private let nonce = Data((0x10...0x1B).map(UInt8.init))
private let password = "Correct horse 電池🔐"
private let expected =
  "000102030405060708090a0b0c0d0e0f" +
  "101112131415161718191a1b" +
  "364a29004ca61dca69b29ce63afbfa7315822fc380f858634e289bbb5b33dd43" +
  "bf50be31944b5e4d9f6bbd81f23c53bc"

do {
  let sealed = try PortableBackupCipher.seal(
    entropy: entropy,
    password: password,
    salt: salt,
    nonce: nonce
  )
  guard hex(sealed) == expected else {
    fatalError("portable backup vector mismatch")
  }
  guard try PortableBackupCipher.open(sealed: sealed, password: password) == entropy else {
    fatalError("portable backup round trip mismatch")
  }

  var tampered = sealed
  tampered[tampered.index(before: tampered.endIndex)] ^= 0x01
  do {
    _ = try PortableBackupCipher.open(sealed: tampered, password: password)
    fatalError("tampered portable backup was accepted")
  } catch PortableBackupCipher.CipherError.openFailed {
    // Expected authentication failure.
  }

  do {
    _ = try PortableBackupCipher.open(sealed: sealed, password: "wrong password")
    fatalError("wrong portable backup password was accepted")
  } catch PortableBackupCipher.CipherError.openFailed {
    // Expected authentication failure.
  }

  print("portable backup Swift vector: OK")
} catch {
  fatalError("portable backup Swift vector failed")
}

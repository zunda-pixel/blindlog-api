import Crypto
import Foundation

@inline(__always)
private func cryptoRandomBytes(_ count: Int) -> [UInt8] {
  precondition(count > 0)
  var out: [UInt8] = []
  out.reserveCapacity(count)

  while out.count < count {
    let key = SymmetricKey(size: .bits256)
    key.withUnsafeBytes { rawBuf in
      let buf = rawBuf.bindMemory(to: UInt8.self)
      let needed = min(buf.count, count - out.count)
      out.append(contentsOf: buf.prefix(needed))
    }
  }
  return out
}

/// ASCIIのみのアルファベットから安全にOTPを生成
struct OTPGenerator {
  var alphabet: [UInt8] = Array(
    "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)

  func generate(length: Int) -> String {
    precondition(length > 0, "length must be > 0")
    let n = alphabet.count
    let threshold = (256 / n) * n

    var out = [UInt8]()
    out.reserveCapacity(length)

    var pool = cryptoRandomBytes(max(length * 2, 32))
    var i = 0

    while out.count < length {
      if i >= pool.count {
        pool = cryptoRandomBytes(max(length, 32))
        i = 0
      }
      let b = pool[i]
      i += 1
      if b < threshold {
        out.append(alphabet[Int(b) % n])
      }
    }
    return String(decoding: out, as: UTF8.self)
  }
}

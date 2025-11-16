import Crypto
import Foundation
import WebAuthn

/// ASCIIのみのアルファベットから安全にOTPを生成
struct OTPGenerator {
  var alphabet: [UInt8] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ".utf8)

  func generate(length: Int) -> String {
    precondition(length > 0, "length must be > 0")
    let n = alphabet.count
    let threshold = (256 / n) * n

    var out = [UInt8]()
    out.reserveCapacity(length)

    var pool = [UInt8].random(count: max(length * 2, 32))
    var i = 0

    while out.count < length {
      if i >= pool.count {
        pool = [UInt8].random(count: max(length, 32))
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

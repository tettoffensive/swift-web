import CommonCrypto
import Cryptor
import Foundation

extension ResponseHeader {
  /// Computes a signed cookie.
  ///
  /// - Parameters:
  ///   - key: The name of the cookie.
  ///   - value: The data of the cookie to sign.
  ///   - options: (Optional) Extra options to attach to the cookie.
  ///   - secret: The secret to sign the cookie with. This value must also be provided to verify a signature.
  ///   - encrypt: (Optional) Further encrypts the signed cookie using the secret provided.
  /// - Returns: A `Set-Cookie` header containing the signed cookie.
  public static func setSignedCookie(
    key: String,
    data: Data,
    options: Set<CookieOption> = [],
    secret: String,
    encrypt: Bool = false
    )
    -> ResponseHeader? {

      let encodedValue = data.base64EncodedString()
      guard let computedDigest = digest(value: encodedValue, secret: secret) else { return nil }

      let signedValue = "\(encodedValue)--\(computedDigest)"
      guard let finalValue = encrypt ? encrypted(text: signedValue, secret: secret) : signedValue
        else { return nil }

      return .some(.setCookie(key: key, value: finalValue, options: options.union([.httpOnly])))
  }

  /// A helper for creating a signed cookie of a string value.
  /// Calls `setSignedCookie(key:data:options:secret)`.
  public static func setSignedCookie(
    key: String,
    value: String,
    options: Set<CookieOption> = [],
    secret: String,
    encrypt: Bool = false
    )
    -> ResponseHeader? {

      return setSignedCookie(
        key: key, data: Data(value.utf8), options: options, secret: secret, encrypt: encrypt
      )
  }

  /// A helper for creating a signed cookie of an encodable value.
  /// Calls `setSignedCookie(key:data:options:secret)`.
  public static func setSignedCookie<A: Encodable>(
    key: String,
    value: A,
    options: Set<CookieOption> = [],
    secret: String,
    encrypt: Bool = false
    )
    -> ResponseHeader? {

      return (try? JSONEncoder().encode(value))
        .flatMap { setSignedCookie(key: key, data: $0, options: options, secret: secret, encrypt: encrypt) }
  }

  /// Verifies signed cookie data using the secret that it was signed with.
  ///
  /// - Parameters:
  ///   - signedCookieValue: The cookie value that was stored in the signed cookie. It should be of the form
  ///                        "\(data)--\(digest)".
  ///   - secret: The secret used to sign the cookie.
  /// - Returns: The data of the cookie value if the verification was successful, and `nil` otherwise.
  public static func verifiedData(signedCookieValue: String, secret: String) -> Data? {
    // We can determine if we need to decrypt by checking if the cookie contains the `--` delimeter.
    let decrypt = !signedCookieValue.contains("--")

    guard let cookieValue = decrypt ? decrypted(text: signedCookieValue, secret: secret) : signedCookieValue
      else { return nil }

    let parts = cookieValue.components(separatedBy: "--")
    guard let encodedValue = parts.first,
      let providedDigest = parts.last,
      parts.count == 2
      else {
        return nil
    }

    let trueDigest = digest(value: encodedValue, secret: secret)

    guard trueDigest == providedDigest else { return nil }
    guard let value = base64DecodedData(string: encodedValue) else { return nil }

    return .some(value)
  }

  /// Helper function that calls `verifiedData` and then tries converting the data to a string.
  public static func verifiedString(signedCookieValue: String, secret: String)
    -> String? {
      return verifiedData(signedCookieValue: signedCookieValue, secret: secret)
        .flatMap { String(data: $0, encoding: .utf8) }
  }

  /// Helper function that calls `verifiedData` and then tries to decode the data into an `A`.
  public static func verifiedValue<A: Decodable>(signedCookieValue: String, secret: String) -> A? {
      return verifiedData(signedCookieValue: signedCookieValue, secret: secret)
        .flatMap { try? JSONDecoder().decode(A.self, from: $0) }
  }
}

private func digest(value: String, secret: String) -> String? {
  let keyBytes = CryptoUtils.byteArray(fromHex: secret)
  let valueBytes = CryptoUtils.byteArray(from: value)
  let digestBytes = HMAC(using: .sha256, key: keyBytes).update(byteArray: valueBytes)?.final()
  return digestBytes.map { Data(bytes: $0).base64EncodedString() }
}

private func base64DecodedData(string: String) -> Data? {
  return Data(base64Encoded: Data(string.utf8))
}

private func encrypted(text plainText: String, secret: String) -> String? {
  let secretBytes = CryptoUtils.byteArray(fromHex: secret)
  let iv = [UInt8](repeating: 0, count: secretBytes.count)
  let plainTextBytes = CryptoUtils.byteArray(from: plainText)

  let blockSize = Cryptor.Algorithm.aes.blockSize
  let paddedPlainTextBytes = plainTextBytes.count % blockSize != 0
    ? CryptoUtils.zeroPad(byteArray: plainTextBytes, blockSize: blockSize)
    : plainTextBytes

  let cipherText = Cryptor(operation: .encrypt, algorithm: .aes, options: .none, key: secretBytes, iv: iv)
    .update(byteArray: paddedPlainTextBytes)?
    .final()

  return cipherText.map { CryptoUtils.hexString(from: $0) }
}

private func decrypted(text encryptedText: String, secret: String) -> String? {
  let secretBytes = CryptoUtils.byteArray(fromHex: secret)
  let iv = [UInt8](repeating: 0, count: secret.count)
  let encryptedTextBytes = CryptoUtils.byteArray(fromHex: encryptedText)

  let decryptedText = Cryptor(operation: .decrypt, algorithm: .aes, options: .none, key: secretBytes, iv: iv)
    .update(byteArray: encryptedTextBytes)?
    .final()

  return decryptedText
    .map { Data($0.filter { $0 != 0 }) }
    .flatMap { String.init(data: $0, encoding: .utf8) }
}

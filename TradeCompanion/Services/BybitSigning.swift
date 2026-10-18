import CryptoKit
import Foundation

nonisolated enum BybitSigning {
    static let recvWindowMilliseconds = "5000"

    static func payloadString(timestamp: String, apiKey: String, recvWindow: String, body: String) -> String {
        timestamp + apiKey + recvWindow + body
    }

    static func hmacSignature(secret: String, payload: String) -> String {
        let key = SymmetricKey(data: Data(secret.utf8))
        let mac = HMAC<SHA256>.authenticationCode(for: Data(payload.utf8), using: key)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}

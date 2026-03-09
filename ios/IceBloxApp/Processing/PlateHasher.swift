import CryptoKit
import Foundation

enum PlateHasher {
    private static var pepperKey: SymmetricKey = {
        SymmetricKey(data: Data(Pepper.value.utf8))
    }()

    static func hash(normalizedPlate: String) -> String {
        let data = Data(normalizedPlate.utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: pepperKey)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}

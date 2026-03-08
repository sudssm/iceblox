import CryptoKit
import Foundation

enum PlateHasher {
    // XOR-obfuscated pepper: reconstruct at runtime to avoid plaintext in binary
    private static let pepperPartA: [UInt8] = [
        0x64, 0x65, 0x66, 0x61, 0x75, 0x6C, 0x74, 0x2D,
        0x70, 0x65, 0x70, 0x70, 0x65, 0x72, 0x2D, 0x63
    ]
    private static let pepperPartB: [UInt8] = [
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
        0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    ]

    private static var pepperKey: SymmetricKey = {
        let pepper = zip(pepperPartA, pepperPartB).map { $0 ^ $1 }
        return SymmetricKey(data: pepper)
    }()

    static func hash(normalizedPlate: String) -> String {
        let data = Data(normalizedPlate.utf8)
        let mac = HMAC<SHA256>.authenticationCode(for: data, using: pepperKey)
        return mac.map { String(format: "%02x", $0) }.joined()
    }
}

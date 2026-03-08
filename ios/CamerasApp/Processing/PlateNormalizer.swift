import Foundation

enum PlateNormalizer {
    static func normalize(_ raw: String) -> String? {
        let cleaned = raw
            .uppercased()
            .replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
            .replacingOccurrences(of: "-", with: "")
            .filter { $0.isLetter || $0.isNumber }

        let length = cleaned.count
        guard length >= AppConfig.minPlateLength, length <= AppConfig.maxPlateLength else {
            return nil
        }
        return String(cleaned.prefix(AppConfig.maxPlateLength))
    }
}

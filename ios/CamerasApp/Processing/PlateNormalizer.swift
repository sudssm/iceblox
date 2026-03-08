import Foundation

enum PlateNormalizer {
    static func normalize(_ raw: String) -> String? {
        let cleaned = raw
            .uppercased()
            .replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
            .replacingOccurrences(of: "-", with: "")
            .filter { $0.isLetter || $0.isNumber }

        let trimmed = String(cleaned.prefix(AppConfig.maxPlateLength))
        guard trimmed.count >= AppConfig.minPlateLength else {
            return nil
        }
        return trimmed
    }
}

enum PlateNormalizer {
    static func normalize(_ text: String) -> String? {
        let normalized = text
            .uppercased()
            .replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
            .replacingOccurrences(of: "-", with: "")
            .filter { $0.isASCII && ($0.isLetter || $0.isNumber) }

        let trimmed = String(normalized.prefix(8))

        guard trimmed.count >= 2 && trimmed.count <= 8 else {
            return nil
        }

        return trimmed
    }
}

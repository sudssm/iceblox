import Foundation

final class DeduplicationCache {
    private var seenTexts = Set<String>()
    private var seenHashes = Set<String>()
    private let lock = NSLock()

    func isDuplicate(_ normalizedPlate: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        if seenTexts.contains(normalizedPlate) {
            return true
        }
        seenTexts.insert(normalizedPlate)
        return false
    }

    func areAllHashesSeen(_ hashes: [String]) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        return hashes.allSatisfy { seenHashes.contains($0) }
    }

    func addHashes(_ hashes: [String]) {
        lock.lock()
        defer { lock.unlock() }

        for hash in hashes {
            seenHashes.insert(hash)
        }
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        seenTexts.removeAll()
        seenHashes.removeAll()
    }
}

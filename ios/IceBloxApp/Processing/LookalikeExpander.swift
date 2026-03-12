import Foundation

enum LookalikeExpander {

    static func expand(
        _ text: String,
        charConfidences: [Float],
        slotCandidates: [[PlateOCR.SlotCandidate]] = [],
        maxVariants: Int = AppConfig.maxLookalikeVariants
    ) -> [(String, Int, Float)] { // swiftlint:disable:this large_tuple
        let slots = buildSlotLists(text: text, charConfidences: charConfidences, slotCandidates: slotCandidates)

        var totalCombinations: Int64 = 1
        for slot in slots {
            totalCombinations *= Int64(slot.count)
            if totalCombinations > Int64(maxVariants) { break }
        }

        if totalCombinations <= Int64(maxVariants) {
            return cartesianExpand(slots: slots, primaryText: text)
        } else {
            return priorityQueueExpand(slots: slots, primaryText: text, maxVariants: maxVariants)
        }
    }

    private static func buildSlotLists(
        text: String,
        charConfidences: [Float],
        slotCandidates: [[PlateOCR.SlotCandidate]]
    ) -> [[PlateOCR.SlotCandidate]] {
        let chars = Array(text)
        var result = [[PlateOCR.SlotCandidate]]()
        for i in chars.indices {
            if i < slotCandidates.count && slotCandidates[i].count > 1 {
                result.append(slotCandidates[i])
            } else {
                let conf: Float = i < charConfidences.count ? charConfidences[i] : 0
                result.append([PlateOCR.SlotCandidate(char: chars[i], probability: conf)])
            }
        }
        return result
    }

    private static func computeConfidence(slots: [[PlateOCR.SlotCandidate]], indices: [Int]) -> Float {
        let count = slots.count
        guard count > 0 else { return 0 }
        var logSum: Float = 0
        for i in 0..<count {
            logSum += log(max(slots[i][indices[i]].probability, 1e-6))
        }
        return exp(logSum / Float(count))
    }

    private static func cartesianExpand(
        slots: [[PlateOCR.SlotCandidate]],
        primaryText: String
    ) -> [(String, Int, Float)] {
        var results = [(String, Int, Float)]()
        let n = slots.count
        var indices = [Int](repeating: 0, count: n)

        while true {
            var chars = [Character]()
            chars.reserveCapacity(n)
            var subs = 0
            for i in 0..<n {
                chars.append(slots[i][indices[i]].char)
                if indices[i] != 0 { subs += 1 }
            }
            let conf = computeConfidence(slots: slots, indices: indices)
            results.append((String(chars), subs, conf))

            var pos = n - 1
            while pos >= 0 {
                indices[pos] += 1
                if indices[pos] < slots[pos].count { break }
                indices[pos] = 0
                pos -= 1
            }
            if pos < 0 { break }
        }

        results.sort { $0.2 > $1.2 }
        if let primaryIdx = results.firstIndex(where: { $0.0 == primaryText }), primaryIdx > 0 {
            let primary = results.remove(at: primaryIdx)
            results.insert(primary, at: 0)
        }
        return results
    }

    private static func priorityQueueExpand(
        slots: [[PlateOCR.SlotCandidate]],
        primaryText: String,
        maxVariants: Int
    ) -> [(String, Int, Float)] {
        let n = slots.count
        var results = [(String, Int, Float)]()
        var seen = Set<[Int]>()

        struct Entry: Comparable {
            let indices: [Int]
            let lastModified: Int
            let confidence: Float

            static func < (lhs: Entry, rhs: Entry) -> Bool {
                lhs.confidence > rhs.confidence
            }
        }

        var heap = [Entry]()

        func heapPush(_ entry: Entry) {
            heap.append(entry)
            var i = heap.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                if heap[i] < heap[parent] {
                    heap.swapAt(i, parent)
                    i = parent
                } else { break }
            }
        }

        func heapPop() -> Entry {
            let top = heap[0]
            let last = heap.removeLast()
            if !heap.isEmpty {
                heap[0] = last
                var i = 0
                while true {
                    let left = 2 * i + 1
                    let right = 2 * i + 2
                    var smallest = i
                    if left < heap.count && heap[left] < heap[smallest] { smallest = left }
                    if right < heap.count && heap[right] < heap[smallest] { smallest = right }
                    if smallest == i { break }
                    heap.swapAt(i, smallest)
                    i = smallest
                }
            }
            return top
        }

        let seedIndices = [Int](repeating: 0, count: n)
        let seedConf = computeConfidence(slots: slots, indices: seedIndices)
        heapPush(Entry(indices: seedIndices, lastModified: 0, confidence: seedConf))
        seen.insert(seedIndices)

        while !heap.isEmpty && results.count < maxVariants {
            let entry = heapPop()
            var chars = [Character]()
            chars.reserveCapacity(n)
            var subs = 0
            for i in 0..<n {
                chars.append(slots[i][entry.indices[i]].char)
                if entry.indices[i] != 0 { subs += 1 }
            }
            results.append((String(chars), subs, entry.confidence))

            for pos in entry.lastModified..<n {
                let nextIdx = entry.indices[pos] + 1
                if nextIdx < slots[pos].count {
                    var childIndices = entry.indices
                    childIndices[pos] = nextIdx
                    if seen.insert(childIndices).inserted {
                        let conf = computeConfidence(slots: slots, indices: childIndices)
                        heapPush(Entry(indices: childIndices, lastModified: pos, confidence: conf))
                    }
                }
            }
        }

        return results
    }
}

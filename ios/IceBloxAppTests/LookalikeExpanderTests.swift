import XCTest
@testable import IceBloxApp

final class LookalikeExpanderTests: XCTestCase {

    private func candidates(_ slots: [[( Character, Float)]]) -> [[PlateOCR.SlotCandidate]] {
        slots.map { slot in slot.map { PlateOCR.SlotCandidate(char: $0.0, probability: $0.1) } }
    }

    func testSingleCandidatePerSlot() {
        let cands = candidates([
            [("A", 0.9)],
            [("B", 0.8)],
            [("C", 0.7)]
        ])
        let result = LookalikeExpander.expand("ABC", charConfidences: [0.9, 0.8, 0.7], slotCandidates: cands)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].0, "ABC")
        XCTAssertEqual(result[0].1, 0)
    }

    func testTwoCandidateSlot() {
        let cands = candidates([
            [("A", 0.8), ("4", 0.1)],
            [("B", 0.95)]
        ])
        let result = LookalikeExpander.expand("AB", charConfidences: [0.8, 0.95], slotCandidates: cands)
        XCTAssertEqual(result.count, 2)
        let texts = Set(result.map { $0.0 })
        XCTAssertEqual(texts, Set(["AB", "4B"]))
    }

    func testMultiSlotCartesian() {
        let cands = candidates([
            [("S", 0.7), ("5", 0.2)],
            [("O", 0.6), ("0", 0.3)]
        ])
        let result = LookalikeExpander.expand("SO", charConfidences: [0.7, 0.6], slotCandidates: cands)
        XCTAssertEqual(result.count, 4)
        let texts = Set(result.map { $0.0 })
        XCTAssertEqual(texts, Set(["SO", "S0", "5O", "50"]))
    }

    func testPrimaryAlwaysFirst() {
        let cands = candidates([
            [("X", 0.5), ("Y", 0.9)],
            [("Z", 0.5)]
        ])
        let result = LookalikeExpander.expand("XZ", charConfidences: [0.5, 0.5], slotCandidates: cands)
        XCTAssertEqual(result[0].0, "XZ")
        XCTAssertEqual(result[0].1, 0)
    }

    func testConfidenceOrdering() {
        let cands = candidates([
            [("A", 0.9), ("B", 0.05)],
            [("C", 0.9), ("D", 0.05)]
        ])
        let result = LookalikeExpander.expand("AC", charConfidences: [0.9, 0.9], slotCandidates: cands)
        XCTAssertEqual(result[0].0, "AC")
        for i in 1..<(result.count - 1) {
            XCTAssertGreaterThanOrEqual(result[i].2, result[i + 1].2)
        }
    }

    func testCapEnforcement() {
        let cands = candidates([
            [("A", 0.5), ("B", 0.1), ("C", 0.1)],
            [("D", 0.5), ("E", 0.1), ("F", 0.1)],
            [("G", 0.5), ("H", 0.1), ("I", 0.1)]
        ])
        let result = LookalikeExpander.expand("ADG", charConfidences: [0.5, 0.5, 0.5], slotCandidates: cands, maxVariants: 10)
        XCTAssertEqual(result.count, 10)
    }

    func testSubstitutionCount() {
        let cands = candidates([
            [("A", 0.8), ("B", 0.1)],
            [("C", 0.9)],
            [("D", 0.7), ("E", 0.2)]
        ])
        let result = LookalikeExpander.expand("ACD", charConfidences: [0.8, 0.9, 0.7], slotCandidates: cands)
        let lookup = Dictionary(uniqueKeysWithValues: result.map { ($0.0, $0.1) })
        XCTAssertEqual(lookup["ACD"], 0)
        XCTAssertEqual(lookup["BCD"], 1)
        XCTAssertEqual(lookup["ACE"], 1)
        XCTAssertEqual(lookup["BCE"], 2)
    }

    func testGeometricMeanCorrectness() {
        let p0: Float = 0.8
        let p1: Float = 0.6
        let cands = candidates([
            [("A", p0)],
            [("B", p1)]
        ])
        let result = LookalikeExpander.expand("AB", charConfidences: [p0, p1], slotCandidates: cands)
        let expected = exp((log(p0) + log(p1)) / 2)
        XCTAssertEqual(result[0].2, expected, accuracy: 1e-5)
    }

    func testEmptyCandidatesFallback() {
        let result = LookalikeExpander.expand("ABC", charConfidences: [0.9, 0.8, 0.7])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].0, "ABC")
    }

    func testNoDuplicates() {
        let cands = candidates([
            [("O", 0.5), ("0", 0.3)],
            [("O", 0.5), ("0", 0.3)]
        ])
        let result = LookalikeExpander.expand("OO", charConfidences: [0.5, 0.5], slotCandidates: cands, maxVariants: 200)
        let texts = result.map { $0.0 }
        XCTAssertEqual(texts.count, Set(texts).count)
    }

    func testPriorityQueuePath() {
        let slot: [(Character, Float)] = [("A", 0.7), ("B", 0.1), ("C", 0.1)]
        let cands = candidates(Array(repeating: slot, count: 5))
        let result = LookalikeExpander.expand(
            "AAAAA",
            charConfidences: [0.7, 0.7, 0.7, 0.7, 0.7],
            slotCandidates: cands,
            maxVariants: 20
        )
        XCTAssertEqual(result.count, 20)
        XCTAssertEqual(result[0].0, "AAAAA")
        for i in 1..<(result.count - 1) {
            XCTAssertGreaterThanOrEqual(result[i].2, result[i + 1].2)
        }
        let texts = result.map { $0.0 }
        XCTAssertEqual(texts.count, Set(texts).count)
    }
}

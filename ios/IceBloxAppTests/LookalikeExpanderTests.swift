import XCTest
@testable import IceBloxApp

final class LookalikeExpanderTests: XCTestCase {
    func testNoConfusableCharacters() {
        let result = LookalikeExpander.expand("XYW", maxVariants: 64)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].0, "XYW")
        XCTAssertEqual(result[0].1, 0)
    }

    func testOriginalAlwaysFirst() {
        let result = LookalikeExpander.expand("ABC1234", maxVariants: 64)
        XCTAssertEqual(result[0].0, "ABC1234")
        XCTAssertEqual(result[0].1, 0)
    }

    func testSinglePositionExpansion() {
        let result = LookalikeExpander.expand("S", maxVariants: 64)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].0, "S")
        XCTAssertEqual(result[0].1, 0)
        XCTAssertEqual(result[1].0, "5")
        XCTAssertEqual(result[1].1, 1)
    }

    func testMergedGroupG1() {
        let result = LookalikeExpander.expand("0", maxVariants: 64)
        let texts = Set(result.map { $0.0 })
        XCTAssertEqual(texts, Set(["0", "O", "D", "Q", "8", "B"]))
        for entry in result {
            if entry.0 == "0" { XCTAssertEqual(entry.1, 0) } else { XCTAssertEqual(entry.1, 1) }
        }
    }

    func testMultiPositionExpansion() {
        let result = LookalikeExpander.expand("5S", maxVariants: 64)
        let texts = Set(result.map { $0.0 })
        XCTAssertEqual(texts, Set(["5S", "SS", "55", "S5"]))
        let lookup = Dictionary(uniqueKeysWithValues: result.map { ($0.0, $0.1) })
        XCTAssertEqual(lookup["5S"], 0)
        XCTAssertEqual(lookup["SS"], 1)
        XCTAssertEqual(lookup["55"], 1)
        XCTAssertEqual(lookup["S5"], 2)
    }

    func testCapEnforcement() {
        let result = LookalikeExpander.expand("0O8BDQ", maxVariants: 10)
        XCTAssertEqual(result.count, 10)
    }

    func testBFSOrdering() {
        let result = LookalikeExpander.expand("0O", maxVariants: 64)
        var lastSub = 0
        for entry in result {
            XCTAssertGreaterThanOrEqual(entry.1, lastSub)
            lastSub = entry.1
        }
    }

    func testNoDuplicates() {
        let result = LookalikeExpander.expand("00", maxVariants: 200)
        let texts = result.map { $0.0 }
        XCTAssertEqual(texts.count, Set(texts).count)
    }

    func testAllGroupsCovered() {
        let result = LookalikeExpander.expand("0IS2A", maxVariants: 500)
        let texts = Set(result.map { $0.0 })
        XCTAssertTrue(texts.contains("OIL2A"))
        XCTAssertTrue(texts.contains("0IS24"))
        XCTAssertTrue(texts.contains("0ISZA"))
    }
}

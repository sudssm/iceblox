import XCTest
@testable import IceBloxApp

final class ZoomControllerTests: XCTestCase {

    // MARK: - UT-1: Zoom eligibility calculation

    func testCenterPlateEligibleAt3x() {
        let box = CGRect(x: 400, y: 400, width: 200, height: 200)
        XCTAssertTrue(
            ZoomController.isPlateEligible(
                boundingBox: box,
                imageWidth: 1000,
                imageHeight: 1000,
                maxOpticalZoom: 3.0,
                margin: 0.8
            )
        )
    }

    func testTopLeftCornerNotEligibleAt3x() {
        let box = CGRect(x: 0, y: 0, width: 200, height: 200)
        XCTAssertFalse(
            ZoomController.isPlateEligible(
                boundingBox: box,
                imageWidth: 1000,
                imageHeight: 1000,
                maxOpticalZoom: 3.0,
                margin: 0.8
            )
        )
    }

    func testLargeCenteredPlateEligibleAt2x() {
        let box = CGRect(x: 300, y: 300, width: 400, height: 400)
        XCTAssertTrue(
            ZoomController.isPlateEligible(
                boundingBox: box,
                imageWidth: 1000,
                imageHeight: 1000,
                maxOpticalZoom: 2.0,
                margin: 0.8
            )
        )
    }

    func testRightSidePlateNotEligibleAt3x() {
        let box = CGRect(x: 700, y: 400, width: 200, height: 200)
        XCTAssertFalse(
            ZoomController.isPlateEligible(
                boundingBox: box,
                imageWidth: 1000,
                imageHeight: 1000,
                maxOpticalZoom: 3.0,
                margin: 0.8
            )
        )
    }

    func testEdgeCaseJustFitsAt2x() {
        let box = CGRect(x: 350, y: 350, width: 300, height: 300)
        XCTAssertTrue(
            ZoomController.isPlateEligible(
                boundingBox: box,
                imageWidth: 1000,
                imageHeight: 1000,
                maxOpticalZoom: 2.0,
                margin: 0.8
            )
        )
    }

    func testNotEligibleWhenZoomIs1x() {
        let box = CGRect(x: 400, y: 400, width: 200, height: 200)
        XCTAssertFalse(
            ZoomController.isPlateEligible(
                boundingBox: box,
                imageWidth: 1000,
                imageHeight: 1000,
                maxOpticalZoom: 1.0,
                margin: 0.8
            )
        )
    }

    func testNotEligibleWithZeroImageDimensions() {
        let box = CGRect(x: 0, y: 0, width: 10, height: 10)
        XCTAssertFalse(
            ZoomController.isPlateEligible(
                boundingBox: box,
                imageWidth: 0,
                imageHeight: 0,
                maxOpticalZoom: 3.0,
                margin: 0.8
            )
        )
    }

    func testMarginOf1MeansFullTheoreticalArea() {
        // With margin=1.0, the limit is 0.5 * (1/3) * 1.0 ≈ 0.1667
        // A box from (0.34, 0.34) to (0.66, 0.66) has corners at most 0.16 from center — eligible
        let box = CGRect(x: 340, y: 340, width: 320, height: 320)
        XCTAssertTrue(
            ZoomController.isPlateEligible(
                boundingBox: box,
                imageWidth: 1000,
                imageHeight: 1000,
                maxOpticalZoom: 3.0,
                margin: 1.0
            )
        )
    }

    func testHigherZoomShrinksCenterRegion() {
        // At 5x zoom, limit = 0.5 * (1/5) * 0.8 = 0.08
        // Box from (0.425, 0.425) to (0.575, 0.575) — corners 0.075 from center — inside limit
        let box = CGRect(x: 425, y: 425, width: 150, height: 150)
        XCTAssertTrue(
            ZoomController.isPlateEligible(
                boundingBox: box,
                imageWidth: 1000,
                imageHeight: 1000,
                maxOpticalZoom: 5.0,
                margin: 0.8
            )
        )

        // 0.1 from center — clearly outside
        let boxTooLarge = CGRect(x: 400, y: 400, width: 200, height: 200)
        XCTAssertFalse(
            ZoomController.isPlateEligible(
                boundingBox: boxTooLarge,
                imageWidth: 1000,
                imageHeight: 1000,
                maxOpticalZoom: 5.0,
                margin: 0.8
            )
        )
    }

    // MARK: - UT-4: Best candidate selection

    func testBestCandidateSelectsClosestToCenter() {
        let controller = makeFakeController(maxOpticalZoom: 3.0)

        let detections: [(boundingBox: CGRect, imageWidth: Int, imageHeight: Int)] = [
            (CGRect(x: 450, y: 450, width: 100, height: 100), 1000, 1000), // center
            (CGRect(x: 350, y: 450, width: 100, height: 100), 1000, 1000), // slightly left
            (CGRect(x: 420, y: 420, width: 100, height: 100), 1000, 1000), // near center but offset
        ]

        let idx = controller.bestCandidateIndex(detections: detections)
        XCTAssertEqual(idx, 0)
    }

    func testBestCandidateReturnsNilWhenNoneEligible() {
        let controller = makeFakeController(maxOpticalZoom: 3.0)

        let detections: [(boundingBox: CGRect, imageWidth: Int, imageHeight: Int)] = [
            (CGRect(x: 0, y: 0, width: 100, height: 100), 1000, 1000),
            (CGRect(x: 800, y: 800, width: 100, height: 100), 1000, 1000),
        ]

        let idx = controller.bestCandidateIndex(detections: detections)
        XCTAssertNil(idx)
    }

    func testBestCandidateSkipsIneligiblePlates() {
        let controller = makeFakeController(maxOpticalZoom: 3.0)

        let detections: [(boundingBox: CGRect, imageWidth: Int, imageHeight: Int)] = [
            (CGRect(x: 0, y: 0, width: 100, height: 100), 1000, 1000),     // corner — ineligible
            (CGRect(x: 440, y: 440, width: 120, height: 120), 1000, 1000),  // center — eligible
            (CGRect(x: 900, y: 900, width: 100, height: 100), 1000, 1000),  // corner — ineligible
        ]

        let idx = controller.bestCandidateIndex(detections: detections)
        XCTAssertEqual(idx, 1)
    }

    // MARK: - Helpers

    /// Creates a ZoomController-like object for testing bestCandidateIndex.
    /// Since ZoomController requires an AVCaptureDevice, we test the static method directly
    /// and use a wrapper for bestCandidateIndex logic.
    private func makeFakeController(maxOpticalZoom: CGFloat) -> FakeZoomController {
        FakeZoomController(maxOpticalZoom: maxOpticalZoom, margin: AppConfig.zoomRetryMargin)
    }
}

/// Minimal stand-in that replicates bestCandidateIndex logic without needing a real AVCaptureDevice.
private struct FakeZoomController {
    let maxOpticalZoom: CGFloat
    let margin: Double

    func bestCandidateIndex(detections: [(boundingBox: CGRect, imageWidth: Int, imageHeight: Int)]) -> Int? {
        var bestIdx: Int?
        var bestDist = Double.greatestFiniteMagnitude

        for (i, det) in detections.enumerated() {
            guard ZoomController.isPlateEligible(
                boundingBox: det.boundingBox,
                imageWidth: det.imageWidth,
                imageHeight: det.imageHeight,
                maxOpticalZoom: maxOpticalZoom,
                margin: margin
            ) else { continue }

            let w = CGFloat(det.imageWidth)
            let h = CGFloat(det.imageHeight)
            let cx = (det.boundingBox.midX / w) - 0.5
            let cy = (det.boundingBox.midY / h) - 0.5
            let dist = sqrt(cx * cx + cy * cy)
            if dist < bestDist {
                bestDist = dist
                bestIdx = i
            }
        }
        return bestIdx
    }
}

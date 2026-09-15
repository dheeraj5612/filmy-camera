import Foundation
import XCTest
@testable import FilmyCamera

final class ImageSizePolicyTests: XCTestCase {
    func testInvalidDimensionsAreRejectedBeforeIntegerConversion() {
        for invalid in [CGFloat.zero, -1, .nan, .infinity, -.infinity] {
            XCTAssertNil(bounded(CGSize(width: invalid, height: 300)))
            XCTAssertNil(bounded(CGSize(width: 300, height: invalid)))
        }
    }

    func testNormalSizesAreNotUpscaledOrChanged() {
        for size in [CGSize(width: 264, height: 160), CGSize(width: 600, height: 400), CGSize(width: 1, height: 1)] {
            XCTAssertEqual(bounded(size), size)
        }
    }

    func testLargeDisplayCanScaleBelowOnePointPerPixel() throws {
        let original = CGSize(width: 7_680, height: 4_320)
        let output = try XCTUnwrap(bounded(original, scale: 3))
        XCTAssertLessThan(output.width, original.width)
        assertBudget(output)
        XCTAssertEqual(output.width / output.height, original.width / original.height, accuracy: 0.003)
    }

    func testRetinaUsesAvailableBudgetWithoutExceedingScreenScale() throws {
        let original = CGSize(width: 390, height: 844)
        let output = try XCTUnwrap(bounded(original, scale: 3))
        XCTAssertGreaterThan(output.width, original.width)
        XCTAssertLessThanOrEqual(output.width, original.width * 3)
        assertBudget(output)
    }

    func testFiniteDimensionsWhoseAreaOverflowsAreStillBounded() throws {
        let output = try XCTUnwrap(bounded(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)))
        assertBudget(output)
    }

    func testThinPanoramaIsLimitedByLongestEdge() throws {
        let output = try XCTUnwrap(bounded(CGSize(width: 100_000, height: 10)))
        XCTAssertEqual(output.width, 4_096)
        XCTAssertEqual(output.height, 1)
        assertBudget(output)
    }

    func testInvalidBudgetsFailClosed() {
        for invalid in [CGFloat.zero, -1, .nan, .infinity] {
            XCTAssertNil(ImageSizePolicy.boundedSize(CGSize(width: 100, height: 100), maximumPixels: invalid, maximumDimension: 1_024))
            XCTAssertNil(ImageSizePolicy.boundedSize(CGSize(width: 100, height: 100), maximumPixels: 1_000, maximumDimension: invalid))
            XCTAssertNil(bounded(CGSize(width: 100, height: 100), scale: invalid))
        }
    }

    func testExactPhotoBudgetDoesNotLoseAPixel() {
        let size = CGSize(width: 8_000, height: 5_000)
        XCTAssertEqual(ImageSizePolicy.boundedSize(size, maximumPixels: 40_000_000, maximumDimension: 16_384), size)
    }

    func testDimensionMatrixAlwaysHonorsBothBudgets() {
        let dimensions: [CGFloat] = [1, 2, 17, 390, 844, 1_024, 4_096, 10_000, 1_000_000, 1e100, .greatestFiniteMagnitude]
        for width in dimensions {
            for height in dimensions {
                for scale in [CGFloat(1), 2, 3] {
                    if let output = bounded(CGSize(width: width, height: height), scale: scale) { assertBudget(output) }
                }
            }
        }
    }

    func testMissingFileErrorsAreDifferentFromLockedOrUnreadableFiles() {
        XCTAssertTrue(CacheMaintenancePolicy.confirmsMissingFile(NSError(domain: NSCocoaErrorDomain, code: NSFileNoSuchFileError)))
        XCTAssertTrue(CacheMaintenancePolicy.confirmsMissingFile(NSError(domain: NSCocoaErrorDomain, code: NSFileReadNoSuchFileError)))
        XCTAssertTrue(CacheMaintenancePolicy.confirmsMissingFile(NSError(domain: NSPOSIXErrorDomain, code: 2)))
        for code in [NSFileReadNoPermissionError, NSFileReadUnknownError, NSFileReadCorruptFileError] {
            XCTAssertFalse(CacheMaintenancePolicy.confirmsMissingFile(NSError(domain: NSCocoaErrorDomain, code: code)))
        }
        XCTAssertFalse(CacheMaintenancePolicy.confirmsMissingFile(NSError(domain: NSPOSIXErrorDomain, code: 13)))
    }

    func testStaleEvictionCannotRemoveReplacementResource() {
        XCTAssertTrue(CacheMaintenancePolicy.canRemove(currentFilename: "old.jpg", inspectedFilename: "old.jpg"))
        XCTAssertFalse(CacheMaintenancePolicy.canRemove(currentFilename: "new.jpg", inspectedFilename: "old.jpg"))
        XCTAssertFalse(CacheMaintenancePolicy.canRemove(currentFilename: nil, inspectedFilename: "old.jpg"))
        XCTAssertFalse(CacheMaintenancePolicy.canRemove(currentFilename: "new.jpg", inspectedFilename: nil))
        XCTAssertFalse(CacheMaintenancePolicy.canRemove(currentFilename: nil, inspectedFilename: nil))
    }

    private func bounded(_ size: CGSize, scale: CGFloat = 1) -> CGSize? {
        ImageSizePolicy.boundedSize(size, maximumPixels: 1_300_000, maximumDimension: 4_096, maximumScale: scale)
    }

    private func assertBudget(_ size: CGSize, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(size.width.isFinite && size.height.isFinite, file: file, line: line)
        XCTAssertGreaterThanOrEqual(size.width, 1, file: file, line: line)
        XCTAssertGreaterThanOrEqual(size.height, 1, file: file, line: line)
        XCTAssertLessThanOrEqual(max(size.width, size.height), 4_096, file: file, line: line)
        XCTAssertLessThanOrEqual(size.width * size.height, 1_300_000, file: file, line: line)
    }
}

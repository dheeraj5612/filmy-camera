import Foundation
import Photos
import UIKit
import XCTest
@testable import FilmyCamera

/// Run only on a disposable simulator with Photos already fully authorized:
/// FILMY_RUN_LARGE_ROLL_QA=1. Creates 160 owned frames and one unrecorded
/// sentinel, then deletes only those test-created assets in async teardown.
final class PhotoLibraryLargeRollTests: XCTestCase {
    @MainActor
    func testActualPhotoKitRollIncludesAll160OwnedFramesAcrossServiceReload() async throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Large Roll fixtures must never run on a physical photo library")
        #endif
        try XCTSkipUnless(ProcessInfo.processInfo.environment["FILMY_RUN_LARGE_ROLL_QA"] == "1",
                          "Set FILMY_RUN_LARGE_ROLL_QA=1 only on a disposable simulator")
        // XCTest can reinstall this disposable host after simctl pre-grants
        // access. Let the external fixture harness grant once after bootstrap;
        // no Photos assets or ownership state may change before authorization.
        if PHPhotoLibrary.authorizationStatus(for: .readWrite) != .authorized {
            print("LARGE_ROLL_WAIT_FOR_PHOTOS_AUTH")
            let deadline = Date(timeIntervalSinceNow: 20)
            while PHPhotoLibrary.authorizationStatus(for: .readWrite) != .authorized,
                  Date() < deadline {
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        try XCTSkipUnless(PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized,
                          "Grant full Photos access before running; this test never requests access")
        try XCTSkipUnless(!ProcessInfo.processInfo.arguments.contains("-ui-testing"),
                          "The real PhotoKit service path requires a normal hosted unit-test launch")
        try requireEmptyAppCache()
        continueAfterFailure = true

        let savedDefaults = try DefaultsSnapshot()
        let fixtureIdentifiers = FixtureIdentifiers()
        // Register before the first mutation so partial PhotoKit failures also
        // clean up. Never derive deletion candidates from the ownership index.
        addTeardownBlock {
            do {
                try await Self.deleteCreatedAssets(fixtureIdentifiers.values)
            } catch {
                XCTFail("Could not clean test-created Photos fixtures: \(error)")
            }
            try await MainActor.run {
                try savedDefaults.restore()
                XCTAssertEqual(try DefaultsSnapshot(), savedDefaults,
                               "Ownership, metadata, and resource preferences must be restored")
            }
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let jpeg = try XCTUnwrap(UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format)
            .image { context in
                UIColor.orange.setFill()
                context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
            }.jpegData(compressionQuality: 0.7))
        try await Self.createFixtures(jpeg: jpeg, identifiers: fixtureIdentifiers)
        let created = fixtureIdentifiers.values
        XCTAssertEqual(created.count, 161)
        guard created.count == 161 else { throw FixtureError.missingIdentifiers }
        let owned = Array(created.prefix(160))
        let sentinelIdentifier = created[160]
        let sentinel = try XCTUnwrap(PHAsset.fetchAssets(
            withLocalIdentifiers: [sentinelIdentifier], options: nil).firstObject)

        // Intentionally persist oldest first: service presentation must sort by
        // capture date independently of the recording order in UserDefaults.
        PhotoLibraryAssetOwnership.persist(owned)
        UserDefaults.standard.removeObject(forKey: "filmyCamera.savedFrameMetadata")
        UserDefaults.standard.removeObject(forKey: "filmyCamera.savedFrameResources")
        let service = PhotoLibraryService()
        service.refresh()
        let expectedNewestFirst = Array(owned.reversed())
        XCTAssertEqual(service.assets.count, 160, "The PhotoKit fetch must pass the former 60-frame limit")
        XCTAssertEqual(Set(service.assets.map(\.localIdentifier)), Set(owned))
        XCTAssertEqual(service.galleryAssets.map(\.assetIdentifier), expectedNewestFirst)
        XCTAssertEqual(service.galleryAssets.last?.assetIdentifier, owned.first,
                       "The oldest owned frame must remain reachable beyond the former 120-ID limit")
        XCTAssertTrue(service.galleryAssets.allSatisfy { service.canDelete(asset: $0) })
        XCTAssertFalse(service.canDelete(asset: .photos(sentinel)),
                       "An accessible but unrecorded photo must never become app-owned")

        let reloaded = PhotoLibraryService()
        reloaded.refresh()
        let actualOrder = reloaded.galleryAssets.map(\.assetIdentifier)
        XCTAssertEqual(reloaded.assets.count, 160)
        XCTAssertEqual(actualOrder, expectedNewestFirst)
        XCTAssertEqual(PhotoLibraryAssetOwnership.load(), owned,
                       "Service reconstruction must preserve every recorded identifier")
        XCTAssertFalse(actualOrder.contains(sentinelIdentifier))
        XCTAssertFalse(reloaded.canDelete(asset: .photos(sentinel)))

        var visited: [String] = []
        var current = actualOrder.first
        while let identifier = current, visited.count <= 160 {
            visited.append(identifier)
            current = GalleryPagingPolicy.targetIdentifier(
                in: actualOrder, selectedIdentifier: identifier, direction: .next)
        }
        XCTAssertEqual(visited, expectedNewestFirst, "Paging must traverse every actual fetched frame exactly once")
        XCTAssertNil(current, "Paging must stop after the oldest frame")
        let attachment = XCTAttachment(string:
            "Created: 161; recorded: 160; fetched: \(service.assets.count); reconstructed: \(reloaded.assets.count); traversed: \(visited.count); unrecorded sentinel excluded: \(!actualOrder.contains(sentinelIdentifier))")
        attachment.name = "actual-photokit-large-roll-counts"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Service initialization can prune obsolete cache files. Refuse to swap
    /// indices in an installation with pre-existing frame or share resources.
    @MainActor
    private func requireEmptyAppCache() throws {
        let manager = FileManager.default
        let directories: [(FileManager.SearchPathDirectory, String)] = [
            (.cachesDirectory, "FilmyCameraFrames"),
            (.applicationSupportDirectory, "FilmyCameraFrames"),
            (.cachesDirectory, "FilmyCameraShare")
        ]
        for (base, name) in directories {
            let root = try XCTUnwrap(manager.urls(for: base, in: .userDomainMask).first)
            let directory = root.appendingPathComponent(name, isDirectory: true)
            if manager.fileExists(atPath: directory.path) {
                let contents = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                try XCTSkipUnless(contents.isEmpty, "Use a disposable simulator with no existing app cache files")
            }
        }
    }

    private static func createFixtures(jpeg: Data, identifiers: FixtureIdentifiers) async throws {
        let changes: @Sendable () -> Void = {
            let start = Date(timeIntervalSince1970: 1_780_000_000)
            for index in 0..<161 {
                let request = PHAssetCreationRequest.forAsset()
                request.creationDate = start.addingTimeInterval(TimeInterval(index * 60))
                request.addResource(with: .photo, data: jpeg, options: nil)
                if let identifier = request.placeholderForCreatedAsset?.localIdentifier {
                    identifiers.append(identifier)
                }
            }
        }
        try await performChanges(changes)
    }

    private static func deleteCreatedAssets(_ identifiers: [String]) async throws {
        guard !identifiers.isEmpty else { return }
        let changes: @Sendable () -> Void = {
            let created = PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil)
            if created.count > 0 { PHAssetChangeRequest.deleteAssets(created) }
        }
        try await performChanges(changes)
        XCTAssertEqual(PHAsset.fetchAssets(withLocalIdentifiers: identifiers, options: nil).count, 0,
                       "Every test-created fixture must be removed from the active photo library")
    }

    private static func performChanges(_ changes: @escaping @Sendable () -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { success, error in
                if success { continuation.resume() }
                else { continuation.resume(throwing: error ?? FixtureError.photoKitChangeFailed) }
            }
        }
    }

    private enum FixtureError: Error {
        case missingIdentifiers
        case photoKitChangeFailed
    }

    private final class FixtureIdentifiers: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []

        func append(_ identifier: String) {
            lock.lock()
            defer { lock.unlock() }
            storage.append(identifier)
        }

        var values: [String] {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    private struct DefaultsSnapshot: Sendable, Equatable {
        private static let keys = ["filmyCamera.savedAssetIdentifiers",
                                   "filmyCamera.savedFrameMetadata",
                                   "filmyCamera.savedFrameResources"]
        private let values: [String: Data]

        init() throws {
            var saved: [String: Data] = [:]
            for key in Self.keys {
                if let value = UserDefaults.standard.object(forKey: key) {
                    saved[key] = try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
                }
            }
            values = saved
        }

        func restore() throws {
            for key in Self.keys {
                if let data = values[key] {
                    let value = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
                    UserDefaults.standard.set(value, forKey: key)
                } else {
                    UserDefaults.standard.removeObject(forKey: key)
                }
            }
        }
    }
}

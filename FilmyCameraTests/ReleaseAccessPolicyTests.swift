import XCTest
@testable import FilmyCamera

@MainActor
final class ReleaseAccessPolicyTests: XCTestCase {
    func testFreeReleaseKeepsFeaturesWithoutInventingSubscription() {
        let store = MembershipStore(persistence: MemoryPhotoQuotaPersistence(),
                                    useStoreKitForTesting: true, monetizationEnabled: false)
        for access in [MembershipStore.Access.checking, .free, .unavailable,
                       .premium(until: .distantPast, trial: true)] {
            store.setAccessForTesting(access)
            XCTAssertTrue(store.hasFullAccess)
            XCTAssertTrue(store.entitlementsResolved)
            XCTAssertFalse(store.isPremium)
            XCTAssertFalse(store.isTrial)
            XCTAssertFalse(store.mayShowAds)
            XCTAssertFalse(store.canPurchase)
            XCTAssertTrue(store.allowsRecipe("velvia-vivid"))
            for feature in PremiumFeature.allCases { XCTAssertTrue(store.require(feature)) }
        }
    }

    func testFreeReleaseCaptureDoesNotConsumeDailyQuota() throws {
        let persistence = MemoryPhotoQuotaPersistence()
        var exhausted = DailyPhotoQuota(now: Date())
        for _ in 0..<MembershipPolicy.dailyPhotoLimit { _ = exhausted.reserve(at: Date()) }
        try persistence.save(exhausted)
        let store = MembershipStore(persistence: persistence, useStoreKitForTesting: true,
                                    monetizationEnabled: false)
        XCTAssertEqual(store.remainingPhotos, MembershipPolicy.dailyPhotoLimit)
        for _ in 0..<20 {
            let permit = try XCTUnwrap(store.reserveCapture())
            XCTAssertNil(permit.chargedDay)
            store.finishCapture(permit, succeeded: true)
        }
        XCTAssertEqual(try persistence.load()?.remaining, 0)
    }

    private final class CountingPersistence: PhotoQuotaPersistence {
        var calls = 0
        func load() throws -> DailyPhotoQuota? { calls += 1; return nil }
        func save(_ quota: DailyPhotoQuota) throws { calls += 1 }
    }

    func testFreeReleaseNeverTouchesQuotaStorage() async throws {
        let persistence = CountingPersistence()
        let store = MembershipStore(persistence: persistence, useStoreKitForTesting: true,
                                    monetizationEnabled: false)
        await store.start()
        await store.refresh()
        for index in 0..<6 {
            let permit = try XCTUnwrap(store.reserveCapture())
            XCTAssertNil(permit.chargedDay)
            store.finishCapture(permit, succeeded: index % 2 == 0)
        }
        XCTAssertNil(store.notice)
        for feature in PremiumFeature.allCases { XCTAssertTrue(store.require(feature)) }
        XCTAssertEqual(persistence.calls, 0)
    }

    func testFreeReleaseDoesNotStartPurchaseOrRestoreWork() async {
        let store = MembershipStore(persistence: MemoryPhotoQuotaPersistence(),
                                    useStoreKitForTesting: true, monetizationEnabled: false)
        await store.start()
        await store.refresh()
        await store.loadProduct()
        await store.purchase()
        await store.restore()
        XCTAssertNil(store.product)
        XCTAssertNil(store.purchaseMessage)
        XCTAssertFalse(store.isWorking)
        XCTAssertFalse(store.isLoadingProduct)
        XCTAssertEqual(store.access, .checking)
        XCTAssertTrue(store.hasFullAccess)
    }

    func testMonetizedReleaseStillRequiresVerifiedAccessAndChargesQuota() throws {
        let store = MembershipStore(persistence: MemoryPhotoQuotaPersistence(),
                                    useStoreKitForTesting: true, monetizationEnabled: true)
        store.setAccessForTesting(.free)
        XCTAssertFalse(store.hasFullAccess)
        XCTAssertFalse(store.allowsRecipe("velvia-vivid"))
        let permit = try XCTUnwrap(store.reserveCapture())
        XCTAssertNotNil(permit.chargedDay)
        XCTAssertEqual(store.remainingPhotos, 9)
        store.setAccessForTesting(.premium(until: Date().addingTimeInterval(3600), trial: false))
        XCTAssertTrue(store.hasFullAccess)
        XCTAssertTrue(store.isPremium)
    }
}

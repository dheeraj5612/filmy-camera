import StoreKit
@preconcurrency import StoreKitTest
import XCTest
@testable import FilmyCamera

/// Real StoreKit test transactions, not a cached premium boolean. This fixture
/// never changes App Store Connect and its $4.99 price is test-only.
@MainActor
final class MembershipStoreKitTests: XCTestCase {
    private func session() throws -> SKTestSession {
        let session = try SKTestSession(configurationFileNamed: "Filmy")
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }

    private func store(persistence: MemoryPhotoQuotaPersistence = MemoryPhotoQuotaPersistence()) async -> MembershipStore {
        let store = MembershipStore(persistence: persistence, useStoreKitForTesting: true)
        await store.start()
        return store
    }

    private func waitForPremium(_ expected: Bool, in store: MembershipStore, logIterations: Bool = false) async throws {
        // StoreKit Test publishes externally initiated purchases, refunds and
        // renewals asynchronously. Keep reconciling Apple's signed state until
        // the requested transition arrives, with a bounded CI-safe timeout.
        let clock = ContinuousClock()
        let start = clock.now
        for i in 0..<100 {
            await store.refresh()
            if logIterations { print("waitForPremium iteration \(i) \(start.duration(to: clock.now))") }
            if store.isPremium == expected { return }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTFail("timed out waiting for premium == \(expected), access \(store.access), after \(start.duration(to: clock.now))")
    }

    func testLocalizedMonthlyProductHasExactlyOneMonthFreeTrial() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = await store()
        await store.refresh()
        await store.loadProduct()
        let product = try XCTUnwrap(store.product)
        XCTAssertEqual(product.subscription?.subscriptionPeriod.unit, .month)
        XCTAssertEqual(product.subscription?.subscriptionPeriod.value, 1)
        XCTAssertEqual(product.subscription?.introductoryOffer?.paymentMode, .freeTrial)
        XCTAssertEqual(product.subscription?.introductoryOffer?.period.unit, .month)
        XCTAssertEqual(product.subscription?.introductoryOffer?.period.value, 1)
        XCTAssertTrue(store.eligibleForOneMonthTrial)
        XCTAssertFalse(product.displayPrice.isEmpty)
    }

    func testPurchaseUnlocksTrialWithoutConsumingAllowance() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = await store()
        await store.refresh()
        await store.loadProduct()
        await store.purchase()
        XCTAssertTrue(store.isPremium, store.purchaseMessage ?? "No active access")
        XCTAssertTrue(store.isTrial)
        XCTAssertFalse(store.mayShowAds)
        let permit = try XCTUnwrap(store.reserveCapture())
        XCTAssertNil(permit.chargedDay)
    }

    func testRestoreFindsPurchaseMadeOutsideTheApp() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        _ = try await session.buyProduct(identifier: MonetizationConfiguration.monthlyProductID)
        let store = await store()
        await store.restore()
        try await waitForPremium(true, in: store)
        XCTAssertTrue(store.isPremium, store.purchaseMessage ?? "Restore did not find purchase")
        // StoreKit Test can publish the purchase after the first restore returns,
        // so the outcome text is pinned on a restore that runs once it is visible.
        await store.restore()
        XCTAssertEqual(store.purchaseMessage, "Your subscription is restored.")
    }

    func testRefundRevokesPremium() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let transaction = try await session.buyProduct(identifier: MonetizationConfiguration.monthlyProductID)
        let store = await store()
        await store.refresh()
        XCTAssertTrue(store.isPremium)
        try session.refundTransaction(identifier: XCTUnwrap(UInt(exactly: transaction.id)))
        try await waitForPremium(false, in: store)
        XCTAssertFalse(store.isPremium)
        XCTAssertFalse(store.allowsRecipe("classic-chrome"))
    }

    func testExpiryReturnsToFreeWithoutDeletingAllowance() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let transaction = try await session.buyProduct(identifier: MonetizationConfiguration.monthlyProductID)
        let persistence = MemoryPhotoQuotaPersistence()
        var seeded = DailyPhotoQuota(now: Date())
        for _ in 0..<3 { _ = seeded.reserve(at: Date()) }
        let seededDay = seeded.day
        persistence.quota = seeded
        let store = await store(persistence: persistence)
        XCTAssertEqual(store.remainingPhotos, 7)
        await store.refresh()
        XCTAssertTrue(store.isPremium)
        try session.disableAutoRenewForTransaction(identifier: XCTUnwrap(UInt(exactly: transaction.id)))
        try session.expireSubscription(productIdentifier: MonetizationConfiguration.monthlyProductID)
        try await waitForPremium(false, in: store, logIterations: true)
        XCTAssertFalse(store.isPremium)
        // The expiry wait has taken about ten minutes on hosted runners; a day rollover in that window refills the allowance.
        if persistence.quota?.day == seededDay { XCTAssertEqual(store.remainingPhotos, 7) }
        else { XCTAssertEqual(store.remainingPhotos, 10) }
    }

    func testTrialConvertsToPaidRenewal() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        _ = try await session.buyProduct(identifier: MonetizationConfiguration.monthlyProductID)
        let store = await store()
        await store.loadProduct()
        await store.refresh()
        XCTAssertTrue(store.isTrial)
        try session.forceRenewalOfSubscription(productIdentifier: MonetizationConfiguration.monthlyProductID)
        // StoreKit Test publishes the renewal asynchronously, and between the
        // trial period ending and the renewal arriving it can report no
        // entitlement at all. Wait for the paid renewal itself: leaving the
        // trial is not enough, because that gap also reads as "not a trial".
        let clock = ContinuousClock()
        let start = clock.now
        var renewed = false
        for _ in 0..<100 {
            await store.refresh()
            if store.isPremium && !store.isTrial { renewed = true; break }
            try await Task.sleep(for: .milliseconds(100))
        }
        if !renewed {
            XCTFail("timed out waiting for the paid renewal, access \(store.access), after \(start.duration(to: clock.now))")
        }
        XCTAssertTrue(store.isPremium)
        XCTAssertFalse(store.isTrial)
        XCTAssertFalse(store.mayShowAds)
    }

    func testFailedPaymentNeverUnlocksPremium() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        try await session.setSimulatedError(.generic(.notAvailableInStorefront), forAPI: .purchase)
        let store = await store()
        await store.refresh()
        await store.loadProduct()
        await store.purchase()
        XCTAssertFalse(store.isPremium)
        XCTAssertNotNil(store.purchaseMessage)
    }

    func testPendingApprovalDoesNotGrantTrial() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        session.askToBuyEnabled = true
        let store = await store()
        await store.refresh()
        await store.loadProduct()
        await store.purchase()
        XCTAssertFalse(store.isPremium)
        XCTAssertTrue(store.purchaseMessage?.contains("awaiting approval") == true)
    }
}

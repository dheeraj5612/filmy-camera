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

    private func store() -> MembershipStore {
        MembershipStore(persistence: MemoryPhotoQuotaPersistence(), useStoreKitForTesting: true)
    }

    private func waitForPremium(_ expected: Bool, in store: MembershipStore) async throws {
        // StoreKit Test publishes externally initiated purchases, refunds and
        // renewals asynchronously. Keep reconciling Apple's signed state until
        // the requested transition arrives, with a bounded CI-safe timeout.
        for _ in 0..<100 {
            await store.refresh()
            if store.isPremium == expected { return }
            try await Task.sleep(for: .milliseconds(100))
        }
    }

    func testLocalizedMonthlyProductHasExactlyOneMonthFreeTrial() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let store = store()
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
        let store = store()
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
        let store = store()
        await store.restore()
        try await waitForPremium(true, in: store)
        XCTAssertTrue(store.isPremium, store.purchaseMessage ?? "Restore did not find purchase")
    }

    func testRefundRevokesPremium() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let transaction = try await session.buyProduct(identifier: MonetizationConfiguration.monthlyProductID)
        let store = store()
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
        let store = store()
        await store.refresh()
        XCTAssertTrue(store.isPremium)
        try session.disableAutoRenewForTransaction(identifier: XCTUnwrap(UInt(exactly: transaction.id)))
        try session.expireSubscription(productIdentifier: MonetizationConfiguration.monthlyProductID)
        try await waitForPremium(false, in: store)
        XCTAssertFalse(store.isPremium)
        XCTAssertEqual(store.remainingPhotos, 10)
    }

    func testTrialConvertsToPaidRenewal() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        _ = try await session.buyProduct(identifier: MonetizationConfiguration.monthlyProductID)
        let store = store()
        await store.loadProduct()
        await store.refresh()
        XCTAssertTrue(store.isTrial)
        try session.forceRenewalOfSubscription(productIdentifier: MonetizationConfiguration.monthlyProductID)
        // StoreKit Test publishes the renewal asynchronously. Poll the signed
        // entitlement briefly so the assertion checks the renewal, not the
        // pre-renewal transaction still being surfaced by the test service.
        for _ in 0..<20 {
            await store.refresh()
            if !store.isTrial { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(store.isPremium)
        XCTAssertFalse(store.isTrial)
        XCTAssertFalse(store.mayShowAds)
    }

    func testFailedPaymentNeverUnlocksPremium() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        try await session.setSimulatedError(.generic(.notAvailableInStorefront), forAPI: .purchase)
        let store = store()
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
        let store = store()
        await store.refresh()
        await store.loadProduct()
        await store.purchase()
        XCTAssertFalse(store.isPremium)
        XCTAssertTrue(store.purchaseMessage?.contains("awaiting approval") == true)
    }
}

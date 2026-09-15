import StoreKit
@preconcurrency import StoreKitTest
import XCTest
@testable import FilmyCamera

/// Real StoreKit test transactions, not a cached premium boolean. This fixture
/// never changes App Store Connect and its $4.99 price is test-only.
@MainActor
final class MembershipStoreKitTests: XCTestCase {
    private func session() throws -> SKTestSession {
        let url = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "Filmy", withExtension: "storekit"))
        let session = try SKTestSession(contentsOf: url)
        session.resetToDefaultState()
        session.clearTransactions()
        session.disableDialogs = true
        return session
    }

    private func store() -> MembershipStore {
        MembershipStore(persistence: MemoryPhotoQuotaPersistence(), useStoreKitForTesting: true)
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
        XCTAssertTrue(store.isPremium, store.purchaseMessage ?? "Restore did not find purchase")
    }

    func testRefundRevokesPremium() async throws {
        let session = try session()
        defer { session.clearTransactions() }
        let transaction = try await session.buyProduct(identifier: MonetizationConfiguration.monthlyProductID)
        let store = store()
        await store.refresh()
        XCTAssertTrue(store.isPremium)
        try session.refundTransaction(identifier: XCTUnwrap(Int(exactly: transaction.id)))
        await store.refresh()
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
        try session.disableAutoRenewForTransaction(identifier: XCTUnwrap(Int(exactly: transaction.id)))
        try session.expireSubscription(productIdentifier: MonetizationConfiguration.monthlyProductID)
        await store.refresh()
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
        await store.refresh()
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

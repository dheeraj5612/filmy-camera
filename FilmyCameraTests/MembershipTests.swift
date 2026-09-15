import Foundation
import XCTest
@testable import FilmyCamera

final class MembershipPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_789_448_400)

    func testFreeTierHasExactlyThreeRealStarterRecipes() {
        XCTAssertEqual(MembershipPolicy.freeRecipeIDs.count, 3)
        let ids = Set(FilmRecipe.builtIns.map(\.id))
        XCTAssertTrue(MembershipPolicy.freeRecipeIDs.isSubset(of: ids))
        XCTAssertTrue(MembershipPolicy.allowsRecipe("g7x-compact", premium: false))
        XCTAssertFalse(MembershipPolicy.allowsRecipe("classic-chrome", premium: false))
        XCTAssertTrue(MembershipPolicy.allowsRecipe("classic-chrome", premium: true))
    }

    func testOnlyVerifiedNonRevokedUnexpiredEntitlementsGrantAccess() {
        let future = now.addingTimeInterval(60)
        XCTAssertTrue(MembershipPolicy.grantsAccess(verified: true, revoked: false, upgraded: false, expiresAt: future, now: now))
        XCTAssertFalse(MembershipPolicy.grantsAccess(verified: false, revoked: false, upgraded: false, expiresAt: future, now: now))
        XCTAssertFalse(MembershipPolicy.grantsAccess(verified: true, revoked: true, upgraded: false, expiresAt: future, now: now))
        XCTAssertFalse(MembershipPolicy.grantsAccess(verified: true, revoked: false, upgraded: true, expiresAt: future, now: now))
        XCTAssertFalse(MembershipPolicy.grantsAccess(verified: true, revoked: false, upgraded: false, expiresAt: now, now: now))
        XCTAssertFalse(MembershipPolicy.grantsAccess(verified: true, revoked: false, upgraded: false, expiresAt: nil, now: now))
    }

    func testAdsRequireEveryGateAndNeverAppearForPremium() {
        for resolved in [false, true] {
            for premium in [false, true] {
                for consent in [false, true] {
                    for configured in [false, true] {
                        let expected = resolved && !premium && consent && configured
                        XCTAssertEqual(MembershipPolicy.showsAds(entitlementsResolved: resolved, premium: premium,
                                                                 consentReady: consent, configured: configured), expected)
                    }
                }
            }
        }
    }

    func testExactlyTenReservationsThenBlocked() {
        var quota = DailyPhotoQuota(now: now, timeZone: .gmt)
        for remaining in stride(from: 9, through: 0, by: -1) {
            XCTAssertNotNil(quota.reserve(at: now))
            XCTAssertEqual(quota.remaining, remaining)
        }
        XCTAssertNil(quota.reserve(at: now))
        XCTAssertEqual(quota.used, 10)
    }

    func testSuccessfulChargeSurvivesEncodingAndRelaunch() throws {
        var quota = DailyPhotoQuota(now: now, timeZone: .gmt)
        _ = quota.reserve(at: now)
        let restored = try JSONDecoder().decode(DailyPhotoQuota.self, from: JSONEncoder().encode(quota))
        XCTAssertEqual(restored.remaining, 9)
        XCTAssertTrue(restored.isValid)
    }

    func testForwardDayResetsButClockRollbackDoesNot() {
        var quota = DailyPhotoQuota(now: now, timeZone: .gmt)
        _ = quota.reserve(at: now)
        quota.advance(to: now.addingTimeInterval(-86_400))
        XCTAssertEqual(quota.remaining, 9)
        quota.advance(to: now.addingTimeInterval(86_400))
        XCTAssertEqual(quota.remaining, 10)
        _ = quota.reserve(at: now.addingTimeInterval(86_400))
        quota.advance(to: now)
        XCTAssertEqual(quota.remaining, 9)
    }

    func testCalendarMidnightResetsBeforeTwentyFourHoursElapsed() throws {
        let formatter = ISO8601DateFormatter()
        let late = try XCTUnwrap(formatter.date(from: "2026-09-15T23:59:59Z"))
        var quota = DailyPhotoQuota(now: late, timeZone: .gmt)
        _ = quota.reserve(at: late)
        quota.advance(to: late.addingTimeInterval(2))
        XCTAssertEqual(quota.remaining, 10)
    }

    func testDSTUsesPinnedLocalCalendarNotFixedTwentyFourHourWindow() throws {
        let zone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        let formatter = ISO8601DateFormatter()
        let before = try XCTUnwrap(formatter.date(from: "2026-03-08T05:00:00Z"))
        let after = try XCTUnwrap(formatter.date(from: "2026-03-09T04:00:00Z"))
        var quota = DailyPhotoQuota(now: before, timeZone: zone)
        _ = quota.reserve(at: before)
        quota.advance(to: after)
        XCTAssertEqual(quota.remaining, 10)
        XCTAssertEqual(quota.timeZoneID, "America/New_York")
    }

    func testAnOldDayRefundCannotIncreaseTheNewDayAllowance() throws {
        var quota = DailyPhotoQuota(now: now, timeZone: .gmt)
        let day = try XCTUnwrap(quota.reserve(at: now))
        quota.advance(to: now.addingTimeInterval(86_400))
        _ = quota.reserve(at: now.addingTimeInterval(86_400))
        quota.refund(reservedDay: day)
        XCTAssertEqual(quota.remaining, 9)
    }

    func testInvalidPersistedQuotaIsRejected() throws {
        let quota = DailyPhotoQuota(now: now, timeZone: .gmt)
        let original = try JSONEncoder().encode(quota)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: original) as? [String: Any])
        fields["used"] = -1
        let decoded = try JSONDecoder().decode(DailyPhotoQuota.self, from: JSONSerialization.data(withJSONObject: fields))
        XCTAssertFalse(decoded.isValid)
    }
}

@MainActor
final class MembershipStoreTests: XCTestCase {
    private final class FailingPersistence: PhotoQuotaPersistence {
        enum Failure: Error { case unavailable }
        var failSave = false
        var failLoad = false
        var value: DailyPhotoQuota?
        func load() throws -> DailyPhotoQuota? {
            if failLoad { throw Failure.unavailable }
            return value
        }
        func save(_ quota: DailyPhotoQuota) throws {
            if failSave { throw Failure.unavailable }
            value = quota
        }
    }

    func testFailedCaptureRefundIsIdempotent() throws {
        let store = MembershipStore(persistence: MemoryPhotoQuotaPersistence())
        store.setAccessForTesting(.free)
        let permit = try XCTUnwrap(store.reserveCapture())
        XCTAssertEqual(store.remainingPhotos, 9)
        store.finishCapture(permit, succeeded: false)
        XCTAssertEqual(store.remainingPhotos, 10)
        store.finishCapture(permit, succeeded: false)
        XCTAssertEqual(store.remainingPhotos, 10)
    }

    func testSavedCaptureCannotBeRefundedByDuplicateCallback() throws {
        let store = MembershipStore(persistence: MemoryPhotoQuotaPersistence())
        store.setAccessForTesting(.free)
        let permit = try XCTUnwrap(store.reserveCapture())
        store.finishCapture(permit, succeeded: true)
        store.finishCapture(permit, succeeded: false)
        XCTAssertEqual(store.remainingPhotos, 9)
    }

    func testTrialAndPaidCapturesNeverConsumeFreeQuota() throws {
        for trial in [false, true] {
            let store = MembershipStore(persistence: MemoryPhotoQuotaPersistence())
            store.setAccessForTesting(.premium(until: Date().addingTimeInterval(3_600), trial: trial))
            for _ in 0..<20 {
                let permit = try XCTUnwrap(store.reserveCapture())
                XCTAssertNil(permit.chargedDay)
                store.finishCapture(permit, succeeded: true)
            }
            XCTAssertEqual(store.remainingPhotos, 10)
            XCTAssertFalse(store.mayShowAds)
        }
    }

    func testTenOutstandingCapturesAreChargedBeforeCompletion() throws {
        let store = MembershipStore(persistence: MemoryPhotoQuotaPersistence())
        store.setAccessForTesting(.free)
        var permits: [MembershipStore.CapturePermit] = []
        for _ in 0..<10 { permits.append(try XCTUnwrap(store.reserveCapture())) }
        XCTAssertNil(store.reserveCapture())
        store.finishCapture(permits[0], succeeded: false)
        XCTAssertNotNil(store.reserveCapture())
        XCTAssertEqual(store.remainingPhotos, 0)
    }

    func testPersistedFreeQuotaSurvivesStoreRecreation() throws {
        let persistence = MemoryPhotoQuotaPersistence()
        let first = MembershipStore(persistence: persistence)
        first.setAccessForTesting(.free)
        _ = try XCTUnwrap(first.reserveCapture())
        let next = MembershipStore(persistence: persistence)
        next.setAccessForTesting(.free)
        XCTAssertEqual(next.remainingPhotos, 9)
    }

    func testUnresolvedOrExpiredAccessCannotCaptureAndDoesNotShowAds() {
        for access in [MembershipStore.Access.checking, .unavailable, .premium(until: .distantPast, trial: true)] {
            let store = MembershipStore(persistence: MemoryPhotoQuotaPersistence())
            store.setAccessForTesting(access)
            XCTAssertFalse(store.isPremium)
            XCTAssertNil(store.reserveCapture())
            XCTAssertFalse(store.mayShowAds)
        }
    }

    func testStorageFailureBlocksInsteadOfResettingAllowance() {
        let persistence = FailingPersistence()
        let store = MembershipStore(persistence: persistence)
        store.setAccessForTesting(.free)
        persistence.failLoad = true
        XCTAssertNil(store.reserveCapture())
        XCTAssertEqual(store.remainingPhotos, 0)
        persistence.failLoad = false
        persistence.failSave = true
        XCTAssertNil(store.reserveCapture())
    }

    func testExpiredMembershipDoesNotMakePaidRecipesAvailable() {
        let store = MembershipStore(persistence: MemoryPhotoQuotaPersistence())
        store.setAccessForTesting(.premium(until: .distantPast, trial: false))
        XCTAssertFalse(store.allowsRecipe("classic-chrome"))
        XCTAssertTrue(store.allowsRecipe("g7x-compact"))
    }
}

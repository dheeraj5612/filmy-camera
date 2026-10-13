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

    func testClockRollbackCannotRefillExhaustedAllowance() {
        var quota = DailyPhotoQuota(now: now, timeZone: .gmt)
        for _ in 0..<MembershipPolicy.dailyPhotoLimit { _ = quota.reserve(at: now) }
        quota.advance(to: now.addingTimeInterval(-86_400))
        quota.advance(to: now)
        XCTAssertEqual(quota.remaining, 0)
    }

    private func exhaustedQuota() -> DailyPhotoQuota {
        var quota = DailyPhotoQuota(now: now, timeZone: .gmt)
        for _ in 0..<MembershipPolicy.dailyPhotoLimit { _ = quota.reserve(at: now, monotonic: 0) }
        return quota
    }

    func testForwardGlitchHealsAfterTwentyFourHoursOfMonotonicTime() {
        var quota = exhaustedQuota()
        let wrong = now.addingTimeInterval(-10 * 86_400)
        quota.advance(to: wrong, monotonic: 1_000)
        XCTAssertEqual(quota.remaining, 0)
        quota.advance(to: wrong, monotonic: 1_000 + 86_399)
        XCTAssertEqual(quota.remaining, 0)
        quota.advance(to: wrong, monotonic: 1_000 + 86_400)
        XCTAssertEqual(quota.remaining, MembershipPolicy.dailyPhotoLimit)
        XCTAssertNil(quota.rollbackHeal)
        XCTAssertEqual(quota.lastObservedAt, wrong)
        XCTAssertTrue(quota.isValid)
    }

    func testHealProgressAccumulatesAcrossObservations() {
        var quota = exhaustedQuota()
        let wrong = now.addingTimeInterval(-86_400)
        quota.advance(to: wrong, monotonic: 100)
        quota.advance(to: wrong, monotonic: 100 + 30_000)
        quota.advance(to: wrong, monotonic: 100 + 60_000)
        XCTAssertEqual(quota.remaining, 0)
        XCTAssertEqual(quota.rollbackHeal?.remaining ?? 0, 86_400 - 60_000, accuracy: 0.001)
        quota.advance(to: wrong, monotonic: 100 + 86_400)
        XCTAssertEqual(quota.remaining, MembershipPolicy.dailyPhotoLimit)
    }

    func testRebootCreditsOnlyTimeSinceBoot() {
        var quota = exhaustedQuota()
        let wrong = now.addingTimeInterval(-86_400)
        quota.advance(to: wrong, monotonic: 500_000)
        quota.advance(to: wrong, monotonic: 600)
        XCTAssertEqual(quota.rollbackHeal?.remaining ?? 0, 86_400 - 600, accuracy: 0.001)
        XCTAssertEqual(quota.rollbackHeal?.lastMonotonic, 600)
        XCTAssertEqual(quota.remaining, 0)
    }

    func testRepeatedRollbacksAndSameMonotonicNeverShortenHeal() {
        var quota = exhaustedQuota()
        let wrong = now.addingTimeInterval(-86_400)
        quota.advance(to: wrong, monotonic: 1_000)
        quota.advance(to: wrong, monotonic: 1_000)
        quota.advance(to: wrong.addingTimeInterval(-500), monotonic: 1_000)
        XCTAssertEqual(quota.rollbackHeal?.remaining, 86_400)
        quota.advance(to: wrong, monotonic: 1_100)
        quota.advance(to: wrong, monotonic: 1_100)
        XCTAssertEqual(quota.rollbackHeal?.remaining ?? 0, 86_300, accuracy: 0.001)
        quota.advance(to: wrong, monotonic: Double.nan)
        quota.advance(to: wrong, monotonic: -5)
        XCTAssertGreaterThan(quota.rollbackHeal?.remaining ?? 0, 86_000)
        XCTAssertEqual(quota.remaining, 0)
    }

    func testRollbackThenForwardToOriginalTimeNeverRefills() {
        var quota = exhaustedQuota()
        quota.advance(to: now.addingTimeInterval(-86_400), monotonic: 10)
        quota.advance(to: now, monotonic: 20)
        XCTAssertNil(quota.rollbackHeal)
        XCTAssertEqual(quota.remaining, 0)
        quota.advance(to: now.addingTimeInterval(-86_400), monotonic: 30)
        XCTAssertEqual(quota.rollbackHeal?.remaining, 86_400)
        XCTAssertEqual(quota.remaining, 0)
    }

    func testRecordWithoutHealKeysDecodesAndIsValid() throws {
        let quota = DailyPhotoQuota(now: now, timeZone: .gmt)
        let data = try JSONEncoder().encode(quota)
        var fields = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        fields.removeValue(forKey: "rollbackHeal")
        let old = try JSONSerialization.data(withJSONObject: fields)
        let restored = try JSONDecoder().decode(DailyPhotoQuota.self, from: old)
        XCTAssertNil(restored.rollbackHeal)
        XCTAssertTrue(restored.isValid)
        XCTAssertEqual(restored.remaining, 10)
    }

    func testHealRecordSurvivesEncodingRoundTrip() throws {
        var quota = exhaustedQuota()
        quota.advance(to: now.addingTimeInterval(-86_400), monotonic: 42)
        let restored = try JSONDecoder().decode(DailyPhotoQuota.self, from: JSONEncoder().encode(quota))
        XCTAssertEqual(restored, quota)
        XCTAssertEqual(restored.rollbackHeal, DailyPhotoQuota.RollbackHeal(remaining: 86_400, lastMonotonic: 42))
        XCTAssertTrue(restored.isValid)
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

    private final class InvalidRecordPersistence: PhotoQuotaPersistence {
        var saved: DailyPhotoQuota?
        func load() throws -> DailyPhotoQuota? { throw KeychainPhotoQuotaPersistence.Failure.invalidRecord }
        func save(_ quota: DailyPhotoQuota) throws { saved = quota }
    }

    func testUndecodableRecordIsReplacedNotLockedOut() {
        let persistence = InvalidRecordPersistence()
        let store = MembershipStore(persistence: persistence)
        XCTAssertEqual(store.remainingPhotos, 10)
        XCTAssertNotNil(persistence.saved)
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
        for access in [MembershipStore.Access.checking, .premium(until: .distantPast, trial: true)] {
            let store = MembershipStore(persistence: MemoryPhotoQuotaPersistence())
            store.setAccessForTesting(access)
            XCTAssertFalse(store.isPremium)
            XCTAssertNil(store.reserveCapture())
            XCTAssertFalse(store.mayShowAds)
        }
    }

    func testUnavailableAccessUsesFreeAllowanceWithoutGrantingPro() {
        let store = MembershipStore(persistence: MemoryPhotoQuotaPersistence())
        store.setAccessForTesting(.unavailable)
        for _ in 0..<MembershipPolicy.dailyPhotoLimit {
            let permit = store.reserveCapture()
            XCTAssertNotNil(permit?.chargedDay)
        }
        XCTAssertNil(store.reserveCapture())
        XCTAssertNotNil(store.notice)
        XCTAssertFalse(store.isPremium)
        XCTAssertFalse(store.mayShowAds)
        XCTAssertFalse(store.allowsRecipe("classic-chrome"))
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

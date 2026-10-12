import Foundation

/// StoreKit is the authority for premium access. Authentication never grants it.
enum PremiumFeature: String, CaseIterable, Identifiable {
    case unlimitedPhotos = "Unlimited photos"
    case allRecipes = "The complete film library"
    case recipeEditing = "Custom film recipes"
    case manualControls = "Manual camera controls"
    case captureSetup = "Advanced shooting tools"
    case photoImport = "Import and edit photos"
    case photoFinishes = "Print finishes"

    var id: String { rawValue }
}

enum MembershipPolicy {
    static let dailyPhotoLimit = 10
    static let freeRecipeIDs: Set<String> = ["g7x-compact", "provia-standard", "acros-monochrome"]

    static func allowsRecipe(_ id: String, premium: Bool) -> Bool {
        premium || freeRecipeIDs.contains(id)
    }

    static func grantsAccess(verified: Bool, revoked: Bool, upgraded: Bool, expiresAt: Date?, now: Date) -> Bool {
        verified && !revoked && !upgraded && (expiresAt.map { $0 > now } ?? false)
    }

    static func showsAds(entitlementsResolved: Bool, premium: Bool, consentReady: Bool, configured: Bool) -> Bool {
        entitlementsResolved && !premium && consentReady && configured
    }
}

/// A per-installation calendar-day budget. The initial time zone is pinned so
/// changing time zones cannot manufacture another daily allowance. Clock
/// rollback cannot reset it. A trusted server is required to defeat clock
/// fast-forward, device resets, and cross-device abuse; this is not such a server.
struct DailyPhotoQuota: Codable, Equatable {
    private(set) var timeZoneID: String
    private(set) var day: Date
    private(set) var lastObservedAt: Date
    private(set) var used: Int
    /// Optional so records written before the heal rule still decode.
    private(set) var rollbackHeal: RollbackHeal?

    /// Trusted elapsed-time countdown started when the wall clock is behind the anchor.
    struct RollbackHeal: Codable, Equatable {
        static let window: TimeInterval = 86_400
        var remaining: TimeInterval
        var lastMonotonic: TimeInterval

        var isValid: Bool {
            guard remaining.isFinite, lastMonotonic.isFinite, lastMonotonic >= 0 else { return false }
            return remaining >= 0 && remaining <= RollbackHeal.window
        }
    }

    /// Seconds from a monotonic, sleep-inclusive clock that cannot be set by the user; resets at reboot.
    static func monotonicNow() -> TimeInterval {
        TimeInterval(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW)) / 1_000_000_000
    }

    init(now: Date, timeZone: TimeZone = .current) {
        timeZoneID = timeZone.identifier
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        day = calendar.startOfDay(for: now)
        lastObservedAt = now
        used = 0
    }

    var remaining: Int { max(0, MembershipPolicy.dailyPhotoLimit - used) }

    var isValid: Bool {
        TimeZone(identifier: timeZoneID) != nil && (0...MembershipPolicy.dailyPhotoLimit).contains(used)
            && day.timeIntervalSince1970.isFinite && lastObservedAt.timeIntervalSince1970.isFinite
            && day <= lastObservedAt
            && (rollbackHeal?.isValid ?? true)
    }

    mutating func advance(to now: Date, monotonic: TimeInterval = DailyPhotoQuota.monotonicNow()) {
        // Freezing after a clock rollback is deliberate anti-tamper. It heals
        // only by trusted elapsed time: once 24 h of monotonic time (or time
        // since boot after a reboot) accrue while the clock stays behind the
        // anchor, the current clock is accepted and the allowance resets.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .gmt
        guard now >= lastObservedAt else {
            guard monotonic.isFinite, monotonic >= 0 else { return }
            guard var heal = rollbackHeal else {
                rollbackHeal = RollbackHeal(remaining: RollbackHeal.window, lastMonotonic: monotonic)
                return
            }
            let credit = monotonic >= heal.lastMonotonic ? monotonic - heal.lastMonotonic : monotonic
            if credit.isFinite, credit > 0 { heal.remaining -= credit }
            heal.lastMonotonic = monotonic
            if heal.remaining <= 0 {
                day = calendar.startOfDay(for: now)
                lastObservedAt = now
                used = 0
                rollbackHeal = nil
            } else {
                rollbackHeal = heal
            }
            return
        }
        rollbackHeal = nil
        let newDay = calendar.startOfDay(for: now)
        if newDay > day {
            day = newDay
            used = 0
        }
        lastObservedAt = now
    }

    /// Charge *before* handing off to asynchronous camera work. A crash cannot
    /// reset a pending charge. Ordinary capture/render failures refund it.
    mutating func reserve(at now: Date, monotonic: TimeInterval = DailyPhotoQuota.monotonicNow()) -> Date? {
        advance(to: now, monotonic: monotonic)
        guard remaining > 0 else { return nil }
        used += 1
        return day
    }

    mutating func refund(reservedDay: Date) {
        guard day == reservedDay, used > 0 else { return }
        used -= 1
    }
}

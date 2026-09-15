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
    }

    mutating func advance(to now: Date) {
        guard now >= lastObservedAt else { return }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: timeZoneID) ?? .gmt
        let newDay = calendar.startOfDay(for: now)
        if newDay > day {
            day = newDay
            used = 0
        }
        lastObservedAt = now
    }

    /// Charge *before* handing off to asynchronous camera work. A crash cannot
    /// reset a pending charge. Ordinary capture/render failures refund it.
    mutating func reserve(at now: Date) -> Date? {
        advance(to: now)
        guard remaining > 0 else { return nil }
        used += 1
        return day
    }

    mutating func refund(reservedDay: Date) {
        guard day == reservedDay, used > 0 else { return }
        used -= 1
    }
}

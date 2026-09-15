#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/main.swift" <<'SWIFT'
import Foundation
let now = ISO8601DateFormatter().date(from: "2026-09-15T23:59:59Z")!
var quota = DailyPhotoQuota(now: now, timeZone: .gmt)
for _ in 0..<10 { precondition(quota.reserve(at: now) != nil) }
precondition(quota.reserve(at: now) == nil)
let restored = try JSONDecoder().decode(DailyPhotoQuota.self, from: JSONEncoder().encode(quota))
precondition(restored.remaining == 0 && restored.isValid)
quota.advance(to: now.addingTimeInterval(-86_400))
precondition(quota.remaining == 0)
quota.advance(to: now.addingTimeInterval(2))
precondition(quota.remaining == 10)
let day = quota.reserve(at: now.addingTimeInterval(2))!
quota.refund(reservedDay: day)
precondition(quota.remaining == 10)
for resolved in [false, true] {
    for premium in [false, true] {
        for consent in [false, true] {
            for configured in [false, true] {
                precondition(MembershipPolicy.showsAds(entitlementsResolved: resolved, premium: premium,
                    consentReady: consent, configured: configured) == (resolved && !premium && consent && configured))
            }
        }
    }
}
precondition(MembershipPolicy.allowsRecipe("g7x-compact", premium: false))
precondition(!MembershipPolicy.allowsRecipe("classic-chrome", premium: false))
precondition(!MembershipPolicy.grantsAccess(verified: false, revoked: false, upgraded: false,
    expiresAt: now.addingTimeInterval(3_600), now: now))
print("Compiled Swift quota, persistence round-trip, midnight, rollback and 16 ad-gate combinations: PASS")
SWIFT
swiftc "$root/FilmyCamera/Monetization/MembershipPolicy.swift" "$work/main.swift" -o "$work/policy-tests"
"$work/policy-tests"

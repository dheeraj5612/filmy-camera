import Foundation

/// One Roll entry reduced to what grouping and filtering need. `date` is nil
/// when the capture date is unknown.
struct GalleryItem: Equatable, Sendable {
    let id: String
    let date: Date?
    let lookName: String?
}

struct GallerySection: Identifiable, Equatable, Sendable {
    /// Start of the capture day, or nil for frames without a known date.
    let day: Date?
    let ids: [String]

    var id: String {
        guard let day else { return "unknown-day" }
        return "day-\(Int(day.timeIntervalSinceReferenceDate))"
    }
}

struct GalleryLookCount: Identifiable, Equatable, Sendable {
    let name: String
    let count: Int

    var id: String { name }
}

/// Day sections and look chips for the Roll. Items must arrive newest first;
/// the order inside and between sections is preserved.
struct GalleryLayoutModel: Equatable, Sendable {
    let sections: [GallerySection]
    let looks: [GalleryLookCount]
    let totalCount: Int
    let visibleIDs: [String]

    static let empty = GalleryLayoutModel(sections: [], looks: [], totalCount: 0, visibleIDs: [])

    init(sections: [GallerySection], looks: [GalleryLookCount], totalCount: Int, visibleIDs: [String]) {
        self.sections = sections
        self.looks = looks
        self.totalCount = totalCount
        self.visibleIDs = visibleIDs
    }

    init(items: [GalleryItem], lookFilter: String?, calendar: Calendar) {
        var lookOrder: [String] = []
        var lookCounts: [String: Int] = [:]
        for item in items {
            guard let name = item.lookName else { continue }
            if lookCounts[name] == nil { lookOrder.append(name) }
            lookCounts[name, default: 0] += 1
        }

        var sectionDays: [Date?] = []
        var sectionIDs: [[String]] = []
        var sectionIndexByDay: [Date: Int] = [:]
        var unknownIndex: Int?
        var visible: [String] = []

        for item in items {
            if let lookFilter, item.lookName != lookFilter { continue }
            visible.append(item.id)
            if let date = item.date {
                let day = calendar.startOfDay(for: date)
                if let index = sectionIndexByDay[day] {
                    sectionIDs[index].append(item.id)
                } else {
                    sectionIndexByDay[day] = sectionDays.count
                    sectionDays.append(day)
                    sectionIDs.append([item.id])
                }
            } else if let index = unknownIndex {
                sectionIDs[index].append(item.id)
            } else {
                unknownIndex = sectionDays.count
                sectionDays.append(nil)
                sectionIDs.append([item.id])
            }
        }

        var built: [GallerySection] = []
        for (index, day) in sectionDays.enumerated() {
            built.append(GallerySection(day: day, ids: sectionIDs[index]))
        }

        self.sections = built
        self.looks = lookOrder.map { GalleryLookCount(name: $0, count: lookCounts[$0] ?? 0) }
        self.totalCount = items.count
        self.visibleIDs = visible
    }
}

enum GallerySectionTitle {
    /// "Today", "Yesterday", then a medium localized date. Frames without a
    /// capture date fall under "Earlier".
    static func title(for day: Date?, now: Date, calendar: Calendar, locale: Locale) -> String {
        guard let day else { return "Earlier" }
        if calendar.isDate(day, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: day)
    }
}

/// Multi-select state for the Roll.
struct GallerySelection: Equatable, Sendable {
    private(set) var ids: Set<String> = []

    var count: Int { ids.count }
    var isEmpty: Bool { ids.isEmpty }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    mutating func toggle(_ id: String) {
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
    }

    mutating func selectAll(_ visibleIDs: [String]) {
        ids = Set(visibleIDs)
    }

    mutating func clear() { ids.removeAll() }

    /// Drops identifiers that are no longer in the Roll.
    mutating func prune(keeping available: Set<String>) {
        ids.formIntersection(available)
    }

    mutating func remove(_ removed: [String]) {
        ids.subtract(removed)
    }

    /// Selected identifiers in Roll order.
    func ordered(in visibleIDs: [String]) -> [String] {
        visibleIDs.filter { ids.contains($0) }
    }

    func isAllSelected(in visibleIDs: [String]) -> Bool {
        !visibleIDs.isEmpty && visibleIDs.allSatisfy { ids.contains($0) }
    }
}

enum GalleryRemovalPolicy {
    /// The frame the detail pager lands on after `removedID` disappears:
    /// the next surviving frame, else the previous surviving one, else nil
    /// (the roll or filtered list is empty, so the pager dismisses).
    static func replacementID(removedID: String, previousIDs: [String], currentIDs: [String]) -> String? {
        guard let removedIndex = previousIDs.firstIndex(of: removedID) else { return nil }
        let surviving = Set(currentIDs)
        if let next = previousIDs[(removedIndex + 1)...].first(where: { surviving.contains($0) }) {
            return next
        }
        return previousIDs[..<removedIndex].last(where: { surviving.contains($0) })
    }
}

enum GalleryInfo {
    struct Row: Equatable, Sendable {
        let title: String
        let value: String
    }

    /// Only rows whose data exists are returned.
    static func rows(
        capturedAt: Date?,
        lookName: String?,
        pixelWidth: Int,
        pixelHeight: Int,
        calendar: Calendar,
        locale: Locale
    ) -> [Row] {
        var rows: [Row] = []
        if let capturedAt {
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.timeZone = calendar.timeZone
            formatter.locale = locale
            formatter.dateStyle = .medium
            formatter.timeStyle = .short
            rows.append(Row(title: "Captured", value: formatter.string(from: capturedAt)))
        }
        if let lookName, !lookName.isEmpty {
            rows.append(Row(title: "Look", value: lookName))
        }
        if pixelWidth > 0, pixelHeight > 0 {
            rows.append(Row(title: "Dimensions", value: "\(pixelWidth) × \(pixelHeight) px"))
        }
        return rows
    }
}

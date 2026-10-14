import Foundation

@main
struct FujiModelChecks {
    static func main() throws {
        var checks = 0
        func check(_ condition: Bool) {
            precondition(condition)
            checks += 1
        }
        let defaults = FujiShootingSettings()
        check(!defaults.enabled && !defaults.needsRAW && defaults.cropFactor == 1 && !defaults.previewIsNatural)
        check(defaults.qItems.count == 16)
        func requiresHashable<T: Hashable>(_ value: T) {}
        requiresHashable(FujiDriveMode.single)
        requiresHashable(FujiQItem.raw)
        let profiles = FujiAutoISOProfile.defaults
        for index in 1...5000 {
            let product = pow(10, Double(index) / 500 - 5)
            let exposure = FujiAutoISOPlanner.resolve(meteredProduct: product, profile: profiles[index % 3],
                                                     isoBounds: 64...3200, durationBounds: 0.0001...1)
            check((64...3200).contains(exposure.iso))
            check((0.0001...1).contains(exposure.seconds))
            check(exposure.iso.isFinite && exposure.seconds.isFinite)
        }
        for count in [3, 5, 7] {
            let values = FujiCapturePlanner.bracketOffsets(count: count, step: 1)
            check(values.count == count && values.first == 0 && Set(values).count == count)
        }
        var settings = defaults
        settings.enabled = true
        settings.drive = .dynamicRangeBracket
        check(settings.needsRAW)
        check(FujiCapturePlanner.steps(for: settings).map(\.dynamicRange) == [.dr100, .dr200, .dr400])
        let encoded = try JSONEncoder().encode(settings)
        check(try JSONDecoder().decode(FujiShootingSettings.self, from: encoded) == settings)
        var buffer = FujiTimedBuffer<Int>(capacity: 12, maximumAge: 2)
        for index in 0..<1000 {
            buffer.append(index, at: Double(index) / 8)
            check(buffer.entries.count <= 12)
        }
        check(buffer.take(at: 125).count == 12)
        check(buffer.entries.isEmpty)
        buffer.append(1, at: 100)
        check(buffer.take(at: 103).isEmpty)
        print("Passed \(checks) Fuji model invariant checks")
    }
}

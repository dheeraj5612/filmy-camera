from pathlib import Path

path = Path('FilmyCamera/Models/SceneAutoPolicy.swift')
source = path.read_text()
old = '        wbMismatchSince = nil\n        wbMeteringSince = nil\n    }\n\n    mutating func update('
new = '        wbMismatchSince = nil\n        wbMeteringSince = nil\n        // A pause can interrupt native WB reacquisition. Warm up and lock\n        // again instead of accidentally leaving continuous WB running.\n        wbReference = nil\n    }\n\n    mutating func update('
assert old in source
path.write_text(source.replace(old, new, 1))

path = Path('FilmyCameraTests/SceneAutoPolicyTests.swift')
source = path.read_text()
marker = '    func testHardwareWhiteBalanceSettlingIsGivenTimeButNotUnboundedTime() {'
test = '''    func testResumeRelocksWhiteBalanceAfterInterruptedReacquisition() {
        var policy = SceneAutoPolicy()
        for tick in 0..<24 { advance(&policy, to: Double(tick) * 0.4) }
        var changed = observation(0)
        changed.redOverGreen = 1.4
        var requestedMetering = false
        for tick in 24..<40 {
            let result = advance(&policy, to: Double(tick) * 0.4, observation: changed)
            if result.whiteBalance == .meter { requestedMetering = true; break }
        }
        XCTAssertTrue(requestedMetering)
        policy.resume()
        var locks = 0
        for tick in 0..<12 {
            let result = advance(&policy, to: 100 + Double(tick) * 0.4)
            if result.whiteBalance == .lock { locks += 1 }
            XCTAssertNotEqual(result.whiteBalance, .meter)
        }
        XCTAssertEqual(locks, 1)
    }

'''
assert marker in source
path.write_text(source.replace(marker, test + marker, 1))

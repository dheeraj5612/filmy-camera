import Foundation

var assertions = 0
func check(_ condition: @autoclosure () -> Bool, _ message: String) {
    assertions += 1
    precondition(condition(), message)
}
for mode in CaptureMode.allCases {
    var sequence = CaptureSequence(mode: mode)
    for index in 0..<mode.frameLimit {
        check(sequence.reserveFrame() == index, "reserve index")
        check(sequence.reserveFrame() == nil, "one in flight")
        check(!sequence.completeFrame(index + 1), "reject wrong callback")
        check(sequence.completeFrame(index), "complete current")
        check(!sequence.completeFrame(index), "reject duplicate")
    }
    check(sequence.shouldFinish, "bounded sequence")
    check(sequence.reserveFrame() == nil, "no extra capture")
    var stopped = CaptureSequence(mode: mode)
    _ = stopped.reserveFrame()
    stopped.requestStop()
    check(!stopped.shouldFinish, "drain first")
    check(stopped.completeFrame(0), "drained")
    check(stopped.shouldFinish, "stopped")
    check(stopped.reserveFrame() == nil, "no capture after stop")
}
for value in ["javascript:alert(1)", "file:///private/a", "data:text/html,x", "https://user:pw@example.com", "https://example.com/\nattack"] {
    check(CaptureModesPolicy.safeWebURL(value) == nil, "reject unsafe URL")
}
check(CaptureModesPolicy.safeWebURL("https://example.com")?.host == "example.com", "safe URL")
for name in ["", ".", "..", "../x", "x/y", "x\\y", "x\u{0}"] {
    check(!CaptureModesPolicy.isSafeFilename(name), "reject traversal")
}
check(CaptureModesPolicy.isSafeFilename("original-000.heic"), "safe filename")
check(CaptureModesPolicy.supportsMacro(minimumFocusDistance: 20, autofocus: true), "macro capability")
check(!CaptureModesPolicy.supportsMacro(minimumFocusDistance: -1, autofocus: true), "unknown focus distance")
check(!CaptureModesPolicy.supportsMacro(minimumFocusDistance: 20, autofocus: false), "fixed-focus ultra-wide")
check(CaptureModesPolicy.acceptableNightTranslation(x: 8, y: -8, width: 100, height: 100), "bounded registration")
check(!CaptureModesPolicy.acceptableNightTranslation(x: .nan, y: 0, width: 100, height: 100), "NaN registration")
check(CaptureModesPolicy.acceptablePanoramaBounds(width: 12000, height: 2000), "panorama budget")
check(!CaptureModesPolicy.acceptablePanoramaBounds(width: 12001, height: 2000), "panorama width")
check(!CaptureModesPolicy.acceptablePanoramaBounds(width: .infinity, height: 2000), "panorama infinity")
var media = CaptureMedia(id: UUID(), mode: .burst, createdAt: Date(), recipeName: "Test")
check(!media.isExported, "empty output is not exported")
media.outputs = ["a.heic", "b.heic"]
media.photosIdentifiers["a.heic"] = "asset-a"
check(!media.isExported, "partial export remains retryable")
media.photosIdentifiers["b.heic"] = "asset-b"
check(media.isExported, "complete export")
let roundTrip = try JSONDecoder().decode(CaptureMedia.self, from: JSONEncoder().encode(media))
check(roundTrip.id == media.id && roundTrip.photosIdentifiers == media.photosIdentifiers, "manifest round trip")
print("PASS: \(assertions) capture policy assertions")

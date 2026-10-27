import XCTest
@testable import RemoteFitCore

final class UUScrollScalingTests: XCTestCase {
    func testSlowMovementAccumulatesInsteadOfDisappearing() {
        var scaler = UUScrollAccumulator()
        let values = (0..<100).map { i in
            scaler.scale(x: -1, y: 1, percent: 5, time: Double(i) * 0.01, context: "a")
        }
        XCTAssertEqual(values.reduce(0) { $0 + $1.x }, -5)
        XCTAssertEqual(values.reduce(0) { $0 + $1.y }, 5)
    }

    func testRemainderDoesNotCrossDirectionTargetPauseOrClockReset() {
        for scenario in 0..<4 {
            var scaler = UUScrollAccumulator()
            _ = scaler.scale(x: 0, y: 9, percent: 10, time: 1, context: "a")
            let result = scaler.scale(x: 0, y: scenario == 0 ? -2 : 2, percent: 10,
                                      time: scenario == 2 ? 2 : (scenario == 3 ? 0 : 1.01),
                                      context: scenario == 1 ? "b" : "a")
            XCTAssertEqual(result.y, 0, "scenario \(scenario)")
        }
    }

    func testSourcePathsMustBeKnownUUComponents() {
        XCTAssertTrue(UUScrollScaling.isUUExecutable("/Applications/UURemote.app/Contents/Helpers/UURemoteServer"))
        XCTAssertTrue(UUScrollScaling.isUUExecutable("/Users/test/Applications/UURemote.app/Contents/MacOS/UURemoteService"))
        for path in ["/tmp/UURemoteServer", "/Applications/OtherUURemote.app/Contents/MacOS/UURemote",
                     "/Applications/UURemote.app/Contents/MacOS/Fake", ""] {
            XCTAssertFalse(UUScrollScaling.isUUExecutable(path))
        }
    }

    func testOldPreferencesStayAtOriginalSpeedAndNewValuesRoundTrip() throws {
        let old = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertEqual(old.uuScrollSpeedPercent, 100)
        var enabled = old
        enabled.uuScrollSpeedPercent = 5
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(enabled))
        XCTAssertEqual(restored.uuScrollSpeedPercent, 5)
        XCTAssertFalse(restored.uuTouchScrollEnabled)
        for (input, expected) in [(-10, 1), (0, 1), (1000, 100)] {
            let json = Data("{\"uuScrollSpeedPercent\":\(input)}".utf8)
            XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: json).uuScrollSpeedPercent, expected)
        }
    }
    func testPreviewToggleMigratesToSpeedWithoutPersistingHiddenSwitch() throws {
        for (legacyFlag, expected) in [(false, 100), (true, 5)] {
            let json = Data("{\"uuScrollSpeedEnabled\":\(legacyFlag),\"uuScrollSpeedPercent\":5}".utf8)
            let restored = try JSONDecoder().decode(Preferences.self, from: json)
            XCTAssertEqual(restored.uuScrollSpeedPercent, expected)
            let encoded = try JSONEncoder().encode(restored)
            XCTAssertFalse(String(decoding: encoded, as: UTF8.self).contains("uuScrollSpeedEnabled"))
        }
    }

}

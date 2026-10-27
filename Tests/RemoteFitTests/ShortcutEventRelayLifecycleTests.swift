import AppKit
import XCTest
@testable import RemoteFit

@MainActor
final class ShortcutEventRelayLifecycleTests: XCTestCase {
    func testIdleTapIsRemovedAndCanBePreparedAgain() throws {
        let relay = ShortcutEventRelay()
        relay.prepare()
        guard relay.isPrepared else { throw XCTSkip("Event tap permission unavailable to test runner") }
        relay.finishWhenIdle()
        XCTAssertFalse(relay.isPrepared)
        relay.prepare()
        XCTAssertTrue(relay.isPrepared)
        relay.finishWhenIdle()
        XCTAssertFalse(relay.isPrepared)
    }
    func testReleasePacketDrainsBeforeTapIsRemoved() async throws {
        let relay = ShortcutEventRelay()
        relay.prepare()
        guard relay.isPrepared else { throw XCTSkip("Event tap permission unavailable to test runner") }
        // Null events exercise delivery without typing or clicking in another application.
        let marker = try XCTUnwrap(CGEvent(source: nil))
        relay.post([marker])
        relay.finishWhenIdle()
        await relay.waitUntilDelivered()
        for _ in 0..<100 where relay.isPrepared { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertFalse(relay.isPrepared)
    }
}

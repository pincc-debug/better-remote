import XCTest
@testable import RemoteFitCore

final class VirtualDisplayIdentityTests: XCTestCase {
    func testRepeatedConnectionsAndSizesUseOnlyTwoIdentities() throws {
        var cursor = VirtualDisplayIdentityCursor()
        var seen = Set<UInt32>()
        var live: UInt32?
        for _ in 0..<100 {
            let next = try XCTUnwrap(VirtualDisplayIdentity.next(after: cursor.lastSerial,
                                                                occupied: Set(live.map { [$0] } ?? [])))
            XCTAssertNotEqual(next, live)
            seen.insert(next)
            // Simulate restart from on-disk state, not an in-memory counter.
            cursor = try JSONDecoder().decode(VirtualDisplayIdentityCursor.self,
                from: JSONEncoder().encode(VirtualDisplayIdentityCursor(lastSerial: next)))
            live = next
        }
        XCTAssertEqual(seen, Set(VirtualDisplayIdentity.serials))
    }
    func testBothOnlineRefusesToAllocateAnotherIdentity() {
        XCTAssertNil(VirtualDisplayIdentity.next(after: nil, occupied: Set(VirtualDisplayIdentity.serials)))
    }
    func testFailedCandidateCanReuseOfflineSlotWithoutReusingHeldSource() {
        let a = VirtualDisplayIdentity.serials[0], b = VirtualDisplayIdentity.serials[1]
        XCTAssertEqual(VirtualDisplayIdentity.next(after: b, occupied: [a]), b)
    }
    func testMissingOrOldCursorStillUsesBoundedPool() {
        XCTAssertEqual(VirtualDisplayIdentity.next(after: 999, occupied: []), VirtualDisplayIdentity.serials[0])
    }
}

import XCTest
@testable import RemoteFitCore

final class DisplayTopologyTests: XCTestCase {
    private let size = Dimensions(1252, 1156)
    private func mode(_ width: Int, _ height: Int, scale: Int = 2) -> DisplayMode {
        .init(width: width, height: height, pixelWidth: width * scale, pixelHeight: height * scale, refresh: 60)
    }
    private func display(_ id: UInt32, physical: Bool, main: Bool = false, x: Int32 = 0, y: Int32 = 0,
                         mirror: UInt32 = 0, mode: DisplayMode? = nil) -> DisplayState {
        .init(id: id, uuid: "display-\(id)", hardwareKey: "hardware-\(id)", physical: physical,
              main: main, x: x, y: y, mirror: mirror,
              mode: mode ?? self.mode(1728, 1117))
    }
    private func virtual(_ id: UInt32, mode: DisplayMode? = nil) -> DisplayState {
        var state = display(id, physical: false, mode: mode ?? self.mode(1400, 630))
        state.mirror = 0
        return state
    }
    private func hidpi(_ dimensions: Dimensions) -> DisplayMode { mode(dimensions.width, dimensions.height) }

    private func assertFields(_ actual: DisplayState, _ expected: DisplayState, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.id, expected.id, file: file, line: line)
        XCTAssertEqual(actual.uuid, expected.uuid, file: file, line: line)
        XCTAssertEqual(actual.hardwareKey, expected.hardwareKey, file: file, line: line)
        XCTAssertEqual(actual.physical, expected.physical, file: file, line: line)
        XCTAssertEqual(actual.main, expected.main, file: file, line: line)
        XCTAssertEqual(actual.x, expected.x, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, file: file, line: line)
        XCTAssertEqual(actual.mirror, expected.mirror, file: file, line: line)
        XCTAssertEqual(actual.skipMode, expected.skipMode, file: file, line: line)
        XCTAssertEqual(actual.skipOrigin, expected.skipOrigin, file: file, line: line)
        XCTAssertTrue(actual.mode.matches(expected.mode), file: file, line: line)
    }

    private func assertSamePlan(_ actual: [DisplayState], _ expected: [DisplayState], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.map(\.id), expected.map(\.id), file: file, line: line)
        for (lhs, rhs) in zip(actual, expected) { assertFields(lhs, rhs, file: file, line: line) }
    }

    func testCopyIsTheLockedChinese() {
        XCTAssertEqual(MultiDisplayExtendCopy.title, "多屏保持扩展")
        XCTAssertEqual(MultiDisplayExtendCopy.footnote, "开启后各屏同尺寸、互不镜像。远程通常只能看到其中一块。")
    }

    func testPreferenceDefaultsOffAndRoundTrips() throws {
        XCTAssertFalse(Preferences().keepMultiDisplayExtended)
        let missing = try JSONDecoder().decode(Preferences.self, from: Data("{}".utf8))
        XCTAssertFalse(missing.keepMultiDisplayExtended)
        var saved = Preferences()
        saved.keepMultiDisplayExtended = true
        let restored = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(saved))
        XCTAssertTrue(restored.keepMultiDisplayExtended)
        var off = Preferences()
        off.keepMultiDisplayExtended = true
        let profile = DeviceConfiguration(preferences: off)
        XCTAssertFalse(profile.applying(to: Preferences()).keepMultiDisplayExtended)
        XCTAssertTrue(profile.applying(to: off).keepMultiDisplayExtended)
    }

    func testMirrorAllPlanMatchesTodaysTransition() throws {
        let source = virtual(43)
        let builtin = display(1, physical: true, main: true)
        let external = display(2, physical: true, x: 1728, y: -1440, mode: mode(3840, 2160, scale: 1))
        let physical = [builtin, external]
        let legacy = try DisplayTransition.targets(source: source, dimensions: size, physical: physical, selectedMode: hidpi(size))
        let planned = try DisplayTopology.targets(topology: .mirrorAll, sources: [source], modes: [hidpi(size)],
                                                  dimensions: size, physical: physical)
        assertSamePlan(planned, legacy)
        XCTAssertEqual(planned.filter(\.physical).map(\.mirror), [43, 43])
        XCTAssertTrue(planned.filter(\.physical).allSatisfy { $0.skipMode && $0.skipOrigin })
    }

    func testSingleScreenAndHeadlessExtendedMatchMirrorAll() throws {
        let source = virtual(43)
        let panel = display(1, physical: true, main: true, x: 40, y: -20)
        let mirror = try DisplayTopology.targets(topology: .mirrorAll, sources: [source], modes: [hidpi(size)], dimensions: size, physical: [panel])
        let extended = try DisplayTopology.targets(topology: .extended, sources: [source], modes: [hidpi(size)], dimensions: size, physical: [panel])
        assertSamePlan(extended, mirror)
        let headlessMirror = try DisplayTransition.targets(source: source, dimensions: size, physical: [], selectedMode: hidpi(size))
        let headlessExtended = try DisplayTopology.targets(topology: .extended, sources: [source], modes: [hidpi(size)], dimensions: size, physical: [])
        assertSamePlan(headlessExtended, headlessMirror)
    }

    func testExtendedDesktopsAreSameSizeUnmirroredAndNotCloned() throws {
        let builtin = display(1, physical: true, main: true, mode: mode(1728, 1117))
        let external = display(2, physical: true, x: 1728, y: -1440, mode: mode(3840, 2160, scale: 1))
        let left = virtual(50)
        let right = virtual(51)
        let targets = try DisplayTopology.targets(topology: .extended, sources: [left, right], modes: [hidpi(size), hidpi(size)],
                                                  dimensions: size, physical: [builtin, external])
        let desktops = targets.filter { !$0.physical }
        XCTAssertEqual(desktops.count, 2)
        XCTAssertTrue(desktops.allSatisfy { $0.mirror == 0 && !$0.skipMode && !$0.skipOrigin })
        XCTAssertTrue(desktops.allSatisfy { $0.mode.width == size.width && $0.mode.height == size.height && $0.mode.pixelWidth == size.width * 2 })
        XCTAssertEqual(desktops.filter(\.main).map(\.id), [50])
        XCTAssertEqual(desktops.first { $0.main }?.x, 0)
        XCTAssertEqual(desktops.first { $0.main }?.y, 0)
        let secondary = try XCTUnwrap(desktops.first { !$0.main })
        XCTAssertEqual(secondary.id, 51)
        XCTAssertEqual(secondary.x, 1728)
        XCTAssertEqual(secondary.y, -1440)
        XCTAssertGreaterThan(secondary.x, 0)
        XCTAssertLessThan(secondary.y, 0)
        let panels = targets.filter(\.physical)
        XCTAssertEqual(panels.map(\.mirror).sorted(), [50, 51])
        XCTAssertEqual(Set(panels.map(\.mirror)).count, 2)
        XCTAssertTrue(panels.allSatisfy { !$0.main && $0.skipMode && $0.skipOrigin })
        XCTAssertNotEqual(panels.map(\.mirror), [50, 50])
        XCTAssertTrue(DisplayTopology.matches(targets, targets: targets, sourceID: 50))
    }

    func testExtendedPushesOverlappingDisplaysApartWithoutReordering() throws {
        let left = display(1, physical: true, main: true, mode: mode(800, 600))
        let right = display(2, physical: true, x: 100, mode: mode(800, 600))
        let wide = Dimensions(1252, 1156)
        let placed = ExtendedArrangement.place([left, right], size: wide)
        XCTAssertEqual(placed.map(\.id), [1, 2])
        XCTAssertEqual(placed[0].x, 0)
        XCTAssertEqual(placed[0].y, 0)
        XCTAssertTrue(placed[0].main)
        XCTAssertEqual(placed[1].x, Int32(wide.width))
        XCTAssertEqual(placed[1].y, 0)
        XCTAssertFalse(overlaps(placed, size: wide))
    }

    func testExtendedKeepsVerticalOrder() throws {
        let bottom = display(1, physical: true, main: true, mode: mode(1000, 800))
        let top = display(2, physical: true, y: 800, mode: mode(1000, 800))
        let tall = Dimensions(1400, 900)
        let placed = ExtendedArrangement.place([bottom, top], size: tall)
        XCTAssertEqual(placed.first { $0.id == 1 }?.y, 0)
        XCTAssertEqual(placed.first { $0.id == 2 }?.y, Int32(tall.height))
        XCTAssertEqual(placed.first { $0.id == 2 }?.x, 0)
        XCTAssertFalse(overlaps(placed, size: tall))
    }

    func testMirroredOriginalsSpreadIntoARow() throws {
        let panels = [display(1, physical: true, main: true), display(2, physical: true), display(3, physical: true)]
        let placed = ExtendedArrangement.place(panels, size: size)
        XCTAssertEqual(placed.map(\.id), [1, 2, 3])
        XCTAssertEqual(placed.map(\.x), [0, Int32(size.width), Int32(size.width * 2)])
        XCTAssertTrue(placed.dropFirst().allSatisfy { $0.y == 0 && !$0.main })
        XCTAssertFalse(overlaps(placed, size: size))
    }

    func testThreePanelsGetThreeSameSizeUnmirroredDesktops() throws {
        let panels = [
            display(1, physical: true, main: true, mode: mode(1728, 1117)),
            display(2, physical: true, x: 1728, mode: mode(1920, 1080, scale: 1)),
            display(3, physical: true, x: -1920, mode: mode(1920, 1080, scale: 1))
        ]
        let slots = DisplayTopology.slots(topology: .extended, physical: panels, dimensions: size)
        XCTAssertEqual(slots.count, 3)
        let sources = slots.indices.map { virtual(UInt32(100 + $0)) }
        let targets = try DisplayTopology.targets(topology: .extended, sources: sources, modes: Array(repeating: hidpi(size), count: 3),
                                                  dimensions: size, physical: panels)
        let desktops = targets.filter { !$0.physical && $0.mirror == 0 }
        XCTAssertEqual(desktops.count, 3)
        XCTAssertTrue(desktops.allSatisfy { $0.mode.width == size.width && $0.mode.height == size.height && $0.mode.pixelWidth == size.width * 2 })
        XCTAssertGreaterThan(Set(desktops.map { "\($0.x),\($0.y)" }).count, 1)
        let bound = targets.filter(\.physical)
        XCTAssertEqual(bound.count, 3)
        XCTAssertEqual(Set(bound.map(\.mirror)), Set(desktops.map(\.id)))
        XCTAssertTrue(DisplayTopology.matches(targets, targets: targets, sourceID: desktops.first { $0.main }!.id))
    }

    func testRebindFollowsUUIDWhenDisplayIDsChange() {
        let original = [virtual(10), virtual(11), virtual(12)]
        var live = original
        live[0].id = 210
        live[1].id = 211
        live[2].id = 212
        var decoy = virtual(10)
        decoy.uuid = "not-the-framebuffer"
        let resolved = DisplayTopology.rebound(original, live: [decoy] + live)
        XCTAssertEqual(resolved?.map(\.id), [210, 211, 212])
        XCTAssertEqual(resolved?.map(\.uuid), original.map(\.uuid))
        XCTAssertNil(DisplayTopology.rebound(original, live: [decoy]))
    }

    func testMirroredProbeStillPlansAnUnmirroredDesktop() throws {
        let panels = [display(1, physical: true, main: true), display(2, physical: true, x: 1800)]
        let slots = DisplayTopology.slots(topology: .extended, physical: panels, dimensions: size)
        var sources = slots.indices.map { virtual(UInt32(50 + $0)) }
        sources[0].mirror = 7
        let targets = try DisplayTopology.targets(topology: .extended, sources: sources, modes: [hidpi(size), hidpi(size)],
                                                  dimensions: size, physical: panels)
        XCTAssertTrue(targets.filter { !$0.physical && $0.mirror == 0 }.allSatisfy { !$0.skipMode })
        XCTAssertEqual(Set(targets.filter(\.physical).map(\.mirror)).count, 2)
        XCTAssertFalse(targets.contains { !$0.physical && $0.mirror == 7 })
    }

    func testNormalizedOriginDoesNotLookLikeAFailedExtend() throws {
        let panels = [display(1, physical: true, main: true), display(2, physical: true, x: 1728, y: -1440, mode: mode(3840, 2160, scale: 1))]
        let targets = try DisplayTopology.targets(topology: .extended, sources: [virtual(50), virtual(51)],
                                                  modes: [hidpi(size), hidpi(size)], dimensions: size, physical: panels)
        var translated = targets
        for index in translated.indices where !translated[index].physical && translated[index].mirror == 0 {
            translated[index].x += 80
            translated[index].y += 40
        }
        XCTAssertTrue(DisplayTopology.matches(translated, targets: targets, sourceID: 50))
        var collapsed = targets
        for index in collapsed.indices where !collapsed[index].physical && collapsed[index].mirror == 0 {
            collapsed[index].x = 0
            collapsed[index].y = 0
        }
        XCTAssertFalse(DisplayTopology.matches(collapsed, targets: targets, sourceID: 50))
    }

    func testExtendedVerificationRejectsASharedMirrorAndAMovedDesktop() throws {
        let builtin = display(1, physical: true, main: true)
        let external = display(2, physical: true, x: 1728, y: -1440, mode: mode(3840, 2160, scale: 1))
        let targets = try DisplayTopology.targets(topology: .extended, sources: [virtual(50), virtual(51)],
                                                  modes: [hidpi(size), hidpi(size)], dimensions: size, physical: [builtin, external])
        var shared = targets
        for index in shared.indices where shared[index].physical { shared[index].mirror = 50 }
        XCTAssertFalse(DisplayTopology.matches(shared, targets: targets, sourceID: 50))
        var moved = targets
        let secondary = try XCTUnwrap(moved.firstIndex { $0.id == 51 })
        moved[secondary].x = 0
        XCTAssertFalse(DisplayTopology.matches(moved, targets: targets, sourceID: 50))
        var unbound = targets
        let panel = try XCTUnwrap(unbound.firstIndex { $0.id == 2 })
        unbound[panel].mirror = 0
        XCTAssertFalse(DisplayTopology.matches(unbound, targets: targets, sourceID: 50))
    }

    func testExtendedAllowsPanelModeToFollowItsOwnFramebuffer() throws {
        let builtin = display(1, physical: true, main: true)
        let external = display(2, physical: true, x: 2000, mode: mode(2560, 1440))
        let targets = try DisplayTopology.targets(topology: .extended, sources: [virtual(50), virtual(51)],
                                                  modes: [hidpi(size), hidpi(size)], dimensions: size, physical: [builtin, external])
        var live = targets
        for index in live.indices where live[index].physical { live[index].mode = hidpi(size) }
        XCTAssertTrue(DisplayTopology.matches(live, targets: targets, sourceID: 50))
    }

    func testRetiringFramebufferIsDemotedOntoTheNewMain() throws {
        let old = virtual(42, mode: hidpi(Dimensions(1400, 630)))
        var oldMain = old
        oldMain.main = true
        let targets = try DisplayTopology.targets(topology: .extended, sources: [virtual(50), virtual(51)],
                                                  modes: [hidpi(size), hidpi(size)], dimensions: size,
                                                  physical: [display(1, physical: true, main: true), display(2, physical: true, x: 1800)],
                                                  retiring: [oldMain])
        let retired = try XCTUnwrap(targets.first { $0.id == 42 })
        XCTAssertFalse(retired.main)
        XCTAssertEqual(retired.mirror, 50)
        XCTAssertTrue(retired.skipMode)
        XCTAssertEqual(targets.first { $0.main }?.id, 50)
        XCTAssertTrue(DisplayTopology.matches(targets, targets: targets, sourceID: 50))
    }

    func testRestoreStillReturnsThePreSessionLayout() throws {
        let saved = [
            display(1, physical: true, main: true, mode: mode(1728, 1117)),
            display(2, physical: true, x: 1728, y: -1440, mode: mode(3840, 2160, scale: 1))
        ]
        let extended = try DisplayTopology.targets(topology: .extended, sources: [virtual(50), virtual(51)],
                                                   modes: [hidpi(size), hidpi(size)], dimensions: size, physical: saved)
        XCTAssertNotEqual(extended.filter(\.physical).map(\.mirror), saved.map(\.mirror))
        guard case .restore(let restored) = try RestorePlan.outcome(saved: saved, live: saved) else {
            return XCTFail("pre-session snapshot should restore")
        }
        XCTAssertEqual(restored.map(\.id), [1, 2])
        XCTAssertEqual(restored.map(\.mirror), [0, 0])
        XCTAssertEqual(restored.map(\.x), [0, 1728])
        XCTAssertEqual(restored.map(\.y), [0, -1440])
        XCTAssertTrue(restored[0].mode.matches(saved[0].mode))
        XCTAssertTrue(restored[1].mode.matches(saved[1].mode))
        XCTAssertTrue(restored[0].main)
        XCTAssertFalse(restored[1].main)
    }

    func testExtendedRejectsBadSourcesAndUnsupportedSizes() {
        let physical = [display(1, physical: true, main: true), display(2, physical: true, x: 1800)]
        XCTAssertThrowsError(try DisplayTopology.targets(topology: .extended, sources: [virtual(50)], modes: [hidpi(size)],
                                                         dimensions: size, physical: physical))
        XCTAssertThrowsError(try DisplayTopology.targets(topology: .extended, sources: [physical[0], virtual(51)], modes: [hidpi(size), hidpi(size)],
                                                         dimensions: size, physical: physical))
        XCTAssertThrowsError(try DisplayTopology.targets(topology: .extended, sources: [virtual(50), virtual(51)], modes: [hidpi(size), hidpi(size)],
                                                         dimensions: .init(4000, 900), physical: physical))
        var mirrored = virtual(50)
        mirrored.mirror = 9
        XCTAssertThrowsError(try DisplayTopology.targets(topology: .extended, sources: [mirrored, virtual(51)], modes: [hidpi(size), hidpi(size)],
                                                         dimensions: size, physical: physical))
    }

    func testMirrorRollbackCanDemoteSeveralNewFramebuffers() throws {
        let kept = virtual(42)
        var keptMain = kept
        keptMain.main = true
        let physical = [display(1, physical: true, mirror: 42), display(2, physical: true, mirror: 42)]
        let retiring = [virtual(50), virtual(51)]
        let targets = try DisplayTopology.targets(topology: .mirrorAll, sources: [keptMain], modes: [hidpi(Dimensions(1400, 630))],
                                                  dimensions: Dimensions(1400, 630), physical: physical, retiring: retiring)
        XCTAssertEqual(targets.map(\.id), [50, 51, 42, 1, 2])
        XCTAssertEqual(targets.filter { !$0.physical && $0.id != 42 }.map(\.mirror), [42, 42])
        XCTAssertEqual(targets.first { $0.main }?.id, 42)
        XCTAssertEqual(targets.filter(\.physical).map(\.mirror), [42, 42])
    }

    private func overlaps(_ placed: [ExtendedArrangement.Placement], size: Dimensions) -> Bool {
        for i in placed.indices {
            for j in placed.indices where i < j {
                let a = placed[i], b = placed[j]
                let separated = a.x + Int32(size.width) <= b.x || b.x + Int32(size.width) <= a.x ||
                    a.y + Int32(size.height) <= b.y || b.y + Int32(size.height) <= a.y
                if !separated { return true }
            }
        }
        return false
    }
}

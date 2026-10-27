import XCTest
@testable import RemoteFitCore

final class OperationOrderTests: XCTestCase {
    func testRemovingPreviousApplicationPreservesOtherSavedActionsAndShortcuts() throws {
        let data = Data(#"{"floatingActions":["resolution","previousApplication","maximizeWindow"],"floatingActionIcons":{"previousApplication":"arrow.left.arrow.right"},"toolbarSide":"left","operationOrder":["builtin:previousApplication","shortcut:copy","builtin:resolution","builtin:maximizeWindow"],"namedShortcuts":[{"id":"copy","name":"复制","key":{"code":8,"modifiers":1048576,"label":"⌘C"}}]}"#.utf8)
        let value = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(value.toolbarSide, .left)
        XCTAssertEqual(value.floatingActions, [.maximizeWindow])
        XCTAssertEqual(value.namedShortcuts.first?.name, "复制")
        XCTAssertEqual(value.operationOrder, ["shortcut:copy", "builtin:maximizeWindow"])
        XCTAssertNil(value.floatingActionIcons["previousApplication"])
        XCTAssertEqual(value.enabledOperations.map(\.id), value.operationOrder)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(value)), value)
    }

    private func preferences() -> Preferences {
        var value = Preferences()
        value.namedShortcuts = [
            .init(id: "copy", name: "复制", key: .init(code: 8, modifiers: 1 << 20, label: "⌘C")),
            .init(id: "paste", name: "粘贴", key: .init(code: 9, modifiers: 1 << 20, label: "⌘V"))
        ]
        value.floatingActions = [.runningApplications, .centerWindow]
        return value
    }

    func testLegacyPreferencesRetainListOrderWithoutAnOrderField() throws {
        let data = Data(#"{"floatingActions":["resolution"],"namedShortcuts":[{"id":"old","name":"复制","key":{"code":8,"modifiers":1048576,"label":"⌘C"}}]}"#.utf8)
        let value = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(value.orderedOperations.map(\.id), ["shortcut:old"] + FloatingAction.configurableActions.filter { $0 != .maximizeWindow }.map { "builtin:\($0.rawValue)" })
        XCTAssertEqual(value.enabledOperations.map(\.id), ["shortcut:old"])
    }

    func testBuiltinAndCustomCanMoveAcrossEachOtherAndSurviveReload() throws {
        var value = preferences()
        value.moveOperations(from: IndexSet(integer: 3), to: 0)
        XCTAssertEqual(Array(value.orderedOperations.map(\.id).prefix(4)), ["builtin:centerWindow", "shortcut:copy", "shortcut:paste", "builtin:runningApplications"])
        value.moveOperations(from: IndexSet(integer: 1), to: value.orderedOperations.count)
        XCTAssertEqual(value.orderedOperations.last?.id, "shortcut:copy")
        let decoded = try JSONDecoder().decode(Preferences.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(decoded.orderedOperations, value.orderedOperations)
        XCTAssertEqual(decoded.enabledOperations, value.enabledOperations)
    }

    func testDisabledOperationsKeepTheirSlotWhenEnabledAgain() {
        var value = preferences()
        value.operationOrder = ["builtin:centerWindow", "shortcut:paste", "shortcut:copy"]
        let fullOrder = value.orderedOperations.map(\.id)
        value.namedShortcuts[1].enabled = false
        value.floatingActions.removeAll { $0 == .centerWindow }
        XCTAssertEqual(value.orderedOperations.map(\.id), fullOrder)
        XCTAssertEqual(value.enabledOperations.first?.id, "shortcut:copy")
        value.namedShortcuts[1].enabled = true
        value.floatingActions.append(.centerWindow)
        XCTAssertEqual(Array(value.enabledOperations.map(\.id).prefix(3)), ["builtin:centerWindow", "shortcut:paste", "shortcut:copy"])
    }

    func testRenamingDoesNotMoveAnOperationAndNewOperationsAppend() {
        var value = preferences()
        value.moveOperations(from: IndexSet(integer: 0), to: value.orderedOperations.count)
        let before = value.orderedOperations.map(\.id)
        value.namedShortcuts[0].name = "复制内容"
        XCTAssertEqual(value.orderedOperations.map(\.id), before)
        value.namedShortcuts.append(.init(id: "save", name: "保存", key: .init(code: 1, modifiers: 1 << 20, label: "⌘S")))
        XCTAssertEqual(value.orderedOperations.map(\.id), before + ["shortcut:save"])
    }

    func testDeletedUnknownAndDuplicateIDsDoNotBreakOrdering() {
        var value = preferences()
        value.operationOrder = ["unknown", "shortcut:paste", "shortcut:paste", "builtin:undoWindowLayout", "shortcut:copy"]
        value.namedShortcuts.removeAll { $0.id == "copy" }
        let ids = value.orderedOperations.map(\.id)
        XCTAssertEqual(ids.first, "shortcut:paste")
        XCTAssertEqual(ids.count, FloatingAction.configurableActions.count)
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testBuiltinAndShortcutWithSameRawIdentifierRemainDistinct() {
        var value = preferences()
        value.namedShortcuts[0].id = "runningApplications"
        value.operationOrder = ["builtin:runningApplications", "shortcut:runningApplications"]
        XCTAssertEqual(Array(value.enabledOperations.map(\.id).prefix(2)), ["builtin:runningApplications", "shortcut:runningApplications"])
    }

    func testMovingSeveralRowsPreservesTheirRelativeOrder() {
        var value = preferences()
        let before = value.orderedOperations.map(\.id)
        value.moveOperations(from: IndexSet([0, 2]), to: 4)
        XCTAssertEqual(value.orderedOperations.map(\.id), [before[1], before[3], before[0], before[2]] + Array(before.dropFirst(4)))
    }
    func testPersistentActionsNeverAppearInConfigurableOrOrderedOperations() throws {
        let data = Data(#"{"floatingActions":["settings","restoreDisplay","resolution","leftWorkspace"],"operationOrder":["builtin:settings","builtin:resolution","builtin:restoreDisplay","builtin:leftWorkspace"]}"#.utf8)
        let value = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertFalse(value.orderedOperations.contains { $0.id == "builtin:settings" || $0.id == "builtin:restoreDisplay" || $0.id == "builtin:leftWorkspace" || $0.id == "builtin:resolution" })
        XCTAssertTrue(value.enabledOperations.isEmpty)
        XCTAssertEqual(FloatingAction.persistentActions, [.resolution, .settings, .restoreDisplay])
        var disabled = value
        disabled.floatingActions = []
        XCTAssertTrue(disabled.enabledOperations.isEmpty)
        XCTAssertEqual(FloatingAction.persistentActions.count, 3)
    }

    func testLegacyResolutionMovesToFixedAreaWithoutDeletingSameNamedShortcut() throws {
        let data = Data(#"{"floatingActions":["resolution","runningApplications"],"operationOrder":["builtin:resolution","shortcut:resolution","builtin:runningApplications"],"namedShortcuts":[{"id":"resolution","name":"我的操作","key":{"code":8,"modifiers":1048576,"label":"⌘C"}}]}"#.utf8)
        let value = try JSONDecoder().decode(Preferences.self, from: data)
        XCTAssertEqual(value.enabledOperations.map(\.id), ["shortcut:resolution", "builtin:runningApplications"])
        XCTAssertEqual(value.operationOrder, ["shortcut:resolution", "builtin:runningApplications"])
        XCTAssertTrue(FloatingAction.persistentActions.contains(.resolution))
    }

}

final class FillWindowActionTests: XCTestCase {
    func testFillWindowIsConfigurableDefaultAndRoundTrips() throws {
        XCTAssertEqual(FloatingAction.fillWindow.title, "铺满")
        XCTAssertEqual(FloatingAction.fillWindow.symbol, ShortcutIcon.fillWindow.rawValue)
        XCTAssertTrue(FloatingAction.configurableActions.contains(.fillWindow))
        XCTAssertTrue(Preferences().floatingActions.contains(.fillWindow))
        XCTAssertTrue(Preferences().orderedOperations.map(\.id).contains("builtin:fillWindow"))
        let data = Data(#"{"floatingActions":["runningApplications","fillWindow"]}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(Preferences.self, from: data).floatingActions, [.runningApplications, .fillWindow, .minimizeWindow, .showDesktop])
    }
}

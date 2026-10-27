import AppKit
import RemoteFitCore

/// UI ownership and busy state stay on the main actor; blocking AX IPC does not.
@MainActor
final class WindowController {
    private let worker: WindowControllerWorker
    private(set) var performing = false

    init(logURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/RemoteFit/WindowActions.log")) {
        worker = WindowControllerWorker(logURL: logURL)
    }

    func perform(_ action: FloatingAction, targetPID: pid_t?, screen: NSScreen, workspace: CGRect? = nil) async throws {
        guard !performing else { return }
        performing = true
        defer { performing = false }
        try Task.checkCancellation()
        try await worker.perform(action, targetPID: targetPID, screen: Self.accessibilityFrame(screen),
                                 screens: NSScreen.screens.map(Self.accessibilityFrame), workspace: workspace)
    }

    @discardableResult
    func place(_ target: CGRect, window: AXUIElement, pid: pid_t, placementArea: CGRect? = nil) async throws -> WindowPlacementResult {
        try await place(target, handle: WindowAXHandle(element: window), pid: pid, placementArea: placementArea)
    }

    @discardableResult
    func place(_ target: CGRect, handle: WindowAXHandle, pid: pid_t, placementArea: CGRect? = nil) async throws -> WindowPlacementResult {
        guard !performing else { throw FitError.message("窗口正在调整，请稍后重试") }
        performing = true
        defer { performing = false }
        try Task.checkCancellation()
        return try await worker.place(target, handle: handle, pid: pid, placementArea: placementArea)
    }

    func moveAsideFromToolbar(_ candidate: ApplicationWindowCatalog.Window, toolbar: CGRect, screen: CGRect, side: ToolbarSide) async {
        guard !performing, !Task.isCancelled else { return }
        performing = true
        defer { performing = false }
        await worker.moveAsideFromToolbar(candidate, toolbar: toolbar, screen: screen, side: side)
    }

    func fillCollapsedToolbar(_ candidate: ApplicationWindowCatalog.Window, toolbar: CGRect, screen: CGRect, side: ToolbarSide) async {
        guard !performing, !Task.isCancelled else { return }
        performing = true
        defer { performing = false }
        await worker.fillCollapsedToolbar(candidate, toolbar: toolbar, screen: screen, side: side)
    }

    static func accessibilityFrame(_ screen: NSScreen) -> CGRect {
        let top = NSScreen.screens.first?.frame.maxY ?? screen.frame.maxY
        let visible = screen.visibleFrame
        return CGRect(x: visible.minX, y: top - visible.maxY, width: visible.width, height: visible.height)
    }
}

/// Retained AX reference transferred between the UI coordinator and AX workers.
/// All reads and writes of the referenced remote element happen on workers.
struct WindowAXHandle: @unchecked Sendable {
    let element: AXUIElement
}

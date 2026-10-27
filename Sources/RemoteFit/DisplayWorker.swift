import Foundation
import CoreGraphics
import IOKit.graphics
import NativeDisplay
import RemoteFitCore

struct CommitRequest: Codable { var targets: [DisplayState] }

enum DisplayWorker {
    static func mode(_ m: CGDisplayMode) -> DisplayMode {
        .init(width: m.width, height: m.height, pixelWidth: m.pixelWidth, pixelHeight: m.pixelHeight,
              refresh: m.refreshRate, modeID: Int(m.ioDisplayModeID))
    }
    static func snapshot() throws -> [DisplayState] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32), count: UInt32 = 0
        try check(CGGetOnlineDisplayList(32, &ids, &count), "读取显示器")
        return ids.prefix(Int(count)).compactMap { id in
            guard let m = CGDisplayCopyDisplayMode(id) else { return nil }
            let bounds = CGDisplayBounds(id)
            let vendor = CGDisplayVendorNumber(id), model = CGDisplayModelNumber(id), serial = CGDisplaySerialNumber(id)
            let builtin = CGDisplayIsBuiltin(id) != 0
            // CG display UUIDs remain stable across display-ID reassignment.
            let uuid = RFDisplayUUID(id)
            // Only our own virtual display is "not physical"; system or remote-tool virtual
            // screens (headless Mac) are base displays like a real monitor.
            let physical = vendor != ActivationBase.ownVendor
            return DisplayState(id: id, uuid: uuid,
                                hardwareKey: "\(vendor):\(model):\(serial):\(builtin)",
                                physical: physical, main: CGDisplayIsMain(id) != 0,
                                x: Int32(bounds.origin.x), y: Int32(bounds.origin.y),
                                mirror: CGDisplayMirrorsDisplay(id), mode: mode(m))
        }
    }
    static func check(_ result: CGError, _ stage: String) throws {
        guard result == .success else { throw FitError.message("\(stage)失败（\(result.rawValue)）") }
    }
    static func normalizeRestoration(_ targets: [DisplayState]) -> [DisplayState] {
        targets.map { target in
            guard target.physical, target.mirror == 0, CGDisplayIsBuiltin(target.id) != 0 else { return target }
            let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
            let modes = (CGDisplayCopyAllDisplayModes(target.id, options) as? [CGDisplayMode]) ?? []
            let native = modes.first { $0.ioFlags & UInt32(kDisplayModeNativeFlag) != 0 }
            var result = target
            result.mode = FullHeightRestore.mode(saved: target.mode,
                available: modes.filter { $0.ioFlags & UInt32(kDisplayModeValidFlag) != 0 }.map(mode),
                nativePixels: native.map { Dimensions($0.pixelWidth, $0.pixelHeight) }, builtin: true)
            return result
        }
    }
    @discardableResult
    static func commit(_ targets: [DisplayState]) throws -> Int {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let chosen: [(DisplayState, CGDisplayMode?)] = try targets.map { d in
            if d.skipMode { return (d, nil) }
            var modes = (CGDisplayCopyAllDisplayModes(d.id, options) as? [CGDisplayMode]) ?? []
            if let current = CGDisplayCopyDisplayMode(d.id) { modes.insert(current, at: 0) }
            let matching = modes.filter { mode($0).matches(d.mode) }
            // Preserve the requested refresh variant (for example 59.94 vs 60 Hz).
            let exactID = matching.first { Int($0.ioDisplayModeID) == d.mode.modeID }
            guard let selected = exactID ?? matching.min(by: { abs($0.refreshRate - d.mode.refresh) < abs($1.refreshRate - d.mode.refresh) }) else {
                throw FitError.message("当前显示器不支持目标模式 \(d.mode.width)×\(d.mode.height) HiDPI 超清渲染。")
            }
            return (d, selected)
        }
        let changes = chosen.map { d, selected in
            let current = CGDisplayCopyDisplayMode(d.id)
            let modeChanged = selected.map { $0.ioDisplayModeID != current?.ioDisplayModeID } ?? false
            let bounds = CGDisplayBounds(d.id)
            let originChanged = !d.skipOrigin && (bounds.origin.x != CGFloat(d.x) || bounds.origin.y != CGFloat(d.y) ||
                                                 (d.main && CGDisplayIsMain(d.id) == 0))
            return (d, selected, modeChanged, CGDisplayMirrorsDisplay(d.id) != d.mirror, originChanged)
        }
        let changedCount = changes.filter { $0.2 || $0.3 || $0.4 }.count
        guard changedCount > 0 else { return 0 }
        var configuration: CGDisplayConfigRef?
        try check(CGBeginDisplayConfiguration(&configuration), "开始配置")
        guard let configuration else { throw FitError.message("无法初始化 CoreGraphics 显示配置会话。") }
        var submitted = false
        defer { if !submitted { CGCancelDisplayConfiguration(configuration) } }
        // Unmirror the incoming source before adding mirrors, including rollback
        // where it was previously a follower. This avoids transient mirror cycles.
        for (d, _, _, mirrorChanged, _) in changes where mirrorChanged && d.mirror == 0 {
            try check(CGConfigureDisplayMirrorOfDisplay(configuration, d.id, 0), "解除源屏幕镜像")
        }
        for (d, _, _, mirrorChanged, _) in changes where mirrorChanged && d.mirror != 0 {
            try check(CGConfigureDisplayMirrorOfDisplay(configuration, d.id, d.mirror), "配置镜像")
        }
        for (d, selected, modeChanged, _, _) in changes {
            if modeChanged, let selected { try check(CGConfigureDisplayWithDisplayMode(configuration, d.id, selected, nil), "配置分辨率") }
        }
        for (d, _, _, _, originChanged) in changes.sorted(by: { !$0.0.main && $1.0.main }) {
            if originChanged { try check(CGConfigureDisplayOrigin(configuration, d.id, d.x, d.y), "配置排列") }
        }
        let result = CGCompleteDisplayConfiguration(configuration, .forSession)
        submitted = true
        try check(result, "提交配置")
        return changedCount
    }
    static func execute(_ args: [String]) -> Int32 {
        do {
            guard let command = args.first else { throw FitError.message("缺少命令") }
            let result: Data
            switch command {
            case "snapshot":
                result = try JSONEncoder().encode(snapshot())
            case "commit":
                let request = try JSONDecoder().decode(CommitRequest.self, from: FileHandle.standardInput.readDataToEndOfFile())
                let changed = try commit(request.targets)
                result = Data("{\"changedDisplays\":\(changed)}".utf8)
            case "normalize-restore":
                let request = try JSONDecoder().decode(CommitRequest.self, from: FileHandle.standardInput.readDataToEndOfFile())
                result = try JSONEncoder().encode(normalizeRestoration(request.targets))
            default: throw FitError.message("未知命令")
            }
            FileHandle.standardOutput.write(result)
            return 0
        } catch {
            FileHandle.standardError.write(Data(error.localizedDescription.utf8))
            return 1
        }
    }
}

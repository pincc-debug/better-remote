import Foundation
import Darwin
import IOKit.pwr_mgt
import RemoteFitCore

/// Connection signals are read-only. Optional UU identity uses a single programmatic window cycle.
/// RustDesk identity is the CM window title, cached until that `--cm` process exits.
actor RemoteSessionProbe {
    private var uuReadAttempted = false
    private var uuIdentifyFailures = 0
    private var uuIdentifyStatus: String?
    private var uuDevice: RemoteDevice?
    private var rustDeskIdentity = RustDeskSessionIdentity()
    /// After within-call AX retries, allow a few more sample cycles before stopping.
    private static let uuIdentifyMaxFailures = 3
    private var anyDeskTrace = AnyDeskTraceReader()
    // Standard installed client location documented by AnyDesk:
    // https://support.anydesk.com/what-are-trace-files
    private var anyDeskServiceTrace = AnyDeskTraceReader(url: URL(fileURLWithPath: "/var/log/anydesk.trace"))

    func sample(identifyUU: Bool = false) async -> RemoteSessionSnapshot {
        var snapshot = RemoteSessionSnapshot()
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let entries = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else {
            var unavailable = RemoteSessionSnapshot(unknown: Set(RemoteSoftware.allCases))
            unavailable.recheckAfter = 2
            return await applyingRustDesk(unavailable)
        }
        var assertions: [RemotePowerAssertion] = []
        var anyDeskBackends: [Int32: Date] = [:]
        for (pid, values) in entries {
            // Most power notifications belong to audio, browsers or the OS.
            // Inspect names first; do not resolve paths for unrelated owners.
            let relevant = values.filter {
                let name = $0[kIOPMAssertionNameKey] as? String
                guard let name else { return false }
                return RemoteSessionEvidence.uuConnectionAssertionNames.contains(name) ||
                    name == RemoteSessionEvidence.toDeskConnectionAssertionName || name == RemoteSessionEvidence.anyDeskAssertionName
            }
            guard !relevant.isEmpty else { continue }
            guard let path = Self.executable(pid.int32Value) else {
                for value in relevant {
                    let name = value[kIOPMAssertionNameKey] as? String ?? ""
                    snapshot.unknown.insert(name == RemoteSessionEvidence.anyDeskAssertionName ? .anyDesk :
                        (RemoteSessionEvidence.uuConnectionAssertionNames.contains(name) ? .uu : .toDesk))
                }
                continue
            }
            for value in relevant {
                guard let type = value[kIOPMAssertionTypeKey] as? String,
                      let name = value[kIOPMAssertionNameKey] as? String,
                      let level = value[kIOPMAssertionLevelKey] as? NSNumber else { continue }
                assertions.append(.init(executable: path, type: type, name: name, level: level.intValue))
                if Self.isAnyDeskRequest(executable: path, type: type, name: name, level: level.intValue) {
                    if let birth = Self.processBirth(pid.int32Value) { anyDeskBackends[pid.int32Value] = birth }
                    else { snapshot.unknown.insert(.anyDesk) }
                }
            }
        }
        snapshot = Self.resolve(assertions: assertions, unknown: snapshot.unknown) {
            Self.processPaths().map { Set($0.values) }
        }
        let statuses = [anyDeskTrace.sample(backends: anyDeskBackends), anyDeskServiceTrace.sample(backends: anyDeskBackends)]
        let status: AnyDeskSessionLog.Status = statuses.contains(.connected) ? .connected :
            (statuses.contains(.disconnected) ? .disconnected : .unknown)
        Self.mergeAnyDesk(status, hasRequest: !anyDeskBackends.isEmpty, into: &snapshot)
        if !snapshot.active.contains(.uu), !snapshot.unknown.contains(.uu) {
            uuReadAttempted = false
            uuIdentifyFailures = 0
            uuIdentifyStatus = nil
            uuDevice = nil
        }
        if identifyUU, snapshot.active.contains(.uu), !uuReadAttempted {
            let result = await UUWindowIdentification.identify()
            if Task.isCancelled {
                uuReadAttempted = false
                uuIdentifyFailures = 0
                uuIdentifyStatus = nil
                uuDevice = nil
            } else if !Self.uuConnectedNow() {
                snapshot.active.remove(.uu)
                uuDevice = nil
                uuReadAttempted = false
                uuIdentifyFailures = 0
                uuIdentifyStatus = nil
            } else if let device = result.device {
                uuDevice = device
                uuIdentifyStatus = result.status
                uuIdentifyFailures = 0
                uuReadAttempted = true
            } else {
                uuDevice = nil
                uuIdentifyStatus = result.status
                if Self.isTerminalIdentifyFailure(result.status) {
                    uuReadAttempted = true
                } else {
                    uuIdentifyFailures += 1
                    if uuIdentifyFailures >= Self.uuIdentifyMaxFailures {
                        uuReadAttempted = true
                    }
                }
            }
        }
        let uuActive = snapshot.active.contains(.uu)
        snapshot.uuDevice = uuActive ? uuDevice : nil
        snapshot.uuIdentifyStatus = uuActive ? uuIdentifyStatus : nil
        snapshot.uuIdentifyExhausted = uuActive && uuReadAttempted && uuDevice == nil
        if uuActive { snapshot.recheckAfter = 1 }
        return await applyingRustDesk(snapshot)
    }

    /// `--cm` means a session even when its window title has no peer id yet.
    /// No device row is created until a peer id is known.
    private func applyingRustDesk(_ input: RemoteSessionSnapshot) async -> RemoteSessionSnapshot {
        var snapshot = input
        switch await RustDeskSessionReader.read() {
        case .absent, .idle:
            _ = rustDeskIdentity.sample(sessionConnected: false, visiblePeerIDs: [])
            snapshot.active.remove(.rustDesk)
            snapshot.unknown.remove(.rustDesk)
            snapshot.rustDeskDevice = nil
            snapshot.rustDeskDevices = []
        case .unknown:
            snapshot.unknown.insert(.rustDesk)
            snapshot.active.remove(.rustDesk)
            scheduleRecheck(1, on: &snapshot)
        case .connected(let peerIDs):
            snapshot.unknown.remove(.rustDesk)
            snapshot.active.insert(.rustDesk)
            let sampled = rustDeskIdentity.sample(sessionConnected: true, visiblePeerIDs: peerIDs)
            snapshot.rustDeskDevice = sampled.sessionDevice
            snapshot.rustDeskDevices = sampled.devices
            scheduleRecheck(1, on: &snapshot)
        }
        return snapshot
    }

    private func scheduleRecheck(_ interval: TimeInterval, on snapshot: inout RemoteSessionSnapshot) {
        snapshot.recheckAfter = min(snapshot.recheckAfter ?? interval, interval)
    }

    /// User tapped「重试」on the panel hint: clear the one-shot latch so the next sample identifies again.
    func retryUUIdentify() {
        uuReadAttempted = false
        uuIdentifyFailures = 0
        uuIdentifyStatus = nil
        uuDevice = nil
    }

    private static func isTerminalIdentifyFailure(_ status: String) -> Bool {
        ["permission_missing", "app_missing", "multiple_controllers"].contains(status)
    }

    nonisolated static func uuConnectedNow() -> Bool {
        var raw: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&raw) == kIOReturnSuccess,
              let entries = raw?.takeRetainedValue() as? [NSNumber: [[String: Any]]] else { return false }
        for (pid, values) in entries {
            guard values.contains(where: { RemoteSessionEvidence.uuConnectionAssertionNames.contains($0[kIOPMAssertionNameKey] as? String ?? "") }),
                  let path = executable(pid.int32Value) else { continue }
            let evidence = values.compactMap { value -> RemotePowerAssertion? in
                guard let name = value[kIOPMAssertionNameKey] as? String,
                      let type = value[kIOPMAssertionTypeKey] as? String,
                      let level = value[kIOPMAssertionLevelKey] as? NSNumber else { return nil }
                return .init(executable: path, type: type, name: name, level: level.intValue)
            }
            if RemoteSessionEvidence.uuConnected(evidence) { return true }
        }
        return false
    }

    nonisolated static func isAnyDeskRequest(executable: String, type: String, name: String, level: Int) -> Bool {
        executable.hasSuffix("/AnyDesk.app/Contents/MacOS/AnyDesk") && level == 255 &&
            name == RemoteSessionEvidence.anyDeskAssertionName &&
            ["NoDisplaySleepAssertion", "PreventUserIdleDisplaySleep"].contains(type)
    }

    nonisolated static func mergeAnyDesk(_ status: AnyDeskSessionLog.Status, hasRequest: Bool, into snapshot: inout RemoteSessionSnapshot) {
        if hasRequest {
            switch status {
            case .connected: snapshot.active.insert(.anyDesk); snapshot.unknown.remove(.anyDesk)
            case .unknown: snapshot.unknown.insert(.anyDesk)
            case .disconnected: break
            }
        }
        // Acceptance need not change an assertion; bounded incremental reads catch
        // it without polling processes or logs while AnyDesk is idle.
        if hasRequest || snapshot.unknown.contains(.anyDesk) { snapshot.recheckAfter = 1 }
    }

    private static func processBirth(_ pid: pid_t) -> Date? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == size else { return nil }
        return Date(timeIntervalSince1970: Double(info.pbi_start_tvsec) + Double(info.pbi_start_tvusec) / 1_000_000)
    }

    nonisolated static func resolve(assertions: [RemotePowerAssertion], unknown: Set<RemoteSoftware> = [],
                                   processes: () -> Set<String>?) -> RemoteSessionSnapshot {
        var snapshot = RemoteSessionSnapshot(unknown: unknown)
        if RemoteSessionEvidence.uuConnected(assertions) { snapshot.active.insert(.uu) }
        // ToDesk needs both pieces of evidence. No session-process enumeration
        // is needed at all when its service does not hold the connection assertion.
        if RemoteSessionEvidence.toDeskHasConnectionAssertion(assertions) {
            if let processes = processes() {
                if RemoteSessionEvidence.toDeskConnected(processes: processes, assertions: assertions) {
                    snapshot.active.insert(.toDesk)
                }
            } else { snapshot.unknown.insert(.toDesk) }
        }
        return snapshot
    }

    private static func executable(_ pid: pid_t) -> String? {
        var bytes = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &bytes, UInt32(bytes.count)) > 0 else { return nil }
        return String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func processPaths() -> [pid_t: String]? {
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return nil }
        let capacity = Int(estimated) + 128
        var pids = [pid_t](repeating: 0, count: capacity)
        let count = proc_listallpids(&pids, Int32(capacity * MemoryLayout<pid_t>.size))
        guard count > 0, count < capacity else { return nil }
        var paths: [pid_t: String] = [:]
        for pid in pids.prefix(Int(count)) {
            var bytes = [CChar](repeating: 0, count: 128)
            guard proc_name(pid, &bytes, UInt32(bytes.count)) > 0 else { continue }
            let name = String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard name == "ToDesk_Session" else { continue }
            guard let path = executable(pid) else { return nil }
            paths[pid] = path
        }
        return paths
    }

}

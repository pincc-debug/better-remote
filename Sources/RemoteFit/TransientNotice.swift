import AppKit
import SwiftUI

/// Restarting the lifetime invalidates earlier deadlines, including sleepers that
/// finish after cancellation. No modal run loop or application activation is used.
@MainActor
final class NoticeLifetime {
    static let duration: Duration = .seconds(3)
    private let sleep: @MainActor (Duration) async throws -> Void
    private var task: Task<Void, Never>?
    private var generation = 0

    init(sleep: @escaping @MainActor (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) {
        self.sleep = sleep
    }

    func restart(onExpire: @escaping @MainActor () -> Void) {
        cancel()
        let current = generation
        let sleep = sleep
        task = Task { @MainActor [weak self] in
            do { try await sleep(Self.duration) } catch { return }
            guard !Task.isCancelled, let self, generation == current else { return }
            task = nil
            onExpire()
        }
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
    }

    deinit { task?.cancel() }
}

private final class NoticePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class TransientNotice {
    private let lifetime = NoticeLifetime()
    private var panel: NoticePanel?

    func show(_ title: String, detail: String? = nil, in area: CGRect) {
        guard area.width > 0, area.height > 0 else { return }
        lifetime.cancel()
        let detail = detail?.trimmingCharacters(in: .whitespacesAndNewlines)
        let visibleDetail = detail?.isEmpty == false && detail != title ? detail : nil
        let titleWidth = (title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 14, weight: .medium)]).width
        let detailWidth = ((visibleDetail ?? "") as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12)]).width
        let width = min(420, max(1, area.width - 32), max(180, ceil(max(titleWidth, detailWidth)) + 76))
        let content = NoticeContent(title: title, detail: visibleDetail)
            .frame(width: width)
        let host = NSHostingView(rootView: content)
        let height = min(max(48, host.fittingSize.height), max(1, area.height - 32))
        host.sizingOptions = []
        let window = panel ?? makePanel()
        window.contentView = NativeGlassView(content: host, cornerRadius: DesignTokens.radiusLg,
                                             contentBackdrop: DesignTokens.NS.glassBackdrop)
        window.setFrame(CGRect(x: area.midX - width / 2,
                               y: max(area.minY + 16, area.maxY - height - 32),
                               width: width, height: height), display: true)
        panel = window
        window.orderFrontRegardless()
        NSAccessibility.post(element: window, notification: .announcementRequested, userInfo: [
            .announcement: [title, visibleDetail].compactMap { $0 }.joined(separator: "，"),
            .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
        lifetime.restart { [weak self] in self?.dismiss() }
    }

    func dismiss() {
        lifetime.cancel()
        panel?.orderOut(nil)
        panel?.contentView = nil
    }

    private func makePanel() -> NoticePanel {
        let window = NoticePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                 backing: .buffered, defer: false)
        window.title = "Better Remote 提示"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .statusBar
        window.hidesOnDeactivate = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        return window
    }
}

private struct NoticeContent: View {
    let title: String
    let detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
    }
}

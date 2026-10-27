import AppKit
import SwiftUI
import RemoteFitCore

enum FeedbackCopy {
    static let page = "关于"
    static let slogan = "手机远程 Mac，画面刚好铺满。"
    static let checkUpdate = "检查更新"
    static let section = "意见反馈"
    static let help = "帮助中心"
    static let placeholder = "遇到什么问题，或想提什么建议"
    static let attach = "上传日志"
    static let note = "方便查问题，不含隐私内容。"
    static let coffee = "请作者喝咖啡"
    static let send = "发送"
    static let copy = "复制编号"
    static let failed = "没能发送，检查网络后重试"
    static func sent(_ id: String) -> String { "已发送，编号 \(id)" }
}

@MainActor
final class FeedbackModel: ObservableObject {
    @Published var message = ""
    @Published var attachLogs = true
    @Published var sending = false
    @Published var sentID: String?
    @Published var failed = false

    var trimmed: String {
        message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func send() {
        let text = trimmed
        guard !sending, !text.isEmpty else { return }
        sending = true
        sentID = nil
        failed = false
        let attach = attachLogs
        Task { @MainActor in
            do {
                sentID = try await DiagnosticLogUpload.submit(message: text, attachLogs: attach)
            } catch {
                failed = true
            }
            sending = false
        }
    }

    func copyIdentifier() {
        guard let sentID else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(sentID, forType: .string)
    }
}

/// About page actions: three equal pills, then a lighter coffee row.
struct FeedbackSettings: View {
    @ObservedObject var model: FeedbackModel
    var showsCheckUpdate: Bool = true
    @State private var hoveringCheck = false
    @State private var hoveringHelp = false
    @State private var hoveringFeedback = false
    @State private var hoveringCoffee = false

    private let pillRowWidth: CGFloat = 460

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: DesignTokens.spacingSm) {
                if showsCheckUpdate {
                    aboutPill(
                        title: FeedbackCopy.checkUpdate,
                        symbol: "arrow.triangle.2.circlepath",
                        hovering: hoveringCheck
                    ) {
                        AppUpdater.shared.checkForUpdates()
                    }
                    .onHover { hoveringCheck = $0 }
                    .disabled(!AppUpdater.shared.isAvailable)
                    .accessibilityLabel(FeedbackCopy.checkUpdate)
                }

                aboutPill(
                    title: FeedbackCopy.help,
                    symbol: "questionmark.circle",
                    hovering: hoveringHelp
                ) {
                    NSWorkspace.shared.open(BetterRemoteSite.help)
                }
                .onHover { hoveringHelp = $0 }
                .accessibilityLabel(FeedbackCopy.help)

                aboutPill(
                    title: FeedbackCopy.section,
                    symbol: "bubble.left",
                    hovering: hoveringFeedback
                ) {
                    FeedbackWindowController.shared.present(model: model)
                }
                .onHover { hoveringFeedback = $0 }
                .accessibilityLabel(FeedbackCopy.section)
            }
            .frame(width: pillRowWidth)

            Rectangle()
                .fill(DesignTokens.Colors.separator)
                .frame(height: 1)
                .frame(width: pillRowWidth)
                .padding(.top, DesignTokens.spacingMd)
                .padding(.bottom, DesignTokens.spacingMd)

            Button {
                CoffeeWindowController.shared.present()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "cup.and.saucer")
                        .font(.system(size: DesignTokens.fontCaption))
                    Text(FeedbackCopy.coffee)
                        .font(.system(size: DesignTokens.fontCaption))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundStyle(hoveringCoffee ? DesignTokens.Colors.textPrimary : .secondary)
            }
            .buttonStyle(.plain)
            .onHover { hoveringCoffee = $0 }
            .accessibilityLabel(FeedbackCopy.coffee)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func aboutPill(
        title: String,
        symbol: String,
        hovering: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: DesignTokens.spacingSm) {
                Image(systemName: symbol)
                    .font(.system(size: DesignTokens.fontBody, weight: .regular))
                    .foregroundStyle(DesignTokens.Colors.icon)
                    .frame(width: 16, alignment: .center)
                Text(title)
                    .font(.system(size: DesignTokens.fontBody, weight: .medium))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, DesignTokens.spacingMd)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(
                hovering ? DesignTokens.Colors.secondaryFillPressed : DesignTokens.Colors.secondaryFill,
                in: Capsule()
            )
            .overlay(
                Capsule().strokeBorder(DesignTokens.Colors.cardBorder, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}

/// Independent closable window: red traffic light only, title text hidden.
@MainActor
final class FeedbackWindowController: NSObject, NSWindowDelegate {
    static let shared = FeedbackWindowController()

    private var window: FeedbackFormWindow?
    private var hosting: NSHostingController<FeedbackFormView>?

    func present(model: FeedbackModel) {
        if let window, window.isVisible {
            refresh(model: model)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = FeedbackFormView(model: model)
        let host = NSHostingController(rootView: root)
        host.sizingOptions = [.intrinsicContentSize]

        let window = FeedbackFormWindow(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = FeedbackCopy.section
        window.titleVisibility = .hidden
        window.contentViewController = host
        window.isReleasedWhenClosed = false
        window.styleMask.remove(.resizable)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.delegate = self
        window.setContentSize(fittedContentSize(for: host))
        position(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.hosting = host
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        // Red light / Esc / Cmd-W: dismiss only; do not send.
        hosting = nil
        window = nil
    }

    private func refresh(model: FeedbackModel) {
        let host = NSHostingController(rootView: FeedbackFormView(model: model))
        host.sizingOptions = [.intrinsicContentSize]
        window?.contentViewController = host
        if let window {
            window.setContentSize(fittedContentSize(for: host))
        }
        hosting = host
    }

    private func fittedContentSize(for host: NSHostingController<FeedbackFormView>) -> NSSize {
        let fitting = host.sizeThatFits(in: NSSize(width: 380, height: 10_000))
        return NSSize(width: 380, height: max(200, ceil(fitting.height)))
    }

    private func position(_ window: NSWindow) {
        if let parent = NSApp.windows.first(where: {
            WindowControlPerformer.isRealWindow($0) && $0.isVisible && $0 !== window
        }) {
            let parentFrame = parent.frame
            var frame = window.frame
            frame.origin.x = parentFrame.midX - frame.width / 2
            frame.origin.y = parentFrame.midY - frame.height / 2
            window.setFrame(frame, display: false)
        } else {
            window.center()
        }
    }
}

private final class FeedbackFormWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        // Esc dismisses without sending, same as the red traffic light.
        close()
    }
}

private struct FeedbackFormView: View {
    @ObservedObject var model: FeedbackModel

    private var trimmed: String { model.trimmed }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(FeedbackCopy.section)
                .font(.system(size: DesignTokens.fontEmphasis, weight: .semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            TextField(FeedbackCopy.placeholder, text: $model.message, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: DesignTokens.fontBody))
                .lineLimit(4...8)
                .disabled(model.sending)
                .padding(8)
                .background(DesignTokens.Colors.secondaryFill, in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Toggle(FeedbackCopy.attach, isOn: $model.attachLogs)
                    .toggleStyle(.checkbox)
                    .font(.system(size: DesignTokens.fontBody))
                    .disabled(model.sending)
                Text(FeedbackCopy.note)
                    .font(.system(size: DesignTokens.fontCaption))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DesignTokens.Colors.secondaryFill, in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous))

            HStack {
                Spacer(minLength: 0)
                Button(action: model.send) {
                    Group {
                        if model.sending {
                            ProgressView()
                                .controlSize(.small)
                                .tint(.white)
                        } else {
                            Text(FeedbackCopy.send)
                        }
                    }
                    .frame(minWidth: 28)
                }
                .buttonStyle(DSPrimaryButtonStyle())
                .disabled(trimmed.isEmpty || model.sending)
                .accessibilityLabel(FeedbackCopy.send)
            }

            if let sentID = model.sentID {
                HStack(alignment: .center, spacing: 8) {
                    Text(FeedbackCopy.sent(sentID))
                        .font(.system(size: DesignTokens.fontBody))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button(FeedbackCopy.copy) { model.copyIdentifier() }
                        .buttonStyle(DSSecondaryButtonStyle())
                }
            } else if model.failed {
                Text(FeedbackCopy.failed)
                    .font(.system(size: DesignTokens.fontBody))
                    .foregroundStyle(DesignTokens.Colors.destructive)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(20)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
    }
}


/// Tip-jar window with the same red close traffic light as feedback.
@MainActor
final class CoffeeWindowController: NSObject, NSWindowDelegate {
    static let shared = CoffeeWindowController()

    private var window: FeedbackFormWindow?

    func present() {
        if let window, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let host = NSHostingController(rootView: CoffeeTipView())
        host.sizingOptions = [.intrinsicContentSize]

        let window = FeedbackFormWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = FeedbackCopy.coffee
        window.titleVisibility = .hidden
        window.contentViewController = host
        window.isReleasedWhenClosed = false
        window.styleMask.remove(.resizable)
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.delegate = self
        let fitting = host.sizeThatFits(in: NSSize(width: 300, height: 10_000))
        window.setContentSize(NSSize(width: 300, height: max(300, ceil(fitting.height))))
        if let parent = NSApp.windows.first(where: {
            WindowControlPerformer.isRealWindow($0) && $0.isVisible && $0 !== window
        }) {
            var frame = window.frame
            frame.origin.x = parent.frame.midX - frame.width / 2
            frame.origin.y = parent.frame.midY - frame.height / 2
            window.setFrame(frame, display: false)
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = window
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private struct CoffeeTipView: View {
    private var qrImage: NSImage? {
        Bundle.main.image(forResource: "RewardQR")
            ?? NSImage(contentsOf: BetterRemoteSite.rewardQR)
    }

    var body: some View {
        Group {
            if let qrImage {
                Image(nsImage: qrImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 232, height: 232)
                    .padding(8)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityLabel(FeedbackCopy.coffee)
            } else {
                Text("打不开赞赏码，请稍后再试")
                    .font(.system(size: DesignTokens.fontBody))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(24)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
    }
}

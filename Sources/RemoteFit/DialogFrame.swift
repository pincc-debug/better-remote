import AppKit
import SwiftUI
import RemoteFitCore

private struct DialogLimitKey: EnvironmentKey { static let defaultValue: CGSize? = nil }
extension EnvironmentValues {
    /// Offscreen renders only: the screen-derived sheet limit to use instead of the real screen's.
    var dialogLimitOverride: CGSize? {
        get { self[DialogLimitKey.self] }
        set { self[DialogLimitKey.self] = newValue }
    }
}

enum DialogLimit {
    /// Set by AppController whenever it fits 设置: the visible area minus an expanded toolbar.
    @MainActor static var settingsArea: CGRect?

    /// The visible area of the screen the settings window (the sheet's parent) is on, minus margins.
    @MainActor static func current(_ override: CGSize?) -> CGSize {
        if let override { return override }
        if let settingsArea { return SettingsWindowLayout.dialogLimit(in: settingsArea) }
        let screen = NSApp.keyWindow?.sheetParent?.screen ?? NSApp.keyWindow?.screen ?? NSApp.mainWindow?.screen ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return CGSize(width: CGFloat.infinity, height: .infinity) }
        return SettingsWindowLayout.dialogLimit(in: visible)
    }
}

/// Sheets keep their designed size on normal screens; on a small screen they shrink to the
/// visible area (16 pt from each edge) and their content scrolls vertically when taller.
private struct DialogFrame: ViewModifier {
    let width: CGFloat
    let height: CGFloat?
    @Environment(\.dialogLimitOverride) private var override
    @State private var naturalHeight: CGFloat = 0

    func body(content: Content) -> some View {
        let limit = DialogLimit.current(override)
        let size = SettingsWindowLayout.dialogSize(width: width, height: height, limit: limit)
        if let fixed = size.height {
            // Fixed-size sheets already scroll their list; only the frame shrinks.
            content.frame(width: size.width, height: fixed)
        } else if naturalHeight > limit.height {
            ScrollView(.vertical) {
                content.frame(width: size.width).fixedSize(horizontal: false, vertical: true).background(measure)
            }
            .frame(width: size.width, height: limit.height)
        } else {
            content.frame(width: size.width).background(measure)
        }
    }

    private var measure: some View {
        GeometryReader { geometry in
            Color.clear
                .onAppear { naturalHeight = geometry.size.height }
                .onChange(of: geometry.size.height) { _, height in naturalHeight = height }
        }
    }
}

extension View {
    func dialogFrame(width: CGFloat, height: CGFloat? = nil) -> some View {
        modifier(DialogFrame(width: width, height: height))
    }
}

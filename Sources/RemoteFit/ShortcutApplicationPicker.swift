import AppKit
import SwiftUI
import RemoteFitCore

struct ShortcutApplicationPicker: View {
    let existing: Set<String>
    let onSelect: (ApplicationShortcuts) -> Bool
    let onCancel: () -> Void
    @State private var applications: [ApplicationShortcuts] = []
    @State private var query = ""
    @State private var loading = true
    @State private var failed = false

    private var filtered: [ApplicationShortcuts] {
        applications.filter { !existing.contains($0.id) &&
            (query.isEmpty || $0.name.localizedStandardContains(query) || $0.bundleID.localizedStandardContains(query)) }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Text("添加应用").font(.system(size: DesignTokens.fontEmphasis, weight: .semibold))
                Spacer()
                Button("取消", action: onCancel).buttonStyle(DSSecondaryButtonStyle()).keyboardShortcut(.cancelAction)
            }
            TextField("搜索应用", text: $query).textFieldStyle(.roundedBorder)
            if loading {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if filtered.isEmpty {
                Text("未找到应用").foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(filtered) { app in
                            Button {
                                failed = !onSelect(app)
                            } label: {
                                HStack(spacing: 12) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                        .resizable().frame(width: 32, height: 32)
                                    Text(app.name).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "plus").foregroundStyle(.secondary)
                                }
                                .padding(8).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                }
            }
            if failed { Text("保存失败，请重试").foregroundStyle(.red).font(.system(size: DesignTokens.fontCaption)) }
        }
        .padding(20).dialogFrame(width: 440, height: 480)
        .background(DesignTokens.Colors.pageBackground)
        .task {
            let running = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular }.compactMap(\.bundleURL)
            applications = await Task.detached(priority: .userInitiated) {
                InstalledShortcutApplications.load(running: running)
            }.value
            loading = false
        }
    }
}

enum InstalledShortcutApplications {
    static func load(running: [URL]) -> [ApplicationShortcuts] {
        let roots = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications"),
                     URL(fileURLWithPath: "/Applications"), URL(fileURLWithPath: "/System/Applications")]
        var urls = running + [URL(fileURLWithPath: "/System/Library/CoreServices/Finder.app")]
        for root in roots {
            guard let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in files where url.pathExtension.lowercased() == "app" { urls.append(url) }
        }
        var seen = Set<String>()
        return urls.compactMap { url in
            guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier, id != "local.RemoteFit",
                  bundle.infoDictionary?["LSBackgroundOnly"] as? Bool != true, seen.insert(id).inserted else { return nil }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            return ApplicationShortcuts(bundleID: id, name: name, path: url.path)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

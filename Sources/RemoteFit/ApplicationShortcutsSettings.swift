import SwiftUI
import AppKit
import RemoteFitCore
import UniformTypeIdentifiers

struct ApplicationShortcutsSettings: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var collapsedApps: Set<String> = []
    @ObservedObject var model: ControlPanelModel
    @State private var choosingApplication = false
    private struct EditDraft: Identifiable {
        let bundleID: String
        let shortcut: NamedShortcut
        var id: String { bundleID + ":" + shortcut.id }
    }
    @State private var editing: EditDraft?
    @State private var error: String?
    @State private var deletingApplication: ApplicationShortcuts?
    @State private var draggedShortcut: ApplicationShortcutDrag?

    var body: some View {
        SettingsView.shortcutSection {
            HStack {
                SettingsView.sectionTitle("应用快捷操作")
                Spacer()
                Toggle("显示应用快捷操作", isOn: Binding(
                    get: { model.preferences.applicationShortcutsEnabled },
                    set: { _ = save(model.preferences.applicationShortcuts, enabled: $0) }
                )).labelsHidden().toggleStyle(StableBlueSwitchStyle()).controlSize(.small)
                    .help("显示应用快捷操作")
            }
            // Same right inset as the switches inside cards (settingRow pads 14).
            .padding(.trailing, 14)
            ForEach(model.preferences.applicationShortcuts) { group in
                applicationCard(group)
            }
            Button("添加应用", systemImage: "plus") { choosingApplication = true }
                .buttonStyle(DSSecondaryButtonStyle()).controlSize(.small)
        }
        .sheet(isPresented: $choosingApplication) {
            ShortcutApplicationPicker(existing: Set(model.preferences.applicationShortcuts.map(\.id))) { app in
                guard saveGroup(app) else { return false }
                choosingApplication = false
                return true
            } onCancel: { choosingApplication = false }
        }
        .sheet(item: $editing) { draft in
            ShortcutEditor(shortcut: draft.shortcut, onSave: { updated in
                guard var group = model.preferences.applicationShortcuts.first(where: { $0.id == draft.bundleID }) else {
                    OperationDiagnostics.write("application-shortcut-save missing-application bundle=\(draft.bundleID)")
                    return false
                }
                if let i = group.shortcuts.firstIndex(where: { $0.id == updated.id }) { group.shortcuts[i] = updated }
                else { group.shortcuts.append(updated) }
                guard saveGroup(group) else { return false }
                editing = nil
                return true
            }, onCancel: { editing = nil }, onDelete: model.preferences.applicationShortcuts
                .first(where: { $0.id == draft.bundleID })?.shortcuts.contains(where: { $0.id == draft.shortcut.id }) == true ? {
                guard var group = model.preferences.applicationShortcuts.first(where: { $0.id == draft.bundleID }) else { return false }
                group.shortcuts.removeAll { $0.id == draft.shortcut.id }
                guard saveGroup(group) else { return false }
                editing = nil
                return true
            } : nil)
        }
        .alert("移除「\(deletingApplication?.name ?? "")」？", isPresented: Binding(
            get: { deletingApplication != nil }, set: { if !$0 { deletingApplication = nil } }
        ), presenting: deletingApplication) { group in
            Button("取消", role: .cancel) { deletingApplication = nil }
            Button("移除", role: .destructive) {
                _ = save(model.preferences.applicationShortcuts.filter { $0.id != group.id })
                deletingApplication = nil
            }
        }
        .alert("保存失败", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("好") { error = nil }
        } message: { Text(error ?? "") }
    }

    private func applicationCard(_ group: ApplicationShortcuts) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: applicationURL(group).path))
                    .resizable().frame(width: 28, height: 28)
                Text(group.name).font(.system(size: DesignTokens.fontBody, weight: .semibold)).lineLimit(1)
                Spacer()
                Menu {
                    Button("移除应用", role: .destructive) { deletingApplication = group }
                } label: { Image(systemName: "ellipsis").frame(width: 24, height: 28) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("应用操作")
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.16)) {
                        if collapsedApps.contains(group.id) { collapsedApps.remove(group.id) }
                        else { collapsedApps.insert(group.id) }
                    }
                } label: {
                    Image(systemName: collapsedApps.contains(group.id) ? "chevron.right" : "chevron.down")
                        .font(.system(size: DesignTokens.fontCaption, weight: .medium)).frame(width: 24, height: 28)
                }.buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel(collapsedApps.contains(group.id) ? "展开\(group.name)操作" : "收起\(group.name)操作")
            }
            if !collapsedApps.contains(group.id) {
                ShortcutFlowLayout(spacing: 8) {
                    ForEach(group.shortcuts) { shortcut in
                        Button { editing = EditDraft(bundleID: group.id, shortcut: shortcut) } label: {
                            Label { Text(shortcut.name) } icon: { IconArt.blueImage(shortcut.icon.rawValue, pointSize: DesignTokens.fontCaption, weight: .medium) }
                                .font(.system(size: DesignTokens.fontCaption, weight: .medium)).lineLimit(1).frame(minHeight: 24)
                        }
                        .buttonStyle(DSSecondaryButtonStyle()).controlSize(.small)
                        .opacity(shortcut.enabled ? 1 : 0.5)
                        .help(shortcut.key.displayLabel)
                        .overlay {
                            OperationDragSurface(id: group.id + ":" + shortcut.id,
                                onTap: { editing = EditDraft(bundleID: group.id, shortcut: shortcut) },
                                onBegin: { draggedShortcut = .init(bundleID: group.id, shortcutID: shortcut.id) },
                                onEnd: { draggedShortcut = nil })
                        }
                        .onDrop(of: [UTType.text], delegate: ApplicationShortcutDropDelegate(
                            bundleID: group.id, targetID: shortcut.id, dragged: $draggedShortcut,
                            move: { source, target in moveShortcut(source, to: target, in: group.id) }))
                        .accessibilityAction(named: "前移") { moveShortcut(shortcut.id, by: -1, in: group.id) }
                        .accessibilityAction(named: "后移") { moveShortcut(shortcut.id, by: 1, in: group.id) }
                        .contextMenu {
                            Button(shortcut.enabled ? "停用" : "启用") {
                                var next = group
                                if let i = next.shortcuts.firstIndex(where: { $0.id == shortcut.id }) {
                                    next.shortcuts[i].enabled.toggle()
                                    _ = saveGroup(next)
                                }
                            }
                        }
                    }
                    Button("添加操作", systemImage: "plus") { addShortcut(to: group) }
                        .font(.system(size: DesignTokens.fontCaption, weight: .medium)).buttonStyle(DSSecondaryButtonStyle()).controlSize(.small)
                        .frame(minHeight: 24)
                }.transition(.opacity)
            }
        }
        .padding(10)
        .cardSurface()
    }

    private func addShortcut(to group: ApplicationShortcuts) {
        collapsedApps.remove(group.id)
        editing = EditDraft(bundleID: group.id, shortcut: .init(name: "", key: .init(code: 0, modifiers: 0, label: "")))
    }

    private func moveShortcut(_ id: String, to targetID: String, in bundleID: String) {
        guard var group = model.preferences.applicationShortcuts.first(where: { $0.id == bundleID }),
              group.moveShortcut(id, to: targetID) else { return }
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) { _ = saveGroup(group) }
    }

    private func moveShortcut(_ id: String, by offset: Int, in bundleID: String) {
        guard let group = model.preferences.applicationShortcuts.first(where: { $0.id == bundleID }),
              let index = group.shortcuts.firstIndex(where: { $0.id == id }),
              group.shortcuts.indices.contains(index + offset) else { return }
        moveShortcut(id, to: group.shortcuts[index + offset].id, in: bundleID)
    }

    private func applicationURL(_ group: ApplicationShortcuts) -> URL {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: group.bundleID) ?? URL(fileURLWithPath: group.path)
    }
    private func save(_ groups: [ApplicationShortcuts], enabled: Bool? = nil) -> Bool {
        let success = model.onSaveApplicationShortcuts(groups, enabled ?? model.preferences.applicationShortcutsEnabled)
        if !success { error = "请重试" }
        return success
    }
    private func saveGroup(_ group: ApplicationShortcuts) -> Bool {
        var groups = model.preferences.applicationShortcuts
        if let i = groups.firstIndex(where: { $0.id == group.id }) { groups[i] = group }
        else { groups.append(group) }
        return save(groups)
    }
}

private struct ApplicationShortcutDrag {
    let bundleID: String
    let shortcutID: String
}

private struct ApplicationShortcutDropDelegate: DropDelegate {
    let bundleID: String
    let targetID: String
    @Binding var dragged: ApplicationShortcutDrag?
    let move: (String, String) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragged?.bundleID == bundleID }
    func dropEntered(info: DropInfo) {
        guard let dragged, dragged.bundleID == bundleID else { return }
        move(dragged.shortcutID, targetID)
    }
    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: dragged?.bundleID == bundleID ? .move : .forbidden)
    }
    func performDrop(info: DropInfo) -> Bool {
        guard dragged?.bundleID == bundleID else { return false }
        dragged = nil
        return true
    }
}

private struct ShortcutFlowLayout: Layout {
    let spacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrange(subviews, width: proposal.width ?? 460).size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = arrange(subviews, width: bounds.width)
        for (index, frame) in layout.frames.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                                 anchor: .topLeading, proposal: ProposedViewSize(frame.size))
        }
    }
    private func arrange(_ subviews: Subviews, width: CGFloat) -> (size: CGSize, frames: [CGRect]) {
        let width = max(1, width)
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        var frames: [CGRect] = []
        for view in subviews {
            let ideal = view.sizeThatFits(.unspecified)
            let size = view.sizeThatFits(ProposedViewSize(width: min(width, ideal.width), height: nil))
            if x > 0, x + size.width > width {
                x = 0; y += rowHeight + spacing; rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return (CGSize(width: width, height: y + rowHeight), frames)
    }
}

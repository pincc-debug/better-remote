import SwiftUI
import RemoteFitCore

struct IconPickerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let columnCount = 6
    private static let collapsedRows = 3
    private static let collapsedLimit = columnCount * collapsedRows
    private static let expandedMaxHeight: CGFloat = 260

    let selected: ShortcutIcon?
    let choose: (ShortcutIcon) -> Void
    @State private var expanded = false
    @State private var searchText = ""

    private var trimmedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isSearching: Bool {
        !trimmedSearchText.isEmpty
    }

    private var displayedIcons: [ShortcutIcon] {
        if isSearching {
            return ShortcutIcon.allCases.filter { $0.matches(query: trimmedSearchText) }
        }
        guard !expanded else { return ShortcutIcon.allCases }
        var icons = Array(ShortcutIcon.allCases.prefix(Self.collapsedLimit))
        if let selected, !icons.contains(selected) {
            if icons.count == Self.collapsedLimit {
                icons[Self.collapsedLimit - 1] = selected
            } else {
                icons.append(selected)
            }
        }
        return icons
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Search Input
            searchBar

            // Grid Content
            if isSearching {
                if displayedIcons.isEmpty {
                    emptySearchResults
                } else {
                    ScrollView {
                        iconGrid(displayedIcons)
                            .padding(.vertical, 2)
                    }
                    .frame(maxHeight: Self.expandedMaxHeight)
                }
            } else if expanded {
                ScrollViewReader { proxy in
                    ScrollView {
                        iconGrid(displayedIcons)
                            .padding(.vertical, 2)
                    }
                    .frame(maxHeight: Self.expandedMaxHeight)
                    .onAppear {
                        guard let selected else { return }
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 60_000_000)
                            proxy.scrollTo(selected.rawValue, anchor: .center)
                        }
                    }
                }
            } else {
                iconGrid(displayedIcons)
            }

            // Footer
            footerView
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: DesignTokens.fontBody))
                .foregroundStyle(.secondary)

            TextField("搜索图标", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: DesignTokens.fontBody))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: DesignTokens.fontBody))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .cardSurface()
    }

    // MARK: - Empty State

    private var emptySearchResults: some View {
        VStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
            Text("未找到图标")
                .font(.system(size: DesignTokens.fontBody))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 90)
        .background(DesignTokens.Colors.secondaryFill, in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous))
    }

    // MARK: - Footer View

    private var footerView: some View {
        HStack {
            if isSearching {
                Text("找到 \(displayedIcons.count) 个图标")
                    .font(.system(size: DesignTokens.fontCaption))
                    .foregroundStyle(.secondary)

                Spacer()

                Button("清除搜索") {
                    searchText = ""
                }
                .font(.system(size: DesignTokens.fontCaption))
                .buttonStyle(.borderless)
                .foregroundStyle(DesignTokens.Colors.accent)
            } else {
                if ShortcutIcon.allCases.count > Self.collapsedLimit {
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                            expanded.toggle()
                        }
                    } label: {
                        Label(expanded ? "收起更多" : "更多图标",
                              systemImage: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: DesignTokens.fontCaption, weight: .medium))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    // MARK: - Icon Grid

    private func iconGrid(_ icons: [ShortcutIcon]) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: Self.columnCount), spacing: 6) {
            ForEach(icons, id: \.rawValue) { icon in
                let isSelected = selected == icon
                Button {
                    choose(icon)
                } label: {
                    VStack(spacing: 2) {
                        IconArt.image(icon.rawValue, pointSize: DesignTokens.fontEmphasis, weight: isSelected ? .semibold : .regular)
                            .font(.system(size: DesignTokens.fontEmphasis, weight: isSelected ? .semibold : .regular))
                            .foregroundStyle(isSelected ? DesignTokens.Colors.accent : Color.primary)
                            .frame(height: 20)
                        Text(icon.title)
                            .font(.system(size: DesignTokens.fontCaption))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, minHeight: 46)
                    .background(
                        DesignTokens.Colors.secondaryFill,
                        in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.radiusMd, style: .continuous)
                            .strokeBorder(isSelected ? DesignTokens.Colors.accent : Color.clear, lineWidth: DesignTokens.selectedStroke)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .id(icon.rawValue)
                .accessibilityLabel(icon.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .help("\(icon.title) (\(icon.rawValue))")
            }
        }
    }
}

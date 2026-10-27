import AppKit
import SwiftUI

struct GitHubStarClient: Sendable {
    static let repository = "pincc-debug/better-remote"
    static let url = URL(string: "https://github.com/\(repository)")!
    var run: @Sendable ([String]) async throws -> Data = { arguments in
        try await Task.detached(priority: .utility) {
            let paths = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"]
                + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map { "\($0)/gh" }
            guard let executable = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
                throw GitHubStarError.unavailable
            }
            return try ProcessRunner.run(executable, arguments, timeout: 15)
        }.value
    }

    func isStarred() async -> Bool? {
        do {
            _ = try await run(["api", "--hostname", "github.com", "user/starred/\(Self.repository)"])
            return true
        } catch {
            // A 404 is an authenticated "not starred" response; all other failures are unknown.
            return error.localizedDescription.contains("HTTP 404") ? false : nil
        }
    }

    func star() async -> Bool {
        do {
            _ = try await run(["api", "--hostname", "github.com", "--method", "PUT", "user/starred/\(Self.repository)"])
            return true
        } catch { return false }
    }
}
private enum GitHubStarError: Error { case unavailable }

@MainActor
final class GitHubStarModel: ObservableObject {
    static let shared = GitHubStarModel()
    private static let cacheKey = "betterRemote.githubStarred"

    /// Cached star state. Missing cache shows the normal unstarred button until a quiet refresh lands.
    @Published private(set) var starred: Bool
    /// Only true while the user-initiated star action is in flight — never for background refresh.
    @Published private(set) var working = false
    private let client: GitHubStarClient
    private let openRepository: () -> Void
    private let defaults: UserDefaults
    private var refreshing = false
    private var didLaunchRefresh = false
    private let persistsCache: Bool

    init(client: GitHubStarClient = GitHubStarClient(),
         openRepository: @escaping () -> Void = { NSWorkspace.shared.open(GitHubStarClient.url) },
         defaults: UserDefaults = .standard,
         persistsCache: Bool = true) {
        self.client = client
        self.openRepository = openRepository
        self.defaults = defaults
        self.persistsCache = persistsCache
        starred = persistsCache ? (defaults.object(forKey: Self.cacheKey) as? Bool ?? false) : false
    }

    /// Launch-time single fetch. About page only reads the published cache.
    func ensureLaunchRefresh() {
        guard !didLaunchRefresh else { return }
        didLaunchRefresh = true
        Task { await refreshQuietly() }
    }

    /// Background status sync — never toggles `working`, so the About page never shows a loading placeholder.
    func refreshQuietly() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        if let value = await client.isStarred() {
            starred = value
            if persistsCache { defaults.set(value, forKey: Self.cacheKey) }
        }
    }

    /// Test / explicit read helper (also quiet — no loading flag).
    func refresh() async { await refreshQuietly() }

    func star() async {
        guard !working, !starred else { return }
        working = true
        let success = await client.star()
        starred = success
        if success, persistsCache { defaults.set(true, forKey: Self.cacheKey) }
        working = false
        if !success { openRepository() }
    }
}

struct GitHubStarSettings: View {
    @ObservedObject private var model: GitHubStarModel
    var allowsNetwork = true

    init(model: GitHubStarModel? = nil, allowsNetwork: Bool = true) {
        _model = ObservedObject(wrappedValue: model ?? .shared)
        self.allowsNetwork = allowsNetwork
    }

    var body: some View {
        Button {
            if allowsNetwork { Task { await model.star() } }
        } label: {
            HStack(spacing: 10) {
                Text("在 GitHub 上支持项目")
                    .font(.system(size: DesignTokens.fontBody, weight: .medium))
                Spacer(minLength: 0)
                // Only the user click shows a spinner; cache / quiet refresh never do.
                if model.working {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: model.starred ? "star.fill" : "star")
                        .foregroundStyle(model.starred ? Color.yellow : Color.secondary)
                    if model.starred {
                        Text("感谢你的支持！")
                            .font(.system(size: DesignTokens.fontCaption)).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(DesignTokens.Colors.card, in: RoundedRectangle(cornerRadius: DesignTokens.radiusMd))
        }
        .buttonStyle(.plain)
        .disabled(model.working || model.starred)
    }
}

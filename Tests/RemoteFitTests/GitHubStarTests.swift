import XCTest
@testable import RemoteFit

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() {
        lock.lock(); value += 1; lock.unlock()
    }
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

@MainActor
final class GitHubStarTests: XCTestCase {
    func testClickStarsCorrectRepositoryAndOnlyMarksSuccess() async {
        let client = GitHubStarClient(run: { arguments in
            XCTAssertEqual(arguments, ["api", "--hostname", "github.com", "--method", "PUT", "user/starred/pincc-debug/better-remote"])
            return Data()
        })
        var opened = false
        let model = GitHubStarModel(client: client, openRepository: { opened = true }, persistsCache: false)
        await model.star()
        XCTAssertTrue(model.starred)
        XCTAssertFalse(model.working)
        XCTAssertFalse(opened)
    }

    func testFailureOpensRepositoryWithoutFakingStar() async {
        let client = GitHubStarClient(run: { _ in throw NSError(domain: "test", code: 401) })
        var opened = false
        let model = GitHubStarModel(client: client, openRepository: { opened = true }, persistsCache: false)
        await model.star()
        XCTAssertTrue(opened)
        XCTAssertFalse(model.starred)
        XCTAssertFalse(model.working)
    }

    func testRefreshReadsActualStatusWithoutSendingStarOrLoading() async {
        let client = GitHubStarClient(run: { arguments in
            XCTAssertEqual(arguments, ["api", "--hostname", "github.com", "user/starred/pincc-debug/better-remote"])
            return Data()
        })
        let model = GitHubStarModel(client: client, openRepository: { XCTFail("Read must not open browser") }, persistsCache: false)
        await model.refresh()
        XCTAssertTrue(model.starred)
        XCTAssertFalse(model.working)
    }

    func testQuietRefreshNeverSetsWorkingAndCachesResult() async {
        let suite = "betterRemote.githubStarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let calls = CallCounter()
        let client = GitHubStarClient(run: { _ in
            calls.increment()
            return Data()
        })
        let model = GitHubStarModel(client: client, openRepository: { XCTFail("must not open") }, defaults: defaults, persistsCache: true)
        XCTAssertFalse(model.starred)
        await model.refreshQuietly()
        XCTAssertTrue(model.starred)
        XCTAssertFalse(model.working)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(defaults.bool(forKey: "betterRemote.githubStarred"), true)

        model.ensureLaunchRefresh()
        model.ensureLaunchRefresh()
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(calls.count, 2)
        model.ensureLaunchRefresh()
        try? await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertEqual(calls.count, 2)
    }

    func testCachedStarShowsWithoutNetworkUntilLaunchRefresh() {
        let suite = "betterRemote.githubStarTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: "betterRemote.githubStarred")
        let client = GitHubStarClient(run: { _ in
            XCTFail("About page must not hit network just to render cache")
            return Data()
        })
        let model = GitHubStarModel(client: client, openRepository: {}, defaults: defaults, persistsCache: true)
        XCTAssertTrue(model.starred)
        XCTAssertFalse(model.working)
    }
}

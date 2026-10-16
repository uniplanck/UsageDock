import AppKit
import XCTest
@testable import UsageDock

@MainActor
final class ProviderOpenTargetTests: XCTestCase {
    private let link = URL(string: "https://example.com/provider")!

    func testAllProvidersDefaultToAppAndResolveInstalledDefaults() {
        let locator = TestAppLocator()
        let expected: [ProviderID: String] = [
            .claude: "Claude", .codex: "ChatGPT", .antigravity: "Antigravity",
            .kimi: "Kimi Code", .cursor: "Cursor", .grok: "Grok Bot"
        ]
        for (provider, name) in expected {
            let app = selection(name, id: "test.\(provider.rawValue)")
            locator.byName[name] = app
            XCTAssertEqual(ProviderOpenPreference().mode, .app)
            XCTAssertEqual(resolve(provider, locator: locator), .app(app))
        }
    }

    func testMissingDefaultFallsBackToLinkForEveryProvider() {
        for provider in ProviderID.allCases {
            XCTAssertEqual(resolve(provider), .link(link, appUnavailable: true))
        }
    }

    func testExplicitLinkDoesNotResolveOrLaunchInstalledApp() {
        let locator = TestAppLocator()
        locator.byName["Claude"] = selection("Claude")
        XCTAssertEqual(
            resolve(.claude, preference: ProviderOpenPreference(mode: .link), locator: locator),
            .link(link, appUnavailable: false)
        )
    }

    func testStoredPathTakesPriorityOverBundleLookupAndProviderDefault() {
        let locator = TestAppLocator()
        let selected = selection("Custom", path: "/Users/test/Applications/Custom.app")
        locator.byPath[selected.path] = selected
        locator.byIdentifier["test.app"] = selection("Other Copy")
        locator.byName["Claude"] = selection("Claude")
        XCTAssertEqual(resolve(.claude, preference: ProviderOpenPreference(app: selected), locator: locator), .app(selected))
    }

    func testMovedSelectionResolvesByBundleIdentifier() {
        let locator = TestAppLocator()
        let selected = selection("Custom", path: "/old/Custom.app")
        let moved = selection("Custom", path: "/new/Custom.app")
        locator.byIdentifier["test.app"] = moved
        XCTAssertEqual(resolve(.kimi, preference: ProviderOpenPreference(app: selected), locator: locator), .app(moved))
    }

    func testRemovedExplicitSelectionFallsBackWithoutUsingProviderDefault() {
        let locator = TestAppLocator()
        locator.byName["Claude"] = selection("Claude")
        XCTAssertEqual(
            resolve(.claude, preference: ProviderOpenPreference(app: selection("Removed")), locator: locator),
            .link(link, appUnavailable: true)
        )
    }

    func testReplacedPathWithDifferentBundleIdentifierIsNotLaunched() {
        let locator = TestAppLocator()
        let selected = selection("Custom")
        locator.byPath[selected.path] = selection("Different", id: "different.app", path: selected.path)
        XCTAssertEqual(
            resolve(.grok, preference: ProviderOpenPreference(app: selected), locator: locator),
            .link(link, appUnavailable: true)
        )
    }

    func testSelectionWithoutIdentifierCanStillResolveByPath() {
        let locator = TestAppLocator()
        let selected = selection("Custom", id: nil)
        locator.byPath[selected.path] = selected
        XCTAssertEqual(resolve(.codex, preference: ProviderOpenPreference(app: selected), locator: locator), .app(selected))
    }

    func testDefaultLookupReadsActualGrokBundleIdentifierFromPlist() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let appURL = root.appendingPathComponent("Grok Bot.app")
        let contents = appURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let info: [String: String] = [
            "CFBundleIdentifier": "test.actual.identifier.from.disk",
            "CFBundleName": "Grok Bots",
            "CFBundlePackageType": "APPL",
            "CFBundleExecutable": "GrokBot"
        ]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: contents.appendingPathComponent("Info.plist"))
        try Data().write(to: contents.appendingPathComponent("MacOS/GrokBot"))
        let locator = WorkspaceProviderAppLocator(applicationDirectories: [root])
        let app = try XCTUnwrap(locator.application(named: "Grok Bot"))
        XCTAssertEqual(app.bundleIdentifier, "test.actual.identifier.from.disk")
        XCTAssertEqual(app.name, "Grok Bots")
        XCTAssertEqual(resolve(.grok, locator: locator), .app(app))
        try FileManager.default.removeItem(at: appURL)
        XCTAssertNil(locator.application(at: appURL))
    }

    func testAppPickerRejectsNonAppAndIncompleteAppBundles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let incomplete = root.appendingPathComponent("Incomplete.app")
        try FileManager.default.createDirectory(at: incomplete, withIntermediateDirectories: true)
        let locator = WorkspaceProviderAppLocator(applicationDirectories: [root])
        XCTAssertNil(locator.application(at: incomplete))
        XCTAssertNil(locator.application(at: root))
        XCTAssertNil(locator.application(at: link))
    }

    func testPreferencesAndURLsPersistAndStayIndependentPerProvider() {
        withStore { store, defaults, locator, _ in
            let selected = selection("Custom")
            locator.byPath[selected.path] = selected
            store.setSelectedApp(selected, for: .codex)
            store.setOpenMode(.link, for: .codex)
            store.setProviderWebURL("https://example.com/custom", for: .codex)
            let restored = UsageStore(defaults: defaults, appLocator: locator)
            XCTAssertEqual(restored.openPreference(for: .codex), ProviderOpenPreference(mode: .link, app: selected))
            XCTAssertEqual(restored.openPreference(for: .claude), ProviderOpenPreference())
            XCTAssertEqual(restored.openResolution(for: .provider(.codex)), .link(URL(string: "https://example.com/custom")!, appUnavailable: false))
            restored.setOpenMode(.app, for: .codex)
            XCTAssertEqual(restored.openResolution(for: .provider(.codex)), .app(selected))
            restored.setSelectedApp(nil, for: .codex)
            XCTAssertNil(UsageStore(defaults: defaults).openPreference(for: .codex).app)
        }
    }

    func testExistingURLsSurviveMigrationToAppDefault() {
        withStore { _, defaults, locator, _ in
            defaults.set(["codex": "https://example.com/saved"], forKey: "UsageDock.providerWebURLs.v1")
            let store = UsageStore(defaults: defaults, appLocator: locator)
            XCTAssertEqual(store.openPreference(for: .codex).mode, .app)
            XCTAssertEqual(store.openResolution(for: .provider(.codex)), .link(URL(string: "https://example.com/saved")!, appUnavailable: true))
            XCTAssertNotNil(store.openStatus(for: .codex))
        }
    }

    func testMalformedSavedPreferencesDoNotBreakDefaults() {
        withStore { _, defaults, locator, _ in
            defaults.set(Data("invalid".utf8), forKey: "UsageDock.providerOpenPreferences.v1")
            let store = UsageStore(defaults: defaults, appLocator: locator)
            XCTAssertEqual(store.openPreference(for: .grok), ProviderOpenPreference())
        }
    }

    func testAccountURLOverridesProviderAndInvalidEditsFallBackToBuiltInURL() {
        withStore { store, _, _, _ in
            let account = UsageAccount(provider: .codex, name: "Login", source: .profile, webURL: "https://example.com/account", buckets: [])
            store.accounts = [account]
            store.setProviderWebURL("https://example.com/provider", for: .codex)
            let target = RailDisplayTarget.account(id: account.id, provider: .codex)
            XCTAssertEqual(store.openResolution(for: target), .link(URL(string: "https://example.com/account")!, appUnavailable: true))
            store.accounts[0].webURL = "javascript:alert(1)"
            XCTAssertEqual(store.webURL(for: target)?.absoluteString, "https://example.com/provider")
            store.setProviderWebURL("https://", for: .codex)
            XCTAssertEqual(store.webURL(for: target)?.absoluteString, ProviderID.codex.defaultWebURL)
            store.setProviderWebURL("", for: .codex)
            XCTAssertEqual(store.webURL(for: target)?.absoluteString, ProviderID.codex.defaultWebURL)
        }
    }

    func testSuccessfulAppLaunchDoesNotOpenBrowser() async throws {
        let (store, defaults, locator, opener, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let app = selection("ChatGPT")
        locator.byName["ChatGPT"] = app
        let opened = await store.openTarget(for: .provider(.codex))
        XCTAssertTrue(opened)
        XCTAssertEqual(opener.apps, [app.url])
        XCTAssertTrue(opener.links.isEmpty)
        XCTAssertNil(store.openStatus(for: .codex))
    }

    func testAppLaunchFailureOpensLinkAndShowsStatus() async throws {
        let (store, defaults, locator, opener, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        locator.byName["Grok Bot"] = selection("Grok Bot")
        opener.failApp = true
        let opened = await store.openTarget(for: .provider(.grok))
        XCTAssertTrue(opened)
        XCTAssertEqual(opener.apps.count, 1)
        XCTAssertEqual(opener.links, [URL(string: ProviderID.grok.defaultWebURL)!])
        if case .appLaunchFailed? = store.openStatus(for: .grok) {} else { XCTFail("Missing launch failure status") }
    }

    func testMissingAppFallsBackAndBrowserFailureIsVisible() async throws {
        let (store, defaults, _, opener, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        let opened = await store.openTarget(for: .provider(.kimi))
        XCTAssertTrue(opened)
        XCTAssertTrue(opener.apps.isEmpty)
        XCTAssertEqual(opener.links, [URL(string: ProviderID.kimi.defaultWebURL)!])
        if case .appUnavailable? = store.openStatus(for: .kimi) {} else { XCTFail("Missing app unavailable status") }
        opener.linkSuccess = false
        let failed = await store.openTarget(for: .provider(.kimi))
        XCTAssertFalse(failed)
        if case .linkOpenFailed? = store.openStatus(for: .kimi) {} else { XCTFail("Missing browser failure status") }
        store.setOpenMode(.link, for: .kimi)
        XCTAssertNil(store.openStatus(for: .kimi))
    }

    private func resolve(
        _ provider: ProviderID,
        preference: ProviderOpenPreference = ProviderOpenPreference(),
        locator: (any ProviderAppLocating)? = nil
    ) -> ProviderOpenResolution {
        ProviderOpenResolver(locator: locator ?? TestAppLocator()).resolve(provider: provider, preference: preference, linkURL: link)
    }

    private func selection(_ name: String, id: String? = "test.app", path: String? = nil) -> ProviderAppSelection {
        ProviderAppSelection(bundleIdentifier: id, path: path ?? "/Applications/\(name).app", name: name)
    }

    private func makeStore() -> (UsageStore, UserDefaults, TestAppLocator, TestTargetOpener, String) {
        let suite = "UsageDockTests.OpenTarget.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let locator = TestAppLocator()
        let opener = TestTargetOpener()
        return (UsageStore(defaults: defaults, appLocator: locator, targetOpener: opener), defaults, locator, opener, suite)
    }

    private func withStore(_ body: (UsageStore, UserDefaults, TestAppLocator, TestTargetOpener) -> Void) {
        let (store, defaults, locator, opener, suite) = makeStore()
        defer { defaults.removePersistentDomain(forName: suite) }
        body(store, defaults, locator, opener)
    }
}

@MainActor
private final class TestAppLocator: ProviderAppLocating {
    var byPath: [String: ProviderAppSelection] = [:]
    var byIdentifier: [String: ProviderAppSelection] = [:]
    var byName: [String: ProviderAppSelection] = [:]

    func application(at url: URL) -> ProviderAppSelection? { byPath[url.path] }
    func application(bundleIdentifier: String) -> ProviderAppSelection? { byIdentifier[bundleIdentifier] }
    func application(named name: String) -> ProviderAppSelection? { byName[name] }
    func runningApplications() -> [ProviderAppSelection] { [] }
}

@MainActor
private final class TestTargetOpener: ProviderTargetOpening {
    var apps: [URL] = []
    var links: [URL] = []
    var failApp = false
    var linkSuccess = true

    func openApplication(at url: URL) async throws {
        apps.append(url)
        if failApp { throw CocoaError(.fileNoSuchFile) }
    }

    func openLink(_ url: URL) -> Bool {
        links.append(url)
        return linkSuccess
    }
}

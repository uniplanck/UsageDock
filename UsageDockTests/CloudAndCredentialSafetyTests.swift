import Foundation
import LocalAuthentication
import Security
import XCTest
@testable import UsageDock

private func cloudFixture(stale: Bool = false, ok: Bool = true) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "version": 1, "updated_epoch": 1000,
        "providers": ["kimi_vivace": [
            "name": "Kimi", "account_label": "Vivace", "ok": ok, "stale": stale,
            "fetched_at": 900, "error": NSNull(),
            "windows": [
                ["key": "five_hour", "label": "5時間", "used_percent": 12.0, "window_seconds": 18000, "resets_at": 950, "extra": false],
                ["key": "weekly", "label": "週間", "used_percent": 34.5, "window_seconds": 604800, "resets_at": NSNull(), "extra": false]
            ]
        ]]
    ])
}

private final class CloudFixtureProtocol: URLProtocol {
    static var captured: URLRequest?
    static var responseData = Data()
    static var statusCode = 200
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.captured = request
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.statusCode, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseData)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class CloudKimiSnapshotTests: XCTestCase {
    func testParsesOnlyVivaceFiveHourAndWeeklyInPercentUnits() throws {
        let result = try CloudKimiSnapshot.parse(cloudFixture())
        XCTAssertTrue(result.isFresh)
        XCTAssertEqual(result.fetchedAt, Date(timeIntervalSince1970: 900))
        XCTAssertEqual(result.buckets.map(\.quotaID), ["kimi-300", "kimi-weekly"])
        XCTAssertEqual(result.buckets[0].percentUsed ?? -1, 0.12, accuracy: 0.000001)
        XCTAssertEqual(result.buckets[1].percentUsed ?? -1, 0.345, accuracy: 0.000001)
        XCTAssertEqual(result.buckets[0].resetsAt, Date(timeIntervalSince1970: 950))
        XCTAssertNil(result.buckets[1].resetsAt)
    }

    func testMissingProviderInvalidWindowAndUnsupportedVersionFailClosed() throws {
        for object: [String: Any] in [
            ["version": 1, "updated_epoch": 1000, "providers": [:]],
            ["version": 2, "updated_epoch": 1000, "providers": [:]],
            ["version": 1, "updated_epoch": 1000, "providers": ["kimi_vivace": ["ok": true, "stale": false, "fetched_at": 900, "windows": []]]]
        ] {
            XCTAssertThrowsError(try CloudKimiSnapshot.parse(JSONSerialization.data(withJSONObject: object)))
        }
        XCTAssertFalse(try CloudKimiSnapshot.parse(cloudFixture(stale: true)).isFresh)
        XCTAssertFalse(try CloudKimiSnapshot.parse(cloudFixture(ok: false)).isFresh)
    }

    func testFetchUsesConfigKeyUserAgentAndTenSecondTimeout() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory); CloudFixtureProtocol.captured = nil; CloudFixtureProtocol.statusCode = 200 }
        let config = directory.appendingPathComponent("cloud.json")
        try Data(#"{"read_key":"test-key"}"#.utf8).write(to: config)
        CloudFixtureProtocol.responseData = try cloudFixture()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CloudFixtureProtocol.self]
        let result = try await CloudKimiSnapshot.fetch(configURL: config, session: URLSession(configuration: configuration))
        XCTAssertTrue(result.isFresh)
        let request = try XCTUnwrap(CloudFixtureProtocol.captured)
        XCTAssertEqual(request.url?.host, "usage-widget.naoyamao-world.workers.dev")
        XCTAssertEqual(request.url?.path, "/u/test-key")
        XCTAssertEqual(request.value(forHTTPHeaderField: "User-Agent"), "usage-widget/1.0")
        XCTAssertEqual(request.timeoutInterval, 10)
        CloudFixtureProtocol.statusCode = 503
        do {
            _ = try await CloudKimiSnapshot.fetch(configURL: config, session: URLSession(configuration: configuration))
            XCTFail("An HTTP failure must fail closed")
        } catch {
            XCTAssertEqual(error.localizedDescription, "クラウド未取得")
        }
    }
}

@MainActor
private final class SafetyLoginOpener: ClaudeLoginOpening {
    var calls = 0
    func openLogin(configDirectory: URL) throws { calls += 1 }
}

@MainActor
final class CloudKimiStoreTests: XCTestCase {
    func testMigratesExistingVivaceOnceBeforeAllegroWithoutCredentialPaths() async throws {
        let suite = "CloudKimiTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("cloud.json")
        try Data("{}".utf8).write(to: config)
        let vivace = UsageAccount(provider: .kimi, name: "Vivace", source: .profile,
                                  credentialPath: "/fixture/vivace", profileHomePath: "/fixture/home", buckets: [
                                    UsageBucket(quotaID: "kimi-300", label: "5h", kind: .fiveHour, percentUsed: 0.1),
                                    UsageBucket(quotaID: "kimi-weekly", label: "1w", kind: .weekly, percentUsed: 0.2),
                                    UsageBucket(quotaID: "kimi-total", label: "Total", kind: .credits, percentUsed: 0.3)
                                  ])
        let allegro = UsageAccount(provider: .kimi, name: "Allegro", source: .profile,
                                   credentialPath: "/fixture/allegro", buckets: [])
        defaults.set(try JSONEncoder().encode([allegro, vivace]), forKey: "UsageDock.accounts.v3")
        let opener = SafetyLoginOpener()
        var loginLaunches = 0
        let store = UsageStore(defaults: defaults, claudeLoginOpener: opener,
                               kimiUsageFetcher: { _ in XCTFail("Cloud must not use local Kimi credentials"); throw CloudKimiSnapshot.Failure.unavailable },
                               kimiIdentityReader: { _ in nil }, cloudConfigURL: config,
                               cloudUsageFetcher: { _ in try CloudKimiSnapshot.parse(cloudFixture()) },
                               profileLoginLauncher: { _, _ in loginLaunches += 1; throw CloudKimiSnapshot.Failure.unavailable })
        XCTAssertEqual(store.accounts.map(\.name), ["Vivace", "Allegro"])
        XCTAssertEqual(store.accounts[0].id, vivace.id)
        XCTAssertEqual(store.accounts[0].source, .cloudSnapshot)
        XCTAssertNil(store.accounts[0].credentialPath)
        XCTAssertNil(store.accounts[0].profileHomePath)
        XCTAssertEqual(store.accounts[0].buckets.map(\.quotaID), ["kimi-300", "kimi-weekly"])
        store.accounts[1].isEnabled = false
        await store.refreshProvider(.kimi)
        XCTAssertEqual(store.accounts[0].buckets.count, 2)
        XCTAssertEqual(opener.calls, 0)
        XCTAssertEqual(loginLaunches, 0)
        XCTAssertThrowsError(try KimiCredentialResolver.credentialPath(for: store.accounts[0]))
        XCTAssertEqual(store.displayAuthenticationState(for: store.accounts[0]), .valid)
        store.removeAccount(id: vivace.id)
        let restarted = UsageStore(defaults: defaults, cloudConfigURL: config)
        XCTAssertFalse(restarted.accounts.contains { $0.source == .cloudSnapshot })
    }

    func testFailureAndStaleResponseKeepLastValuesGreyAndNeverLaunchLogin() async throws {
        let suite = "CloudKimiTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: directory) }
        let config = directory.appendingPathComponent("cloud.json")
        try Data("{}".utf8).write(to: config)
        var date = Date(timeIntervalSince1970: 1000)
        var mode = 0
        let opener = SafetyLoginOpener()
        var loginLaunches = 0
        let store = UsageStore(defaults: defaults, claudeLoginOpener: opener, now: { date },
                               kimiUsageFetcher: { _ in XCTFail("Cloud must not fetch local login"); throw CloudKimiSnapshot.Failure.unavailable },
                               cloudConfigURL: config, cloudUsageFetcher: { _ in
            if mode == 1 { throw CloudKimiSnapshot.Failure.unavailable }
            return try CloudKimiSnapshot.parse(cloudFixture(stale: mode == 2))
        }, profileLoginLauncher: { _, _ in loginLaunches += 1; throw CloudKimiSnapshot.Failure.unavailable })
        let id = try XCTUnwrap(store.accounts.first?.id)
        let target = RailDisplayTarget.account(id: id, provider: .kimi)
        XCTAssertEqual(store.refreshFailureLabel(for: target), "クラウド未取得")
        await store.refreshProvider(.kimi)
        XCTAssertNil(store.refreshFailureLabel(for: target))
        date += 61; mode = 1
        await store.refreshProvider(.kimi)
        XCTAssertEqual(store.refreshFailureLabel(for: target), "クラウド未取得")
        XCTAssertEqual(store.summary(for: target, now: date).aggregates.first?.percentUsed ?? -1, 0.12, accuracy: 0.000001)
        XCTAssertEqual(store.displayAuthenticationState(for: store.accounts[0]), .valid)
        date += 61; mode = 2
        await store.refreshProvider(.kimi)
        XCTAssertEqual(store.refreshFailureLabel(for: target), "クラウド未取得")
        XCTAssertEqual(opener.calls, 0)
        XCTAssertEqual(loginLaunches, 0)
    }

    func testMissingLocalKimiProfileNeverAutoOpensTerminal() async {
        let suite = "CloudKimiTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let opener = SafetyLoginOpener()
        var loginLaunches = 0
        let store = UsageStore(defaults: defaults, claudeLoginOpener: opener,
                               kimiUsageFetcher: { _ in XCTFail("Missing path must not be used"); throw CloudKimiSnapshot.Failure.unavailable },
                               profileLoginLauncher: { _, _ in loginLaunches += 1; throw CloudKimiSnapshot.Failure.unavailable })
        store.accounts = [UsageAccount(provider: .kimi, name: "Allegro", source: .profile, buckets: [])]
        await store.refreshProvider(.kimi)
        XCTAssertEqual(opener.calls, 0)
        XCTAssertEqual(loginLaunches, 0)
    }
}

final class SecureCredentialFileStoreTests: XCTestCase {
    func testPrivateDirectoryFileAndAtomicReplacementPermissions() throws {
        let parent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: parent) }
        let store = SecureCredentialFileStore(directory: parent.appendingPathComponent("UsageDock"))
        try store.write(Data("first".utf8), account: "fixture")
        try store.write(Data("replacement".utf8), account: "fixture")
        XCTAssertEqual(store.read(account: "fixture"), Data("replacement".utf8))
        func mode(_ url: URL) throws -> Int {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            return (attributes[.posixPermissions] as? NSNumber)?.intValue ?? -1
        }
        XCTAssertEqual(try mode(store.directory), 0o700)
        XCTAssertEqual(try mode(store.fileURL(account: "fixture")), 0o600)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: store.directory.path).count, 1)
    }

    func testMigrationStartsEmptyAndDoesNotConsultAnyKeychain() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cache = ClaudeCredentialCache(readOwned: { _ in
            XCTFail("No source means the old app-owned item must not be read")
            return nil
        })
        let records = await Task.detached {
            ClaudeCredentialStore.credentialRecords(fileURL: file, cache: cache)
        }.value
        XCTAssertTrue(records.isEmpty)
    }

    func testSourceFileReacquiresPrivateCopy() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent(".credentials.json")
        let data = Data(#"{"claudeAiOauth":{"accessToken":"synthetic"}}"#.utf8)
        try data.write(to: source)
        let store = SecureCredentialFileStore(directory: directory.appendingPathComponent("private"))
        let cache = ClaudeCredentialCache(readOwned: { store.read(account: $0) },
                                         writeOwned: { account, data in try? store.write(data, account: account) })
        let records = await Task.detached { ClaudeCredentialStore.credentialRecords(fileURL: source, cache: cache) }.value
        XCTAssertEqual(records.first?.data, data)
        let account = "file:\(source.standardizedFileURL.path)"
        XCTAssertNotNil(store.read(account: account))
        let mode = try FileManager.default.attributesOfItem(atPath: store.fileURL(account: account).path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)
    }

    func testExplicitImportKeepsOnlyValidAccessTokenAndUsesPrivateFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SecureCredentialFileStore(directory: directory)
        let credentialPath = "/fixture/claude/.credentials.json"
        let source = Data(#"{"claudeAiOauth":{"accessToken":"synthetic-access","refreshToken":"synthetic-refresh","expiresAt":4000000000000,"subscriptionType":"max"},"otherSecret":"synthetic-other"}"#.utf8)
        try ClaudeCredentialStore.importKeychainCredential(source, credentialPath: credentialPath,
                                                          store: store, now: Date(timeIntervalSince1970: 1000))
        let importedID = "imported:\(ClaudeCredentialStore.providerKeychainService(credentialPath: credentialPath))"
        let saved = try XCTUnwrap(store.read(account: importedID))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        let oauth = try XCTUnwrap(root["claudeAiOauth"] as? [String: Any])
        XCTAssertEqual(Set(root.keys), ["claudeAiOauth"])
        XCTAssertEqual(Set(oauth.keys), ["accessToken", "expiresAt", "subscriptionType"])
        XCTAssertNil(oauth["refreshToken"])
        let mode = try FileManager.default.attributesOfItem(atPath: store.fileURL(account: importedID).path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(mode?.intValue, 0o600)

        let cache = ClaudeCredentialCache(readOwned: { _ in nil })
        let missing = directory.appendingPathComponent("missing-source")
        let imported = await Task.detached {
            ClaudeCredentialStore.credentialRecords(fileURL: missing, cache: cache, importedID: importedID,
                                                     readImported: { store.read(account: importedID) })
        }.value
        XCTAssertEqual(imported.first?.data, saved)

        let authoritative = Data(#"{"claudeAiOauth":{"accessToken":"source-wins"}}"#.utf8)
        try authoritative.write(to: missing)
        let sourceRecords = await Task.detached {
            ClaudeCredentialStore.credentialRecords(fileURL: missing, cache: cache, reload: true,
                                                     importedID: importedID, readImported: { store.read(account: importedID) })
        }.value
        XCTAssertEqual(sourceRecords.first?.data, authoritative)
        try Data("malformed".utf8).write(to: missing)
        let malformed = await Task.detached {
            ClaudeCredentialStore.credentialRecords(fileURL: missing, cache: cache, reload: true,
                                                     importedID: importedID, readImported: { XCTFail("Existing source is authoritative"); return nil })
        }.value
        XCTAssertTrue(malformed.isEmpty)
    }

    func testExplicitImportRejectsExpiredOrMalformedCredentials() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = SecureCredentialFileStore(directory: directory)
        for payload in ["{}", #"{"claudeAiOauth":{"accessToken":"synthetic","expiresAt":10}}"#] {
            XCTAssertThrowsError(try ClaudeCredentialStore.importKeychainCredential(Data(payload.utf8), credentialPath: "/fixture/.credentials.json",
                                                                                     store: store, now: Date(timeIntervalSince1970: 1000)))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
    }

    func testImportAllowsRecoveryWithoutWaitingForPreviousBackoff() async throws {
        func record(_ token: String, expiry: Int) throws -> ClaudeCredentialStore.CredentialRecord {
            let data = try JSONSerialization.data(withJSONObject: ["claudeAiOauth": ["accessToken": token, "expiresAt": expiry]])
            return .init(data: data, target: .init(account: "fixture", sourceFingerprint: token))
        }
        var source = try record("expired-fixture", expiry: 100)
        let resolver = ClaudeCredentialResolver(records: { _, _ in [source] }, runCLI: { _ in .unavailable },
                                                now: { Date(timeIntervalSince1970: 1000) })
        do { _ = try await resolver.accessToken(); XCTFail("Expired credential must fail") } catch {}
        source = try record("new-fixture", expiry: 2000)
        await resolver.credentialWasImported(credentialPath: nil)
        let token = try await resolver.accessToken()
        XCTAssertEqual(token, "new-fixture")
    }
}

@MainActor
final class KeychainWarningTests: XCTestCase {
    func testExplicitProbeDisablesInteractionWithoutCallingSecurity() {
        let result = ClaudeKeychainProbe.check(service: "fixture") { query, _ in
            let dictionary = query as NSDictionary
            let context = dictionary[kSecUseAuthenticationContext] as? LAContext
            XCTAssertEqual(context?.interactionNotAllowed, true)
            XCTAssertEqual(dictionary[kSecAttrService] as? String, "fixture")
            return errSecInteractionNotAllowed
        }
        XCTAssertEqual(result.status, errSecInteractionNotAllowed)
        XCTAssertNil(result.data)
    }

    func testInteractionStatusesAndRateLimit() {
        XCTAssertTrue(ClaudeKeychainProbe.requiresInteraction(errSecInteractionNotAllowed))
        XCTAssertTrue(ClaudeKeychainProbe.requiresInteraction(errSecAuthFailed))
        XCTAssertFalse(ClaudeKeychainProbe.requiresInteraction(errSecItemNotFound))
        let suite = "KeychainWarningTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var date = Date(timeIntervalSince1970: 1000)
        var requests = 0
        var deliveries = 0
        let notifier = KeychainWarningNotifier(defaults: defaults, now: { date }, requestAuthorization: { completion in
            requests += 1; completion(true)
        }, deliver: { deliveries += 1 })
        notifier.warn(); notifier.warn()
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(deliveries, 1)
        date += 3600
        notifier.warn()
        XCTAssertEqual(requests, 1)
        XCTAssertEqual(deliveries, 2)
    }

    func testMissingFileShowsWarningWithoutOpeningTerminal() async {
        let suite = "KeychainWarningTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var notifications = 0
        let notifier = KeychainWarningNotifier(defaults: defaults, requestAuthorization: { $0(true) }, deliver: { notifications += 1 })
        let opener = SafetyLoginOpener()
        let store = UsageStore(defaults: defaults, claudeLoginOpener: opener, usageFetcher: { _ in
            throw UsageAdapterError.keychainAccessRequired
        }, keychainWarningNotifier: notifier, keychainProbe: { _ in
            XCTFail("Background refresh must not query Keychain")
            return .init(status: errSecAuthFailed, data: nil)
        })
        let account = UsageAccount(provider: .claude, name: "Claude", source: .profile, buckets: [])
        store.accounts = [account]
        await store.refreshProvider(.claude)
        XCTAssertEqual(opener.calls, 0)
        XCTAssertEqual(notifications, 1)
        XCTAssertNotNil(store.refreshFailureLabel(for: .account(id: account.id, provider: .claude)))
    }

    func testExplicitProbeFailureNotifiesAndMarksOnlyThatAccount() async {
        let suite = "KeychainWarningTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var notifications = 0
        let notifier = KeychainWarningNotifier(defaults: defaults, requestAuthorization: { $0(true) }, deliver: { notifications += 1 })
        let store = UsageStore(defaults: defaults, keychainWarningNotifier: notifier,
                               keychainProbe: { _ in .init(status: errSecAuthFailed, data: nil) })
        let account = UsageAccount(provider: .claude, name: "Claude", source: .profile,
                                   credentialPath: "/fixture/.claude/.credentials.json", buckets: [])
        store.accounts = [account]
        await store.importClaudeKeychain(for: account)
        XCTAssertEqual(notifications, 1)
        XCTAssertTrue(store.claudeKeychainWarningIDs.contains(account.id))
        XCTAssertNotNil(store.claudeKeychainCheckMessages[account.id])
    }

    func testExplicitCurrentSessionImportRegistersOnlyAfterSuccessfulRead() async {
        let suite = "KeychainWarningTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let fixture = Data("synthetic-data".utf8)
        var imports = 0
        let store = UsageStore(defaults: defaults, keychainProbe: { _ in .init(status: errSecSuccess, data: fixture) },
                               importClaudeCredential: { data, path in
            XCTAssertEqual(data, fixture)
            XCTAssertNil(path)
            imports += 1
        })
        await store.importClaudeCurrentSession()
        XCTAssertEqual(imports, 1)
        XCTAssertEqual(store.accounts.filter { $0.provider == .claude && $0.source == .currentSession }.count, 1)
    }

    func testExplicitImportNeverFallsBackToDefaultForMissingProfilePath() async {
        let suite = "KeychainWarningTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = UsageStore(defaults: defaults, keychainProbe: { _ in
            XCTFail("Missing profile must not query the default Keychain")
            return .init(status: errSecSuccess, data: nil)
        })
        let account = UsageAccount(provider: .claude, name: "Missing", source: .profile, buckets: [])
        store.accounts = [account]
        await store.importClaudeKeychain(for: account)
        XCTAssertNotNil(store.claudeKeychainCheckMessages[account.id])
    }
}

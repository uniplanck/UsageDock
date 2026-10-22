import SwiftUI
import XCTest
@testable import UsageDock

final class UsageDockDistributionPolicyTests: XCTestCase {
    func testLoginSourceAllowlistAcceptsOnlyAuthenticatedSources() {
        XCTAssertTrue(UsageDockDistributionPolicy.isPublicLoginSource(.currentSession))
        XCTAssertTrue(UsageDockDistributionPolicy.isPublicLoginSource(.profile))
        XCTAssertFalse(UsageDockDistributionPolicy.isPublicLoginSource(.legacyUnsupported))
        XCTAssertFalse(UsageDockDistributionPolicy.isPublicLoginSource(nil))
    }

    @MainActor
    func testFreshStoreStartsWithoutAccounts() {
        let suiteName = "UsageDockTests.LoginOnly.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(UsageStore(defaults: defaults).accounts.isEmpty)
    }
}

final class ClaudeCredentialStoreTests: XCTestCase {
    func testProfileKeychainServiceUsesNormalizedConfigDirectoryHashPrefix() {
        XCTAssertEqual(
            ClaudeCredentialStore.keychainServiceName(
                configDirectory: "/tmp/UsageDock/Profiles/claude/test/.claude"
            ),
            "Claude Code-credentials-fb1ebbbb"
        )
    }

    func testRefreshMergeRotatesTokensAndUpdatesExpiryWithoutDroppingMetadata() throws {
        let original = try JSONSerialization.data(withJSONObject: [
            "claudeAiOauth": [
                "accessToken": "old-access",
                "refreshToken": "old-refresh",
                "expiresAt": 1_000,
                "subscriptionType": "pro",
                "rateLimitTier": "default"
            ],
            "mcpOAuth": ["preserve": true]
        ])
        let refreshed = try JSONSerialization.data(withJSONObject: [
            "access_token": "new-access",
            "refresh_token": "new-refresh",
            "expires_in": 3_600,
            "refresh_token_expires_in": 7_200,
            "scope": "user:profile user:inference"
        ])
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        let merged = try ClaudeCredentialStore.mergedCredentialData(
            originalData: original,
            refreshData: refreshed,
            now: now
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: merged.data) as? [String: Any])
        let oauth = try XCTUnwrap(root["claudeAiOauth"] as? [String: Any])

        XCTAssertEqual(merged.accessToken, "new-access")
        XCTAssertEqual(oauth["accessToken"] as? String, "new-access")
        XCTAssertEqual(oauth["refreshToken"] as? String, "new-refresh")
        XCTAssertEqual(oauth["expiresAt"] as? Int, 1_700_003_600_000)
        XCTAssertEqual(oauth["refreshTokenExpiresAt"] as? Int, 1_700_007_200_000)
        XCTAssertEqual(oauth["scopes"] as? [String], ["user:profile", "user:inference"])
        XCTAssertEqual(oauth["subscriptionType"] as? String, "pro")
        XCTAssertNotNil(root["mcpOAuth"])
    }

    func testRefreshMergeKeepsExistingRefreshTokenWhenServerDoesNotRotateIt() throws {
        let original = try JSONSerialization.data(withJSONObject: [
            "claudeAiOauth": [
                "accessToken": "old-access",
                "refreshToken": "keep-refresh",
                "expiresAt": 1_000
            ]
        ])
        let refreshed = try JSONSerialization.data(withJSONObject: [
            "access_token": "new-access",
            "expires_in": 60
        ])

        let merged = try ClaudeCredentialStore.mergedCredentialData(
            originalData: original,
            refreshData: refreshed,
            now: Date(timeIntervalSince1970: 2_000)
        )
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: merged.data) as? [String: Any])
        let oauth = try XCTUnwrap(root["claudeAiOauth"] as? [String: Any])

        XCTAssertEqual(oauth["refreshToken"] as? String, "keep-refresh")
        XCTAssertEqual(oauth["expiresAt"] as? Int, 2_060_000)
    }
}

final class UsageAggregatorTests: XCTestCase {
    func testExactAggregationUsesCapacityWeighting() throws {
        let accounts = [
            account(name: "A", bucket: UsageBucket(quotaID: "five-hour", label: "5h", kind: .fiveHour, used: 80, limit: 100, unit: "requests")),
            account(name: "B", bucket: UsageBucket(quotaID: "five-hour", label: "5h", kind: .fiveHour, used: 100, limit: 500, unit: "requests"))
        ]

        let aggregate = try XCTUnwrap(UsageAggregator.aggregates(for: .claude, accounts: accounts).first)
        XCTAssertEqual(aggregate.quality, .exact)
        XCTAssertEqual(aggregate.percentUsed ?? -1, 0.3, accuracy: 0.0001)
        XCTAssertEqual(aggregate.accountCount, 2)
    }

    func testPercentageOnlyAggregationIsExplicitFallback() throws {
        let accounts = [
            account(name: "A", bucket: UsageBucket(quotaID: "weekly", label: "1w", kind: .weekly, percentUsed: 0.8)),
            account(name: "B", bucket: UsageBucket(quotaID: "weekly", label: "1w", kind: .weekly, percentUsed: 0.2))
        ]

        let aggregate = try XCTUnwrap(UsageAggregator.aggregates(for: .claude, accounts: accounts).first)
        XCTAssertEqual(aggregate.quality, .unweightedAverage)
        XCTAssertEqual(aggregate.percentUsed ?? -1, 0.5, accuracy: 0.0001)
    }

    func testIncompatibleUnitsNeverClaimExactTotal() throws {
        let accounts = [
            account(name: "A", bucket: UsageBucket(quotaID: "five-hour", label: "5h", kind: .fiveHour, used: 80, limit: 100, unit: "requests")),
            account(name: "B", bucket: UsageBucket(quotaID: "five-hour", label: "5h", kind: .fiveHour, used: 100, limit: 500, unit: "tokens"))
        ]

        let aggregate = try XCTUnwrap(UsageAggregator.aggregates(for: .claude, accounts: accounts).first)
        XCTAssertEqual(aggregate.quality, .unweightedAverage)
        XCTAssertEqual(aggregate.percentUsed ?? -1, 0.5, accuracy: 0.0001)
    }

    func testMissingUsageBecomesUnavailable() throws {
        let accounts = [
            account(name: "A", bucket: UsageBucket(quotaID: "weekly", label: "1w", kind: .weekly, percentUsed: 0.4)),
            account(name: "B", bucket: UsageBucket(quotaID: "weekly", label: "1w", kind: .weekly))
        ]

        let aggregate = try XCTUnwrap(UsageAggregator.aggregates(for: .claude, accounts: accounts).first)
        XCTAssertEqual(aggregate.quality, .unavailable)
        XCTAssertNil(aggregate.percentUsed)
    }

    private func account(name: String, bucket: UsageBucket) -> UsageAccount {
        UsageAccount(provider: .claude, name: name, buckets: [bucket])
    }
}

@MainActor
final class AntigravityRailQuotaTests: XCTestCase {
    private let fixtureText = """
    Gemini Models\t5 hour\t80%\t2026-10-22T17:00:00Z
    Gemini Models\tweekly\t60%\t2026-10-29T17:00:00Z
    Claude and GPT models\t5 hour\t45%\t2026-10-22T18:00:00Z
    Claude and GPT models\tweekly\t25%\t2026-10-29T18:00:00Z
    """

    private func fixtureBuckets() throws -> [UsageBucket] {
        try AntigravityUsageAdapter.parseUsage(text: fixtureText)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func bucket(_ quotaID: String, in buckets: [UsageBucket]) throws -> UsageBucket {
        try XCTUnwrap(buckets.first(where: { $0.quotaID == quotaID }))
    }

    func testAntigravityFixtureParsesAllBucketsWithActualValuesAndResets() throws {
        let buckets = try fixtureBuckets()
        let expected: [(id: String, label: String, kind: UsageWindowKind, percent: Double, reset: String)] = [
            ("antigravity-gemini-models-fiveHour", "Gemini Models · 5h", .fiveHour, 0.20, "2026-10-22T17:00:00Z"),
            ("antigravity-gemini-models-weekly", "Gemini Models · 1w", .weekly, 0.40, "2026-10-29T17:00:00Z"),
            ("antigravity-claude-and-gpt-models-fiveHour", "Claude and GPT models · 5h", .fiveHour, 0.55, "2026-10-22T18:00:00Z"),
            ("antigravity-claude-and-gpt-models-weekly", "Claude and GPT models · 1w", .weekly, 0.75, "2026-10-29T18:00:00Z")
        ]

        XCTAssertEqual(buckets.count, expected.count)
        for item in expected {
            let parsed = try bucket(item.id, in: buckets)
            XCTAssertEqual(parsed.label, item.label)
            XCTAssertEqual(parsed.kind, item.kind)
            XCTAssertEqual(parsed.percentUsed ?? -1, item.percent, accuracy: 0.0001)
            XCTAssertEqual(parsed.resetsAt, date(item.reset))
        }
    }

    func testAntigravityRailBucketSourcesReturnSelectedValuesAndResetDates() throws {
        let buckets = try fixtureBuckets()
        let accountID = UUID()
        let account = UsageAccount(
            id: accountID,
            provider: .antigravity,
            name: "Antigravity Session",
            source: .currentSession,
            buckets: buckets
        )
        let suiteName = "UsageDockTests.AntigravityRailValues.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(defaults: defaults)
        store.accounts = [account]
        let target = RailDisplayTarget.account(id: accountID, provider: .antigravity)
        let expected: [(id: String, percent: Double, reset: String)] = [
            ("antigravity-gemini-models-fiveHour", 0.20, "2026-10-22T17:00:00Z"),
            ("antigravity-gemini-models-weekly", 0.40, "2026-10-29T17:00:00Z"),
            ("antigravity-claude-and-gpt-models-fiveHour", 0.55, "2026-10-22T18:00:00Z"),
            ("antigravity-claude-and-gpt-models-weekly", 0.75, "2026-10-29T18:00:00Z")
        ]

        for item in expected {
            let source = RailQuotaSource.bucket(quotaID: item.id)
            let aggregate = try XCTUnwrap(store.railAggregate(for: target, source: source))
            XCTAssertEqual(aggregate.quotaID, item.id)
            XCTAssertEqual(aggregate.percentUsed ?? -1, item.percent, accuracy: 0.0001)
            XCTAssertEqual(store.railDisplayPercent(for: target, source: source) ?? -1, item.percent, accuracy: 0.0001)
            XCTAssertEqual(store.railResetDate(for: target, source: source), date(item.reset))
            store.presentationMode = .remaining
            XCTAssertEqual(store.railDisplayPercent(for: target, source: source) ?? -1, 1 - item.percent, accuracy: 0.0001)
            store.presentationMode = .used
        }
    }

    func testAntigravityDefaultsAndLegacyWindowSelectionStayUnchanged() throws {
        let suiteName = "UsageDockTests.AntigravityRailDefaults.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(defaults: defaults)
        let buckets = try fixtureBuckets()
        let account = UsageAccount(provider: .antigravity, name: "Antigravity", source: .currentSession, buckets: buckets)
        store.accounts = [account]
        let target = RailDisplayTarget.account(id: account.id, provider: .antigravity)

        XCTAssertEqual(store.railPercentSource(for: target), .automatic)
        XCTAssertEqual(store.railOuterRingSource(for: target), .automatic)
        XCTAssertEqual(store.railInnerRingSource(for: target), .none)
        XCTAssertEqual(store.railTimeSource(for: target), .weekly)
        XCTAssertEqual(store.railAggregate(for: target, source: .fiveHour)?.quotaID, buckets[0].quotaID)
        XCTAssertEqual(store.railAggregate(for: target, source: .weekly)?.quotaID, buckets[1].quotaID)
        XCTAssertEqual(store.railDisplayPercent(for: target, source: .automatic) ?? -1, 0.75, accuracy: 0.0001)
        XCTAssertEqual(store.railResetDate(for: target, source: .automatic), buckets[3].resetsAt)
        XCTAssertNil(store.railDisplayPercent(for: target, source: .none))
        XCTAssertNil(store.railResetDate(for: target, source: .none))
    }

    func testAntigravityRailOverridesPersistIndependentlyByAccountAndProvider() throws {
        let buckets = try fixtureBuckets()
        let firstID = UUID()
        let secondID = UUID()
        let claudeID = UUID()
        var first = UsageAccount(
            id: firstID,
            provider: .antigravity,
            name: "Antigravity A",
            source: .currentSession,
            buckets: buckets
        )
        first.railPercentSource = .bucket(quotaID: "antigravity-gemini-models-fiveHour")
        first.railOuterRingSource = .bucket(quotaID: "antigravity-gemini-models-weekly")
        first.railInnerRingSource = .bucket(quotaID: "antigravity-claude-and-gpt-models-fiveHour")
        first.railTimeSource = .bucket(quotaID: "antigravity-claude-and-gpt-models-weekly")
        let second = UsageAccount(
            id: secondID,
            provider: .antigravity,
            name: "Antigravity B",
            source: .currentSession,
            buckets: buckets
        )
        let otherProvider = UsageAccount(
            id: claudeID,
            provider: .claude,
            name: "Claude",
            source: .currentSession,
            buckets: [UsageBucket(quotaID: "claude-weekly", label: "1w", kind: .weekly, percentUsed: 0.3)]
        )
        let suiteName = "UsageDockTests.AntigravityRailOverrides.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(defaults: defaults)
        store.railPercentSource = .automatic
        store.railOuterRingSource = .weekly
        store.railInnerRingSource = .none
        store.railTimeSource = .fiveHour
        store.accounts = [first, second, otherProvider]

        let restored = UsageStore(defaults: defaults)
        let firstTarget = RailDisplayTarget.account(id: firstID, provider: .antigravity)
        let secondTarget = RailDisplayTarget.account(id: secondID, provider: .antigravity)
        let providerTarget = RailDisplayTarget.provider(.claude)
        XCTAssertEqual(restored.railPercentSource(for: firstTarget), .bucket(quotaID: "antigravity-gemini-models-fiveHour"))
        XCTAssertEqual(restored.railOuterRingSource(for: firstTarget), .bucket(quotaID: "antigravity-gemini-models-weekly"))
        XCTAssertEqual(restored.railInnerRingSource(for: firstTarget), .bucket(quotaID: "antigravity-claude-and-gpt-models-fiveHour"))
        XCTAssertEqual(restored.railTimeSource(for: firstTarget), .bucket(quotaID: "antigravity-claude-and-gpt-models-weekly"))
        XCTAssertEqual(restored.railPercentSource(for: secondTarget), .automatic)
        XCTAssertEqual(restored.railOuterRingSource(for: secondTarget), .weekly)
        XCTAssertEqual(restored.railInnerRingSource(for: secondTarget), .none)
        XCTAssertEqual(restored.railTimeSource(for: secondTarget), .fiveHour)
        XCTAssertEqual(restored.railPercentSource(for: providerTarget), .automatic)
        XCTAssertEqual(restored.railOuterRingSource(for: providerTarget), .weekly)
        XCTAssertEqual(restored.railInnerRingSource(for: providerTarget), .none)
        XCTAssertEqual(restored.railTimeSource(for: providerTarget), .fiveHour)
    }

    func testRailQuotaSourceKeepsLegacyRawValuesAndBucketEncoding() throws {
        let expected: [(source: RailQuotaSource, raw: String)] = [
            (.none, "none"),
            (.automatic, "automatic"),
            (.fiveHour, "fiveHour"),
            (.weekly, "weekly"),
            (.bucket(quotaID: "antigravity-claude-and-gpt-models-weekly"), "bucket:antigravity-claude-and-gpt-models-weekly")
        ]

        for item in expected {
            XCTAssertEqual(item.source.rawValue, item.raw)
            let encoded = try JSONEncoder().encode(item.source)
            XCTAssertEqual(String(data: encoded, encoding: .utf8), "\"\(item.raw)\"")
            XCTAssertEqual(try JSONDecoder().decode(RailQuotaSource.self, from: encoded), item.source)
        }
    }

    func testAntigravityOldSettingsAndAccountsWithoutOverridesRemainReadable() throws {
        let accountID = UUID()
        let legacyAccount = UsageAccount(
            id: accountID,
            provider: .antigravity,
            name: "Legacy Antigravity",
            source: .currentSession,
            buckets: [UsageBucket(quotaID: "legacy-weekly", label: "1w", kind: .weekly, percentUsed: 0.4)]
        )
        var legacyObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(legacyAccount)) as? [String: Any]
        )
        for key in ["railPercentSource", "railOuterRingSource", "railInnerRingSource", "railTimeSource"] {
            legacyObject.removeValue(forKey: key)
        }
        let suiteName = "UsageDockTests.AntigravityLegacySettings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            try JSONSerialization.data(withJSONObject: [legacyObject]),
            forKey: "UsageDock.accounts.v3"
        )
        defaults.set("fiveHour", forKey: "UsageDock.railPercentSource.v1")
        defaults.set("weekly", forKey: "UsageDock.railOuterRingSource.v1")
        defaults.set("none", forKey: "UsageDock.railInnerRingSource.v1")
        defaults.set("fiveHour", forKey: "UsageDock.railTimeSource.v1")

        let store = UsageStore(defaults: defaults)
        let account = try XCTUnwrap(store.accounts.first)
        XCTAssertEqual(account.id, accountID)
        XCTAssertNil(account.railPercentSource)
        XCTAssertNil(account.railOuterRingSource)
        XCTAssertNil(account.railInnerRingSource)
        XCTAssertNil(account.railTimeSource)
        let target = RailDisplayTarget.account(id: accountID, provider: .antigravity)
        XCTAssertEqual(store.railPercentSource(for: target), .fiveHour)
        XCTAssertEqual(store.railOuterRingSource(for: target), .weekly)
        XCTAssertEqual(store.railInnerRingSource(for: target), .none)
        XCTAssertEqual(store.railTimeSource(for: target), .fiveHour)
    }

    func testAntigravityBucketSelectionSurvivesRefreshUUIDRenameAndReorder() throws {
        let original = try fixtureBuckets().enumerated().map { index, bucket in
            var bucket = bucket
            bucket.id = UUID(uuidString: "00000000-0000-0000-0000-00000000000\(index + 1)")!
            return bucket
        }
        let fetched = original.reversed().map { bucket -> UsageBucket in
            var refreshed = bucket
            refreshed.id = UUID()
            refreshed.label = "Renamed \(bucket.label)"
            refreshed.percentUsed = min((bucket.percentUsed ?? 0) + 0.1, 1)
            return refreshed
        }
        let merged = UsageStore.mergeRefreshedBuckets(existing: original, fetched: fetched)
        XCTAssertEqual(merged.map(\.quotaID), original.map(\.quotaID))
        for saved in original {
            let refreshed = try XCTUnwrap(merged.first(where: { $0.quotaID == saved.quotaID }))
            XCTAssertEqual(refreshed.id, saved.id)
            XCTAssertTrue(refreshed.label.hasPrefix("Renamed "))
        }

        let selectedID = "antigravity-claude-and-gpt-models-weekly"
        let accountID = UUID()
        var account = UsageAccount(
            id: accountID,
            provider: .antigravity,
            name: "Antigravity",
            source: .currentSession,
            railPercentSource: .bucket(quotaID: selectedID),
            buckets: original
        )
        let suiteName = "UsageDockTests.AntigravityRefreshSelection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(defaults: defaults)
        store.accounts = [account]
        account.buckets = merged
        store.accounts = [account]
        let target = RailDisplayTarget.account(id: accountID, provider: .antigravity)
        let aggregate = try XCTUnwrap(store.railAggregate(for: target, source: .bucket(quotaID: selectedID)))
        let selectedFetched = try XCTUnwrap(fetched.first(where: { $0.quotaID == selectedID }))
        XCTAssertEqual(store.railPercentSource(for: target), .bucket(quotaID: selectedID))
        XCTAssertEqual(aggregate.label, selectedFetched.label)
        XCTAssertEqual(aggregate.percentUsed ?? -1, selectedFetched.percentUsed ?? -1, accuracy: 0.0001)
    }

    func testAntigravityHiddenOrMissingSelectedBucketDoesNotFallbackAndRecovers() throws {
        let allBuckets = try fixtureBuckets()
        let selectedID = "antigravity-gemini-models-fiveHour"
        let weeklyID = "antigravity-gemini-models-weekly"
        let accountID = UUID()
        var account = UsageAccount(
            id: accountID,
            provider: .antigravity,
            name: "Antigravity",
            source: .currentSession,
            railPercentSource: .bucket(quotaID: selectedID),
            buckets: allBuckets
        )
        let suiteName = "UsageDockTests.AntigravityMissingSelection.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(defaults: defaults)
        let target = RailDisplayTarget.account(id: accountID, provider: .antigravity)

        account.buckets[account.buckets.firstIndex(where: { $0.quotaID == selectedID })!].isEnabled = false
        store.accounts = [account]
        XCTAssertNil(store.railAggregate(for: target, source: .bucket(quotaID: selectedID)))
        XCTAssertNil(store.railDisplayPercent(for: target, source: .bucket(quotaID: selectedID)))
        XCTAssertNil(store.railResetDate(for: target, source: .bucket(quotaID: selectedID)))
        XCTAssertEqual(store.railAggregate(for: target, source: .bucket(quotaID: weeklyID))?.quotaID, weeklyID)

        account.buckets[account.buckets.firstIndex(where: { $0.quotaID == selectedID })!].isEnabled = true
        store.accounts = [account]
        XCTAssertEqual(store.railAggregate(for: target, source: .bucket(quotaID: selectedID))?.quotaID, selectedID)

        account.buckets.removeAll(where: { $0.quotaID == selectedID })
        store.accounts = [account]
        XCTAssertNil(store.railAggregate(for: target, source: .bucket(quotaID: selectedID)))
        XCTAssertNil(store.railDisplayPercent(for: target, source: .bucket(quotaID: selectedID)))
        XCTAssertNil(store.railResetDate(for: target, source: .bucket(quotaID: selectedID)))
        let missingSelection = RailQuotaSource.bucket(quotaID: selectedID)
        XCTAssertTrue(RailQuotaSource.options(buckets: account.buckets, selection: missingSelection, allowNone: false).contains(missingSelection))

        account.buckets = allBuckets
        store.accounts = [account]
        XCTAssertEqual(store.railAggregate(for: target, source: missingSelection)?.quotaID, selectedID)
    }

    func testAntigravityQuotaOptionsIncludeHiddenMissingAndNoDuplicates() throws {
        var buckets = try fixtureBuckets()
        var hidden = try bucket("antigravity-claude-and-gpt-models-weekly", in: buckets)
        hidden.id = UUID()
        hidden.isEnabled = false
        hidden.label = "Hidden renamed Claude and GPT models · 1w"
        buckets.append(hidden)
        let uniqueHiddenID = "antigravity-hidden-model-weekly"
        buckets.append(UsageBucket(quotaID: uniqueHiddenID, label: "Hidden model · 1w", kind: .weekly, isEnabled: false))
        let missing = RailQuotaSource.bucket(quotaID: "antigravity-removed-model-weekly")

        let options = RailQuotaSource.options(buckets: buckets, selection: missing, allowNone: false)
        let bucketIDs = options.compactMap { source -> String? in
            guard case .bucket(let quotaID) = source else { return nil }
            return quotaID
        }
        XCTAssertFalse(options.contains(.none))
        XCTAssertTrue(bucketIDs.contains(hidden.quotaID))
        XCTAssertTrue(bucketIDs.contains(uniqueHiddenID))
        XCTAssertTrue(bucketIDs.contains("antigravity-removed-model-weekly"))
        XCTAssertEqual(bucketIDs.filter { $0 == hidden.quotaID }.count, 1)
        XCTAssertEqual(Set(options).count, options.count)
        XCTAssertTrue(RailQuotaSource.options(buckets: buckets, selection: missing, allowNone: true).contains(.none))
        XCTAssertFalse(RailQuotaSource.options(buckets: buckets, selection: .some(.none), allowNone: false).contains(.none))
    }

    func testNamedQuotaSelectionAlsoWorksForOtherProvidersAndWindowKinds() throws {
        let buckets = [
            UsageBucket(quotaID: "included-credits", label: "Included credits", kind: .credits, percentUsed: 0.2),
            UsageBucket(quotaID: "extra-credits", label: "Additional credits", kind: .credits, percentUsed: 0.6)
        ]
        let selected = RailQuotaSource.bucket(quotaID: "extra-credits")
        let account = UsageAccount(
            provider: .codex,
            name: "Codex",
            source: .currentSession,
            railPercentSource: selected,
            buckets: buckets
        )
        let suiteName = "UsageDockTests.OtherProviderRailQuota.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(defaults: defaults)
        store.accounts = [account]
        let target = RailDisplayTarget.account(id: account.id, provider: .codex)
        XCTAssertTrue(RailQuotaSource.options(buckets: buckets, selection: nil, allowNone: false).contains(selected))
        XCTAssertEqual(store.railPercentSource(for: target), selected)
        XCTAssertEqual(store.railDisplayPercent(for: target, source: selected) ?? -1, 0.6, accuracy: 0.0001)
    }

    func testQuotaNameWrapsInsteadOfTruncatingAtNarrowWidths() {
        func height(_ name: String, width: CGFloat) -> CGFloat {
            let view = NSHostingView(rootView: QuotaNameLabel(name: name)
                .font(.caption.weight(.medium))
                .frame(width: width))
            return view.fittingSize.height
        }

        let name = "Claude and GPT models · 1w"
        let singleLineHeight = height("5h", width: 100)
        XCTAssertGreaterThan(height(name, width: 100), singleLineHeight * 1.5)
        XCTAssertEqual(height(name, width: 400), singleLineHeight, accuracy: 1)
    }

    func testAccountEditorRendersNamedQuotasInEnglishAndJapanese() throws {
        let account = UsageAccount(
            provider: .antigravity,
            name: "Antigravity",
            source: .currentSession,
            railPercentSource: .bucket(quotaID: "antigravity-claude-and-gpt-models-fiveHour"),
            railOuterRingSource: .bucket(quotaID: "antigravity-gemini-models-weekly"),
            railInnerRingSource: .bucket(quotaID: "antigravity-claude-and-gpt-models-weekly"),
            railTimeSource: .bucket(quotaID: "antigravity-claude-and-gpt-models-weekly"),
            buckets: try fixtureBuckets()
        )

        // Match the account content area at the minimum and default settings
        // window widths, including native macOS pickers in the render.
        for width: CGFloat in [630, 670] {
            for language in ["en", "ja"] {
                let editor = AccountEditor(
                    account: .constant(account),
                    statusText: "Live",
                    presentationMode: .used,
                    canMoveUp: false,
                    canMoveDown: false,
                    supportsMultiplier: false,
                    multiplierDetectionText: nil,
                    onMoveUp: {},
                    onMoveDown: {},
                    onAutoDetectMultiplier: {},
                    onDelete: {}
                )
                let view = NSHostingView(rootView: editor
                    .environment(\.locale, Locale(identifier: language))
                    .environment(\.colorScheme, .light)
                    .frame(width: width)
                    .padding(16)
                    .background(Color(nsColor: .windowBackgroundColor)))
                view.appearance = NSAppearance(named: .aqua)
                let size = view.fittingSize
                XCTAssertEqual(size.width, width + 32, accuracy: 1)
                XCTAssertGreaterThan(size.height, 300)
                view.frame = NSRect(origin: .zero, size: size)
                view.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                view.cacheDisplay(in: view.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                attachment.name = "AccountEditor-\(language)-\(Int(width))"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }
}

@MainActor
final class PersistenceTests: XCTestCase {
    private func loginAccount(
        provider: ProviderID,
        name: String,
        multiplier: Int? = nil,
        percent: Double = 0.4
    ) -> UsageAccount {
        UsageAccount(
            provider: provider,
            name: name,
            source: .profile,
            planMultiplier: multiplier,
            multiplierMode: multiplier == nil ? nil : .manual,
            buckets: [
                UsageBucket(
                    quotaID: "weekly",
                    label: "1w",
                    kind: .weekly,
                    percentUsed: percent,
                    resetsAt: Date().addingTimeInterval(3 * 24 * 60 * 60)
                )
            ]
        )
    }

    private func seedLoginAccounts(_ store: UsageStore) {
        store.accounts = [
            loginAccount(provider: .claude, name: "Claude Profile", multiplier: 20, percent: 0.42),
            loginAccount(provider: .codex, name: "Codex Profile", multiplier: 20, percent: 0.35)
        ]
    }

    func testSettingsWindowControllerShowMakesWindowVisible() {
        let suiteName = "UsageDockTests.SettingsWindow.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let controller = SettingsWindowController(
            usageStore: UsageStore(defaults: defaults),
            placement: PlacementStore(defaults: defaults)
        )
        controller.show()
        XCTAssertTrue(controller.window?.isVisible == true)
        XCTAssertGreaterThanOrEqual(controller.window?.contentLayoutRect.width ?? 0, 1000)
        XCTAssertGreaterThanOrEqual(controller.window?.minSize.width ?? 0, 1000)
        controller.close()
    }

    func testF1725LiquidCategoryIsMergedIntoAppearance() {
        XCTAssertFalse(SettingsCategory.allCases.contains { $0.label == "Liquid" })
        XCTAssertTrue(SettingsCategory.allCases.contains { $0 == .appearance })
    }

    func testF1725BubblePreviewPolicyTracksOnlyExpandedShape() {
        XCTAssertTrue(SettingsHoverPreviewPolicy.shouldShow(category: .shape, bubbleExpanded: true))
        XCTAssertFalse(SettingsHoverPreviewPolicy.shouldShow(category: .shape, bubbleExpanded: false))
        XCTAssertFalse(SettingsHoverPreviewPolicy.shouldShow(category: .appearance, bubbleExpanded: true))
    }

    func testF1725DockBubblePreviewSelectsTopTarget() throws {
        let suiteName = "UsageDockTests.DockBubblePreview.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(defaults: defaults)
        seedLoginAccounts(store)
        let expected = try XCTUnwrap(store.railTargets().first)

        XCTAssertEqual(
            DockPanelController.settingsPreviewTarget(from: store.railTargets()),
            expected
        )
    }

    func testF1725SettingsCloseStopsBubblePreview() {
        let suiteName = "UsageDockTests.SettingsPreviewClose.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(defaults: defaults)
        store.settingsBubblePreviewRequested = true
        let controller = SettingsWindowController(
            usageStore: store,
            placement: PlacementStore(defaults: defaults)
        )

        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        XCTAssertFalse(store.settingsBubblePreviewRequested)
        controller.close()
    }

    func testPlacementPersistsLeftAndRight() {
        let suiteName = "UsageDockTests.Placement.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = PlacementStore(defaults: defaults)
        XCTAssertEqual(first.edge, .right)
        first.edge = .left
        XCTAssertEqual(PlacementStore(defaults: defaults).edge, .left)
        first.edge = .right
        XCTAssertEqual(PlacementStore(defaults: defaults).edge, .right)
    }

    func testRailDisplayPreferencesPersistAndClamp() {
        let suiteName = "UsageDockTests.RailDisplay.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        store.railScale = 0.1
        store.railItemSpacing = 17
        store.railVerticalPosition = 0.64
        store.railShowPercent = false
        store.railShowRing = false
        store.railShowMultiplier = false
        store.railHoverEnabled = false

        XCTAssertEqual(store.railScale, 0.45, accuracy: 0.0001)
        let restored = UsageStore(defaults: defaults)
        XCTAssertEqual(restored.railScale, 0.45, accuracy: 0.0001)
        XCTAssertEqual(restored.railItemSpacing, 17, accuracy: 0.0001)
        XCTAssertEqual(restored.railVerticalPosition, 0.64, accuracy: 0.0001)
        XCTAssertFalse(restored.railShowPercent)
        XCTAssertFalse(restored.railShowRing)
        XCTAssertFalse(restored.railShowMultiplier)
        XCTAssertFalse(restored.railHoverEnabled)
    }

    func testF1718HorizontalSafeInsetAllowsNearEdgePlacement() {
        XCTAssertEqual(RailMetrics.minimumSafeHorizontalInset(showRing: true, iconSize: 24), 2, accuracy: 0.0001)
        XCTAssertEqual(RailMetrics.minimumSafeHorizontalInset(showRing: false, iconSize: 24), 1, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(RailMetrics.minimumSafeHorizontalInset(showRing: true, iconSize: 44), 4)

        let narrow = RailMetrics.clampedHorizontalLayout(
            availableWidth: 78,
            scale: 1,
            showRing: true,
            showMultiplier: false,
            iconSize: 24,
            titleWidth: 66,
            timeWidth: 72,
            desiredScreenInset: 0,
            desiredWindowInset: 0,
            screenEdgeAmount: 0,
            stretch: 0,
            neck: 0,
            detach: 0
        )
        XCTAssertGreaterThanOrEqual(narrow.screenInset, 2)
        XCTAssertGreaterThanOrEqual(narrow.windowInset, 2)
    }

    func testAccountSpecificAccentPersistsForSameProvider() {
        let suiteName = "UsageDockTests.AccountAccent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        store.accounts = [
            loginAccount(provider: .codex, name: "Codex A", multiplier: 20, percent: 0.3),
            loginAccount(provider: .codex, name: "Codex B", multiplier: 20, percent: 0.6)
        ]
        let ids = store.accounts.filter { $0.provider == .codex }.map(\.id)
        XCTAssertGreaterThanOrEqual(ids.count, 2)
        store.setAccountAccent("#FF0000", accountID: ids[0])
        store.setAccountAccent("#00FF00", accountID: ids[1])

        let restored = UsageStore(defaults: defaults)
        XCTAssertEqual(restored.accounts.first(where: { $0.id == ids[0] })?.accentHex, "#FF0000")
        XCTAssertEqual(restored.accounts.first(where: { $0.id == ids[1] })?.accentHex, "#00FF00")
    }

    func testLoginAccountRemovePersists() {
        let suiteName = "UsageDockTests.Accounts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        XCTAssertTrue(store.accounts.isEmpty)

        let added = loginAccount(provider: .codex, name: "Codex Profile", multiplier: 20)
        store.accounts.append(added)
        XCTAssertTrue(UsageStore(defaults: defaults).accounts.contains { $0.id == added.id })

        store.removeAccount(id: added.id)
        XCTAssertFalse(UsageStore(defaults: defaults).accounts.contains { $0.id == added.id })
    }

    func testMultiplierNormalAndFusionModes() {
        let suiteName = "UsageDockTests.Multiplier.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        store.accounts = [
            loginAccount(provider: .codex, name: "Codex A", multiplier: 20, percent: 0.3),
            loginAccount(provider: .codex, name: "Codex B", multiplier: 20, percent: 0.5)
        ]
        XCTAssertEqual(store.displayMultiplier(for: .codex), 20)

        store.setFusionEnabled(true, for: .codex)
        XCTAssertEqual(store.displayMultiplier(for: .codex), 40)
        XCTAssertTrue(UsageStore(defaults: defaults).fusionEnabled(for: .codex))
    }

    func testMigrationPreservesPersistedAccountsWithoutInjectingDefaults() throws {
        let suiteName = "UsageDockTests.Migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let current = UsageAccount(provider: .codex, name: "Current Session", source: .currentSession, buckets: [])
        let unsupported = UsageAccount(provider: .kimi, name: "Old Record", source: .legacyUnsupported, buckets: [])
        defaults.set(try JSONEncoder().encode([current, unsupported]), forKey: "UsageDock.accounts.v3")

        let store = UsageStore(defaults: defaults)
        XCTAssertEqual(store.accounts, [current])
        XCTAssertEqual(store.accounts.count, 1)
    }

    func testF17RefreshPreservesDisabledBucketByQuotaIDAndOrder() throws {
        let sparkID = UUID()
        let existing = [
            UsageBucket(id: sparkID, quotaID: "codex-spark-18000", label: "Spark 5h", kind: .fiveHour, percentUsed: 0.9, isEnabled: false),
            UsageBucket(quotaID: "codex-general-604800", label: "1w", kind: .weekly, percentUsed: 0.4, isEnabled: true)
        ]
        let fetched = [
            UsageBucket(quotaID: "codex-general-604800", label: "1w", kind: .weekly, percentUsed: 0.12),
            UsageBucket(quotaID: "codex-spark-18000", label: "Spark 5h", kind: .fiveHour, percentUsed: 0.21),
            UsageBucket(quotaID: "codex-spark-604800", label: "Spark 1w", kind: .weekly, percentUsed: 0.33)
        ]

        let merged = UsageStore.mergeRefreshedBuckets(existing: existing, fetched: fetched)
        XCTAssertEqual(merged.map(\.quotaID), ["codex-spark-18000", "codex-general-604800", "codex-spark-604800"])
        let spark = try XCTUnwrap(merged.first(where: { $0.quotaID == "codex-spark-18000" }))
        XCTAssertFalse(spark.isEnabled)
        XCTAssertEqual(spark.id, sparkID)
        XCTAssertEqual(spark.resolvedPercentUsed ?? -1, 0.21, accuracy: 0.0001)
        XCTAssertTrue(merged.last?.isEnabled == true)
    }

    func testF1718RailSettingsPersistWithoutChangingAccountPayload() throws {
        let suiteName = "UsageDockTests.F1718Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        let originalAccounts = store.accounts
        store.railScreenEdgeShape = 0.6
        store.railScreenEdgeCurvature = -0.72
        store.railInnerShape = -0.25
        store.railInnerPaddingY = 13
        store.railScreenInnerPadding = 11
        store.railWindowInnerPadding = 17
        store.railMaterialMode = .waterdrop
        store.railEdgeStyle = .soft
        store.railEdgeWidth = 1.5
        store.railGlowRadius = 14
        store.railBorderColorMode = .custom
        store.railBorderCustomHex = "#ABCDEF"
        store.railIconSize = 29
        store.railPercentFontSize = 13.5
        store.railTitleWidth = 92
        store.railTimeWidth = 84
        store.railShowTitle = false

        let restored = UsageStore(defaults: defaults)
        XCTAssertEqual(restored.accounts, originalAccounts)
        XCTAssertEqual(restored.railScreenEdgeShape, 0.6, accuracy: 0.0001)
        XCTAssertEqual(restored.railScreenEdgeCurvature, -0.72, accuracy: 0.0001)
        XCTAssertEqual(restored.railInnerShape, -0.25, accuracy: 0.0001)
        XCTAssertEqual(restored.railInnerPaddingY, 13, accuracy: 0.0001)
        XCTAssertEqual(restored.railScreenInnerPadding, 11, accuracy: 0.0001)
        XCTAssertEqual(restored.railWindowInnerPadding, 17, accuracy: 0.0001)
        XCTAssertEqual(restored.railMaterialMode, .waterdrop)
        XCTAssertEqual(restored.railEdgeStyle, .soft)
        XCTAssertEqual(restored.railEdgeWidth, 1.5, accuracy: 0.0001)
        XCTAssertEqual(restored.railGlowRadius, 14, accuracy: 0.0001)
        XCTAssertEqual(restored.railBorderColorMode, .custom)
        XCTAssertEqual(restored.railBorderCustomHex, "#ABCDEF")
        XCTAssertEqual(restored.railIconSize, 29, accuracy: 0.0001)
        XCTAssertEqual(restored.railPercentFontSize, 13.5, accuracy: 0.0001)
        XCTAssertEqual(restored.railTitleWidth, 92, accuracy: 0.0001)
        XCTAssertEqual(restored.railTimeWidth, 84, accuracy: 0.0001)
        XCTAssertFalse(restored.railShowTitle)
    }

    func testF1724DropletsDefaultOnAndPersistWithoutChangingAccounts() {
        let suiteName = "UsageDockTests.F1724Droplets.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        let originalAccounts = store.accounts
        XCTAssertTrue(store.railDropletsEnabled)

        store.railDropletsEnabled = false
        let restored = UsageStore(defaults: defaults)
        XCTAssertFalse(restored.railDropletsEnabled)
        XCTAssertEqual(restored.accounts, originalAccounts)
    }

    func testF1724DisplayAccountReferencesClampToThreeAndCleanDeletedAccount() throws {
        let suiteName = "UsageDockTests.F1724DisplayAccounts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let persisted = (0..<4).map { index in
            UsageAccount(
                provider: index.isMultiple(of: 2) ? .codex : .claude,
                name: "Profile \(index + 1)",
                source: .profile,
                buckets: [UsageBucket(quotaID: "weekly-\(index)", label: "1w", kind: .weekly, percentUsed: 0.2)]
            )
        }
        defaults.set(try JSONEncoder().encode(persisted), forKey: "UsageDock.accounts.v3")
        defaults.set(
            persisted.map { $0.id.uuidString } + [persisted[0].id.uuidString],
            forKey: "UsageDock.displayAccountIDs.v1"
        )
        defaults.set(persisted[1].id.uuidString, forKey: "UsageDock.activeDisplayAccountID.v1")

        let store = UsageStore(defaults: defaults)
        XCTAssertEqual(store.accounts, persisted)
        XCTAssertEqual(store.displayAccountIDs, Array(persisted.prefix(3).map(\.id)))
        XCTAssertEqual(store.activeDisplayAccountID, persisted[1].id)
        XCTAssertEqual(store.displayAccountCandidates().map(\.id), Array(persisted.prefix(3).map(\.id)))

        store.removeAccount(id: persisted[1].id)
        let restored = UsageStore(defaults: defaults)
        XCTAssertFalse(restored.displayAccountIDs.contains(persisted[1].id))
        XCTAssertEqual(restored.activeDisplayAccountID, persisted[0].id)
        XCTAssertFalse(restored.accounts.contains { $0.id == persisted[1].id })
    }

    func testF1727MenuBarSelectionPersistsIndependentlyFromRailDisplaySelection() throws {
        let suiteName = "UsageDockTests.F1727MenuBarIndependent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let railAccount = UsageAccount(
            provider: .claude,
            name: "Rail Profile",
            source: .profile,
            buckets: [UsageBucket(quotaID: "weekly-rail", label: "1w", kind: .weekly, percentUsed: 0.31)]
        )
        let menuAccount = UsageAccount(
            provider: .codex,
            name: "Menu Profile",
            source: .profile,
            buckets: [UsageBucket(quotaID: "weekly-menu", label: "1w", kind: .weekly, percentUsed: 0.72)]
        )
        defaults.set(try JSONEncoder().encode([railAccount, menuAccount]), forKey: "UsageDock.accounts.v3")
        defaults.set([railAccount.id.uuidString], forKey: "UsageDock.displayAccountIDs.v1")
        defaults.set([menuAccount.id.uuidString], forKey: "UsageDock.menuBarAccountIDs.v1")

        let store = UsageStore(defaults: defaults)
        XCTAssertEqual(store.displayAccountIDs, [railAccount.id])
        XCTAssertEqual(store.menuBarAccountIDs, [menuAccount.id])

        store.setMenuBarAccountSelected(railAccount.id, enabled: true)
        store.menuBarShowRing = false
        store.menuBarShowPercentage = true
        let restored = UsageStore(defaults: defaults)
        XCTAssertEqual(restored.displayAccountIDs, [railAccount.id])
        XCTAssertEqual(restored.menuBarAccountIDs, [menuAccount.id, railAccount.id])
        XCTAssertFalse(restored.menuBarShowRing)
        XCTAssertTrue(restored.menuBarShowPercentage)
    }

    func testF1727MenuBarSelectionCleansDeletedAccount() throws {
        let suiteName = "UsageDockTests.F1727MenuBarDelete.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let account = UsageAccount(
            provider: .claude,
            name: "Menu Profile",
            source: .profile,
            buckets: [UsageBucket(quotaID: "weekly", label: "1w", kind: .weekly, percentUsed: 0.44)]
        )
        defaults.set(try JSONEncoder().encode([account]), forKey: "UsageDock.accounts.v3")
        defaults.set([account.id.uuidString], forKey: "UsageDock.menuBarAccountIDs.v1")

        let store = UsageStore(defaults: defaults)
        XCTAssertEqual(store.menuBarAccountIDs, [account.id])
        store.removeAccount(id: account.id)

        let restored = UsageStore(defaults: defaults)
        XCTAssertTrue(restored.menuBarAccountIDs.isEmpty)
        XCTAssertTrue(restored.menuBarUsageItems().isEmpty)
    }

    func testF1727MenuBarUnavailableUsageFallsBackWithoutStalePercent() throws {
        let suiteName = "UsageDockTests.F1727MenuBarUnavailable.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let account = UsageAccount(
            provider: .codex,
            name: "Expired Later",
            source: .profile,
            accentHex: "#22AAFF",
            buckets: [UsageBucket(quotaID: "weekly", label: "1w", kind: .weekly, percentUsed: 0.92)]
        )
        defaults.set(try JSONEncoder().encode([account]), forKey: "UsageDock.accounts.v3")
        defaults.set([account.id.uuidString], forKey: "UsageDock.menuBarAccountIDs.v1")

        let store = UsageStore(defaults: defaults)
        let item = try XCTUnwrap(store.menuBarUsageItems().first)
        XCTAssertEqual(item.id, account.id)
        XCTAssertEqual(item.authenticationState, .checking)
        XCTAssertNil(item.percent)
        XCTAssertEqual(item.accentHex, "#22AAFF")
    }

    func testF1724AuthInvalidDisplayAccountNeverUsesPersistedStaleUsage() throws {
        let suiteName = "UsageDockTests.F1724AuthInvalid.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let account = UsageAccount(
            provider: .codex,
            name: "Saved Profile",
            source: .profile,
            buckets: [UsageBucket(quotaID: "weekly", label: "1w", kind: .weekly, percentUsed: 0.92)]
        )
        defaults.set(try JSONEncoder().encode([account]), forKey: "UsageDock.accounts.v3")
        defaults.set([account.id.uuidString], forKey: "UsageDock.displayAccountIDs.v1")
        defaults.set(account.id.uuidString, forKey: "UsageDock.activeDisplayAccountID.v1")

        let store = UsageStore(defaults: defaults)
        XCTAssertEqual(store.displayAuthenticationState(for: account), .checking)
        XCTAssertTrue(store.railTargets().isEmpty)
        XCTAssertEqual(DisplayAccountPolicy.authenticationState(account: account, refreshState: .live(Date())), .valid)
        XCTAssertEqual(DisplayAccountPolicy.authenticationState(account: account, refreshState: .failed("expired")), .required)
        XCTAssertEqual(
            DisplayAccountPolicy.authenticationState(
                account: UsageAccount(provider: .codex, name: "Old Record", source: .legacyUnsupported, buckets: account.buckets),
                refreshState: .live(Date())
            ),
            .required
        )
    }

    func testF1718LegacyPaddingMigratesWithoutRewritingLegacyKeys() {
        let suiteName = "UsageDockTests.F1718Migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(7.0, forKey: "UsageDock.railTopPadding.v1")
        defaults.set(19.0, forKey: "UsageDock.railBottomPadding.v1")
        defaults.set(11.0, forKey: "UsageDock.railIconEdgeInset.v1")

        let store = UsageStore(defaults: defaults)
        XCTAssertEqual(store.railInnerPaddingY, 13, accuracy: 0.0001)
        XCTAssertEqual(store.railScreenInnerPadding, 11, accuracy: 0.0001)
        XCTAssertEqual(store.railWindowInnerPadding, 0, accuracy: 0.0001)
        XCTAssertEqual(defaults.double(forKey: "UsageDock.railTopPadding.v1"), 7, accuracy: 0.0001)
        XCTAssertEqual(defaults.double(forKey: "UsageDock.railBottomPadding.v1"), 19, accuracy: 0.0001)
        XCTAssertEqual(defaults.double(forKey: "UsageDock.railIconEdgeInset.v1"), 11, accuracy: 0.0001)
    }

    func testF1718SharedVerticalPaddingChangesBothEndsEqually() {
        let compact = RailMetrics.contentHeight(
            entryCount: 3,
            scale: 1,
            itemSpacing: 8,
            innerPaddingY: 0,
            showRing: true,
            showPercent: true
        )
        let padded = RailMetrics.contentHeight(
            entryCount: 3,
            scale: 1,
            itemSpacing: 8,
            innerPaddingY: 12,
            showRing: true,
            showPercent: true
        )
        XCTAssertEqual(padded - compact, 24, accuracy: 0.0001)
        XCTAssertGreaterThan(RailMetrics.borderRenderPadding(scale: 1, edgeStyle: .glass, edgeWidth: 2.6), 3)
        XCTAssertGreaterThan(
            RailMetrics.borderRenderPadding(scale: 1, edgeStyle: .neon, edgeWidth: 2.6, glowRadius: 12),
            RailMetrics.borderRenderPadding(scale: 1, edgeStyle: .neon, edgeWidth: 2.6, glowRadius: 0)
        )
        XCTAssertLessThanOrEqual(
            RailMetrics.borderRenderPadding(scale: 1, edgeStyle: .neon, edgeWidth: 2.6, glowRadius: 24),
            16
        )
    }

    func testF1718HorizontalInsetsClampInsideAvailableRailWidth() {
        let availableWidth: CGFloat = 90
        let layout = RailMetrics.clampedHorizontalLayout(
            availableWidth: availableWidth,
            scale: 1,
            showRing: true,
            showMultiplier: true,
            iconSize: 24,
            titleWidth: 66,
            timeWidth: 72,
            desiredScreenInset: 40,
            desiredWindowInset: 40,
            screenEdgeAmount: 1,
            stretch: 1.2,
            neck: 1,
            detach: 1
        )
        let contentWidth = RailMetrics.contentWidth(
            showRing: true,
            showMultiplier: true,
            iconSize: 24,
            titleWidth: 66,
            timeWidth: 72
        ) * layout.contentScaleX
        XCTAssertGreaterThanOrEqual(layout.screenInset, 0)
        XCTAssertGreaterThanOrEqual(layout.windowInset, 0)
        XCTAssertGreaterThanOrEqual(layout.contentScaleX, 0.50)
        XCTAssertLessThanOrEqual(layout.contentScaleX, 1)
        XCTAssertLessThanOrEqual(layout.screenInset + contentWidth + layout.windowInset, availableWidth + 0.001)
    }

    func testF17TimerFallsBackToMinutesUnderOneHour() {
        let suiteName = "UsageDockTests.F17Timer.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(defaults: defaults)
        store.railShowHours = false
        store.railShowMinutes = false
        store.railAutoHideZeroDays = true
        store.railAutoHideZeroHours = true
        store.railMinuteDigits = .one

        let now = Date(timeIntervalSince1970: 1_000_000)
        XCTAssertEqual(store.railRemainingTimeText(until: now.addingTimeInterval(23 * 60), now: now), "23m")
    }

    func testF16PerAccountRailSourcesPersistAndOverrideGlobal() throws {
        let suiteName = "UsageDockTests.F16RailSources.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        store.accounts = [
            loginAccount(provider: .codex, name: "Codex Profile", multiplier: 20, percent: 0.35),
            loginAccount(provider: .kimi, name: "Kimi Profile", percent: 0.55)
        ]
        let codexID = try XCTUnwrap(store.accounts.first(where: { $0.provider == .codex })?.id)
        let kimiID = try XCTUnwrap(store.accounts.first(where: { $0.provider == .kimi })?.id)
        let codexIndex = try XCTUnwrap(store.accounts.firstIndex(where: { $0.id == codexID }))
        let kimiIndex = try XCTUnwrap(store.accounts.firstIndex(where: { $0.id == kimiID }))
        store.accounts[codexIndex].railPercentSource = .weekly
        store.accounts[codexIndex].railOuterRingSource = .weekly
        store.accounts[kimiIndex].railPercentSource = .fiveHour
        store.accounts[kimiIndex].railOuterRingSource = .fiveHour
        store.railPercentSource = .automatic

        let restored = UsageStore(defaults: defaults)
        XCTAssertEqual(restored.railPercentSource(for: .account(id: codexID, provider: .codex)), .weekly)
        XCTAssertEqual(restored.railOuterRingSource(for: .account(id: codexID, provider: .codex)), .weekly)
        XCTAssertEqual(restored.railPercentSource(for: .account(id: kimiID, provider: .kimi)), .fiveHour)
        XCTAssertEqual(restored.railOuterRingSource(for: .account(id: kimiID, provider: .kimi)), .fiveHour)
    }

    func testF15EmptyProvidersAreNotRailTargets() {
        let suiteName = "UsageDockTests.F15Empty.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        seedLoginAccounts(store)
        let providers = Set(store.railTargets().map(\.provider))
        XCTAssertEqual(providers, Set([.claude, .codex]))
        XCTAssertFalse(providers.contains(.antigravity))
        XCTAssertFalse(providers.contains(.cursor))
        XCTAssertFalse(providers.contains(.grok))
    }

    func testF15AppearancePersists() {
        let suiteName = "UsageDockTests.F15Appearance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        store.theme = .transparentFloating
        store.resetTimeDisplayMode = .both
        store.railBackgroundOpacity = 0
        store.railCornerRadius = 36
        store.railScallopDepth = 30
        let restored = UsageStore(defaults: defaults)
        XCTAssertEqual(restored.theme, .transparentFloating)
        XCTAssertEqual(restored.resetTimeDisplayMode, .both)
        XCTAssertEqual(restored.railBackgroundOpacity, 0, accuracy: 0.0001)
        XCTAssertEqual(restored.railCornerRadius, 36, accuracy: 0.0001)
        XCTAssertEqual(restored.railScallopDepth, 30, accuracy: 0.0001)
    }

    func testF15ProviderAndAccountWebURLResolution() {
        let suiteName = "UsageDockTests.F15URL.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        seedLoginAccounts(store)
        store.setProviderWebURL("https://chatgpt.com/", for: .codex)
        let codex = try! XCTUnwrap(store.accounts.first(where: { $0.provider == .codex }))
        XCTAssertEqual(store.webURL(for: .account(id: codex.id, provider: .codex))?.host, "chatgpt.com")

        let index = store.accounts.firstIndex(where: { $0.id == codex.id })!
        store.accounts[index].webURL = "https://example.com/custom"
        XCTAssertEqual(store.webURL(for: .account(id: codex.id, provider: .codex))?.absoluteString, "https://example.com/custom")
        XCTAssertEqual(UsageStore(defaults: defaults).providerWebURL(for: .codex), "https://chatgpt.com/")
    }
}

final class LiveUsageAdapterParsingTests: XCTestCase {
    func testF16AntigravityCLIUsageParsesWeeklyAndFiveHourGroups() throws {
        let text = """
        Gemini Models\tWeekly Limit Remaining\t70%\t2026-09-05T16:51:26Z
        Gemini Models\tFive Hour Limit Remaining\t40%\t2026-08-29T21:51:26Z
        Claude and GPT models\tWeekly Limit Remaining\t80%\t2026-09-05T16:51:26Z
        Claude and GPT models\tFive Hour Limit Remaining\t55%\t2026-08-29T21:51:26Z
        """

        let buckets = try AntigravityUsageAdapter.parseUsage(text: text)
        XCTAssertEqual(buckets.count, 4)
        let geminiWeekly = try XCTUnwrap(buckets.first(where: { $0.model == "Gemini Models" && $0.kind == .weekly }))
        let geminiFiveHour = try XCTUnwrap(buckets.first(where: { $0.model == "Gemini Models" && $0.kind == .fiveHour }))
        XCTAssertEqual(geminiWeekly.resolvedPercentUsed ?? -1, 0.30, accuracy: 0.0001)
        XCTAssertEqual(geminiFiveHour.resolvedPercentUsed ?? -1, 0.60, accuracy: 0.0001)
        XCTAssertNotNil(geminiWeekly.resetsAt)
        XCTAssertNotNil(geminiFiveHour.resetsAt)
    }

    func testClaudeLegacyUsageParsesSessionWeeklyAndModelWindow() throws {
        let data = try jsonData([
            "five_hour": ["utilization": 53.0, "resets_at": "2026-08-29T01:00:00Z"],
            "seven_day": ["utilization": 21.0, "resets_at": "2026-09-02T01:00:00Z"],
            "seven_day_fable": ["utilization": 7.0, "resets_at": "2026-09-02T01:00:00Z"]
        ])

        let buckets = try ClaudeUsageAdapter.parseUsage(data: data)
        XCTAssertEqual(buckets.count, 3)
        XCTAssertEqual(buckets.first(where: { $0.kind == .fiveHour })?.resolvedPercentUsed ?? -1, 0.53, accuracy: 0.0001)
        XCTAssertEqual(buckets.first(where: { $0.kind == .weekly })?.resolvedPercentUsed ?? -1, 0.21, accuracy: 0.0001)
        let fable = try XCTUnwrap(buckets.first(where: { $0.model == "Fable" }))
        XCTAssertEqual(fable.kind, .modelSpecific)
        XCTAssertEqual(fable.resolvedPercentUsed ?? -1, 0.07, accuracy: 0.0001)
    }

    func testClaudeLimitsArrayParsesScopedModel() throws {
        let data = try jsonData([
            "limits": [
                ["kind": "session", "group": "session", "percent": 0.44, "resets_at": "2026-08-29T01:00:00Z"],
                ["kind": "weekly_all", "group": "weekly", "percent": 0.12, "resets_at": "2026-09-02T01:00:00Z"],
                [
                    "kind": "weekly_scoped",
                    "group": "weekly",
                    "percent": 0.28,
                    "resets_at": "2026-09-02T01:00:00Z",
                    "scope": ["model": ["display_name": "Fable"]]
                ]
            ]
        ])

        let buckets = try ClaudeUsageAdapter.parseUsage(data: data)
        XCTAssertEqual(buckets.count, 3)
        XCTAssertEqual(buckets.first(where: { $0.kind == .fiveHour })?.label, "5h")
        XCTAssertEqual(buckets.first(where: { $0.kind == .weekly })?.label, "1w")
        XCTAssertEqual(buckets.first(where: { $0.model == "Fable" })?.resolvedPercentUsed ?? -1, 0.28, accuracy: 0.0001)
    }

    func testKimiUsageParsesWeeklyFiveHourAndExtraUsage() throws {
        let data = try jsonData([
            "usage": [
                "used": "25",
                "limit": "100",
                "resetTime": "2026-09-01T00:00:00Z"
            ],
            "limits": [
                [
                    "name": "rolling-five-hour",
                    "used": "20",
                    "limit": "100",
                    "reset_at": "2026-08-29T18:00:00Z",
                    "window": [
                        "duration": 300,
                        "timeUnit": "TIME_UNIT_MINUTE"
                    ]
                ]
            ],
            "extra_usage": [
                "monthly_used_cents": 150,
                "monthly_charge_limit_cents": 1000,
                "currency": "USD"
            ]
        ])

        let buckets = try KimiUsageAdapter.parseUsage(data: data)
        let weekly = try XCTUnwrap(buckets.first(where: { $0.kind == .weekly }))
        XCTAssertEqual(weekly.label, "1w")
        XCTAssertEqual(weekly.resolvedPercentUsed ?? -1, 0.25, accuracy: 0.0001)

        let fiveHour = try XCTUnwrap(buckets.first(where: { $0.kind == .fiveHour }))
        XCTAssertEqual(fiveHour.label, "5h")
        XCTAssertEqual(fiveHour.resolvedPercentUsed ?? -1, 0.20, accuracy: 0.0001)

        let extra = try XCTUnwrap(buckets.first(where: { $0.kind == .credits }))
        XCTAssertEqual(extra.resolvedPercentUsed ?? -1, 0.15, accuracy: 0.0001)
    }

    func testCodexUsageParsesDynamicGeneralAndAdditionalWindows() throws {
        let data = try jsonData([
            "rate_limit": [
                "primary_window": [
                    "used_percent": 11,
                    "limit_window_seconds": 604800,
                    "reset_at": 1788452749
                ]
            ],
            "additional_rate_limits": [
                [
                    "limit_name": "GPT-5.3-Codex-Spark",
                    "metered_feature": "codex_bengalfox",
                    "rate_limit": [
                        "primary_window": [
                            "used_percent": 4,
                            "limit_window_seconds": 18000,
                            "reset_at": 1787942049
                        ],
                        "secondary_window": [
                            "used_percent": 18,
                            "limit_window_seconds": 604800,
                            "reset_at": 1788528849
                        ]
                    ]
                ]
            ]
        ])

        let buckets = try CodexUsageAdapter.parseUsage(data: data)
        XCTAssertEqual(buckets.count, 3)

        let general = try XCTUnwrap(buckets.first(where: { $0.model == nil }))
        XCTAssertEqual(general.label, "1w")
        XCTAssertEqual(general.resolvedPercentUsed ?? -1, 0.11, accuracy: 0.0001)

        let sparkFiveHour = try XCTUnwrap(buckets.first(where: { $0.model == "GPT-5.3-Codex-Spark" && $0.label.hasSuffix("5h") }))
        XCTAssertEqual(sparkFiveHour.kind, .modelSpecific)
        XCTAssertEqual(sparkFiveHour.resolvedPercentUsed ?? -1, 0.04, accuracy: 0.0001)

        let sparkWeekly = try XCTUnwrap(buckets.first(where: { $0.model == "GPT-5.3-Codex-Spark" && $0.label.hasSuffix("1w") }))
        XCTAssertEqual(sparkWeekly.resolvedPercentUsed ?? -1, 0.18, accuracy: 0.0001)
    }

    func testGrokProviderAcceptsLoginBackedUsage() {
        XCTAssertTrue(ProviderID.grok.supportsLiveUsage)
        XCTAssertTrue(ProviderID.grok.supportsProfileLogin)
        XCTAssertFalse(ProviderID.cursor.supportsLiveUsage)
        XCTAssertFalse(ProviderID.cursor.supportsProfileLogin)
        XCTAssertEqual(ProviderBrand.assetName(for: .grok), "Grok")
    }

    func testGrokBillingParsesWeeklyPoolResetAndExtraUsage() throws {
        let data = try jsonData([
            "config": [
                "currentPeriod": [
                    "type": "USAGE_PERIOD_TYPE_WEEKLY",
                    "start": "2026-08-08T01:53:09.930537+00:00",
                    "end": "2026-08-15T01:53:09.930537+00:00"
                ],
                "creditUsagePercent": 42.5,
                "onDemandCap": ["val": 5000],
                "onDemandUsed": ["val": "300"],
                "prepaidBalance": ["val": 1250],
                "isUnifiedBillingUser": true,
                "productUsage": [
                    ["product": "GrokBuild", "usagePercent": 30.0],
                    ["product": "GrokChat"]
                ],
                "billingPeriodEnd": "2026-08-15T01:53:09.930537+00:00"
            ]
        ])

        let buckets = try GrokUsageAdapter.parseUsage(data: data)
        XCTAssertEqual(buckets.count, 2)

        let weekly = try XCTUnwrap(buckets.first(where: { $0.kind == .weekly }))
        XCTAssertEqual(weekly.quotaID, "grok-weekly")
        XCTAssertEqual(weekly.label, "1w")
        XCTAssertEqual(weekly.resolvedPercentUsed ?? -1, 0.425, accuracy: 0.0001)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reset = try XCTUnwrap(weekly.resetsAt)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reset)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 8)
        XCTAssertEqual(parts.day, 15)
        XCTAssertEqual(parts.hour, 1)
        XCTAssertEqual(parts.minute, 53)

        let extra = try XCTUnwrap(buckets.first(where: { $0.kind == .credits }))
        XCTAssertEqual(extra.label, "Extra")
        XCTAssertEqual(extra.used ?? -1, 300, accuracy: 0.0001)
        XCTAssertEqual(extra.limit ?? -1, 5000, accuracy: 0.0001)
        XCTAssertEqual(extra.resolvedPercentUsed ?? -1, 0.06, accuracy: 0.0001)
        XCTAssertNil(buckets.first(where: { $0.model == "GrokChat" || $0.label == "GrokChat" }))
    }

    func testGrokBillingReadsOmittedWeeklyPercentAsZeroLikeTheCLI() throws {
        // Live SuperGrok credits body: proto3 dropped creditUsagePercent, and
        // every zero money field is still present as {"val":0}.
        let omitted = try jsonData([
            "config": [
                "currentPeriod": [
                    "type": "USAGE_PERIOD_TYPE_WEEKLY",
                    "start": "2026-10-08T12:29:30.534268+00:00",
                    "end": "2026-10-15T12:29:30.534268+00:00"
                ],
                "onDemandCap": ["val": 0],
                "onDemandUsed": ["val": 0],
                "isUnifiedBillingUser": true,
                "prepaidBalance": ["val": 0],
                "topUpMethod": "TOP_UP_METHOD_SAVED_PAYMENT_METHOD",
                "billingPeriodStart": "2026-10-08T12:29:30.534268+00:00",
                "billingPeriodEnd": "2026-10-15T12:29:30.534268+00:00"
            ]
        ])

        let buckets = try GrokUsageAdapter.parseUsage(data: omitted)
        XCTAssertEqual(buckets.count, 1)
        let weekly = try XCTUnwrap(buckets.first)
        XCTAssertEqual(weekly.quotaID, "grok-weekly")
        XCTAssertEqual(weekly.label, "1w")
        XCTAssertEqual(weekly.kind, .weekly)
        XCTAssertEqual(weekly.resolvedPercentUsed ?? -1, 0, accuracy: 0.0001)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reset = try XCTUnwrap(weekly.resetsAt)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reset)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 10)
        XCTAssertEqual(parts.day, 15)
        XCTAssertEqual(parts.hour, 12)
        XCTAssertEqual(parts.minute, 29)

        let extraAndZero = try jsonData([
            "config": [
                "currentPeriod": [
                    "type": "USAGE_PERIOD_TYPE_WEEKLY",
                    "start": "2026-08-16T12:54:39.515635+00:00",
                    "end": "2026-08-23T12:54:39.515635+00:00"
                ],
                "onDemandCap": ["val": 100],
                "onDemandUsed": ["val": 0]
            ]
        ])
        let withExtra = try GrokUsageAdapter.parseUsage(data: extraAndZero)
        XCTAssertEqual(withExtra.count, 2)
        let included = try XCTUnwrap(withExtra.first(where: { $0.kind == .weekly }))
        XCTAssertEqual(included.resolvedPercentUsed ?? -1, 0, accuracy: 0.0001)
        XCTAssertNotNil(withExtra.first(where: { $0.kind == .credits }))
    }

    func testGrokBillingDoesNotInventZeroFromTheUnformattedLedger() throws {
        // GET /v1/billing without format=credits. monthlyLimit is 0, so used
        // cannot be a percentage, and there is no credits currentPeriod.
        let ledger = try jsonData([
            "config": [
                "monthlyLimit": ["val": 0],
                "used": ["val": 190],
                "onDemandCap": ["val": 0],
                "billingPeriodStart": "2026-10-01T00:00:00+00:00",
                "billingPeriodEnd": "2026-11-01T00:00:00+00:00",
                "history": []
            ]
        ])
        XCTAssertThrowsError(try GrokUsageAdapter.parseUsage(data: ledger)) { error in
            XCTAssertTrue(error.localizedDescription.contains("will not invent 0%"))
        }

        XCTAssertThrowsError(try GrokUsageAdapter.parseUsage(data: try jsonData(["config": [:]]))) { error in
            XCTAssertTrue(error.localizedDescription.contains("will not invent 0%"))
        }
    }

    func testGrokBillingParsesLegacyMonthlyAllowance() throws {
        let data = try jsonData([
            "config": [
                "monthlyLimit": ["val": 2000],
                "used": ["val": 1234],
                "onDemandCap": ["val": 0],
                "billingPeriodEnd": "2026-05-01T00:00:00Z"
            ]
        ])

        let buckets = try GrokUsageAdapter.parseUsage(data: data)
        XCTAssertEqual(buckets.count, 1)
        let monthly = try XCTUnwrap(buckets.first)
        XCTAssertEqual(monthly.quotaID, "grok-monthly")
        XCTAssertEqual(monthly.label, "Month")
        XCTAssertEqual(monthly.resolvedPercentUsed ?? -1, 0.617, accuracy: 0.0001)
        XCTAssertNotNil(monthly.resetsAt)
    }

    func testGrokAuthFileRecognizesLoginSessionAndRejectsAPIKey() throws {
        let session = try jsonData([
            "https://accounts.x.ai/sign-in": [
                "key": "session-token",
                "auth_mode": "oidc",
                "user_id": "user-1"
            ],
            "xai::api_key": [
                "key": "xai-secret",
                "auth_mode": "api_key"
            ]
        ])
        XCTAssertTrue(GrokCredentialStore.containsSession(data: session))
        let parsed = try GrokCredentialStore.session(in: session)
        XCTAssertEqual(parsed.session.scope, "https://accounts.x.ai/sign-in")
        XCTAssertEqual(parsed.session.userID, "user-1")

        let apiKeyOnly = try jsonData([
            "xai::api_key": [
                "key": "xai-secret",
                "auth_mode": "api_key"
            ]
        ])
        XCTAssertFalse(GrokCredentialStore.containsSession(data: apiKeyOnly))
        XCTAssertThrowsError(try GrokCredentialStore.session(in: apiKeyOnly)) { error in
            XCTAssertTrue(error.localizedDescription.contains("API key"))
        }

        let deprecated = try jsonData([
            "https://accounts.x.ai/sign-in": [
                "key": "old-web-token",
                "auth_mode": "web_login"
            ]
        ])
        XCTAssertFalse(GrokCredentialStore.containsSession(data: deprecated))
    }

    func testGrokAuthFileReadsOIDCKeyUnderAuthXAIScope() throws {
        let session = try jsonData([
            "https://auth.x.ai::6f1c2a40-1111-2222-3333-444455556666": [
                "key": "oidc-access-key",
                "refresh_token": "refresh-token",
                "expires_at": "2026-10-15T12:29:30Z",
                "auth_mode": "oidc",
                "oidc_issuer": "https://auth.x.ai",
                "oidc_client_id": "client",
                "user_id": "user-oidc"
            ],
            "xai::api_key": [
                "key": "xai-secret",
                "auth_mode": "api_key"
            ]
        ])

        let parsed = try GrokCredentialStore.session(in: session)
        XCTAssertEqual(parsed.session.scope, "https://auth.x.ai::6f1c2a40-1111-2222-3333-444455556666")
        XCTAssertEqual(parsed.session.accessToken, "oidc-access-key")
        XCTAssertEqual(parsed.session.refreshToken, "refresh-token")
        XCTAssertEqual(parsed.session.userID, "user-oidc")
        XCTAssertEqual(parsed.session.issuer, "https://auth.x.ai")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let expiry = try XCTUnwrap(parsed.session.expiresAt)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: expiry)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 10)
        XCTAssertEqual(parts.day, 15)
        XCTAssertEqual(parts.hour, 12)
        XCTAssertEqual(parts.minute, 29)
    }

    func testGrokWebCreditsReadsWeeklyPercentResetAndProducts() throws {
        let config = protoDouble(1, 6)
            + protoString(4, "2026-10-14T15:27:00Z")
            + protoString(5, "2026-10-21T15:27:00Z")
            + protoMessage(7, protoVarintField(1, 9) + protoDouble(2, 4))
            + protoMessage(7, protoVarintField(1, 3) + protoDouble(2, 2))
        let body = grpcFrame(protoMessage(1, config)) + grpcFrame(Data("grpc-status: 0\r\n".utf8), trailer: true)

        let verdict = GrokWebCredits.interpret(body: body, httpStatus: 200, contentType: "application/grpc-web+proto")
        guard case .usage(let reading) = verdict.interpretation else {
            return XCTFail(verdict.diagnostic)
        }
        XCTAssertEqual(reading.percentUsed, 0.06, accuracy: 0.0001)
        XCTAssertEqual(reading.products.map(\.name), ["Product 9", "Other"])
        XCTAssertEqual(reading.products[0].percentUsed, 0.04, accuracy: 0.0001)
        XCTAssertEqual(reading.products[1].percentUsed, 0.02, accuracy: 0.0001)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reset = try XCTUnwrap(reading.resetsAt)
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: reset)
        XCTAssertEqual(parts.year, 2026)
        XCTAssertEqual(parts.month, 10)
        XCTAssertEqual(parts.day, 21)
        XCTAssertEqual(parts.hour, 15)
        XCTAssertEqual(parts.minute, 27)
        XCTAssertTrue(verdict.diagnostic.contains("1.1"))
        XCTAssertFalse(verdict.diagnostic.localizedCaseInsensitiveContains("cookie"))
        XCTAssertFalse(verdict.diagnostic.contains("sso="))

        let buckets = GrokWebCredits.buckets(from: reading)
        let weekly = try XCTUnwrap(buckets.first(where: { $0.kind == .weekly }))
        XCTAssertEqual(weekly.quotaID, "grok-weekly")
        XCTAssertEqual(weekly.label, "1w")
        XCTAssertEqual(weekly.resolvedPercentUsed ?? -1, 0.06, accuracy: 0.0001)
        XCTAssertEqual(buckets.first(where: { $0.label == "Other" })?.resolvedPercentUsed ?? -1, 0.02, accuracy: 0.0001)
    }

    func testGrokWebCreditsReadsVarintPercentAndTimestampMessage() throws {
        let reset = protoMessage(5, protoVarintField(1, 1_792_596_420))
        let config = protoVarintField(1, 6) + reset
        let verdict = GrokWebCredits.interpret(body: grpcFrame(protoMessage(1, config)), httpStatus: 200)
        guard case .usage(let reading) = verdict.interpretation else {
            return XCTFail(verdict.diagnostic)
        }
        XCTAssertEqual(reading.percentUsed, 0.06, accuracy: 0.0001)
        let date = try XCTUnwrap(reading.resetsAt)
        XCTAssertEqual(date.timeIntervalSince1970, 1_792_596_420, accuracy: 0.5)
    }

    func testGrokWebCreditsDoesNotInventZeroOrShiftOmittedProductPercents() {
        let missing = protoMessage(1, protoString(5, "2026-10-21T15:27:00Z") + protoMessage(7, protoVarintField(1, 3) + protoDouble(2, 2)))
        let omitted = GrokWebCredits.interpret(body: grpcFrame(missing), httpStatus: 200)
        guard case .undecodable(let message) = omitted.interpretation else {
            return XCTFail("missing percent was accepted")
        }
        XCTAssertTrue(message.contains("will not invent 0%"))

        let shifted = protoMessage(1, protoDouble(1, 21) + protoMessage(7, protoVarintField(1, 6)) + protoMessage(7, protoVarintField(1, 4) + protoDouble(2, 21)))
        let parsed = GrokWebCredits.interpret(body: grpcFrame(shifted), httpStatus: 200)
        guard case .usage(let reading) = parsed.interpretation else {
            return XCTFail(parsed.diagnostic)
        }
        XCTAssertEqual(reading.products.map(\.name), ["Chat"])
        XCTAssertEqual(reading.products.first?.percentUsed ?? -1, 0.21, accuracy: 0.0001)

        let explicitZero = GrokWebCredits.interpret(body: grpcFrame(protoMessage(1, protoDouble(1, 0))), httpStatus: 200)
        guard case .usage(let zero) = explicitZero.interpretation else {
            return XCTFail(explicitZero.diagnostic)
        }
        XCTAssertEqual(zero.percentUsed, 0, accuracy: 0.0001)
    }

    func testGrokWebCreditsTreatsAuthFailuresAsReLogin() {
        let html = GrokWebCredits.interpret(body: Data("<!DOCTYPE html><html>".utf8), httpStatus: 200, contentType: "text/html")
        guard case .needsReLogin = html.interpretation else {
            return XCTFail("HTML was not treated as a signed-out page")
        }
        let denied = GrokWebCredits.interpret(body: Data(), httpStatus: 403)
        guard case .needsReLogin = denied.interpretation else {
            return XCTFail("HTTP 403 was not treated as a signed-out session")
        }
        let trailer = grpcFrame(Data()) + grpcFrame(Data("grpc-status: 16\r\n".utf8), trailer: true)
        let unauthenticated = GrokWebCredits.interpret(body: trailer, httpStatus: 200)
        guard case .needsReLogin = unauthenticated.interpretation else {
            return XCTFail("grpc-status 16 was not treated as a signed-out session")
        }
        let compressed = Data([0x01, 0, 0, 0, 1, 0])
        let compressedVerdict = GrokWebCredits.interpret(body: compressed, httpStatus: 200)
        guard case .undecodable(let message) = compressedVerdict.interpretation else {
            return XCTFail("compressed frame was accepted")
        }
        XCTAssertTrue(message.contains("will not invent 0%"))
    }

    func testGrokWebSessionIDSurvivesAccountDecoding() throws {
        let account = UsageAccount(
            provider: .grok,
            name: "Grok Web",
            source: .currentSession,
            grokWebSessionID: "6f1c2a40-1111-2222-3333-444455556666",
            buckets: []
        )
        let data = try JSONEncoder().encode(account)
        let decoded = try JSONDecoder().decode(UsageAccount.self, from: data)
        XCTAssertEqual(decoded.grokWebSessionID, account.grokWebSessionID)

        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "grokWebSessionID")
        let legacy = try JSONDecoder().decode(UsageAccount.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(legacy.grokWebSessionID)
        XCTAssertEqual(
            DisplayAccountPolicy.authenticationState(
                account: account,
                refreshState: .degraded(Date(), "Grok web login expired. Sign in again on grok.com.")
            ),
            .valid
        )
    }

    private func jsonData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private func protoVarint(_ value: UInt64) -> Data {
        var rest = value
        var data = Data()
        while true {
            var byte = UInt8(rest & 0x7F)
            rest >>= 7
            if rest != 0 { byte |= 0x80 }
            data.append(byte)
            if rest == 0 { break }
        }
        return data
    }

    private func protoKey(_ field: Int, wire: Int) -> Data {
        protoVarint(UInt64((field << 3) | wire))
    }

    private func protoVarintField(_ field: Int, _ value: UInt64) -> Data {
        protoKey(field, wire: 0) + protoVarint(value)
    }

    private func protoDouble(_ field: Int, _ value: Double) -> Data {
        var data = protoKey(field, wire: 1)
        let bits = value.bitPattern
        for offset in 0..<8 {
            data.append(UInt8((bits >> UInt64(offset * 8)) & 0xFF))
        }
        return data
    }

    private func protoMessage(_ field: Int, _ payload: Data) -> Data {
        protoKey(field, wire: 2) + protoVarint(UInt64(payload.count)) + payload
    }

    private func protoString(_ field: Int, _ value: String) -> Data {
        protoMessage(field, Data(value.utf8))
    }

    private func grpcFrame(_ payload: Data, trailer: Bool = false) -> Data {
        var data = Data([trailer ? 0x80 : 0x00])
        let length = UInt32(payload.count)
        data.append(UInt8((length >> 24) & 0xFF))
        data.append(UInt8((length >> 16) & 0xFF))
        data.append(UInt8((length >> 8) & 0xFF))
        data.append(UInt8(length & 0xFF))
        data.append(payload)
        return data
    }
}

final class RailMotionRuntimeTests: XCTestCase {
    func testSurfaceBreakAndDockThresholdsStaySeparated() {
        XCTAssertEqual(RailMotionRuntime.detachStart, 0.12, accuracy: 0.0001)
        XCTAssertEqual(RailMotionRuntime.surfaceBreakThreshold, 0.30, accuracy: 0.0001)
        XCTAssertEqual(RailMotionRuntime.dockThreshold, 0.50, accuracy: 0.0001)
        XCTAssertEqual(RailMotionRuntime.detachThreshold, 0.30, accuracy: 0.0001)
    }

    func testFastPullCarriesMoreKineticEnergyThanSlowPull() {
        var slow = RailMotionRuntime()
        slow.begin(verticalPosition: 0.5, timestamp: 0.001)
        _ = slow.updateDrag(
            outwardDistance: 0,
            screenProgress: 0,
            screenWidth: 1_440,
            verticalTarget: 0.5,
            timestamp: 0.011
        )
        let slowFrame = slow.updateDrag(
            outwardDistance: 140,
            screenProgress: 0.20,
            screenWidth: 1_440,
            verticalTarget: 0.5,
            timestamp: 0.211
        )

        var fast = RailMotionRuntime()
        fast.begin(verticalPosition: 0.5, timestamp: 0.001)
        _ = fast.updateDrag(
            outwardDistance: 0,
            screenProgress: 0,
            screenWidth: 1_440,
            verticalTarget: 0.5,
            timestamp: 0.011
        )
        let fastFrame = fast.updateDrag(
            outwardDistance: 140,
            screenProgress: 0.20,
            screenWidth: 1_440,
            verticalTarget: 0.5,
            timestamp: 0.051
        )

        XCTAssertGreaterThan(fastFrame.kinetic, slowFrame.kinetic)
    }

    func testContentClusterTrailsRailBodyDuringPull() {
        var runtime = RailMotionRuntime()
        runtime.begin(verticalPosition: 0.5, timestamp: 0.001)
        _ = runtime.updateDrag(
            outwardDistance: 0,
            screenProgress: 0,
            screenWidth: 1_440,
            verticalTarget: 0.5,
            timestamp: 0.011
        )
        let frame = runtime.updateDrag(
            outwardDistance: 180,
            screenProgress: 0.23,
            screenWidth: 1_440,
            verticalTarget: 0.5,
            timestamp: 0.061
        )

        XCTAssertGreaterThan(frame.canvasExtraWidth, 0)
        XCTAssertGreaterThan(frame.contentTravel, 0)
        XCTAssertLessThan(frame.contentTravel, frame.canvasExtraWidth)
    }

    func testVerticalMotionLagsThenConverges() {
        var runtime = RailMotionRuntime()
        runtime.begin(verticalPosition: 0.2, timestamp: 0.001)
        let first = runtime.updateDrag(
            outwardDistance: 0,
            screenProgress: 0,
            screenWidth: 1_440,
            verticalTarget: 0.8,
            timestamp: 0.021
        )
        XCTAssertGreaterThan(first.verticalPosition, 0.2)
        XCTAssertLessThan(first.verticalPosition, 0.8)

        var frame = first
        for index in 1...90 {
            frame = runtime.updateDrag(
                outwardDistance: 0,
                screenProgress: 0,
                screenWidth: 1_440,
                verticalTarget: 0.8,
                timestamp: 0.021 + Double(index) / 120.0
            )
        }
        XCTAssertEqual(frame.verticalPosition, 0.8, accuracy: 0.01)
    }

    func testReleaseSettlesBackToRestWithVerticalTargetPreserved() {
        var runtime = RailMotionRuntime()
        runtime.begin(verticalPosition: 0.4, timestamp: 0.001)
        _ = runtime.updateDrag(
            outwardDistance: 0,
            screenProgress: 0,
            screenWidth: 1_440,
            verticalTarget: 0.4,
            timestamp: 0.011
        )
        _ = runtime.updateDrag(
            outwardDistance: 190,
            screenProgress: 0.25,
            screenWidth: 1_440,
            verticalTarget: 0.65,
            timestamp: 0.061
        )
        _ = runtime.release(timestamp: 0.071)

        var frame = runtime.frame
        for index in 1...220 {
            frame = runtime.stepTowardRest(timestamp: 0.071 + Double(index) / 120.0)
        }

        XCTAssertTrue(runtime.isSettled)
        XCTAssertLessThan(frame.canvasExtraWidth, 1)
        XCTAssertLessThan(frame.stretch, 0.02)
        XCTAssertEqual(frame.verticalPosition, 0.65, accuracy: 0.01)
    }

    func testSurfaceBreakCreatesIndependentDropAndResidue() {
        var runtime = RailMotionRuntime()
        runtime.begin(
            verticalPosition: 0.5,
            originCenter: CGPoint(x: 80, y: 400),
            timestamp: 0.001
        )
        _ = runtime.updateDrag(
            outwardDistance: 320,
            screenProgress: 0.29,
            screenWidth: 1_440,
            verticalTarget: 0.55,
            timestamp: 0.041
        )
        let broken = runtime.breakSurface(
            floatingCenter: CGPoint(x: 450, y: 430),
            verticalPosition: 0.55,
            timestamp: 0.051
        )

        XCTAssertGreaterThan(broken.residue, 0.5)
        XCTAssertGreaterThan(broken.impact, 0.5)
        XCTAssertEqual(broken.floatingCenterX, 450, accuracy: 1.0)
        XCTAssertEqual(broken.floatingCenterY, 430, accuracy: 1.0)
        XCTAssertLessThan(broken.canvasExtraWidth, 80)
    }

    func testSurfaceBreakPochanImpulseIsEventDrivenRatherThanDistanceDriven() {
        func breakFrame(distance: CGFloat) -> RailMotionFrame {
            var runtime = RailMotionRuntime()
            runtime.begin(
                verticalPosition: 0.5,
                originCenter: CGPoint(x: 80, y: 400),
                timestamp: 0.001
            )
            _ = runtime.updateDrag(
                outwardDistance: 0,
                screenProgress: 0,
                screenWidth: 1_440,
                verticalTarget: 0.5,
                timestamp: 0.011
            )
            _ = runtime.updateDrag(
                outwardDistance: distance,
                screenProgress: 0.29,
                screenWidth: 1_440,
                verticalTarget: 0.5,
                timestamp: 0.041
            )
            return runtime.breakSurface(
                floatingCenter: CGPoint(x: 440, y: 420),
                verticalPosition: 0.5,
                timestamp: 0.051
            )
        }

        let shortPull = breakFrame(distance: 90)
        let longPull = breakFrame(distance: 340)
        XCTAssertGreaterThan(shortPull.impact, 0.75)
        XCTAssertGreaterThan(longPull.impact, 0.75)
        XCTAssertGreaterThan(abs(shortPull.breakPulse), 0.02)
        XCTAssertEqual(shortPull.breakPulse, longPull.breakPulse, accuracy: 0.02)
    }

    func testSurfaceBreakPulseContinuesWithoutFurtherDragDistance() {
        var runtime = RailMotionRuntime()
        runtime.begin(
            verticalPosition: 0.5,
            originCenter: CGPoint(x: 80, y: 400),
            timestamp: 0.001
        )
        _ = runtime.updateDrag(
            outwardDistance: 240,
            screenProgress: 0.29,
            screenWidth: 1_440,
            verticalTarget: 0.5,
            timestamp: 0.041
        )
        let broken = runtime.breakSurface(
            floatingCenter: CGPoint(x: 440, y: 420),
            verticalPosition: 0.5,
            timestamp: 0.051
        )
        var frames: [CGFloat] = [broken.breakPulse]
        for index in 1...24 {
            frames.append(runtime.tickFloating(timestamp: 0.051 + Double(index) / 120.0).breakPulse)
        }
        XCTAssertGreaterThan(frames.map { abs($0) }.max() ?? 0, 0.12)
        XCTAssertGreaterThan(Set(frames.map { Int(($0 * 1_000).rounded()) }).count, 4)
    }

    func testSeededDragDropletsAreDeterministicAndActuallyFall() {
        let first = RailDragDropletEmitter.samples(seed: 0xC0FFEE, elapsed: 0.73, intensity: 0.82)
        let repeated = RailDragDropletEmitter.samples(seed: 0xC0FFEE, elapsed: 0.73, intensity: 0.82)
        let otherSeed = RailDragDropletEmitter.samples(seed: 0xBADF00D, elapsed: 0.73, intensity: 0.82)

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, repeated)
        XCTAssertNotEqual(first, otherSeed)
        XCTAssertTrue(first.allSatisfy { $0.yOffset >= 0 && $0.height >= $0.width })
        XCTAssertTrue(first.contains { $0.phase == .falling && $0.yOffset > 2 })
    }

    func testF1721ContentDeformationIsClusterWideAndFreeSideBiased() {
        let weak = RailContentDeformationField.resolve(
            stretch: 0.10,
            neck: 0.04,
            kinetic: 0,
            detach: 0,
            scale: 1,
            attached: true
        )
        let strong = RailContentDeformationField.resolve(
            stretch: 1.15,
            neck: 0.92,
            kinetic: 0.55,
            detach: 0.35,
            scale: 1,
            attached: true
        )

        XCTAssertLessThan(strong.neckZone, strong.midZone)
        XCTAssertLessThan(strong.midZone, strong.freeSideZone)
        XCTAssertGreaterThan(strong.groupScaleX, 1.20)
        XCTAssertLessThan(strong.groupScaleY, 1)
        XCTAssertGreaterThan(strong.freeSideTranslation, weak.freeSideTranslation + 6)
        XCTAssertGreaterThan(strong.bodyPlacementWeight, 0.7)
        XCTAssertGreaterThan(strong.spacingScale, 1)
        XCTAssertLessThan(strong.perspectiveDegrees, 8)
    }

    func testF1720DragVelocityTrackerProducesDirectionalReleaseVector() {
        var tracker = RailDragVelocityTracker()
        tracker.begin(timestamp: 0.001)
        _ = tracker.update(translation: CGSize(width: 42, height: 8), timestamp: 0.031)
        let velocity = tracker.update(translation: CGSize(width: 118, height: 29), timestamp: 0.061)

        XCTAssertGreaterThan(velocity.dx, 500)
        XCTAssertGreaterThan(velocity.dy, 100)
        XCTAssertGreaterThan(velocity.dx, velocity.dy)
    }

    func testF1722DragDropletsFavorHeavyDropsAndIncludeHangingPhase() {
        var samples: [RailDragDropletSample] = []
        for seed in 1...24 {
            samples.append(contentsOf: RailDragDropletEmitter.samples(
                seed: UInt64(seed) * 0x9E37,
                elapsed: 0.73,
                intensity: 0.88
            ))
        }

        let small = samples.filter { $0.sizeClass == .small }.count
        let medium = samples.filter { $0.sizeClass == .medium }.count
        let large = samples.filter { $0.sizeClass == .large }.count
        let hanging = samples.filter { $0.phase == .hanging }
        XCTAssertGreaterThan(samples.count, 20)
        XCTAssertGreaterThan(medium, small * 3)
        XCTAssertGreaterThan(large, small)
        XCTAssertGreaterThan(medium + large, samples.count * 4 / 5)
        XCTAssertFalse(hanging.isEmpty)
        XCTAssertTrue(hanging.allSatisfy { $0.shape == .hangingDrop && abs($0.yOffset) < 0.001 })
        XCTAssertTrue(samples.allSatisfy { $0.height <= $0.width * 1.8 })
    }

    func testF1722AttachedHighVelocityOnlyAddsGentleBackwardDrift() {
        let fastVelocity = CGVector(dx: 1_800, dy: 90)
        var fastSamples: [RailDragDropletSample] = []
        var slowSamples: [RailDragDropletSample] = []
        for seed in 1...18 {
            let value = UInt64(seed) * 0xA24B
            fastSamples.append(contentsOf: RailDragDropletEmitter.samples(
                seed: value,
                elapsed: 0.82,
                intensity: 0.84,
                velocity: fastVelocity
            ))
            slowSamples.append(contentsOf: RailDragDropletEmitter.samples(
                seed: value,
                elapsed: 0.82,
                intensity: 0.84,
                velocity: .zero
            ))
        }

        let fastFalling = fastSamples.filter { $0.phase == .falling }
        let slowFalling = slowSamples.filter { $0.phase == .falling }
        XCTAssertFalse(fastFalling.isEmpty)
        XCTAssertEqual(fastSamples.map(\.sizeClass), slowSamples.map(\.sizeClass))
        let fastMeanX = fastFalling.map(\.xOffset).reduce(0, +) / CGFloat(fastFalling.count)
        let slowMeanX = slowFalling.map(\.xOffset).reduce(0, +) / CGFloat(slowFalling.count)
        XCTAssertLessThan(fastMeanX, slowMeanX - 4)
        XCTAssertGreaterThan(fastMeanX, -45)
    }

    func testF1721NeckGeometryAndBodyPlacementFollowSameThroat() {
        let rect = CGRect(x: 0, y: 0, width: 420, height: 238)
        let right = RailNeckGeometryResolver.resolve(
            in: rect,
            edge: .right,
            screenEdgeAmount: 0.55,
            screenEdgeCurvature: -0.45,
            innerEdgeAmount: -0.18,
            cornerRadius: 28,
            scallopDepth: 28,
            smoothing: 0.78,
            stretchAmount: 1.08,
            neckAmount: 0.91,
            kineticAmount: 0.42,
            screenEdgeOutset: 4,
            renderInset: 3
        )
        let left = RailNeckGeometryResolver.resolve(
            in: rect,
            edge: .left,
            screenEdgeAmount: 0.55,
            screenEdgeCurvature: -0.45,
            innerEdgeAmount: -0.18,
            cornerRadius: 28,
            scallopDepth: 28,
            smoothing: 0.78,
            stretchAmount: 1.08,
            neckAmount: 0.91,
            kineticAmount: 0.42,
            screenEdgeOutset: 4,
            renderInset: 3
        )

        XCTAssertEqual(right, left)
        XCTAssertGreaterThan(right.distanceFromScreen, 40)
        XCTAssertLessThan(right.distanceFromScreen, rect.width * 0.57)
        XCTAssertGreaterThan(right.thickness, 1.5)
        XCTAssertLessThan(right.thickness, rect.height * 0.35)
        XCTAssertEqual(right.centerY, rect.midY, accuracy: 1.5)

        let renderedContentWidth: CGFloat = 92
        let rightOffset = RailContentBodyPlacement.targetOffset(
            railWidth: rect.width,
            renderedContentWidth: renderedContentWidth,
            neckDistanceFromScreen: right.distanceFromScreen,
            edge: .right,
            freeSideWeight: 0.92,
            borderPadding: 3
        )
        let leftOffset = RailContentBodyPlacement.targetOffset(
            railWidth: rect.width,
            renderedContentWidth: renderedContentWidth,
            neckDistanceFromScreen: left.distanceFromScreen,
            edge: .left,
            freeSideWeight: 0.92,
            borderPadding: 3
        )
        XCTAssertLessThan(rightOffset, 0)
        XCTAssertGreaterThan(leftOffset, 0)
        XCTAssertEqual(abs(rightOffset), abs(leftOffset), accuracy: 0.001)
        XCTAssertLessThan(abs(rightOffset), rect.width * 0.5 - renderedContentWidth * 0.5)
    }

    func testF1722FloatingDropletsTrailGentlyAndStillHangAtLowSpeed() {
        let fastVelocity = CGVector(dx: 1_800, dy: 120)
        var fast: [RailDragDropletSample] = []
        var slow: [RailDragDropletSample] = []
        var repeated: [RailDragDropletSample] = []
        for seed in 1...14 {
            let value = UInt64(seed) * 0xF1721BEE
            fast.append(contentsOf: RailFloatingDropletEmitter.samples(
                seed: value,
                elapsed: 0.61,
                intensity: 0.84,
                velocity: fastVelocity
            ))
            repeated.append(contentsOf: RailFloatingDropletEmitter.samples(
                seed: value,
                elapsed: 0.61,
                intensity: 0.84,
                velocity: fastVelocity
            ))
            slow.append(contentsOf: RailFloatingDropletEmitter.samples(
                seed: value,
                elapsed: 0.61,
                intensity: 0.84,
                velocity: .zero
            ))
        }

        XCTAssertFalse(fast.isEmpty)
        XCTAssertFalse(slow.isEmpty)
        XCTAssertEqual(fast, repeated)
        let fastFalling = fast.filter { $0.phase == .falling }
        let slowFalling = slow.filter { $0.phase == .falling }
        let fastMeanX = fastFalling.map(\.xOffset).reduce(0, +) / CGFloat(fastFalling.count)
        let slowMeanX = slowFalling.map(\.xOffset).reduce(0, +) / CGFloat(slowFalling.count)
        XCTAssertLessThan(fastMeanX, slowMeanX - 4)
        XCTAssertGreaterThan(fastMeanX, -55)
        XCTAssertTrue(slow.contains { $0.phase == .hanging && $0.shape == .hangingDrop })
        XCTAssertGreaterThan(slow.filter { $0.yOffset >= 0 }.count, slow.count * 3 / 4)
        XCTAssertTrue((fast + slow).allSatisfy { $0.height <= $0.width * 1.8 })
    }

    func testF1723FloatingDropletsDistributeAcrossUndersideBand() {
        let halfWidth: CGFloat = 42
        var samples: [RailDragDropletSample] = []
        var repeated: [RailDragDropletSample] = []
        for seed in 1...18 {
            let value = UInt64(seed) * 0xF1723D0C
            let batch = RailFloatingDropletEmitter.samples(
                seed: value,
                elapsed: 0.64,
                intensity: 0.82,
                velocity: .zero,
                emitterHalfWidth: halfWidth
            )
            samples.append(contentsOf: batch)
            repeated.append(contentsOf: RailFloatingDropletEmitter.samples(
                seed: value,
                elapsed: 0.64,
                intensity: 0.82,
                velocity: .zero,
                emitterHalfWidth: halfWidth
            ))
        }

        XCTAssertEqual(samples, repeated)
        XCTAssertFalse(samples.isEmpty)
        XCTAssertTrue(samples.contains { $0.xOffset < -halfWidth * 0.30 })
        XCTAssertTrue(samples.contains { $0.xOffset > halfWidth * 0.30 })
        XCTAssertTrue(samples.allSatisfy { abs($0.xOffset) <= halfWidth + 4 })
        XCTAssertTrue(samples.contains { $0.phase == .hanging && $0.shape == .hangingDrop })
    }

    func testF1724FloatingDropletsAnchorToExactRoundedUndersideAcrossBand() {
        let rect = CGRect(x: 0, y: 0, width: 220, height: 118)
        let halfWidth: CGFloat = 58
        let impact = 0.22
        let kinetic = 0.30
        let surface: (CGFloat) -> CGFloat = { xOffset in
            FloatingRailGeometry.undersideOffsetFromCenter(
                in: rect,
                xOffset: xOffset,
                impact: impact,
                kinetic: kinetic
            )
        }
        var hanging: [RailDragDropletSample] = []

        for seed in 1...24 {
            hanging.append(contentsOf: RailFloatingDropletEmitter.samples(
                seed: UInt64(seed) * 0xF1724D0C,
                elapsed: 0.64,
                intensity: 0.84,
                velocity: .zero,
                emitterHalfWidth: halfWidth,
                surfaceYOffset: surface
            ).filter { $0.phase == .hanging })
        }

        XCTAssertFalse(hanging.isEmpty)
        XCTAssertTrue(hanging.contains { $0.xOffset < -halfWidth * 0.25 })
        XCTAssertTrue(hanging.contains { $0.xOffset > halfWidth * 0.25 })
        for sample in hanging {
            XCTAssertEqual(sample.yOffset, surface(sample.xOffset), accuracy: 0.001)
        }
        XCTAssertEqual(surface(0), FloatingRailGeometry.bodyRect(in: rect).maxY - rect.midY, accuracy: 0.001)
    }

    func testF1726FloatingDropletsTrackRenderedUndersideAndSurfaceTensionAfterBreak() {
        let rect = CGRect(x: 0, y: 0, width: 220, height: 118)
        let rawHalfWidth: CGFloat = 58
        let impact = 0.52
        let kinetic = 0.38
        let breakPulse: CGFloat = 0.78
        let visualScaleX = FloatingRailGeometry.bodyScaleX(impact: impact)
            * RailBreakVisualTransform.scaleX(for: breakPulse)
        let halfWidth = rawHalfWidth * visualScaleX
        let tensionSeed: UInt64 = 0xF1726A051D51A61
        let tension = FloatingSurfaceTensionGeometry.intensity(
            stretch: 0.82,
            kinetic: CGFloat(kinetic),
            breakPulse: breakPulse
        )
        let renderedSurface: (CGFloat) -> CGFloat = { xOffset in
            FloatingRailGeometry.visualUndersideOffsetFromCenter(
                in: rect,
                xOffset: xOffset,
                impact: impact,
                kinetic: kinetic,
                breakPulse: breakPulse
            )
        }
        let hangingSurface: (CGFloat) -> CGFloat = { xOffset in
            renderedSurface(xOffset) - FloatingSurfaceTensionGeometry.bodyOverlap
        }
        let detachmentSurface: (CGFloat) -> CGFloat = { xOffset in
            renderedSurface(xOffset) + FloatingSurfaceTensionGeometry.sagOffset(
                xOffset: xOffset,
                halfWidth: halfWidth,
                intensity: tension,
                seed: tensionSeed
            )
        }
        var hanging: [RailDragDropletSample] = []
        var falling: [RailDragDropletSample] = []

        for seed in 1...28 {
            let samples = RailFloatingDropletEmitter.samples(
                seed: UInt64(seed) * 0xF1726D0C,
                elapsed: 0.64,
                intensity: 0.86,
                velocity: .zero,
                emitterHalfWidth: halfWidth,
                surfaceYOffset: hangingSurface,
                fallingSurfaceYOffset: detachmentSurface
            )
            hanging.append(contentsOf: samples.filter { $0.phase == .hanging })
            falling.append(contentsOf: samples.filter { $0.phase == .falling })
        }

        XCTAssertFalse(hanging.isEmpty)
        XCTAssertFalse(falling.isEmpty)
        for sample in hanging {
            XCTAssertEqual(sample.yOffset, hangingSurface(sample.xOffset), accuracy: 0.001)
        }
        let rawCenter = FloatingRailGeometry.undersideOffsetFromCenter(
            in: rect,
            xOffset: 0,
            impact: impact,
            kinetic: kinetic
        )
        let renderedCenter = FloatingRailGeometry.visualUndersideOffsetFromCenter(
            in: rect,
            xOffset: 0,
            impact: impact,
            kinetic: kinetic,
            breakPulse: breakPulse
        )
        XCTAssertGreaterThan(abs(renderedCenter - rawCenter), 0.5)
        XCTAssertGreaterThan(FloatingSurfaceTensionGeometry.bodyOverlap, 1)
        XCTAssertLessThan(hangingSurface(0), renderedCenter)
        XCTAssertGreaterThan(detachmentSurface(0), renderedCenter + 3)
        XCTAssertGreaterThan(
            FloatingSurfaceTensionGeometry.sagOffset(
                xOffset: 0,
                halfWidth: halfWidth,
                intensity: tension,
                seed: tensionSeed
            ),
            3
        )
        XCTAssertEqual(
            FloatingSurfaceTensionGeometry.sagOffset(
                xOffset: halfWidth * 1.1,
                halfWidth: halfWidth,
                intensity: tension,
                seed: tensionSeed
            ),
            0,
            accuracy: 0.001
        )
    }

    func testF1727FloatingOverlayUsesSameRenderedHeightAsActualFloatingRail() {
        let baseHeight: CGFloat = 118
        let screenOutset: CGFloat = 17
        let borderPadding: CGFloat = 5
        let attachedHeight = RailMetrics.renderedHeight(
            baseHeight: baseHeight,
            visualOutset: screenOutset,
            borderPadding: borderPadding
        )
        let floatingHeight = RailMetrics.renderedHeight(
            baseHeight: baseHeight,
            visualOutset: 0,
            borderPadding: borderPadding
        )

        XCTAssertEqual(floatingHeight, baseHeight + borderPadding * 2, accuracy: 0.001)
        XCTAssertEqual(attachedHeight - floatingHeight, screenOutset * 2, accuracy: 0.001)
        XCTAssertLessThan(floatingHeight, attachedHeight)
    }

    func testF1727SpaceSurfaceStarsAreDeterministicAndBounded() {
        let size = CGSize(width: 220, height: 118)
        let first = SpaceSurfaceGeometry.stars(in: size)
        let second = SpaceSurfaceGeometry.stars(in: size)

        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 36)
        XCTAssertTrue(first.allSatisfy { star in
            star.center.x >= 0 && star.center.x <= size.width
                && star.center.y >= 0 && star.center.y <= size.height
                && star.radius >= 0.32 && star.radius <= 1.04
                && star.opacity >= 0.075 && star.opacity <= 0.235
        })
        XCTAssertGreaterThan(Set(first.map { Int($0.center.x.rounded()) }).count, 20)
        XCTAssertGreaterThan(Set(first.map { Int($0.center.y.rounded()) }).count, 20)
    }

    func testF1726LegacyCurveRadiusAndSmoothnessDoNotMutateCanonicalContour() {
        let rect = CGRect(x: 0, y: 0, width: 340, height: 180)
        func points(scallopRadius: Double, smoothing: Double) -> [CGPoint] {
            let path = EdgeRailShape(
                edge: .right,
                screenEdgeAmount: 0.48,
                screenEdgeCurvature: -0.58,
                innerEdgeAmount: -0.32,
                cornerRadius: 28,
                scallopDepth: 34,
                scallopRadius: scallopRadius,
                smoothing: smoothing,
                stretchAmount: 0.72,
                neckAmount: 0.58,
                kineticAmount: 0.34,
                screenEdgeOutset: 0,
                renderInset: 4
            ).path(in: rect).cgPath
            var result: [CGPoint] = []
            path.applyWithBlock { elementPointer in
                let element = elementPointer.pointee
                let count: Int
                switch element.type {
                case .moveToPoint, .addLineToPoint: count = 1
                case .addQuadCurveToPoint: count = 2
                case .addCurveToPoint: count = 3
                case .closeSubpath: count = 0
                @unknown default: count = 0
                }
                for index in 0..<count {
                    result.append(element.points[index])
                }
            }
            return result
        }

        let minimum = points(scallopRadius: 4, smoothing: 0)
        let maximum = points(scallopRadius: 64, smoothing: 1)
        XCTAssertEqual(minimum.count, maximum.count)
        for (lhs, rhs) in zip(minimum, maximum) {
            XCTAssertEqual(lhs.x, rhs.x, accuracy: 0.001)
            XCTAssertEqual(lhs.y, rhs.y, accuracy: 0.001)
        }
    }

    func testF1725HangingDropletVisualStartsExactlyAtEmitterOrigin() {
        let rect = CGRect(x: 20, y: 40, width: 12, height: 28)
        let cgPath = LiquidDropletDrawing.path(in: rect, shape: .hangingDrop, secondaryLobe: 0).cgPath
        var firstMove: CGPoint?
        cgPath.applyWithBlock { elementPointer in
            if firstMove == nil, elementPointer.pointee.type == .moveToPoint {
                firstMove = elementPointer.pointee.points[0]
            }
        }
        XCTAssertEqual(firstMove?.y ?? .nan, rect.minY, accuracy: 0.001)
    }

    func testF1725AttachedEdgeIsValleyOnlyAndInwardModeIsBubbleSemantic() {
        let mountainAttempt = EdgeRailSemanticProfile.resolve(screenEdgeAmount: 0.7, screenEdgeCurvature: 1)
        XCTAssertEqual(mountainAttempt.valley, 0, accuracy: 0.001)
        XCTAssertEqual(mountainAttempt.outwardSpread, 0.7, accuracy: 0.001)
        XCTAssertEqual(mountainAttempt.inwardBubble, 0, accuracy: 0.001)

        let inward = EdgeRailSemanticProfile.resolve(screenEdgeAmount: -0.8, screenEdgeCurvature: -0.65)
        XCTAssertEqual(inward.valley, 0.65, accuracy: 0.001)
        XCTAssertEqual(inward.outwardSpread, 0, accuracy: 0.001)
        XCTAssertEqual(inward.inwardBubble, 0.8, accuracy: 0.001)
    }

    func testF1725CornerRadiusChangesInteriorContourWithoutRoundingAttachedEdge() {
        let rect = CGRect(x: 0, y: 0, width: 340, height: 180)
        func points(radius: Double) -> (start: CGPoint, interior: CGPoint, attachedBottom: CGPoint) {
            let shape = EdgeRailShape(
                edge: .right,
                screenEdgeAmount: 0.6,
                screenEdgeCurvature: -0.4,
                innerEdgeAmount: -0.2,
                cornerRadius: radius,
                scallopDepth: 22,
                scallopRadius: 30,
                smoothing: 0.76,
                stretchAmount: 0,
                neckAmount: 0,
                kineticAmount: 0,
                screenEdgeOutset: 0,
                renderInset: 4
            )
            var start: CGPoint = .zero
            var curveEndpoints: [CGPoint] = []
            shape.path(in: rect).cgPath.applyWithBlock { elementPointer in
                let element = elementPointer.pointee
                if element.type == .moveToPoint { start = element.points[0] }
                if element.type == .addCurveToPoint { curveEndpoints.append(element.points[2]) }
            }
            return (start, curveEndpoints[2], curveEndpoints[7])
        }

        let compact = points(radius: 6)
        let rounded = points(radius: 42)
        XCTAssertEqual(compact.start.x, rounded.start.x, accuracy: 0.001)
        XCTAssertEqual(compact.start.y, rounded.start.y, accuracy: 0.001)
        XCTAssertEqual(compact.attachedBottom.x, rounded.attachedBottom.x, accuracy: 0.001)
        XCTAssertEqual(compact.attachedBottom.y, rounded.attachedBottom.y, accuracy: 0.001)
        XCTAssertNotEqual(compact.interior.x, rounded.interior.x)
    }

    func testF1725InwardBubbleUsesShorterAttachedNeckThanOutwardSpread() {
        let rect = CGRect(x: 0, y: 0, width: 340, height: 180)
        let inward = RailNeckGeometryResolver.resolve(
            in: rect,
            edge: .right,
            screenEdgeAmount: -1,
            screenEdgeCurvature: -0.5,
            innerEdgeAmount: -0.2,
            cornerRadius: 28,
            scallopDepth: 24,
            smoothing: 0.76,
            stretchAmount: 0,
            neckAmount: 0,
            kineticAmount: 0,
            screenEdgeOutset: 0,
            renderInset: 4
        )
        let outward = RailNeckGeometryResolver.resolve(
            in: rect,
            edge: .right,
            screenEdgeAmount: 1,
            screenEdgeCurvature: -0.5,
            innerEdgeAmount: -0.2,
            cornerRadius: 28,
            scallopDepth: 24,
            smoothing: 0.76,
            stretchAmount: 0,
            neckAmount: 0,
            kineticAmount: 0,
            screenEdgeOutset: 0,
            renderInset: 4
        )
        XCTAssertLessThan(inward.distanceFromScreen, outward.distanceFromScreen)
    }

    func testF1724RightEdgeVisibleBorderKeepsLeftInteriorContourAndOmitsRightAttachedVertical() {
        let rect = CGRect(x: 0, y: 0, width: 340, height: 180)
        assertF1724VisibleBorderSemantics(
            edge: .right,
            rect: rect,
            expectedInteriorX: rect.minX,
            expectedAttachedX: rect.maxX
        )
    }

    func testF1724LeftEdgeVisibleBorderKeepsRightInteriorContourAndOmitsLeftAttachedVertical() {
        let rect = CGRect(x: 0, y: 0, width: 340, height: 180)
        assertF1724VisibleBorderSemantics(
            edge: .left,
            rect: rect,
            expectedInteriorX: rect.maxX,
            expectedAttachedX: rect.minX
        )
    }

    func testF1724VisibleBorderIsOneContinuousOpenSubpathForBothDockEdges() {
        let rect = CGRect(x: 0, y: 0, width: 340, height: 180)
        for edge in [DockEdge.left, DockEdge.right] {
            let cgPath = f1724VisibleBorderPath(edge: edge, rect: rect)
            var moveCount = 0
            var curveCount = 0
            var closeCount = 0
            cgPath.applyWithBlock { elementPointer in
                switch elementPointer.pointee.type {
                case .moveToPoint:
                    moveCount += 1
                case .addCurveToPoint:
                    curveCount += 1
                case .closeSubpath:
                    closeCount += 1
                default:
                    break
                }
            }

            XCTAssertEqual(moveCount, 1)
            XCTAssertEqual(curveCount, 8)
            XCTAssertEqual(closeCount, 0)
        }
    }

    private func assertF1724VisibleBorderSemantics(
        edge: DockEdge,
        rect: CGRect,
        expectedInteriorX: CGFloat,
        expectedAttachedX: CGFloat,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let cgPath = f1724VisibleBorderPath(edge: edge, rect: rect)
        var movePoints: [CGPoint] = []
        var curveEndpoints: [CGPoint] = []
        var lineEndpoints: [CGPoint] = []
        var closeCount = 0
        cgPath.applyWithBlock { elementPointer in
            let element = elementPointer.pointee
            switch element.type {
            case .moveToPoint:
                movePoints.append(element.points[0])
            case .addLineToPoint:
                lineEndpoints.append(element.points[0])
            case .addCurveToPoint:
                curveEndpoints.append(element.points[2])
            case .closeSubpath:
                closeCount += 1
            default:
                break
            }
        }

        XCTAssertEqual(movePoints.count, 1, file: file, line: line)
        XCTAssertEqual(closeCount, 0, file: file, line: line)
        XCTAssertTrue(lineEndpoints.isEmpty, file: file, line: line)
        XCTAssertTrue(
            curveEndpoints.contains { abs($0.x - expectedInteriorX) < 0.001 },
            "interior-facing cap must remain in the visible border path",
            file: file,
            line: line
        )
        if let start = movePoints.first, let end = curveEndpoints.last {
            XCTAssertEqual(start.x, expectedAttachedX, accuracy: 0.001, file: file, line: line)
            XCTAssertEqual(end.x, expectedAttachedX, accuracy: 0.001, file: file, line: line)
            XCTAssertGreaterThan(end.y, start.y, file: file, line: line)
        } else {
            XCTFail("visible border must have attached-edge endpoints", file: file, line: line)
        }
    }

    private func f1724VisibleBorderPath(edge: DockEdge, rect: CGRect) -> CGPath {
        let shape = EdgeRailShape(
            edge: edge,
            screenEdgeAmount: 0.42,
            screenEdgeCurvature: -0.36,
            innerEdgeAmount: -0.20,
            cornerRadius: 26,
            scallopDepth: 20,
            scallopRadius: 30,
            smoothing: 0.76,
            stretchAmount: 0.72,
            neckAmount: 0.82,
            kineticAmount: 0.24,
            screenEdgeOutset: 4,
            renderInset: 6
        )
        return EdgeRailVisibleBorderShape(base: shape).path(in: rect).cgPath
    }

    func testF1723PreBreakNeckGetsThinnerWithoutCollapsing() {
        let rect = CGRect(x: 0, y: 0, width: 420, height: 238)
        let moderate = RailNeckGeometryResolver.resolve(
            in: rect,
            edge: .left,
            screenEdgeAmount: 0.55,
            screenEdgeCurvature: -0.45,
            innerEdgeAmount: -0.18,
            cornerRadius: 28,
            scallopDepth: 28,
            smoothing: 0.78,
            stretchAmount: 0.72,
            neckAmount: 0.58,
            kineticAmount: 0.18,
            screenEdgeOutset: 4,
            renderInset: 3
        )
        let preBreak = RailNeckGeometryResolver.resolve(
            in: rect,
            edge: .left,
            screenEdgeAmount: 0.55,
            screenEdgeCurvature: -0.45,
            innerEdgeAmount: -0.18,
            cornerRadius: 28,
            scallopDepth: 28,
            smoothing: 0.78,
            stretchAmount: 1.18,
            neckAmount: 1.0,
            kineticAmount: 0.55,
            screenEdgeOutset: 4,
            renderInset: 3
        )

        XCTAssertLessThan(preBreak.thickness, moderate.thickness * 0.55)
        XCTAssertGreaterThanOrEqual(preBreak.thickness, 1.7)
        XCTAssertLessThan(preBreak.thickness, 8)
        XCTAssertEqual(preBreak.centerY, rect.midY, accuracy: 1.5)
    }

    func testF1721DragVelocityDecaysToVerticalDripWhenPointerStops() {
        var tracker = RailDragVelocityTracker()
        tracker.begin(timestamp: 1.0)
        _ = tracker.update(translation: CGSize(width: 120, height: 18), timestamp: 1.04)
        let live = tracker.decayedVelocity(at: 1.04)
        let paused = tracker.decayedVelocity(at: 1.45)

        XCTAssertGreaterThan(abs(live.dx), 500)
        XCTAssertLessThan(abs(paused.dx), abs(live.dx) * 0.05)
        XCTAssertLessThan(abs(paused.dy), abs(live.dy) * 0.05)
    }

    func testF1722BreakBurstIsSparseHeavyAndSubordinate() {
        let samples = RailBreakDropletEmitter.samples(
            seed: 0x1721CAFE,
            elapsed: 0.18,
            velocity: CGVector(dx: 1_550, dy: -180),
            freeDirection: 1
        )
        let anchor = samples.filter { $0.group == .anchorSideSplash }
        XCTAssertFalse(samples.isEmpty)
        XCTAssertLessThanOrEqual(samples.count, 9)
        XCTAssertGreaterThanOrEqual(anchor.count, 1)
        XCTAssertLessThanOrEqual(anchor.count, 3)
        XCTAssertGreaterThan(samples.filter { $0.width >= 4 }.count, samples.count * 2 / 3)
        XCTAssertFalse(samples.contains { $0.secondaryLobe > 0 })
        XCTAssertTrue(Set(samples.map(\.shape)).isSubset(of: Set([.round, .teardrop, .stretchedTeardrop, .hangingDrop])))
        XCTAssertTrue(samples.allSatisfy { $0.height <= $0.width * 1.45 })
    }

    func testF1722BreakVelocityInfluenceStaysBoundedInsteadOfSpraying() {
        let highVelocity = CGVector(dx: 1_900, dy: -220)
        let high = RailBreakDropletEmitter.samples(
            seed: 0x1720BEEF,
            elapsed: 0.22,
            velocity: highVelocity,
            freeDirection: 1
        )
        let repeated = RailBreakDropletEmitter.samples(
            seed: 0x1720BEEF,
            elapsed: 0.22,
            velocity: highVelocity,
            freeDirection: 1
        )
        let slow = RailBreakDropletEmitter.samples(
            seed: 0x1720BEEF,
            elapsed: 0.22,
            velocity: .zero,
            freeDirection: 1
        )

        XCTAssertEqual(high, repeated)
        let highFree = high.filter { $0.group == .freeSideSpray }
        let slowFree = slow.filter { $0.group == .freeSideSpray }
        let anchor = high.filter { $0.group == .anchorSideSplash }
        XCTAssertFalse(highFree.isEmpty)
        XCTAssertFalse(slowFree.isEmpty)
        XCTAssertFalse(anchor.isEmpty)
        let highMeanX = highFree.map(\.xOffset).reduce(0, +) / CGFloat(highFree.count)
        let slowMeanX = slowFree.map(\.xOffset).reduce(0, +) / CGFloat(slowFree.count)
        XCTAssertGreaterThan(highMeanX, slowMeanX + 4)
        XCTAssertLessThan(highFree.map { abs($0.xOffset) }.max() ?? 0, 35)
        XCTAssertGreaterThan(slowFree.filter { $0.yOffset > 0 }.count, slowFree.count / 2)
        XCTAssertTrue(anchor.allSatisfy { abs($0.xOffset) < 22 })
    }

    func testF1720AnchorResidueBulgesThenSnapsBack() {
        var runtime = RailMotionRuntime()
        runtime.begin(
            verticalPosition: 0.5,
            originCenter: CGPoint(x: 80, y: 400),
            timestamp: 0.001
        )
        _ = runtime.updateDrag(
            outwardDistance: 260,
            screenProgress: 0.29,
            screenWidth: 1_440,
            verticalTarget: 0.5,
            timestamp: 0.041
        )
        let broken = runtime.breakSurface(
            floatingCenter: CGPoint(x: 440, y: 420),
            verticalPosition: 0.5,
            timestamp: 0.051
        )

        var residues: [CGFloat] = [broken.residue]
        for index in 1...72 {
            residues.append(runtime.tickFloating(timestamp: 0.051 + Double(index) / 120.0).residue)
        }
        XCTAssertGreaterThan(residues.max() ?? 0, 0.9)
        XCTAssertLessThan(residues.min() ?? 0, -0.02)
    }

    func testDragContentTravelCompensatesForExpandedCanvasCenterMotion() {
        let offset = RailMetrics.compensatedDragContentOffset(
            semanticOffset: 0,
            dragDirection: 1,
            contentTravel: 300,
            canvasExtraWidth: 350,
            railWidth: 500,
            renderedContentWidth: 80,
            borderPadding: 4
        )
        XCTAssertEqual(offset, 125, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(abs(offset), 205)
    }

    func testFloatingDropTrailsPointerThenConverges() {
        var runtime = RailMotionRuntime()
        runtime.begin(
            verticalPosition: 0.4,
            originCenter: CGPoint(x: 70, y: 320),
            timestamp: 0.001
        )
        _ = runtime.breakSurface(
            floatingCenter: CGPoint(x: 300, y: 360),
            verticalPosition: 0.4,
            timestamp: 0.011
        )
        let first = runtime.updateFloating(
            floatingCenter: CGPoint(x: 700, y: 500),
            verticalPosition: 0.65,
            timestamp: 0.031
        )
        XCTAssertGreaterThan(first.floatingCenterX, 300)
        XCTAssertLessThan(first.floatingCenterX, 700)
        XCTAssertGreaterThan(first.floatingCenterY, 360)
        XCTAssertLessThan(first.floatingCenterY, 500)

        var frame = first
        for index in 1...120 {
            frame = runtime.updateFloating(
                floatingCenter: CGPoint(x: 700, y: 500),
                verticalPosition: 0.65,
                timestamp: 0.031 + Double(index) / 120.0
            )
        }
        XCTAssertEqual(frame.floatingCenterX, 700, accuracy: 2.0)
        XCTAssertEqual(frame.floatingCenterY, 500, accuracy: 2.0)
    }

    func testFloatingReleaseReturnsToOriginSideTarget() {
        var runtime = RailMotionRuntime()
        runtime.begin(
            verticalPosition: 0.45,
            originCenter: CGPoint(x: 70, y: 340),
            timestamp: 0.001
        )
        _ = runtime.breakSurface(
            floatingCenter: CGPoint(x: 520, y: 420),
            verticalPosition: 0.58,
            timestamp: 0.021
        )
        _ = runtime.updateFloating(
            floatingCenter: CGPoint(x: 620, y: 460),
            verticalPosition: 0.58,
            timestamp: 0.041
        )
        _ = runtime.beginReturn(
            to: CGPoint(x: 70, y: 390),
            verticalPosition: 0.58,
            timestamp: 0.051
        )

        var frame = runtime.frame
        for index in 1...220 {
            frame = runtime.stepReturn(timestamp: 0.051 + Double(index) / 120.0)
        }

        XCTAssertTrue(runtime.isFloatingSettled)
        XCTAssertEqual(frame.floatingCenterX, 70, accuracy: 1.5)
        XCTAssertEqual(frame.floatingCenterY, 390, accuracy: 1.5)
        XCTAssertEqual(frame.verticalPosition, 0.58, accuracy: 0.01)
    }

    func testDockWettingSpreadsGraduallyThenSettlesAtFullRail() {
        var runtime = RailMotionRuntime()
        runtime.begin(
            verticalPosition: 0.52,
            originCenter: CGPoint(x: 80, y: 410),
            timestamp: 0.001
        )
        _ = runtime.breakSurface(
            floatingCenter: CGPoint(x: 640, y: 430),
            verticalPosition: 0.52,
            timestamp: 0.021
        )
        _ = runtime.beginDock(
            to: CGPoint(x: 1_360, y: 430),
            verticalPosition: 0.52,
            incomingVelocity: 1_500,
            timestamp: 0.041
        )

        // Match the production dock loop's bounded attraction phase. Wetting begins after
        // arrival even if the high-energy contact spring has a tiny residual oscillation.
        for index in 1...150 {
            _ = runtime.stepDock(timestamp: 0.041 + Double(index) / 120.0)
        }

        let first = runtime.beginWetting(
            verticalPosition: 0.52,
            incomingVelocity: 1_200,
            timestamp: 1.30
        )
        XCTAssertGreaterThan(first.wetting, 0)
        XCTAssertLessThan(first.wetting, 0.30)

        var middle = first
        for index in 1...36 {
            middle = runtime.stepWetting(timestamp: 1.30 + Double(index) / 120.0)
        }
        XCTAssertGreaterThan(middle.wetting, first.wetting)
        XCTAssertLessThan(middle.wetting, 1.08)

        var final = middle
        for index in 37...220 {
            final = runtime.stepWetting(timestamp: 1.30 + Double(index) / 120.0)
        }
        XCTAssertTrue(runtime.isWettingSettled)
        XCTAssertEqual(final.wetting, 1, accuracy: 0.01)
    }
}

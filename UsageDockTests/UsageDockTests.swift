import XCTest
@testable import UsageDock

final class UsageDockDistributionPolicyTests: XCTestCase {
    func testPublicLoginSourceAllowlistRejectsNonLoginSources() {
        XCTAssertTrue(UsageDockDistributionPolicy.isPublicLoginSource(.currentSession))
        XCTAssertTrue(UsageDockDistributionPolicy.isPublicLoginSource(.profile))
        XCTAssertFalse(UsageDockDistributionPolicy.isPublicLoginSource(.credentialFile))
        XCTAssertFalse(UsageDockDistributionPolicy.isPublicLoginSource(.manual))
        XCTAssertFalse(UsageDockDistributionPolicy.isPublicLoginSource(.synthetic))
        XCTAssertFalse(UsageDockDistributionPolicy.isPublicLoginSource(.mock))
        XCTAssertFalse(UsageDockDistributionPolicy.isPublicLoginSource(nil))
    }

    @MainActor
    func testReleaseBuildRejectsDevelopmentAccountRegistration() {
        #if DEBUG
        XCTAssertTrue(UsageDockDistributionPolicy.allowsDevelopmentAccounts)
        #else
        let suiteName = "UsageDockTests.PublicLoginOnly.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        XCTAssertTrue(UsageDockDistributionPolicy.isPublicRelease)
        XCTAssertTrue(store.accounts.isEmpty)

        store.addSyntheticAccount(provider: .codex, multiplier: 20)
        store.addAccount(provider: .claude)
        XCTAssertTrue(store.accounts.isEmpty)
        #endif
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
final class PersistenceTests: XCTestCase {
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

    func testF17IconEdgeSafeInsetAllowsNearEdgePlacement() {
        XCTAssertEqual(RailMetrics.minimumSafeIconEdgeInset(showRing: true, iconSize: 24), 2, accuracy: 0.0001)
        XCTAssertEqual(RailMetrics.minimumSafeIconEdgeInset(showRing: false, iconSize: 24), 1, accuracy: 0.0001)
        XCTAssertLessThanOrEqual(RailMetrics.minimumSafeIconEdgeInset(showRing: true, iconSize: 44), 4)
        XCTAssertEqual(
            RailMetrics.effectiveIconEdgeInset(requested: 0, showRing: true, iconSize: 24),
            2,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            RailMetrics.effectiveIconEdgeInset(requested: 12, showRing: true, iconSize: 24),
            12,
            accuracy: 0.0001
        )
    }

    func testSyntheticAccountsSupportAllProvidersAndRegeneration() {
        let suiteName = "UsageDockTests.SyntheticF14.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        store.addSyntheticAccount(provider: .antigravity)
        store.addSyntheticAccount(provider: .kimi)

        let gemini = try! XCTUnwrap(store.accounts.last(where: { $0.provider == .antigravity && $0.source == .synthetic }))
        let kimi = try! XCTUnwrap(store.accounts.last(where: { $0.provider == .kimi && $0.source == .synthetic }))
        XCTAssertEqual(gemini.syntheticMode, .random)
        XCTAssertEqual(kimi.syntheticMode, .random)
        XCTAssertFalse(gemini.buckets.isEmpty)
        XCTAssertFalse(kimi.buckets.isEmpty)
        XCTAssertTrue((gemini.buckets + kimi.buckets).allSatisfy { ($0.resolvedPercentUsed ?? -1) >= 0 && ($0.resolvedPercentUsed ?? 2) <= 1 })

        store.regenerateSyntheticAccount(id: gemini.id)
        let regenerated = try! XCTUnwrap(store.accounts.first(where: { $0.id == gemini.id }))
        XCTAssertEqual(regenerated.syntheticMode, .random)
        XCTAssertFalse(regenerated.buckets.isEmpty)
    }

    func testAccountSpecificAccentPersistsForSameProvider() {
        let suiteName = "UsageDockTests.AccountAccent.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        store.addSyntheticAccount(provider: .codex, multiplier: 20)
        let ids = store.accounts.filter { $0.provider == .codex }.map(\.id)
        XCTAssertGreaterThanOrEqual(ids.count, 2)
        store.setAccountAccent("#FF0000", accountID: ids[0])
        store.setAccountAccent("#00FF00", accountID: ids[1])

        let restored = UsageStore(defaults: defaults)
        XCTAssertEqual(restored.accounts.first(where: { $0.id == ids[0] })?.accentHex, "#FF0000")
        XCTAssertEqual(restored.accounts.first(where: { $0.id == ids[1] })?.accentHex, "#00FF00")
    }

    func testAccountAddRemovePersistsWithSyntheticDefaults() {
        let suiteName = "UsageDockTests.Accounts.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        XCTAssertEqual(store.accounts.count, 2)
        XCTAssertEqual(Set(store.accounts.map(\.provider)), Set([.claude, .codex]))
        XCTAssertTrue(store.accounts.allSatisfy { $0.source == .synthetic && $0.planMultiplier == 20 })
        XCTAssertFalse(store.accounts.contains { $0.source == .currentSession })

        let claude = try! XCTUnwrap(store.accounts.first(where: { $0.provider == .claude }))
        XCTAssertEqual(claude.buckets.count, 3)
        XCTAssertTrue(claude.buckets.allSatisfy { ($0.resolvedPercentUsed ?? -1) >= 0 && ($0.resolvedPercentUsed ?? 2) <= 1 })

        let codex = try! XCTUnwrap(store.accounts.first(where: { $0.provider == .codex }))
        XCTAssertEqual(codex.buckets.count, 3)
        XCTAssertFalse(codex.buckets.contains { $0.quotaID == "codex-general-18000" })
        XCTAssertTrue(codex.buckets.contains { $0.quotaID == "codex-spark-18000" })
        XCTAssertTrue(codex.buckets.allSatisfy { ($0.resolvedPercentUsed ?? -1) >= 0 && ($0.resolvedPercentUsed ?? 2) <= 1 })
        XCTAssertTrue(codex.buckets.contains { ($0.resolvedPercentUsed ?? 1) < 1 })

        store.addAccount(provider: .codex)
        let added = store.accounts.last!
        XCTAssertEqual(added.source, .manual)
        XCTAssertEqual(added.planMultiplier, 1)
        XCTAssertTrue(added.buckets.isEmpty)
        XCTAssertTrue(UsageStore(defaults: defaults).accounts.contains { $0.id == added.id })

        let credentialPath = "/tmp/usagedock-profile/auth.json"
        store.connectCredentialFile(accountID: added.id, path: credentialPath)
        let connected = UsageStore(defaults: defaults).accounts.first { $0.id == added.id }
        XCTAssertEqual(connected?.source, .credentialFile)
        XCTAssertEqual(connected?.credentialPath, credentialPath)
        XCTAssertTrue(connected?.buckets.isEmpty == true)

        store.disconnectCredentialFile(accountID: added.id)
        let disconnected = UsageStore(defaults: defaults).accounts.first { $0.id == added.id }
        XCTAssertEqual(disconnected?.source, .manual)
        XCTAssertNil(disconnected?.credentialPath)

        store.removeAccount(id: added.id)
        XCTAssertFalse(UsageStore(defaults: defaults).accounts.contains { $0.id == added.id })
    }

    func testMultiplierNormalAndFusionModes() {
        let suiteName = "UsageDockTests.Multiplier.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        XCTAssertEqual(store.displayMultiplier(for: .codex), 20)

        store.addSyntheticAccount(provider: .codex, multiplier: 20)
        XCTAssertEqual(store.displayMultiplier(for: .codex), 20)

        store.setFusionEnabled(true, for: .codex)
        XCTAssertEqual(store.displayMultiplier(for: .codex), 40)
        XCTAssertTrue(UsageStore(defaults: defaults).fusionEnabled(for: .codex))
    }

    func testMigrationPreservesPersistedAccountsWithoutInjectingDefaults() throws {
        let suiteName = "UsageDockTests.Migration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let persisted = [
            UsageAccount(provider: .codex, name: "Current Session", source: .currentSession, buckets: []),
            UsageAccount(provider: .kimi, name: "My Kimi", source: .manual, buckets: [])
        ]
        defaults.set(try JSONEncoder().encode(persisted), forKey: "UsageDock.accounts.v3")

        let store = UsageStore(defaults: defaults)
        XCTAssertEqual(store.accounts, persisted)
        XCTAssertEqual(store.accounts.count, 2)
        XCTAssertFalse(store.accounts.contains { $0.source == .synthetic })
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

    func testF17NewRailSettingsPersistWithoutChangingAccountPayload() throws {
        let suiteName = "UsageDockTests.F17Settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        let originalAccounts = store.accounts
        store.railScreenEdgeShape = 0.6
        store.railInnerShape = -0.25
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
        XCTAssertEqual(restored.railInnerShape, -0.25, accuracy: 0.0001)
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
        store.addSyntheticAccount(provider: .kimi)
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
        let providers = Set(store.railTargets().map(\.provider))
        XCTAssertEqual(providers, Set([.claude, .codex]))
        XCTAssertFalse(providers.contains(.antigravity))
        XCTAssertFalse(providers.contains(.cursor))
        XCTAssertFalse(providers.contains(.grok))
    }

    func testF15CodexSyntheticPlansMatchWindowShapes() {
        let x1 = SyntheticUsageFactory.account(provider: .codex, multiplier: 1)
        let x5 = SyntheticUsageFactory.account(provider: .codex, multiplier: 5)
        let x20 = SyntheticUsageFactory.account(provider: .codex, multiplier: 20)

        XCTAssertTrue(x1.buckets.contains { $0.quotaID == "codex-general-18000" })
        for account in [x5, x20] {
            XCTAssertFalse(account.buckets.contains { $0.quotaID == "codex-general-18000" })
            XCTAssertTrue(account.buckets.contains { $0.quotaID == "codex-general-604800" })
            XCTAssertTrue(account.buckets.contains { $0.quotaID == "codex-spark-604800" })
            XCTAssertTrue(account.buckets.contains { $0.quotaID == "codex-spark-18000" })
        }
    }

    func testF15RemainingFullAndAppearancePersist() {
        let suiteName = "UsageDockTests.F15Appearance.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UsageStore(defaults: defaults)
        let codex = try! XCTUnwrap(store.accounts.first(where: { $0.provider == .codex }))
        store.setSyntheticRemainingFull(id: codex.id)
        XCTAssertTrue(store.accounts.first(where: { $0.id == codex.id })!.buckets.allSatisfy { $0.resolvedPercentUsed == 0 })

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

    private func jsonData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
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

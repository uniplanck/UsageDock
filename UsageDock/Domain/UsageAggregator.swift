import Foundation

enum UsageAggregator {
    static func aggregates(
        for provider: ProviderID,
        accounts: [UsageAccount],
        now: Date = Date()
    ) -> [UsageAggregate] {
        let activeBuckets = accounts
            .filter { $0.provider == provider && $0.isEnabled }
            .flatMap { account in
                account.buckets
                    .filter(\.isEnabled)
                    .map { (accountID: account.id, bucket: $0.forDisplay(at: now)) }
            }

        let grouped = Dictionary(grouping: activeBuckets, by: { $0.bucket.quotaID })
        var seen = Set<String>()
        let quotaOrder = activeBuckets.compactMap { member -> String? in
            let id = member.bucket.quotaID
            return seen.insert(id).inserted ? id : nil
        }

        return quotaOrder.compactMap { id in
            grouped[id].flatMap(makeAggregate)
        }
    }

    static func summary(
        for provider: ProviderID,
        accounts: [UsageAccount],
        now: Date = Date()
    ) -> ProviderUsageSummary {
        let rows = aggregates(for: provider, accounts: accounts, now: now)
        let pressure = rows.compactMap(\.percentUsed).max()
        return ProviderUsageSummary(provider: provider, aggregates: rows, pressurePercent: pressure)
    }

    static func summaries(accounts: [UsageAccount], now: Date = Date()) -> [ProviderUsageSummary] {
        ProviderID.allCases.map { summary(for: $0, accounts: accounts, now: now) }
    }

    private static func makeAggregate(
        _ members: [(accountID: UUID, bucket: UsageBucket)]
    ) -> UsageAggregate? {
        guard let first = members.first else { return nil }

        let buckets = members.map(\.bucket)
        let exactCandidates = buckets.compactMap { bucket -> (used: Double, limit: Double, unit: String)? in
            guard
                let used = bucket.used,
                let limit = bucket.limit,
                limit > 0,
                let unit = bucket.unit,
                !unit.isEmpty
            else {
                return nil
            }
            return (used, limit, unit)
        }

        let percent: Double?
        let quality: AggregationQuality

        if exactCandidates.count == buckets.count,
           Set(exactCandidates.map(\.unit)).count == 1 {
            let totalUsed = exactCandidates.reduce(0) { $0 + $1.used }
            let totalLimit = exactCandidates.reduce(0) { $0 + $1.limit }
            percent = totalLimit > 0 ? clamp(totalUsed / totalLimit) : nil
            quality = percent == nil ? .unavailable : .exact
        } else {
            let percentages = buckets.compactMap(\.resolvedPercentUsed)
            if percentages.count == buckets.count, !percentages.isEmpty {
                percent = clamp(percentages.reduce(0, +) / Double(percentages.count))
                quality = .unweightedAverage
            } else {
                percent = nil
                quality = .unavailable
            }
        }

        let reset = buckets.compactMap(\.resetsAt).min()

        return UsageAggregate(
            quotaID: first.bucket.quotaID,
            label: first.bucket.label,
            kind: first.bucket.kind,
            model: first.bucket.model,
            percentUsed: percent,
            quality: quality,
            accountCount: Set(members.map(\.accountID)).count,
            resetsAt: reset
        )
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

struct AntigravityGroupUsage {
    static let slots = 1...5
    static let capacity = slots.count
    static let cacheLifetime: TimeInterval = 30 * 60

    enum Cell {
        case observed(Double)
        case missing(String)

        var percentUsed: Double? {
            if case .observed(let value) = self { return value }
            return nil
        }

        func text(mode: UsagePresentationMode) -> String {
            switch self {
            case .observed(let value):
                let fraction = mode == .used ? value : 1 - value
                return "\(Int((fraction * 100).rounded()))%"
            case .missing(let state): return state
            }
        }
    }

    struct Row: Identifiable {
        let slot: Int
        let accountName: String?
        let cells: [Cell]

        var id: Int { slot }
    }

    let rows: [Row]

    var summary: ProviderUsageSummary {
        let aggregates = AntigravityQuotaDisplay.windows.enumerated().map { index, window in
            let values = rows.compactMap { $0.cells[index].percentUsed }
            return UsageAggregate(
                quotaID: window.id,
                label: window.label,
                kind: window.kind,
                model: window.family,
                percentUsed: values.isEmpty ? nil : values.reduce(0, +) / Double(Self.capacity),
                quality: values.isEmpty ? .unavailable : .exact,
                accountCount: values.count,
                resetsAt: nil
            )
        }
        return ProviderUsageSummary(
            provider: .antigravity, aggregates: aggregates, pressurePercent: aggregates.compactMap(\.percentUsed).max()
        )
    }

    static func fraction(_ aggregate: UsageAggregate, mode: UsagePresentationMode) -> Double? {
        guard let used = aggregate.percentUsed else { return nil }
        if mode == .used { return used }
        return max(0, Double(aggregate.accountCount) / Double(capacity) - used)
    }

    static func percentText(_ fraction: Double?) -> String {
        fraction.map { "\(Int(($0 * Double(capacity) * 100).rounded()))%" } ?? "—"
    }

    static func totalText(_ aggregate: UsageAggregate, mode: UsagePresentationMode) -> String {
        guard let fraction = fraction(aggregate, mode: mode) else { return "—" }
        let total = Int((fraction * Double(capacity) * 100).rounded())
        let value = "\(total) / \(capacity * 100)%"
        guard aggregate.accountCount < capacity else { return value }
        return "観測分 \(value) · \(aggregate.accountCount)/\(capacity)件"
    }
}

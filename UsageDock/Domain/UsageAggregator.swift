import Foundation

enum UsageAggregator {
    static func aggregates(
        for provider: ProviderID,
        accounts: [UsageAccount]
    ) -> [UsageAggregate] {
        let activeBuckets = accounts
            .filter { $0.provider == provider && $0.isEnabled }
            .flatMap { account in
                account.buckets
                    .filter(\.isEnabled)
                    .map { (accountID: account.id, bucket: $0) }
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
        accounts: [UsageAccount]
    ) -> ProviderUsageSummary {
        let rows = aggregates(for: provider, accounts: accounts)
        let pressure = rows.compactMap(\.percentUsed).max()
        return ProviderUsageSummary(provider: provider, aggregates: rows, pressurePercent: pressure)
    }

    static func summaries(accounts: [UsageAccount]) -> [ProviderUsageSummary] {
        ProviderID.allCases.map { summary(for: $0, accounts: accounts) }
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

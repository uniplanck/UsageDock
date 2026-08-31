import Foundation

enum SyntheticUsageFactory {
    static func account(provider: ProviderID, multiplier: Int = 20, name: String? = nil) -> UsageAccount {
        let clampedMultiplier = min(max(multiplier, 1), 999)
        let supportsMultiplier = provider == .claude || provider == .codex
        return UsageAccount(
            provider: provider,
            name: name ?? (supportsMultiplier ? "Synthetic ×\(clampedMultiplier)" : "Synthetic"),
            source: .synthetic,
            planMultiplier: supportsMultiplier ? clampedMultiplier : nil,
            multiplierMode: supportsMultiplier ? .manual : nil,
            syntheticMode: .random,
            buckets: buckets(for: provider, multiplier: clampedMultiplier)
        )
    }

    static func buckets(for provider: ProviderID, multiplier: Int = 1, now: Date = Date()) -> [UsageBucket] {
        switch provider {
        case .claude:
            return coherentClaudeBuckets(now: now)
        case .codex:
            return coherentCodexBuckets(multiplier: multiplier, now: now)
        case .antigravity:
            let fiveHour = Double.random(in: 0.10...0.70)
            let weekly = min(max(fiveHour * Double.random(in: 0.48...0.86) + Double.random(in: 0.02...0.12), 0.05), 0.78)
            return [
                UsageBucket(quotaID: "antigravity-five-hour", label: "5h", kind: .fiveHour, percentUsed: fiveHour, resetsAt: now.addingTimeInterval(Double.random(in: 30 * 60...5 * 60 * 60))),
                UsageBucket(quotaID: "antigravity-weekly", label: "1w", kind: .weekly, percentUsed: weekly, resetsAt: now.addingTimeInterval(Double.random(in: 2 * 24 * 60 * 60...7 * 24 * 60 * 60)))
            ]
        case .kimi:
            let fiveHour = Double.random(in: 0.14...0.74)
            let weekly = min(max(fiveHour * Double.random(in: 0.48...0.82) + Double.random(in: 0.02...0.13), 0.07), 0.72)
            return [
                UsageBucket(quotaID: "kimi-five-hour", label: "5h", kind: .fiveHour, percentUsed: fiveHour, resetsAt: now.addingTimeInterval(Double.random(in: 40 * 60...5 * 60 * 60))),
                UsageBucket(quotaID: "kimi-weekly", label: "1w", kind: .weekly, percentUsed: weekly, resetsAt: now.addingTimeInterval(Double.random(in: 2 * 24 * 60 * 60...7 * 24 * 60 * 60)))
            ]
        case .cursor:
            let fast = Double.random(in: 0.08...0.66)
            let weekly = min(max(fast * Double.random(in: 0.5...0.9) + Double.random(in: 0.01...0.12), 0.04), 0.74)
            return [
                UsageBucket(quotaID: "cursor-fast", label: "Fast", kind: .custom, percentUsed: fast, resetsAt: now.addingTimeInterval(Double.random(in: 2 * 60 * 60...24 * 60 * 60))),
                UsageBucket(quotaID: "cursor-weekly", label: "1w", kind: .weekly, percentUsed: weekly, resetsAt: now.addingTimeInterval(Double.random(in: 2 * 24 * 60 * 60...7 * 24 * 60 * 60)))
            ]
        case .grok:
            let session = Double.random(in: 0.09...0.68)
            let weekly = min(max(session * Double.random(in: 0.46...0.88) + Double.random(in: 0.02...0.11), 0.04), 0.75)
            return [
                UsageBucket(quotaID: "grok-session", label: "Session", kind: .custom, percentUsed: session, resetsAt: now.addingTimeInterval(Double.random(in: 1 * 60 * 60...24 * 60 * 60))),
                UsageBucket(quotaID: "grok-weekly", label: "1w", kind: .weekly, percentUsed: weekly, resetsAt: now.addingTimeInterval(Double.random(in: 2 * 24 * 60 * 60...7 * 24 * 60 * 60)))
            ]
        }
    }

    static func setRemainingFull(_ buckets: [UsageBucket]) -> [UsageBucket] {
        buckets.map { bucket in
            var updated = bucket
            updated.used = nil
            updated.limit = nil
            updated.percentUsed = 0
            return updated
        }
    }

    private static func coherentCodexBuckets(multiplier: Int, now: Date) -> [UsageBucket] {
        let weekly = Double.random(in: 0.08...0.72)
        if multiplier <= 1 {
            let fiveHour = min(max(weekly * Double.random(in: 0.72...1.45) + Double.random(in: 0.01...0.12), 0.08), 0.80)
            return [
                UsageBucket(
                    quotaID: "codex-general-18000",
                    label: "5h",
                    kind: .fiveHour,
                    percentUsed: fiveHour,
                    resetsAt: now.addingTimeInterval(Double.random(in: 35 * 60...5 * 60 * 60))
                ),
                UsageBucket(
                    quotaID: "codex-general-604800",
                    label: "1w",
                    kind: .weekly,
                    percentUsed: weekly,
                    resetsAt: now.addingTimeInterval(Double.random(in: 2 * 24 * 60 * 60...7 * 24 * 60 * 60))
                )
            ]
        }

        let sparkWeekly = min(max(weekly * Double.random(in: 0.72...1.18) + Double.random(in: -0.04...0.10), 0.06), 0.82)
        let sparkFiveHour = min(max(sparkWeekly * Double.random(in: 0.78...1.30) + Double.random(in: 0.01...0.12), 0.08), 0.86)
        return [
            UsageBucket(
                quotaID: "codex-general-604800",
                label: "1w",
                kind: .weekly,
                percentUsed: weekly,
                resetsAt: now.addingTimeInterval(Double.random(in: 2 * 24 * 60 * 60...7 * 24 * 60 * 60))
            ),
            UsageBucket(
                quotaID: "codex-spark-604800",
                label: "Spark 1w",
                kind: .modelSpecific,
                model: "Spark",
                percentUsed: sparkWeekly,
                resetsAt: now.addingTimeInterval(Double.random(in: 2 * 24 * 60 * 60...7 * 24 * 60 * 60))
            ),
            UsageBucket(
                quotaID: "codex-spark-18000",
                label: "Spark 5h",
                kind: .modelSpecific,
                model: "Spark",
                percentUsed: sparkFiveHour,
                resetsAt: now.addingTimeInterval(Double.random(in: 35 * 60...5 * 60 * 60))
            )
        ]
    }

    private static func coherentClaudeBuckets(now: Date) -> [UsageBucket] {
        let session = Double.random(in: 0.24...0.72)
        let weeklyBase = session * Double.random(in: 0.52...0.86)
        let weekly = min(max(weeklyBase + Double.random(in: 0.02...0.14), 0.08), 0.72)
        let fable = min(max(weekly + Double.random(in: -0.10...0.14), 0.06), 0.80)

        return [
            UsageBucket(
                quotaID: "claude-five-hour",
                label: "5h",
                kind: .fiveHour,
                percentUsed: session,
                resetsAt: now.addingTimeInterval(Double.random(in: 45 * 60...5 * 60 * 60))
            ),
            UsageBucket(
                quotaID: "claude-seven-day",
                label: "1w",
                kind: .weekly,
                percentUsed: weekly,
                resetsAt: now.addingTimeInterval(Double.random(in: 2 * 24 * 60 * 60...7 * 24 * 60 * 60))
            ),
            UsageBucket(
                quotaID: "claude-seven-day-fable",
                label: "Fable",
                kind: .modelSpecific,
                model: "Fable",
                percentUsed: fable,
                resetsAt: now.addingTimeInterval(Double.random(in: 2 * 24 * 60 * 60...7 * 24 * 60 * 60))
            )
        ]
    }
}

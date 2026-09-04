import Foundation

enum ProviderID: String, CaseIterable, Codable, Identifiable {
    case claude
    case codex
    case antigravity = "gemini"
    case kimi
    case cursor
    case grok

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .antigravity: "Antigravity"
        case .kimi: "Kimi"
        case .cursor: "Cursor"
        case .grok: "Grok"
        }
    }

    var shortLabel: String {
        switch self {
        case .claude: "C"
        case .codex: "O"
        case .antigravity: "A"
        case .kimi: "K"
        case .cursor: "Cu"
        case .grok: "G"
        }
    }

    var supportsProfileLogin: Bool {
        switch self {
        case .claude, .codex, .antigravity, .kimi: true
        case .cursor, .grok: false
        }
    }

    var supportsLiveUsage: Bool {
        switch self {
        case .claude, .codex, .antigravity, .kimi: true
        case .cursor, .grok: false
        }
    }

    var defaultWebURL: String {
        switch self {
        case .claude: "https://claude.ai/new"
        case .codex: "https://chatgpt.com/"
        case .antigravity: "https://antigravity.google/"
        case .kimi: "https://www.kimi.ai/"
        case .cursor: "https://cursor.com/"
        case .grok: "https://grok.com/"
        }
    }
}

enum UsageWindowKind: String, Codable, CaseIterable {
    case fiveHour
    case weekly
    case modelSpecific
    case credits
    case custom
}

struct UsageBucket: Identifiable, Codable, Hashable {
    var id: UUID
    var quotaID: String
    var label: String
    var kind: UsageWindowKind
    var model: String?
    var used: Double?
    var limit: Double?
    var unit: String?
    var percentUsed: Double?
    var resetsAt: Date?
    var isEnabled: Bool

    init(
        id: UUID = UUID(),
        quotaID: String,
        label: String,
        kind: UsageWindowKind,
        model: String? = nil,
        used: Double? = nil,
        limit: Double? = nil,
        unit: String? = nil,
        percentUsed: Double? = nil,
        resetsAt: Date? = nil,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.quotaID = quotaID
        self.label = label
        self.kind = kind
        self.model = model
        self.used = used
        self.limit = limit
        self.unit = unit
        self.percentUsed = percentUsed
        self.resetsAt = resetsAt
        self.isEnabled = isEnabled
    }

    var resolvedPercentUsed: Double? {
        if let used, let limit, limit > 0 {
            return Self.clamp(used / limit)
        }
        if let percentUsed {
            return Self.clamp(percentUsed)
        }
        return nil
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

enum UsageAccountSource: String, Codable, Hashable {
    case currentSession
    case profile
    case legacyUnsupported

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Self(rawValue: rawValue) ?? .legacyUnsupported
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum UsageDockDistributionPolicy {
    static func isPublicLoginSource(_ source: UsageAccountSource?) -> Bool {
        source == .currentSession || source == .profile
    }

    static func isAccountVisible(_ account: UsageAccount) -> Bool {
        isPublicLoginSource(account.source)
    }
}

enum MultiplierMode: String, Codable, Hashable {
    case manual
    case automatic
}

enum UsagePresentationMode: String, Codable, CaseIterable, Identifiable {
    case used
    case remaining

    var id: String { rawValue }
    var label: String { self == .used ? "Used" : "Remaining" }
}

enum UsageDockTheme: String, Codable, CaseIterable, Identifiable {
    case dark
    case light
    case monochrome
    case pop
    case transparentFloating

    var id: String { rawValue }

    var label: String {
        switch self {
        case .dark: "Dark"
        case .light: "Light"
        case .monochrome: "Monochrome"
        case .pop: "Pop"
        case .transparentFloating: "Transparent"
        }
    }
}

enum ResetTimeDisplayMode: String, Codable, CaseIterable, Identifiable {
    case relative
    case absolute
    case both

    var id: String { rawValue }

    var label: String {
        switch self {
        case .relative: "Remaining"
        case .absolute: "Date & time"
        case .both: "Both"
        }
    }
}

enum RailEdgeProfile: String, Codable, CaseIterable, Identifiable {
    case inset
    case straight
    case flare

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inset: "Inset"
        case .straight: "Straight"
        case .flare: "Spread at edge"
        }
    }

    var continuousValue: Double {
        switch self {
        case .inset: -1
        case .straight: 0
        case .flare: 1
        }
    }
}

enum RailQuotaSource: String, Codable, CaseIterable, Identifiable {
    case none
    case automatic
    case fiveHour
    case weekly

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "None"
        case .automatic: "Auto"
        case .fiveHour: "5h"
        case .weekly: "1w"
        }
    }
}

enum RailDigitWidth: Int, Codable, CaseIterable, Identifiable {
    case one = 1
    case two = 2

    var id: Int { rawValue }
    var label: String { rawValue == 1 ? "0" : "00" }
}

enum RailMaterialMode: String, Codable, CaseIterable, Identifiable {
    case standard
    case waterdrop
    case space
    case bar3D

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard: "Standard"
        case .waterdrop: "Waterdrop"
        case .space: "Space"
        case .bar3D: "3D Bar"
        }
    }
}

enum RailEdgeStyle: String, Codable, CaseIterable, Identifiable {
    case off
    case simple
    case soft
    case neon
    case glass

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum RailEdgeColorMode: String, Codable, CaseIterable, Identifiable {
    case automatic
    case accountAccent
    case providerAccent
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: "Auto"
        case .accountAccent: "Account accent"
        case .providerAccent: "Provider accent"
        case .custom: "Custom"
        }
    }
}

enum RailDisplayTarget: Hashable, Identifiable {
    case provider(ProviderID)
    case account(id: UUID, provider: ProviderID)

    var id: String {
        switch self {
        case .provider(let provider): "provider:\(provider.rawValue)"
        case .account(let id, _): "account:\(id.uuidString)"
        }
    }

    var provider: ProviderID {
        switch self {
        case .provider(let provider), .account(_, let provider): provider
        }
    }
}

struct UsageAccount: Identifiable, Codable, Hashable {
    var id: UUID
    var provider: ProviderID
    var name: String
    var isEnabled: Bool
    var source: UsageAccountSource?
    var credentialPath: String?
    var planMultiplier: Int?
    var multiplierMode: MultiplierMode?
    var accentHex: String?
    var profileHomePath: String?
    var webURL: String?
    var railPercentSource: RailQuotaSource?
    var railOuterRingSource: RailQuotaSource?
    var railInnerRingSource: RailQuotaSource?
    var railTimeSource: RailQuotaSource?
    var buckets: [UsageBucket]

    init(
        id: UUID = UUID(),
        provider: ProviderID,
        name: String,
        isEnabled: Bool = true,
        source: UsageAccountSource? = nil,
        credentialPath: String? = nil,
        planMultiplier: Int? = nil,
        multiplierMode: MultiplierMode? = nil,
        accentHex: String? = nil,
        profileHomePath: String? = nil,
        webURL: String? = nil,
        railPercentSource: RailQuotaSource? = nil,
        railOuterRingSource: RailQuotaSource? = nil,
        railInnerRingSource: RailQuotaSource? = nil,
        railTimeSource: RailQuotaSource? = nil,
        buckets: [UsageBucket]
    ) {
        self.id = id
        self.provider = provider
        self.name = name
        self.isEnabled = isEnabled
        self.source = source
        self.credentialPath = credentialPath
        self.planMultiplier = planMultiplier
        self.multiplierMode = multiplierMode
        self.accentHex = accentHex
        self.profileHomePath = profileHomePath
        self.webURL = webURL
        self.railPercentSource = railPercentSource
        self.railOuterRingSource = railOuterRingSource
        self.railInnerRingSource = railInnerRingSource
        self.railTimeSource = railTimeSource
        self.buckets = buckets
    }

    var normalizedPlanMultiplier: Int? {
        guard let planMultiplier, planMultiplier > 0 else { return nil }
        return min(planMultiplier, 999)
    }
}

enum AggregationQuality: String, Codable, Equatable {
    case exact
    case unweightedAverage
    case unavailable
}

struct UsageAggregate: Identifiable, Equatable {
    var id: String { quotaID }
    let quotaID: String
    let label: String
    let kind: UsageWindowKind
    let model: String?
    let percentUsed: Double?
    let quality: AggregationQuality
    let accountCount: Int
    let resetsAt: Date?
}

struct ProviderUsageSummary: Identifiable, Equatable {
    var id: ProviderID { provider }
    let provider: ProviderID
    let aggregates: [UsageAggregate]
    let pressurePercent: Double?
}

protocol UsageProviderAdapter {
    var provider: ProviderID { get }
    func fetchAccounts() async throws -> [UsageAccount]
}

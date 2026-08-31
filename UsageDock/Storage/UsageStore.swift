import AppKit
import Combine
import Foundation

@MainActor
final class UsageStore: ObservableObject {
    private static let accountsKey = "UsageDock.accounts.v3"
    private static let fusionProvidersKey = "UsageDock.fusionProviders.v1"
    private static let presentationModeKey = "UsageDock.presentationMode.v1"
    private static let railScaleKey = "UsageDock.railScale.v1"
    private static let providerOrderKey = "UsageDock.providerOrder.v1"
    private static let providerAccentKey = "UsageDock.providerAccent.v1"
    private static let railSpacingKey = "UsageDock.railSpacing.v1"
    private static let railVerticalPositionKey = "UsageDock.railVerticalPosition.v1"
    private static let railShowPercentKey = "UsageDock.railShowPercent.v1"
    private static let railShowRingKey = "UsageDock.railShowRing.v1"
    private static let railShowMultiplierKey = "UsageDock.railShowMultiplier.v1"
    private static let railHoverEnabledKey = "UsageDock.railHoverEnabled.v1"
    private static let themeKey = "UsageDock.theme.v1"
    private static let languageKey = "UsageDock.language.v1"
    private static let resetTimeModeKey = "UsageDock.resetTimeMode.v1"
    private static let railBackgroundOpacityKey = "UsageDock.railBackgroundOpacity.v1"
    private static let railBackplateEnabledKey = "UsageDock.railBackplateEnabled.v1"
    private static let railAutoContrastKey = "UsageDock.railAutoContrast.v1"
    private static let railCornerRadiusKey = "UsageDock.railCornerRadius.v1"
    private static let railScallopDepthKey = "UsageDock.railScallopDepth.v1"
    private static let railScallopRadiusKey = "UsageDock.railScallopRadius.v1"
    private static let railScallopSmoothingKey = "UsageDock.railScallopSmoothing.v1"
    private static let bubbleCornerRadiusKey = "UsageDock.bubbleCornerRadius.v1"
    private static let bubblePointerDepthKey = "UsageDock.bubblePointerDepth.v1"
    private static let bubblePointerWidthKey = "UsageDock.bubblePointerWidth.v1"
    private static let providerWebURLKey = "UsageDock.providerWebURLs.v1"
    private static let railEdgeProfileKey = "UsageDock.railEdgeProfile.v1"
    private static let railInnerEdgeProfileKey = "UsageDock.railInnerEdgeProfile.v1"
    private static let railIconEdgeInsetKey = "UsageDock.railIconEdgeInset.v1"
    private static let railPercentSourceKey = "UsageDock.railPercentSource.v1"
    private static let railOuterRingSourceKey = "UsageDock.railOuterRingSource.v1"
    private static let railInnerRingSourceKey = "UsageDock.railInnerRingSource.v1"
    private static let railShowRemainingTimeKey = "UsageDock.railShowRemainingTime.v1"
    private static let railTimeSourceKey = "UsageDock.railTimeSource.v1"
    private static let railDayDigitsKey = "UsageDock.railDayDigits.v1"
    private static let railHourDigitsKey = "UsageDock.railHourDigits.v1"
    private static let railMinuteDigitsKey = "UsageDock.railMinuteDigits.v1"
    private static let railShowHoursKey = "UsageDock.railShowHours.v1"
    private static let railShowMinutesKey = "UsageDock.railShowMinutes.v1"
    private static let railAutoHideZeroDaysKey = "UsageDock.railAutoHideZeroDays.v1"
    private static let railAutoHideZeroHoursKey = "UsageDock.railAutoHideZeroHours.v1"
    private static let railVisualOnlyModeKey = "UsageDock.railVisualOnlyMode.v1"
    private static let railAccountLabelFontSizeKey = "UsageDock.railAccountLabelFontSize.v1"
    private static let railRemainingTimeFontSizeKey = "UsageDock.railRemainingTimeFontSize.v1"
    private static let railScreenEdgeShapeKey = "UsageDock.railScreenEdgeShape.v1"
    private static let railInnerShapeKey = "UsageDock.railInnerShape.v1"
    private static let railEdgeStyleKey = "UsageDock.railEdgeStyle.v1"
    private static let railEdgeWidthKey = "UsageDock.railEdgeWidth.v1"
    private static let railEdgeOpacityKey = "UsageDock.railEdgeOpacity.v1"
    private static let railGlowRadiusKey = "UsageDock.railGlowRadius.v1"
    private static let railGlowOpacityKey = "UsageDock.railGlowOpacity.v1"
    private static let railBorderColorModeKey = "UsageDock.railBorderColorMode.v1"
    private static let railBorderCustomHexKey = "UsageDock.railBorderCustomHex.v1"
    private static let railIconSizeKey = "UsageDock.railIconSize.v1"
    private static let railPercentFontSizeKey = "UsageDock.railPercentFontSize.v1"
    private static let railTitleWidthKey = "UsageDock.railTitleWidth.v1"
    private static let railTimeWidthKey = "UsageDock.railTimeWidth.v1"
    private static let railShowTitleKey = "UsageDock.railShowTitle.v1"

    @Published var accounts: [UsageAccount] {
        didSet { persistAccounts() }
    }
    @Published private(set) var fusionProviders: Set<ProviderID> {
        didSet { persistFusionProviders() }
    }
    @Published var presentationMode: UsagePresentationMode {
        didSet { defaults.set(presentationMode.rawValue, forKey: Self.presentationModeKey) }
    }
    @Published var railScale: Double {
        didSet {
            let clamped = min(max(railScale, 0.45), 1.45)
            if clamped != railScale { railScale = clamped; return }
            defaults.set(clamped, forKey: Self.railScaleKey)
        }
    }
    @Published private(set) var providerOrder: [ProviderID] {
        didSet { defaults.set(providerOrder.map(\.rawValue), forKey: Self.providerOrderKey) }
    }
    @Published private(set) var providerAccentHex: [ProviderID: String] {
        didSet { defaults.set(Dictionary(uniqueKeysWithValues: providerAccentHex.map { ($0.key.rawValue, $0.value) }), forKey: Self.providerAccentKey) }
    }
    @Published var railItemSpacing: Double {
        didSet {
            let clamped = min(max(railItemSpacing, 0), 36)
            if clamped != railItemSpacing { railItemSpacing = clamped; return }
            defaults.set(clamped, forKey: Self.railSpacingKey)
        }
    }
    @Published var railVerticalPosition: Double {
        didSet {
            let clamped = min(max(railVerticalPosition, 0), 1)
            if clamped != railVerticalPosition { railVerticalPosition = clamped; return }
            defaults.set(clamped, forKey: Self.railVerticalPositionKey)
        }
    }
    @Published var railShowPercent: Bool { didSet { defaults.set(railShowPercent, forKey: Self.railShowPercentKey) } }
    @Published var railShowRing: Bool { didSet { defaults.set(railShowRing, forKey: Self.railShowRingKey) } }
    @Published var railShowMultiplier: Bool { didSet { defaults.set(railShowMultiplier, forKey: Self.railShowMultiplierKey) } }
    @Published var railHoverEnabled: Bool { didSet { defaults.set(railHoverEnabled, forKey: Self.railHoverEnabledKey) } }
    @Published var theme: UsageDockTheme { didSet { defaults.set(theme.rawValue, forKey: Self.themeKey) } }
    @Published var appLanguage: UsageDockLanguage { didSet { defaults.set(appLanguage.rawValue, forKey: Self.languageKey) } }
    @Published var resetTimeDisplayMode: ResetTimeDisplayMode { didSet { defaults.set(resetTimeDisplayMode.rawValue, forKey: Self.resetTimeModeKey) } }
    @Published var railBackgroundOpacity: Double {
        didSet {
            let clamped = min(max(railBackgroundOpacity, 0), 1)
            if clamped != railBackgroundOpacity { railBackgroundOpacity = clamped; return }
            defaults.set(clamped, forKey: Self.railBackgroundOpacityKey)
        }
    }
    @Published var railBackplateEnabled: Bool { didSet { defaults.set(railBackplateEnabled, forKey: Self.railBackplateEnabledKey) } }
    @Published var railAutoContrast: Bool { didSet { defaults.set(railAutoContrast, forKey: Self.railAutoContrastKey) } }
    @Published var railCornerRadius: Double {
        didSet {
            let clamped = min(max(railCornerRadius, 4), 48)
            if clamped != railCornerRadius { railCornerRadius = clamped; return }
            defaults.set(clamped, forKey: Self.railCornerRadiusKey)
        }
    }
    @Published var railScallopDepth: Double {
        didSet {
            let clamped = min(max(railScallopDepth, 0), 42)
            if clamped != railScallopDepth { railScallopDepth = clamped; return }
            defaults.set(clamped, forKey: Self.railScallopDepthKey)
        }
    }
    @Published var railScallopRadius: Double {
        didSet {
            let clamped = min(max(railScallopRadius, 4), 64)
            if clamped != railScallopRadius { railScallopRadius = clamped; return }
            defaults.set(clamped, forKey: Self.railScallopRadiusKey)
        }
    }
    @Published var railScallopSmoothing: Double {
        didSet {
            let clamped = min(max(railScallopSmoothing, 0), 1)
            if clamped != railScallopSmoothing { railScallopSmoothing = clamped; return }
            defaults.set(clamped, forKey: Self.railScallopSmoothingKey)
        }
    }
    @Published var bubbleCornerRadius: Double {
        didSet {
            let clamped = min(max(bubbleCornerRadius, 8), 40)
            if clamped != bubbleCornerRadius { bubbleCornerRadius = clamped; return }
            defaults.set(clamped, forKey: Self.bubbleCornerRadiusKey)
        }
    }
    @Published var bubblePointerDepth: Double {
        didSet {
            let clamped = min(max(bubblePointerDepth, 0), 32)
            if clamped != bubblePointerDepth { bubblePointerDepth = clamped; return }
            defaults.set(clamped, forKey: Self.bubblePointerDepthKey)
        }
    }
    @Published var bubblePointerWidth: Double {
        didSet {
            let clamped = min(max(bubblePointerWidth, 6), 56)
            if clamped != bubblePointerWidth { bubblePointerWidth = clamped; return }
            defaults.set(clamped, forKey: Self.bubblePointerWidthKey)
        }
    }
    // The screen-attached side and the inward/free side are intentionally independent.
    // Keep railEdgeProfile as the screen-edge setting to preserve the existing preference key.
    @Published var railEdgeProfile: RailEdgeProfile { didSet { defaults.set(railEdgeProfile.rawValue, forKey: Self.railEdgeProfileKey) } }
    @Published var railInnerEdgeProfile: RailEdgeProfile { didSet { defaults.set(railInnerEdgeProfile.rawValue, forKey: Self.railInnerEdgeProfileKey) } }
    @Published var railIconEdgeInset: Double {
        didSet {
            let clamped = min(max(railIconEdgeInset, 0), 48)
            if clamped != railIconEdgeInset { railIconEdgeInset = clamped; return }
            defaults.set(clamped, forKey: Self.railIconEdgeInsetKey)
        }
    }
    @Published var railPercentSource: RailQuotaSource { didSet { defaults.set(railPercentSource.rawValue, forKey: Self.railPercentSourceKey) } }
    @Published var railOuterRingSource: RailQuotaSource { didSet { defaults.set(railOuterRingSource.rawValue, forKey: Self.railOuterRingSourceKey) } }
    @Published var railInnerRingSource: RailQuotaSource { didSet { defaults.set(railInnerRingSource.rawValue, forKey: Self.railInnerRingSourceKey) } }
    @Published var railShowRemainingTime: Bool { didSet { defaults.set(railShowRemainingTime, forKey: Self.railShowRemainingTimeKey) } }
    @Published var railTimeSource: RailQuotaSource { didSet { defaults.set(railTimeSource.rawValue, forKey: Self.railTimeSourceKey) } }
    @Published var railDayDigits: RailDigitWidth { didSet { defaults.set(railDayDigits.rawValue, forKey: Self.railDayDigitsKey) } }
    @Published var railHourDigits: RailDigitWidth { didSet { defaults.set(railHourDigits.rawValue, forKey: Self.railHourDigitsKey) } }
    @Published var railMinuteDigits: RailDigitWidth { didSet { defaults.set(railMinuteDigits.rawValue, forKey: Self.railMinuteDigitsKey) } }
    @Published var railShowHours: Bool { didSet { defaults.set(railShowHours, forKey: Self.railShowHoursKey) } }
    @Published var railShowMinutes: Bool { didSet { defaults.set(railShowMinutes, forKey: Self.railShowMinutesKey) } }
    @Published var railAutoHideZeroDays: Bool { didSet { defaults.set(railAutoHideZeroDays, forKey: Self.railAutoHideZeroDaysKey) } }
    @Published var railAutoHideZeroHours: Bool { didSet { defaults.set(railAutoHideZeroHours, forKey: Self.railAutoHideZeroHoursKey) } }
    @Published var railVisualOnlyMode: Bool { didSet { defaults.set(railVisualOnlyMode, forKey: Self.railVisualOnlyModeKey) } }
    @Published var railAccountLabelFontSize: Double {
        didSet {
            let clamped = min(max(railAccountLabelFontSize, 7), 20)
            if clamped != railAccountLabelFontSize { railAccountLabelFontSize = clamped; return }
            defaults.set(clamped, forKey: Self.railAccountLabelFontSizeKey)
        }
    }
    @Published var railRemainingTimeFontSize: Double {
        didSet {
            let clamped = min(max(railRemainingTimeFontSize, 6), 20)
            if clamped != railRemainingTimeFontSize { railRemainingTimeFontSize = clamped; return }
            defaults.set(clamped, forKey: Self.railRemainingTimeFontSizeKey)
        }
    }
    @Published var railScreenEdgeShape: Double {
        didSet {
            let clamped = min(max(railScreenEdgeShape, -1), 1)
            if clamped != railScreenEdgeShape { railScreenEdgeShape = clamped; return }
            defaults.set(clamped, forKey: Self.railScreenEdgeShapeKey)
        }
    }
    @Published var railInnerShape: Double {
        didSet {
            let clamped = min(max(railInnerShape, -1), 1)
            if clamped != railInnerShape { railInnerShape = clamped; return }
            defaults.set(clamped, forKey: Self.railInnerShapeKey)
        }
    }
    @Published var railEdgeStyle: RailEdgeStyle {
        didSet { defaults.set(railEdgeStyle.rawValue, forKey: Self.railEdgeStyleKey) }
    }
    @Published var railEdgeWidth: Double {
        didSet {
            let clamped = min(max(railEdgeWidth, 0.25), 4)
            if clamped != railEdgeWidth { railEdgeWidth = clamped; return }
            defaults.set(clamped, forKey: Self.railEdgeWidthKey)
        }
    }
    @Published var railEdgeOpacity: Double {
        didSet {
            let clamped = min(max(railEdgeOpacity, 0), 1)
            if clamped != railEdgeOpacity { railEdgeOpacity = clamped; return }
            defaults.set(clamped, forKey: Self.railEdgeOpacityKey)
        }
    }
    @Published var railGlowRadius: Double {
        didSet {
            let clamped = min(max(railGlowRadius, 0), 32)
            if clamped != railGlowRadius { railGlowRadius = clamped; return }
            defaults.set(clamped, forKey: Self.railGlowRadiusKey)
        }
    }
    @Published var railGlowOpacity: Double {
        didSet {
            let clamped = min(max(railGlowOpacity, 0), 1)
            if clamped != railGlowOpacity { railGlowOpacity = clamped; return }
            defaults.set(clamped, forKey: Self.railGlowOpacityKey)
        }
    }
    @Published var railBorderColorMode: RailEdgeColorMode {
        didSet { defaults.set(railBorderColorMode.rawValue, forKey: Self.railBorderColorModeKey) }
    }
    @Published var railBorderCustomHex: String? {
        didSet {
            if let railBorderCustomHex, !railBorderCustomHex.isEmpty {
                defaults.set(railBorderCustomHex, forKey: Self.railBorderCustomHexKey)
            } else {
                defaults.removeObject(forKey: Self.railBorderCustomHexKey)
            }
        }
    }
    @Published var railIconSize: Double {
        didSet {
            let clamped = min(max(railIconSize, 14), 44)
            if clamped != railIconSize { railIconSize = clamped; return }
            defaults.set(clamped, forKey: Self.railIconSizeKey)
        }
    }
    @Published var railPercentFontSize: Double {
        didSet {
            let clamped = min(max(railPercentFontSize, 7), 22)
            if clamped != railPercentFontSize { railPercentFontSize = clamped; return }
            defaults.set(clamped, forKey: Self.railPercentFontSizeKey)
        }
    }
    @Published var railTitleWidth: Double {
        didSet {
            let clamped = min(max(railTitleWidth, 36), 160)
            if clamped != railTitleWidth { railTitleWidth = clamped; return }
            defaults.set(clamped, forKey: Self.railTitleWidthKey)
        }
    }
    @Published var railTimeWidth: Double {
        didSet {
            let clamped = min(max(railTimeWidth, 36), 160)
            if clamped != railTimeWidth { railTimeWidth = clamped; return }
            defaults.set(clamped, forKey: Self.railTimeWidthKey)
        }
    }
    @Published var railShowTitle: Bool {
        didSet { defaults.set(railShowTitle, forKey: Self.railShowTitleKey) }
    }
    @Published private(set) var providerWebURLs: [ProviderID: String] {
        didSet { persistProviderWebURLs() }
    }
    @Published private(set) var refreshStates: [ProviderID: ProviderRefreshState] = [:]
    @Published private(set) var accountRefreshStates: [UUID: AccountRefreshState] = [:]
    @Published private(set) var multiplierDetectionStates: [UUID: MultiplierDetectionState] = [:]
    @Published private(set) var isRefreshing = false

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var autoRefreshTask: Task<Void, Never>?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        fusionProviders = Set(
            (defaults.stringArray(forKey: Self.fusionProvidersKey) ?? [])
                .compactMap(ProviderID.init(rawValue:))
        )
        presentationMode = UsagePresentationMode(
            rawValue: defaults.string(forKey: Self.presentationModeKey) ?? "used"
        ) ?? .used
        railScale = defaults.object(forKey: Self.railScaleKey) == nil
            ? 1.0
            : min(max(defaults.double(forKey: Self.railScaleKey), 0.45), 1.45)
        railItemSpacing = defaults.object(forKey: Self.railSpacingKey) == nil ? 0 : min(max(defaults.double(forKey: Self.railSpacingKey), 0), 36)
        railVerticalPosition = defaults.object(forKey: Self.railVerticalPositionKey) == nil ? 0 : min(max(defaults.double(forKey: Self.railVerticalPositionKey), 0), 1)
        railShowPercent = defaults.object(forKey: Self.railShowPercentKey) == nil ? true : defaults.bool(forKey: Self.railShowPercentKey)
        railShowRing = defaults.object(forKey: Self.railShowRingKey) == nil ? true : defaults.bool(forKey: Self.railShowRingKey)
        railShowMultiplier = defaults.object(forKey: Self.railShowMultiplierKey) == nil ? true : defaults.bool(forKey: Self.railShowMultiplierKey)
        railHoverEnabled = defaults.object(forKey: Self.railHoverEnabledKey) == nil ? true : defaults.bool(forKey: Self.railHoverEnabledKey)
        theme = UsageDockTheme(rawValue: defaults.string(forKey: Self.themeKey) ?? "dark") ?? .dark
        appLanguage = UsageDockLanguage(rawValue: defaults.string(forKey: Self.languageKey) ?? "system") ?? .system
        resetTimeDisplayMode = ResetTimeDisplayMode(rawValue: defaults.string(forKey: Self.resetTimeModeKey) ?? "both") ?? .both
        railBackgroundOpacity = defaults.object(forKey: Self.railBackgroundOpacityKey) == nil ? 0.95 : min(max(defaults.double(forKey: Self.railBackgroundOpacityKey), 0), 1)
        railBackplateEnabled = defaults.object(forKey: Self.railBackplateEnabledKey) == nil ? true : defaults.bool(forKey: Self.railBackplateEnabledKey)
        railAutoContrast = defaults.object(forKey: Self.railAutoContrastKey) == nil ? true : defaults.bool(forKey: Self.railAutoContrastKey)
        railCornerRadius = defaults.object(forKey: Self.railCornerRadiusKey) == nil ? 24 : min(max(defaults.double(forKey: Self.railCornerRadiusKey), 4), 48)
        railScallopDepth = defaults.object(forKey: Self.railScallopDepthKey) == nil ? 18 : min(max(defaults.double(forKey: Self.railScallopDepthKey), 0), 42)
        railScallopRadius = defaults.object(forKey: Self.railScallopRadiusKey) == nil ? 28 : min(max(defaults.double(forKey: Self.railScallopRadiusKey), 4), 64)
        railScallopSmoothing = defaults.object(forKey: Self.railScallopSmoothingKey) == nil ? 0.72 : min(max(defaults.double(forKey: Self.railScallopSmoothingKey), 0), 1)
        bubbleCornerRadius = defaults.object(forKey: Self.bubbleCornerRadiusKey) == nil ? 22 : min(max(defaults.double(forKey: Self.bubbleCornerRadiusKey), 8), 40)
        bubblePointerDepth = defaults.object(forKey: Self.bubblePointerDepthKey) == nil ? 14 : min(max(defaults.double(forKey: Self.bubblePointerDepthKey), 0), 32)
        bubblePointerWidth = defaults.object(forKey: Self.bubblePointerWidthKey) == nil ? 22 : min(max(defaults.double(forKey: Self.bubblePointerWidthKey), 6), 56)
        let savedEdgeProfile = RailEdgeProfile(rawValue: defaults.string(forKey: Self.railEdgeProfileKey) ?? "inset") ?? .inset
        let savedInnerEdgeProfile = RailEdgeProfile(rawValue: defaults.string(forKey: Self.railInnerEdgeProfileKey) ?? "straight") ?? .straight
        railEdgeProfile = savedEdgeProfile
        railInnerEdgeProfile = savedInnerEdgeProfile
        railScreenEdgeShape = defaults.object(forKey: Self.railScreenEdgeShapeKey) == nil
            ? savedEdgeProfile.continuousValue
            : min(max(defaults.double(forKey: Self.railScreenEdgeShapeKey), -1), 1)
        railInnerShape = defaults.object(forKey: Self.railInnerShapeKey) == nil
            ? savedInnerEdgeProfile.continuousValue
            : min(max(defaults.double(forKey: Self.railInnerShapeKey), -1), 1)
        railEdgeStyle = RailEdgeStyle(rawValue: defaults.string(forKey: Self.railEdgeStyleKey) ?? "simple") ?? .simple
        railEdgeWidth = defaults.object(forKey: Self.railEdgeWidthKey) == nil ? 0.8 : min(max(defaults.double(forKey: Self.railEdgeWidthKey), 0.25), 4)
        railEdgeOpacity = defaults.object(forKey: Self.railEdgeOpacityKey) == nil ? 0.62 : min(max(defaults.double(forKey: Self.railEdgeOpacityKey), 0), 1)
        railGlowRadius = defaults.object(forKey: Self.railGlowRadiusKey) == nil ? 10 : min(max(defaults.double(forKey: Self.railGlowRadiusKey), 0), 32)
        railGlowOpacity = defaults.object(forKey: Self.railGlowOpacityKey) == nil ? 0.20 : min(max(defaults.double(forKey: Self.railGlowOpacityKey), 0), 1)
        railBorderColorMode = RailEdgeColorMode(rawValue: defaults.string(forKey: Self.railBorderColorModeKey) ?? "automatic") ?? .automatic
        railBorderCustomHex = defaults.string(forKey: Self.railBorderCustomHexKey)
        railIconEdgeInset = defaults.object(forKey: Self.railIconEdgeInsetKey) == nil ? 0 : min(max(defaults.double(forKey: Self.railIconEdgeInsetKey), 0), 48)
        railPercentSource = RailQuotaSource(rawValue: defaults.string(forKey: Self.railPercentSourceKey) ?? "automatic") ?? .automatic
        railOuterRingSource = RailQuotaSource(rawValue: defaults.string(forKey: Self.railOuterRingSourceKey) ?? "automatic") ?? .automatic
        railInnerRingSource = RailQuotaSource(rawValue: defaults.string(forKey: Self.railInnerRingSourceKey) ?? "none") ?? .none
        railShowRemainingTime = defaults.object(forKey: Self.railShowRemainingTimeKey) == nil ? false : defaults.bool(forKey: Self.railShowRemainingTimeKey)
        railTimeSource = RailQuotaSource(rawValue: defaults.string(forKey: Self.railTimeSourceKey) ?? "weekly") ?? .weekly
        railDayDigits = RailDigitWidth(rawValue: defaults.integer(forKey: Self.railDayDigitsKey)) ?? .one
        railHourDigits = RailDigitWidth(rawValue: defaults.integer(forKey: Self.railHourDigitsKey)) ?? .one
        railMinuteDigits = RailDigitWidth(rawValue: defaults.integer(forKey: Self.railMinuteDigitsKey)) ?? .two
        railShowHours = defaults.object(forKey: Self.railShowHoursKey) == nil ? true : defaults.bool(forKey: Self.railShowHoursKey)
        railShowMinutes = defaults.object(forKey: Self.railShowMinutesKey) == nil ? true : defaults.bool(forKey: Self.railShowMinutesKey)
        railAutoHideZeroDays = defaults.object(forKey: Self.railAutoHideZeroDaysKey) == nil ? true : defaults.bool(forKey: Self.railAutoHideZeroDaysKey)
        railAutoHideZeroHours = defaults.object(forKey: Self.railAutoHideZeroHoursKey) == nil ? false : defaults.bool(forKey: Self.railAutoHideZeroHoursKey)
        railVisualOnlyMode = defaults.object(forKey: Self.railVisualOnlyModeKey) == nil ? false : defaults.bool(forKey: Self.railVisualOnlyModeKey)
        railAccountLabelFontSize = defaults.object(forKey: Self.railAccountLabelFontSizeKey) == nil
            ? 11.0
            : min(max(defaults.double(forKey: Self.railAccountLabelFontSizeKey), 7), 20)
        railRemainingTimeFontSize = defaults.object(forKey: Self.railRemainingTimeFontSizeKey) == nil
            ? 8.5
            : min(max(defaults.double(forKey: Self.railRemainingTimeFontSizeKey), 6), 20)
        railIconSize = defaults.object(forKey: Self.railIconSizeKey) == nil ? 24 : min(max(defaults.double(forKey: Self.railIconSizeKey), 14), 44)
        railPercentFontSize = defaults.object(forKey: Self.railPercentFontSizeKey) == nil ? 12 : min(max(defaults.double(forKey: Self.railPercentFontSizeKey), 7), 22)
        railTitleWidth = defaults.object(forKey: Self.railTitleWidthKey) == nil ? 66 : min(max(defaults.double(forKey: Self.railTitleWidthKey), 36), 160)
        railTimeWidth = defaults.object(forKey: Self.railTimeWidthKey) == nil ? 72 : min(max(defaults.double(forKey: Self.railTimeWidthKey), 36), 160)
        railShowTitle = defaults.object(forKey: Self.railShowTitleKey) == nil ? true : defaults.bool(forKey: Self.railShowTitleKey)

        let savedOrder = (defaults.stringArray(forKey: Self.providerOrderKey) ?? [])
            .compactMap(ProviderID.init(rawValue:))
        providerOrder = savedOrder + ProviderID.allCases.filter { !savedOrder.contains($0) }

        let savedAccent = defaults.dictionary(forKey: Self.providerAccentKey) as? [String: String] ?? [:]
        providerAccentHex = Dictionary(uniqueKeysWithValues: savedAccent.compactMap { key, value in
            ProviderID(rawValue: key).map { ($0, value) }
        })

        let savedURLs = defaults.dictionary(forKey: Self.providerWebURLKey) as? [String: String] ?? [:]
        providerWebURLs = Dictionary(uniqueKeysWithValues: ProviderID.allCases.map { provider in
            (provider, savedURLs[provider.rawValue] ?? provider.defaultWebURL)
        })

        if let data = defaults.data(forKey: Self.accountsKey),
           let decoded = try? decoder.decode([UsageAccount].self, from: data) {
            accounts = Self.migratedAccounts(decoded)
        } else {
            accounts = UsageDockDistributionPolicy.allowsDevelopmentAccounts
                ? LiveUsageData.accounts()
                : []
        }

        persistAccounts()
    }

    deinit {
        autoRefreshTask?.cancel()
    }

    private var runtimeAccounts: [UsageAccount] {
        accounts.filter(UsageDockDistributionPolicy.isAccountVisible)
    }

    func visibleAccounts(for provider: ProviderID) -> [UsageAccount] {
        runtimeAccounts.filter { $0.provider == provider }
    }

    func isAccountVisibleInCurrentBuild(_ account: UsageAccount) -> Bool {
        UsageDockDistributionPolicy.isAccountVisible(account)
    }

    func summaries() -> [ProviderUsageSummary] {
        UsageAggregator.summaries(accounts: runtimeAccounts)
    }

    func summary(for provider: ProviderID) -> ProviderUsageSummary {
        UsageAggregator.summary(for: provider, accounts: runtimeAccounts)
    }

    func summary(for target: RailDisplayTarget) -> ProviderUsageSummary {
        switch target {
        case .provider(let provider):
            return summary(for: provider)
        case .account(let id, let provider):
            let scoped = runtimeAccounts.filter { $0.id == id && $0.isEnabled }
            return UsageAggregator.summary(for: provider, accounts: scoped)
        }
    }

    func railTargets() -> [RailDisplayTarget] {
        providerOrder.flatMap { provider -> [RailDisplayTarget] in
            let enabled = runtimeAccounts.filter { $0.provider == provider && $0.isEnabled }
            guard !enabled.isEmpty else { return [] }
            if fusionEnabled(for: provider) {
                return [.provider(provider)]
            }
            return enabled.map { .account(id: $0.id, provider: provider) }
        }
    }

    func account(for target: RailDisplayTarget) -> UsageAccount? {
        guard case .account(let id, _) = target else { return nil }
        return runtimeAccounts.first { $0.id == id }
    }

    func displayPercent(_ percentUsed: Double?) -> Double? {
        guard let percentUsed else { return nil }
        let clamped = min(max(percentUsed, 0), 1)
        return presentationMode == .used ? clamped : 1 - clamped
    }

    func displayPercent(for target: RailDisplayTarget) -> Double? {
        displayPercent(summary(for: target).pressurePercent)
    }

    func railAggregate(for target: RailDisplayTarget, source: RailQuotaSource) -> UsageAggregate? {
        let aggregates = summary(for: target).aggregates
        switch source {
        case .none, .automatic:
            return nil
        case .fiveHour:
            return aggregates.first(where: { $0.kind == .fiveHour })
                ?? aggregates.first(where: { $0.label.lowercased().contains("5h") })
        case .weekly:
            return aggregates.first(where: { $0.kind == .weekly })
                ?? aggregates.first(where: {
                    let label = $0.label.lowercased()
                    return label == "1w" || label.contains("weekly") || label.contains("7d")
                })
        }
    }

    func railPercentSource(for target: RailDisplayTarget) -> RailQuotaSource {
        account(for: target)?.railPercentSource ?? railPercentSource
    }

    func railOuterRingSource(for target: RailDisplayTarget) -> RailQuotaSource {
        account(for: target)?.railOuterRingSource ?? railOuterRingSource
    }

    func railInnerRingSource(for target: RailDisplayTarget) -> RailQuotaSource {
        account(for: target)?.railInnerRingSource ?? railInnerRingSource
    }

    func railTimeSource(for target: RailDisplayTarget) -> RailQuotaSource {
        account(for: target)?.railTimeSource ?? railTimeSource
    }

    func railDisplayPercent(for target: RailDisplayTarget, source: RailQuotaSource) -> Double? {
        if source == .none { return nil }
        if source == .automatic { return displayPercent(summary(for: target).pressurePercent) }
        return displayPercent(railAggregate(for: target, source: source)?.percentUsed)
    }

    func railResetDate(for target: RailDisplayTarget, source: RailQuotaSource) -> Date? {
        if source == .none { return nil }
        if source == .automatic {
            return summary(for: target).aggregates
                .filter { $0.resetsAt != nil }
                .max(by: { ($0.percentUsed ?? -1) < ($1.percentUsed ?? -1) })?
                .resetsAt
        }
        return railAggregate(for: target, source: source)?.resetsAt
    }

    func railRemainingTimeText(until resetDate: Date?, now: Date = Date()) -> String? {
        guard let resetDate else { return nil }
        let totalMinutes = max(Int(resetDate.timeIntervalSince(now) / 60), 0)
        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60
        var parts: [String] = []

        if !(railAutoHideZeroDays && days == 0) {
            parts.append("\(formatTimerValue(days, width: railDayDigits))d")
        }
        if railShowHours && !(railAutoHideZeroHours && hours == 0) {
            parts.append("\(formatTimerValue(hours, width: railHourDigits))h")
        }
        if railShowMinutes || (days == 0 && hours == 0) {
            parts.append("\(formatTimerValue(minutes, width: railMinuteDigits))m")
        }
        if parts.isEmpty {
            parts.append("\(formatTimerValue(minutes, width: railMinuteDigits))m")
        }
        return parts.joined(separator: " ")
    }

    private func formatTimerValue(_ value: Int, width: RailDigitWidth) -> String {
        width == .two ? String(format: "%02d", value) : "\(value)"
    }

    func displayName(for target: RailDisplayTarget) -> String {
        account(for: target)?.name ?? target.provider.displayName
    }

    func accentHex(for target: RailDisplayTarget) -> String? {
        account(for: target)?.accentHex ?? providerAccentHex[target.provider]
    }

    func setProviderAccent(_ hex: String?, for provider: ProviderID) {
        if let hex, !hex.isEmpty { providerAccentHex[provider] = hex }
        else { providerAccentHex[provider] = nil }
    }

    func setAccountAccent(_ hex: String?, accountID: UUID) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].accentHex = hex
    }

    func providerWebURL(for provider: ProviderID) -> String {
        providerWebURLs[provider] ?? provider.defaultWebURL
    }

    func setProviderWebURL(_ value: String, for provider: ProviderID) {
        providerWebURLs[provider] = value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func webURL(for target: RailDisplayTarget) -> URL? {
        let raw = account(for: target)?.webURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = providerWebURL(for: target.provider)
        let value = (raw?.isEmpty == false ? raw! : fallback)
        guard let url = URL(string: value), let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        return url
    }

    @discardableResult
    func openWeb(for target: RailDisplayTarget) -> Bool {
        guard let url = webURL(for: target) else { return false }
        return NSWorkspace.shared.open(url)
    }

    func moveProvider(_ provider: ProviderID, direction: Int) {
        guard direction != 0, let index = providerOrder.firstIndex(of: provider) else { return }
        let destination = index + (direction < 0 ? -1 : 1)
        guard providerOrder.indices.contains(destination) else { return }
        providerOrder.swapAt(index, destination)
    }

    func moveAccount(_ id: UUID, direction: Int) {
        guard direction != 0, let current = accounts.firstIndex(where: { $0.id == id }) else { return }
        let provider = accounts[current].provider
        let positions = accounts.indices.filter { accounts[$0].provider == provider }
        guard let local = positions.firstIndex(of: current) else { return }
        let destinationLocal = local + (direction < 0 ? -1 : 1)
        guard positions.indices.contains(destinationLocal) else { return }
        accounts.swapAt(current, positions[destinationLocal])
    }

    func moveBucket(accountID: UUID, bucketID: UUID, direction: Int) {
        guard direction != 0, let accountIndex = accounts.firstIndex(where: { $0.id == accountID }),
              let current = accounts[accountIndex].buckets.firstIndex(where: { $0.id == bucketID }) else { return }
        let destination = current + (direction < 0 ? -1 : 1)
        guard accounts[accountIndex].buckets.indices.contains(destination) else { return }
        accounts[accountIndex].buckets.swapAt(current, destination)
    }

    func displayMultiplier(for target: RailDisplayTarget) -> Int? {
        switch target {
        case .provider(let provider): return displayMultiplier(for: provider)
        case .account: return account(for: target)?.normalizedPlanMultiplier
        }
    }

    func addAccount(provider: ProviderID) {
        guard UsageDockDistributionPolicy.allowsDevelopmentAccounts else {
            refreshStates[provider] = .failed("Public builds accept account registration only through a verified provider login.")
            return
        }
        let nextNumber = accounts.filter { $0.provider == provider }.count + 1
        accounts.append(
            UsageAccount(
                provider: provider,
                name: "Account \(nextNumber)",
                source: .manual,
                planMultiplier: provider == .claude || provider == .codex ? 1 : nil,
                multiplierMode: provider == .claude || provider == .codex ? .manual : nil,
                buckets: []
            )
        )
    }

    func addSyntheticAccount(provider: ProviderID, multiplier: Int = 20) {
        guard UsageDockDistributionPolicy.allowsDevelopmentAccounts else {
            refreshStates[provider] = .failed("Synthetic accounts are disabled in public builds.")
            return
        }
        let existingCount = accounts.filter { $0.provider == provider && $0.source == .synthetic }.count
        let suffix = existingCount == 0 ? "" : " \(existingCount + 1)"
        let supportsMultiplier = provider == .claude || provider == .codex
        accounts.append(
            SyntheticUsageFactory.account(
                provider: provider,
                multiplier: multiplier,
                name: supportsMultiplier
                    ? "Synthetic\(suffix) ×\(min(max(multiplier, 1), 999))"
                    : "Synthetic\(suffix)"
            )
        )
    }

    func regenerateSyntheticAccount(id: UUID) {
        guard UsageDockDistributionPolicy.allowsDevelopmentAccounts else { return }
        guard let index = accounts.firstIndex(where: { $0.id == id && $0.source == .synthetic }) else { return }
        accounts[index].syntheticMode = .random
        accounts[index].buckets = SyntheticUsageFactory.buckets(
            for: accounts[index].provider,
            multiplier: accounts[index].normalizedPlanMultiplier ?? 1
        )
    }

    func setSyntheticRemainingFull(id: UUID) {
        guard UsageDockDistributionPolicy.allowsDevelopmentAccounts else { return }
        guard let index = accounts.firstIndex(where: { $0.id == id && $0.source == .synthetic }) else { return }
        accounts[index].syntheticMode = .manual
        accounts[index].buckets = SyntheticUsageFactory.setRemainingFull(accounts[index].buckets)
    }

    @discardableResult
    func launchLoginProfile(provider: ProviderID) -> Bool {
        guard provider.supportsProfileLogin else {
            refreshStates[provider] = .failed("Direct \(provider.displayName) profile login is not available in UsageDock yet.")
            return false
        }
        let ordinal = accounts.filter { $0.provider == provider && $0.source == .profile }.count + 1
        do {
            let account = try UsageProfileLoginLauncher.launch(provider: provider, ordinal: ordinal)
            if provider == .antigravity,
               let existing = accounts.firstIndex(where: { $0.provider == .antigravity && $0.source == .currentSession }) {
                accounts[existing].isEnabled = true
            } else {
                accounts.append(account)
            }
            refreshStates[provider] = .idle
            if provider == .antigravity { scheduleAntigravityLoginRefresh() }
            return true
        } catch {
            refreshStates[provider] = .failed(error.localizedDescription)
            return false
        }
    }

    private func scheduleAntigravityLoginRefresh() {
        Task { [weak self] in
            // Browser sign-in completes after the Terminal launcher returns. Poll briefly so
            // the newly authenticated native agy session appears without waiting a full
            // auto-refresh interval or requiring a manual Refresh click.
            for attempt in 0..<18 {
                if attempt > 0 { try? await Task.sleep(nanoseconds: 4_000_000_000) }
                guard let self else { return }
                await self.refreshProvider(.antigravity)
                switch self.refreshState(for: .antigravity) {
                case .live, .partial: return
                case .idle, .refreshing, .failed: continue
                }
            }
        }
    }

    func removeAccount(id: UUID) {
        accounts.removeAll { $0.id == id }
        accountRefreshStates[id] = nil
        multiplierDetectionStates[id] = nil
    }

    @discardableResult
    func registerCurrentSessionAccount(provider: ProviderID) -> Bool {
        guard !accounts.contains(where: { $0.provider == provider && $0.source == .currentSession }) else { return true }
        guard hasLocalLogin(for: provider) else {
            refreshStates[provider] = .failed("No local \(provider.displayName) login was found. Sign in with the official client first.")
            return false
        }

        accounts.append(
            UsageAccount(
                provider: provider,
                name: "Local Login",
                source: .currentSession,
                planMultiplier: provider == .claude || provider == .codex ? 1 : nil,
                multiplierMode: provider == .claude || provider == .codex ? .manual : nil,
                buckets: []
            )
        )
        return true
    }

    func canRegisterCurrentSession(provider: ProviderID) -> Bool {
        guard !accounts.contains(where: { $0.provider == provider && $0.source == .currentSession }) else { return false }
        return hasLocalLogin(for: provider)
    }

    private func hasLocalLogin(for provider: ProviderID) -> Bool {
        guard provider.supportsLiveUsage else { return false }
        if provider == .antigravity {
            return AntigravityUsageAdapter.executableURL() != nil
        }
        return ProviderPlanMultiplierDetector.hasCurrentSession(for: provider)
    }

    func connectCredentialFile(accountID: UUID, path: String) {
        guard UsageDockDistributionPolicy.allowsCredentialFileRegistration else { return }
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].source = .credentialFile
        accounts[index].credentialPath = path
        accounts[index].buckets = []
        accountRefreshStates[accountID] = .idle
    }

    func disconnectCredentialFile(accountID: UUID) {
        guard UsageDockDistributionPolicy.allowsCredentialFileRegistration else { return }
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].source = .manual
        accounts[index].credentialPath = nil
        accounts[index].buckets = []
        accountRefreshStates[accountID] = .idle
    }

    func setPlanMultiplier(accountID: UUID, value: Int) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        accounts[index].planMultiplier = min(max(value, 1), 999)
        accounts[index].multiplierMode = .manual
        multiplierDetectionStates[accountID] = .idle
    }

    func detectPlanMultiplier(accountID: UUID) {
        guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { return }
        let account = accounts[index]
        let result = ProviderPlanMultiplierDetector.detect(for: account)
        if let multiplier = result.multiplier {
            accounts[index].planMultiplier = multiplier
            accounts[index].multiplierMode = .automatic
            multiplierDetectionStates[accountID] = .detected(multiplier, result.detail)
        } else {
            multiplierDetectionStates[accountID] = .unavailable(result.detail)
        }
    }

    func multiplierDetectionText(for accountID: UUID) -> String? {
        switch multiplierDetectionStates[accountID] ?? .idle {
        case .idle:
            return nil
        case .detected(_, let detail), .unavailable(let detail):
            return detail
        }
    }

    func setFusionEnabled(_ enabled: Bool, for provider: ProviderID) {
        if enabled {
            fusionProviders.insert(provider)
        } else {
            fusionProviders.remove(provider)
        }
    }

    func fusionEnabled(for provider: ProviderID) -> Bool {
        fusionProviders.contains(provider)
    }

    func displayMultiplier(for provider: ProviderID) -> Int? {
        guard provider == .claude || provider == .codex else { return nil }
        let multipliers = runtimeAccounts
            .filter { $0.provider == provider && $0.isEnabled }
            .compactMap(\.normalizedPlanMultiplier)
        guard !multipliers.isEmpty else { return nil }
        if fusionEnabled(for: provider) {
            return min(multipliers.reduce(0, +), 999)
        }
        return multipliers.max()
    }

    func startAutoRefresh(intervalSeconds: UInt64 = 60) {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                await self.refreshLiveUsage()
                do {
                    try await Task.sleep(nanoseconds: intervalSeconds * 1_000_000_000)
                } catch {
                    return
                }
            }
        }
    }

    func stopAutoRefresh() {
        autoRefreshTask?.cancel()
        autoRefreshTask = nil
    }

    func refreshLiveUsage() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        await refreshProvider(.claude)
        await refreshProvider(.codex)
        await refreshProvider(.antigravity)
        await refreshProvider(.kimi)
    }

    func refreshState(for provider: ProviderID) -> ProviderRefreshState {
        refreshStates[provider] ?? .idle
    }

    func accountRefreshState(for accountID: UUID) -> AccountRefreshState {
        accountRefreshStates[accountID] ?? .idle
    }

    func statusText(for provider: ProviderID) -> String {
        switch refreshState(for: provider) {
        case .idle:
            if !provider.supportsLiveUsage {
                return UsageDockDistributionPolicy.isPublicRelease
                    ? "Login integration is not available yet"
                    : "Manual / synthetic tracker · direct provider login is not available yet"
            }
            if UsageDockDistributionPolicy.allowsDevelopmentAccounts,
               accounts.contains(where: { $0.provider == provider && $0.source == .synthetic }) {
                return "Synthetic preview · register a local login for live usage"
            }
            return "Waiting for a registered login"
        case .refreshing:
            return "Refreshing…"
        case .live(let date, let accountCount):
            let accountText = accountCount == 1 ? "1 live account" : "\(accountCount) live accounts"
            return "Live · \(accountText) · \(Self.timeFormatter.string(from: date))"
        case .partial(let date, let success, let total, let message):
            return "Partial \(success)/\(total) · \(Self.timeFormatter.string(from: date)) · \(message)"
        case .failed(let message):
            return message
        }
    }

    func accountStatusText(for account: UsageAccount) -> String {
        if account.source == .synthetic {
            return "Synthetic preview · no provider authentication"
        }
        if account.source == .manual || account.source == nil {
            return "Not connected"
        }
        if account.source == .profile, case .idle = accountRefreshState(for: account.id) {
            return "UsageDock profile · finish login in Terminal, then Refresh"
        }
        if account.source == .mock {
            return "Legacy mock account"
        }

        switch accountRefreshState(for: account.id) {
        case .idle:
            return account.source == .currentSession ? "Registered local provider login" : "Credential file connected"
        case .refreshing:
            return "Refreshing…"
        case .live(let date):
            return "Live · \(Self.timeFormatter.string(from: date))"
        case .failed(let message):
            return message
        }
    }

    private func refreshProvider(_ provider: ProviderID) async {
        let accountIDs = accounts
            .filter {
                $0.provider == provider &&
                $0.isEnabled &&
                UsageDockDistributionPolicy.isAccountVisible($0) &&
                ($0.source == .currentSession || $0.source == .credentialFile || $0.source == .profile)
            }
            .map(\.id)

        guard !accountIDs.isEmpty else {
            refreshStates[provider] = .idle
            return
        }

        refreshStates[provider] = .refreshing
        var successes = 0
        var failureMessages: [String] = []
        var lastSuccessAt: Date?

        for accountID in accountIDs {
            if let autoAccount = accounts.first(where: { $0.id == accountID }),
               autoAccount.multiplierMode == .automatic {
                detectPlanMultiplier(accountID: accountID)
            }

            guard let account = accounts.first(where: { $0.id == accountID }) else { continue }
            accountRefreshStates[accountID] = .refreshing

            do {
                let fetched: UsageAccount
                switch provider {
                case .claude:
                    let fetchedAccounts = try await ClaudeUsageAdapter(
                        credentialPath: account.source == .currentSession ? nil : account.credentialPath
                    ).fetchAccounts()
                    guard let first = fetchedAccounts.first else {
                        throw UsageAdapterError.invalidResponse("Claude returned no account data.")
                    }
                    fetched = first
                case .codex:
                    let fetchedAccounts = try await CodexUsageAdapter(
                        credentialPath: account.source == .currentSession ? nil : account.credentialPath
                    ).fetchAccounts()
                    guard let first = fetchedAccounts.first else {
                        throw UsageAdapterError.invalidResponse("Codex returned no account data.")
                    }
                    fetched = first
                case .antigravity:
                    let fetchedAccounts = try await AntigravityUsageAdapter(
                        profileHomePath: account.source == .currentSession ? nil : account.profileHomePath
                    ).fetchAccounts()
                    guard let first = fetchedAccounts.first else {
                        throw UsageAdapterError.invalidResponse("Antigravity returned no account data.")
                    }
                    fetched = first
                case .kimi:
                    let fetchedAccounts = try await KimiUsageAdapter(
                        credentialPath: account.source == .currentSession ? nil : account.credentialPath
                    ).fetchAccounts()
                    guard let first = fetchedAccounts.first else {
                        throw UsageAdapterError.invalidResponse("Kimi returned no account data.")
                    }
                    fetched = first
                case .cursor, .grok:
                    throw UsageAdapterError.credentialsUnavailable("\(provider.displayName) live quota adapter is not configured. Use a synthetic/manual account for now.")
                }

                guard let index = accounts.firstIndex(where: { $0.id == accountID }) else { continue }
                accounts[index].buckets = Self.mergeRefreshedBuckets(
                    existing: accounts[index].buckets,
                    fetched: fetched.buckets
                )
                let now = Date()
                accountRefreshStates[accountID] = .live(now)
                lastSuccessAt = now
                successes += 1
            } catch {
                if shouldClearBuckets(for: error),
                   let index = accounts.firstIndex(where: { $0.id == accountID }) {
                    accounts[index].buckets = []
                }
                let message = error.localizedDescription
                accountRefreshStates[accountID] = .failed(message)
                failureMessages.append("\(account.name): \(message)")
            }
        }

        if successes == accountIDs.count, let lastSuccessAt {
            refreshStates[provider] = .live(lastSuccessAt, accountCount: successes)
        } else if successes > 0 {
            refreshStates[provider] = .partial(
                lastSuccessAt ?? Date(),
                success: successes,
                total: accountIDs.count,
                message: failureMessages.first ?? "Some accounts failed"
            )
        } else {
            refreshStates[provider] = .failed(failureMessages.first ?? "No registered account returned live usage.")
        }
    }

    private func shouldClearBuckets(for error: Error) -> Bool {
        // F17: keep the last known quota rows on refresh failures so persisted per-quota
        // visibility (for example a disabled Spark 5h row) cannot be erased and later
        // silently re-created as enabled by a successful refresh.
        _ = error
        return false
    }

    static func mergeRefreshedBuckets(existing: [UsageBucket], fetched: [UsageBucket]) -> [UsageBucket] {
        var remaining = fetched
        var merged: [UsageBucket] = []
        merged.reserveCapacity(fetched.count)

        for saved in existing {
            guard let index = remaining.firstIndex(where: { $0.quotaID == saved.quotaID }) else { continue }
            var refreshed = remaining.remove(at: index)
            refreshed.id = saved.id
            refreshed.isEnabled = saved.isEnabled
            merged.append(refreshed)
        }

        merged.append(contentsOf: remaining)
        return merged
    }

    private static func migratedAccounts(_ existing: [UsageAccount]) -> [UsageAccount] {
        // F16 onward: persisted user state is authoritative. New builds must not silently
        // delete accounts, re-add synthetic defaults, or rewrite source types during launch.
        // Schema additions are optional/defaulted so old payloads remain decodable in place.
        existing
    }

    private func persistAccounts() {
        guard let data = try? encoder.encode(accounts) else { return }
        defaults.set(data, forKey: Self.accountsKey)
    }

    private func persistFusionProviders() {
        defaults.set(fusionProviders.map(\.rawValue).sorted(), forKey: Self.fusionProvidersKey)
    }

    private func persistProviderWebURLs() {
        defaults.set(
            Dictionary(uniqueKeysWithValues: providerWebURLs.map { ($0.key.rawValue, $0.value) }),
            forKey: Self.providerWebURLKey
        )
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}

enum ProviderRefreshState: Equatable {
    case idle
    case refreshing
    case live(Date, accountCount: Int)
    case partial(Date, success: Int, total: Int, message: String)
    case failed(String)
}

enum AccountRefreshState: Equatable {
    case idle
    case refreshing
    case live(Date)
    case failed(String)
}

enum MultiplierDetectionState: Equatable {
    case idle
    case detected(Int, String)
    case unavailable(String)
}

enum LiveUsageData {
    static func accounts() -> [UsageAccount] {
        [
            SyntheticUsageFactory.account(provider: .claude, multiplier: 20),
            SyntheticUsageFactory.account(provider: .codex, multiplier: 20)
        ]
    }
}

private enum UsageProfileLoginError: LocalizedError {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let message): return message
        }
    }
}

private enum UsageProfileLoginLauncher {
    static func launch(provider: ProviderID, ordinal: Int) throws -> UsageAccount {
        guard provider.supportsProfileLogin else {
            throw UsageProfileLoginError.launchFailed("Direct \(provider.displayName) profile login is not available in UsageDock yet.")
        }
        let id = UUID()
        guard let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            throw UsageProfileLoginError.launchFailed("Application Support directory is unavailable.")
        }

        let profileHome = applicationSupport
            .appendingPathComponent("UsageDock", isDirectory: true)
            .appendingPathComponent("Profiles", isDirectory: true)
            .appendingPathComponent(provider.rawValue, isDirectory: true)
            .appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: profileHome, withIntermediateDirectories: true)

        let credentialURL = credentialURL(for: provider, profileHome: profileHome)
        if provider == .kimi || provider == .antigravity {
            try FileManager.default.createDirectory(at: credentialURL, withIntermediateDirectories: true)
        } else {
            try FileManager.default.createDirectory(at: credentialURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        }

        let command = terminalCommand(provider: provider, profileHome: profileHome)
        let appleScript = "tell application \"Terminal\" to do script \"\(appleScriptEscaped(command))\""
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", appleScript]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UsageProfileLoginError.launchFailed("Could not open Terminal for \(provider.displayName) profile login.")
        }

        let supportsMultiplier = provider == .claude || provider == .codex
        let isAntigravity = provider == .antigravity
        return UsageAccount(
            id: id,
            provider: provider,
            name: isAntigravity ? "Antigravity Login" : "Profile \(ordinal)",
            source: isAntigravity ? .currentSession : .profile,
            credentialPath: isAntigravity ? nil : credentialURL.path,
            planMultiplier: supportsMultiplier ? 1 : nil,
            multiplierMode: supportsMultiplier ? .manual : nil,
            profileHomePath: isAntigravity ? nil : profileHome.path,
            buckets: []
        )
    }

    private static func credentialURL(for provider: ProviderID, profileHome: URL) -> URL {
        switch provider {
        case .claude:
            return profileHome.appendingPathComponent(".claude/.credentials.json")
        case .codex:
            return profileHome.appendingPathComponent(".codex/auth.json")
        case .antigravity:
            return profileHome.appendingPathComponent(".gemini/antigravity-cli", isDirectory: true)
        case .kimi:
            return profileHome.appendingPathComponent(".kimi-code/credentials", isDirectory: true)
        case .cursor, .grok:
            return profileHome.appendingPathComponent("usage.json")
        }
    }

    private static func terminalCommand(provider: ProviderID, profileHome: URL) -> String {
        let home = shellQuote(profileHome.path)
        let missing: String
        let availabilityCheck: String
        let command: String

        switch provider {
        case .claude:
            missing = "Claude CLI not found. Install Claude Code, then retry."
            availabilityCheck = "command -v claude >/dev/null 2>&1"
            let config = shellQuote(profileHome.appendingPathComponent(".claude").path)
            command = "HOME=\(home) CLAUDE_CONFIG_DIR=\(config) claude auth login"
        case .codex:
            missing = "Codex CLI not found. Install Codex, then retry."
            availabilityCheck = "command -v codex >/dev/null 2>&1"
            let config = shellQuote(profileHome.appendingPathComponent(".codex").path)
            command = "HOME=\(home) CODEX_HOME=\(config) codex login"
        case .antigravity:
            let bundledCandidate = shellQuote(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/agy").path)
            missing = "Antigravity CLI (agy) not found. Install the official Antigravity CLI, then retry."
            availabilityCheck = "command -v agy >/dev/null 2>&1 || test -x \(bundledCandidate)"
            command = "AGY=$(command -v agy 2>/dev/null || true); if [ -z \"$AGY\" ]; then AGY=\(bundledCandidate); fi; \"$AGY\""
        case .kimi:
            missing = "Kimi CLI not found. Install Kimi Code, then retry."
            availabilityCheck = "command -v kimi >/dev/null 2>&1 || command -v kimi-code >/dev/null 2>&1"
            let kimiHome = shellQuote(profileHome.appendingPathComponent(".kimi-code").path)
            command = "if command -v kimi >/dev/null 2>&1; then HOME=\(home) KIMI_CODE_HOME=\(kimiHome) kimi login; else HOME=\(home) KIMI_CODE_HOME=\(kimiHome) kimi-code login; fi"
        case .cursor, .grok:
            missing = "\(provider.displayName) profile login is not exposed by UsageDock."
            availabilityCheck = "false"
            command = "true"
        }

        let boundaryMessage = provider == .antigravity
            ? "Uses the official agy native macOS Keychain session."
            : "This login is isolated from your normal HOME."
        return "\(availabilityCheck) || { printf '%s\\n' \(shellQuote(missing)); exit 127; }; clear; echo 'UsageDock · \(provider.displayName) Login'; echo \(shellQuote(boundaryMessage)); \(command)"
    }

    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

import AppKit
import SwiftUI

enum ProviderBrand {
    static func assetName(for provider: ProviderID) -> String? {
        switch provider {
        case .claude: "Claude"
        case .codex: "OpenAI"
        case .kimi: "Kimi"
        case .antigravity, .cursor, .grok: nil
        }
    }

    static func systemSymbol(for provider: ProviderID) -> String {
        switch provider {
        case .antigravity: "sparkles"
        case .cursor: "cursorarrow"
        case .grok: "bolt.circle"
        case .claude, .codex, .kimi: "circle"
        }
    }

    static func gradient(
        for provider: ProviderID,
        customHex: String? = nil,
        theme: UsageDockTheme = .dark
    ) -> LinearGradient {
        let colors: [Color]
        if theme == .monochrome {
            colors = [Color.white.opacity(0.98), Color.white.opacity(0.48)]
        } else if let customHex, let custom = color(hex: customHex) {
            colors = [custom, custom.opacity(0.62)]
        } else {
            colors = defaultColors(for: provider, pop: theme == .pop)
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    static func glow(
        for provider: ProviderID,
        customHex: String? = nil,
        theme: UsageDockTheme = .dark
    ) -> Color {
        if theme == .monochrome { return .white }
        if let customHex, let custom = color(hex: customHex) { return custom }
        switch provider {
        case .claude: return Color(red: 0.94, green: 0.44, blue: 0.25)
        case .codex: return Color(red: 0.20, green: 0.82, blue: 0.62)
        case .antigravity: return Color(red: 0.59, green: 0.46, blue: 1.0)
        case .kimi: return Color(red: 0.37, green: 0.43, blue: 0.95)
        case .cursor: return Color(red: 0.38, green: 0.86, blue: 0.98)
        case .grok: return Color(red: 0.95, green: 0.35, blue: 0.64)
        }
    }

    static func railFill(theme: UsageDockTheme, opacity: Double) -> Color {
        switch theme {
        case .dark: return Color.black.opacity(opacity)
        case .light: return Color.white.opacity(opacity)
        case .monochrome: return Color.black.opacity(opacity)
        case .pop: return Color(red: 0.12, green: 0.035, blue: 0.20).opacity(opacity)
        case .transparentFloating: return .clear
        }
    }

    static func primaryText(theme: UsageDockTheme) -> Color {
        theme == .light ? Color.black.opacity(0.92) : Color.white.opacity(0.96)
    }

    static func secondaryText(theme: UsageDockTheme) -> Color {
        theme == .light ? Color.black.opacity(0.50) : Color.white.opacity(0.44)
    }

    static func tertiaryText(theme: UsageDockTheme) -> Color {
        theme == .light ? Color.black.opacity(0.34) : Color.white.opacity(0.30)
    }

    static func ringTrack(theme: UsageDockTheme) -> Color {
        theme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.13)
    }

    static func surface(theme: UsageDockTheme, opacity: Double = 1) -> Color {
        switch theme {
        case .dark: return Color.white.opacity(0.045 * opacity)
        case .light: return Color.black.opacity(0.055 * opacity)
        case .monochrome: return Color.white.opacity(0.055 * opacity)
        case .pop: return Color.white.opacity(0.075 * opacity)
        case .transparentFloating: return Color.black.opacity(0.58 * opacity)
        }
    }

    static func border(theme: UsageDockTheme) -> Color {
        theme == .light ? Color.black.opacity(0.12) : Color.white.opacity(0.16)
    }

    static func contrastShadow(theme: UsageDockTheme, enabled: Bool) -> Color {
        guard enabled else { return .clear }
        return theme == .light ? Color.white.opacity(0.90) : Color.black.opacity(0.92)
    }

    static func color(hex: String?) -> Color? {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard cleaned.count == 6, let value = UInt64(cleaned, radix: 16) else { return nil }
        return Color(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }

    static func hexString(from color: Color) -> String? {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let red = Int((rgb.redComponent * 255).rounded())
        let green = Int((rgb.greenComponent * 255).rounded())
        let blue = Int((rgb.blueComponent * 255).rounded())
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func defaultColors(for provider: ProviderID, pop: Bool) -> [Color] {
        let boost = pop ? 1.0 : 0.88
        switch provider {
        case .claude:
            return [Color(red: 1.0, green: 0.55 * boost, blue: 0.28), Color(red: 0.88, green: 0.30, blue: 0.18)]
        case .codex:
            return [Color(red: 0.30, green: 1.0, blue: 0.72 * boost), Color(red: 0.12, green: 0.70, blue: 0.55)]
        case .antigravity:
            return [Color(red: 0.38, green: 0.60, blue: 1.0), Color(red: 0.74, green: 0.36, blue: 1.0), Color(red: 0.98, green: 0.42, blue: 0.68)]
        case .kimi:
            return [Color(red: 0.48, green: 0.62, blue: 1.0), Color(red: 0.27, green: 0.30, blue: 0.92)]
        case .cursor:
            return [Color(red: 0.20, green: 0.95, blue: 0.98), Color(red: 0.30, green: 0.57, blue: 1.0)]
        case .grok:
            return [Color(red: 1.0, green: 0.38, blue: 0.68), Color(red: 0.67, green: 0.34, blue: 1.0)]
        }
    }
}

struct ProviderIcon: View {
    let provider: ProviderID
    var size: CGFloat = 24
    var accentHex: String? = nil
    var theme: UsageDockTheme = .dark
    var horizontalStretch: CGFloat = 1
    var verticalStretch: CGFloat = 1

    private var stretchedWidth: CGFloat { size * max(horizontalStretch, 1) }
    private var stretchedHeight: CGFloat { size * min(max(verticalStretch, 0.76), 1.04) }
    private var isDistorted: Bool { abs(horizontalStretch - 1) > 0.002 || abs(verticalStretch - 1) > 0.002 }

    @ViewBuilder
    var body: some View {
        if let asset = ProviderBrand.assetName(for: provider) {
            if isDistorted {
                Image(asset)
                    .resizable()
                    .renderingMode(.template)
                    .foregroundStyle(ProviderBrand.gradient(for: provider, customHex: accentHex, theme: theme))
                    .frame(width: stretchedWidth, height: stretchedHeight)
                    .accessibilityHidden(true)
            } else {
                Image(asset)
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(ProviderBrand.gradient(for: provider, customHex: accentHex, theme: theme))
                    .frame(width: size, height: size)
                    .accessibilityHidden(true)
            }
        } else if isDistorted {
            Image(systemName: ProviderBrand.systemSymbol(for: provider))
                .resizable()
                .foregroundStyle(ProviderBrand.gradient(for: provider, customHex: accentHex, theme: theme))
                .frame(width: stretchedWidth, height: stretchedHeight)
                .accessibilityHidden(true)
        } else {
            Image(systemName: ProviderBrand.systemSymbol(for: provider))
                .resizable()
                .scaledToFit()
                .foregroundStyle(ProviderBrand.gradient(for: provider, customHex: accentHex, theme: theme))
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        }
    }
}

struct UsageProgressBar: View {
    let provider: ProviderID
    let value: Double?
    var accentHex: String? = nil
    var theme: UsageDockTheme = .dark

    private var progress: Double {
        min(max(value ?? 0, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ProviderBrand.ringTrack(theme: theme))

                Capsule()
                    .fill(ProviderBrand.gradient(for: provider, customHex: accentHex, theme: theme))
                    .frame(width: proxy.size.width * progress)
                    .shadow(
                        color: ProviderBrand.glow(for: provider, customHex: accentHex, theme: theme).opacity(progress > 0.7 ? 0.35 : 0.14),
                        radius: 5
                    )
            }
        }
        .frame(height: 5)
    }
}

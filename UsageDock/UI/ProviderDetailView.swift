import SwiftUI

struct ProviderDetailView: View {
    let target: RailDisplayTarget
    let edge: DockEdge
    @ObservedObject var usageStore: UsageStore

    private var provider: ProviderID { target.provider }
    private var summary: ProviderUsageSummary { usageStore.summary(for: target) }
    private var accentHex: String? { usageStore.accentHex(for: target) }
    private var account: UsageAccount? { usageStore.account(for: target) }
    private var theme: UsageDockTheme { usageStore.theme }

    private var scopedAccounts: [UsageAccount] {
        if let account { return [account] }
        return usageStore.visibleAccounts(for: provider).filter(\.isEnabled)
    }

    var body: some View {
        let shape = DetailBubbleShape(
            pointerEdge: edge,
            cornerRadius: CGFloat(usageStore.bubbleCornerRadius),
            pointerDepth: CGFloat(usageStore.bubblePointerDepth),
            pointerWidth: CGFloat(usageStore.bubblePointerWidth)
        )

        ZStack {
            shape
                .fill(detailBackground)
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                ProviderBrand.glow(for: provider, customHex: accentHex, theme: theme).opacity(theme == .monochrome ? 0.02 : 0.075),
                                theme == .light ? Color.black.opacity(0.012) : Color.white.opacity(0.02),
                                theme == .light ? Color.white.opacity(0.08) : Color.black.opacity(0.18)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay {
                    shape.stroke(
                        ProviderBrand.glow(for: provider, customHex: accentHex, theme: theme).opacity(theme == .monochrome ? 0.22 : 0.40),
                        lineWidth: 0.8
                    )
                }
                .shadow(color: .black.opacity(theme == .light ? 0.18 : 0.38), radius: 20, y: 7)

            TimelineView(.periodic(from: .now, by: 30)) { _ in
                content
            }
            .padding(.leading, edge == .left ? CGFloat(usageStore.bubblePointerDepth) + 14 : 16)
            .padding(.trailing, edge == .right ? CGFloat(usageStore.bubblePointerDepth) + 14 : 16)
            .padding(.vertical, 16)
        }
    }

    private var detailBackground: Color {
        switch theme {
        case .dark: return Color.black.opacity(0.965)
        case .light: return Color.white.opacity(0.975)
        case .monochrome: return Color.black.opacity(0.975)
        case .pop: return Color(red: 0.10, green: 0.025, blue: 0.18).opacity(0.97)
        case .transparentFloating: return Color.black.opacity(usageStore.railBackplateEnabled ? 0.78 : 0.64)
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if summary.aggregates.isEmpty {
                emptyState
            } else {
                VStack(spacing: 9) {
                    ForEach(summary.aggregates.prefix(7)) { aggregate in
                        quotaRow(aggregate)
                    }
                }
                .opacity(usageStore.refreshFailureLabel(for: target) == nil ? 1 : 0.55)
            }

            footer
        }
    }

    private var header: some View {
        HStack(spacing: 11) {
            ZStack {
                Circle().fill(ProviderBrand.surface(theme: theme, opacity: 0.9))
                ProviderIcon(provider: provider, size: 25, accentHex: accentHex, theme: theme)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(usageStore.displayName(for: target))
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(ProviderBrand.primaryText(theme: theme))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(provider.displayName)
                    if let account {
                        Text("·")
                        Text(sourceLabel(account.source))
                    } else if usageStore.fusionEnabled(for: provider) {
                        Text("· Fusion")
                    }
                }
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(ProviderBrand.secondaryText(theme: theme))
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(pressureText)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(summary.pressurePercent == nil ? ProviderBrand.tertiaryText(theme: theme) : ProviderBrand.primaryText(theme: theme))
                Text(usageStore.presentationMode.label)
                    .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(ProviderBrand.tertiaryText(theme: theme))
                    .textCase(.uppercase)
            }
            .opacity(usageStore.refreshFailureLabel(for: target) == nil ? 1 : 0.55)
        }
    }

    private var emptyState: some View {
        HStack(spacing: 9) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(ProviderBrand.secondaryText(theme: theme))
            Text("No live quota data yet")
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .foregroundStyle(ProviderBrand.secondaryText(theme: theme))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(ProviderBrand.surface(theme: theme, opacity: 0.84), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func quotaRow(_ aggregate: UsageAggregate) -> some View {
        let displayed = usageStore.displayPercent(aggregate.percentUsed)
        return VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(LocalizedStringKey(aggregate.label))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(ProviderBrand.primaryText(theme: theme))
                    .lineLimit(1)

                if aggregate.accountCount > 1 {
                    Text("×\(aggregate.accountCount)")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(ProviderBrand.tertiaryText(theme: theme))
                }

                Spacer()

                Text(aggregate.resetsAt.map(resetText) ?? "—")
                    .font(.system(size: 9.2, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ProviderBrand.secondaryText(theme: theme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)

                Text(percentText(displayed))
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(ProviderBrand.primaryText(theme: theme))
                    .frame(width: 42, alignment: .trailing)
            }

            UsageProgressBar(provider: provider, value: displayed, accentHex: accentHex, theme: theme)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(ProviderBrand.surface(theme: theme, opacity: 0.92), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 5, height: 5)

            if let failureLabel = usageStore.refreshFailureLabel(for: target) {
                Text(failureLabel)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let account {
                Text(usageStore.accountStatusText(for: account))
            } else {
                Text("\(scopedAccounts.count) account\(scopedAccounts.count == 1 ? "" : "s")")
            }

            Spacer()

            if let multiplier = usageStore.displayMultiplier(for: target) {
                Text("×\(multiplier)")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }
        }
        .font(.system(size: 9.5, weight: .medium, design: .rounded))
        .foregroundStyle(ProviderBrand.secondaryText(theme: theme))
        .lineLimit(2)
    }

    private var pressureText: String {
        percentText(usageStore.displayPercent(summary.pressurePercent))
    }

    private var statusColor: Color {
        switch usageStore.refreshState(for: provider) {
        case .live: return .green
        case .partial: return .orange
        case .refreshing: return .blue
        case .failed: return .orange
        case .idle: return ProviderBrand.tertiaryText(theme: theme)
        }
    }

    private func sourceLabel(_ source: UsageAccountSource?) -> String {
        switch source {
        case .currentSession: return "Local Login"
        case .profile: return "UsageDock Profile"
        case .legacyUnsupported, nil: return "Unavailable"
        }
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func resetText(_ date: Date) -> String {
        switch usageStore.resetTimeDisplayMode {
        case .relative:
            return usageStore.remainingResetTimeText(until: date) ?? "—"
        case .absolute:
            return Self.absoluteResetFormatter.string(from: date)
        case .both:
            return "\(usageStore.remainingResetTimeText(until: date) ?? "—") · \(Self.absoluteResetFormatter.string(from: date))"
        }
    }

    private static let absoluteResetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MdHm")
        return formatter
    }()
}

private struct DetailBubbleShape: Shape {
    let pointerEdge: DockEdge
    let cornerRadius: CGFloat
    let pointerDepth: CGFloat
    let pointerWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let depth = min(max(pointerDepth, 0), rect.width * 0.22)
        let halfWidth = min(max(pointerWidth / 2, 3), rect.height * 0.22)
        let cardRect: CGRect

        switch pointerEdge {
        case .right:
            cardRect = CGRect(x: rect.minX, y: rect.minY, width: rect.width - depth, height: rect.height)
        case .left:
            cardRect = CGRect(x: rect.minX + depth, y: rect.minY, width: rect.width - depth, height: rect.height)
        }

        var path = Path(roundedRect: cardRect, cornerRadius: min(cornerRadius, cardRect.height / 2))
        guard depth > 0 else { return path }

        var pointer = Path()
        let centerY = rect.midY
        if pointerEdge == .right {
            pointer.move(to: CGPoint(x: cardRect.maxX - 1, y: centerY - halfWidth))
            pointer.addCurve(
                to: CGPoint(x: rect.maxX, y: centerY),
                control1: CGPoint(x: cardRect.maxX + depth * 0.42, y: centerY - halfWidth * 0.72),
                control2: CGPoint(x: rect.maxX - depth * 0.16, y: centerY - halfWidth * 0.18)
            )
            pointer.addCurve(
                to: CGPoint(x: cardRect.maxX - 1, y: centerY + halfWidth),
                control1: CGPoint(x: rect.maxX - depth * 0.16, y: centerY + halfWidth * 0.18),
                control2: CGPoint(x: cardRect.maxX + depth * 0.42, y: centerY + halfWidth * 0.72)
            )
        } else {
            pointer.move(to: CGPoint(x: cardRect.minX + 1, y: centerY - halfWidth))
            pointer.addCurve(
                to: CGPoint(x: rect.minX, y: centerY),
                control1: CGPoint(x: cardRect.minX - depth * 0.42, y: centerY - halfWidth * 0.72),
                control2: CGPoint(x: rect.minX + depth * 0.16, y: centerY - halfWidth * 0.18)
            )
            pointer.addCurve(
                to: CGPoint(x: cardRect.minX + 1, y: centerY + halfWidth),
                control1: CGPoint(x: rect.minX + depth * 0.16, y: centerY + halfWidth * 0.18),
                control2: CGPoint(x: cardRect.minX - depth * 0.42, y: centerY + halfWidth * 0.72)
            )
        }
        pointer.closeSubpath()
        path.addPath(pointer)
        return path
    }
}

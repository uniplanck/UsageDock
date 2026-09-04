import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum TimerFieldMode: String, CaseIterable, Identifiable {
    case hidden
    case one
    case two

    var id: String { rawValue }
    var label: String {
        switch self {
        case .hidden: "Hidden"
        case .one: "0"
        case .two: "00"
        }
    }
}

enum SettingsCategory: String, CaseIterable, Identifiable {
    case accounts
    case menuBar
    case layout
    case shape
    case appearance
    case border
    case data

    var id: String { rawValue }

    var label: String {
        switch self {
        case .accounts: "Accounts"
        case .menuBar: "Menu Bar"
        case .layout: "Layout"
        case .shape: "Shape"
        case .appearance: "Appearance"
        case .border: "Border"
        case .data: "Data"
        }
    }

    var systemImage: String {
        switch self {
        case .accounts: "person.2"
        case .menuBar: "menubar.rectangle"
        case .layout: "rectangle.3.group"
        case .shape: "capsule.portrait"
        case .appearance: "paintbrush"
        case .border: "square.dashed"
        case .data: "chart.bar"
        }
    }
}

enum SettingsHoverPreviewPolicy {
    static func shouldShow(category: SettingsCategory, bubbleExpanded: Bool) -> Bool {
        category == .shape && bubbleExpanded
    }
}

private struct FullRowDisclosure<Content: View>: View {
    let title: LocalizedStringKey
    @Binding var isExpanded: Bool
    let onExpansionChanged: (Bool) -> Void
    let content: Content

    init(
        title: LocalizedStringKey,
        isExpanded: Binding<Bool>,
        onExpansionChanged: @escaping (Bool) -> Void = { _ in },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        _isExpanded = isExpanded
        self.onExpansionChanged = onExpansionChanged
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                let next = !isExpanded
                withAnimation(.easeInOut(duration: 0.16)) { isExpanded = next }
                onExpansionChanged(next)
            } label: {
                HStack {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                content
                    .padding(.top, 2)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var usageStore: UsageStore
    @ObservedObject var placement: PlacementStore
    @State private var selectedCategory: SettingsCategory = .accounts
    @State private var appearanceExpanded = true
    @State private var dataExpanded = true
    @State private var advancedShapeExpanded = false

    private let formLabelWidth: CGFloat = 168
    private let formControlWidth: CGFloat = 420
    private let formValueWidth: CGFloat = 88
    private let dataCaptionWidth: CGFloat = 58

    var body: some View {
        HStack(spacing: 0) {
            List(SettingsCategory.allCases, selection: $selectedCategory) { category in
                Label(category.label, systemImage: category.systemImage)
                    .tag(category)
            }
            .listStyle(.sidebar)
            .frame(minWidth: 176, idealWidth: 188, maxWidth: 205)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    categoryIntro
                    selectedSettingsPage
                }
                .padding(.horizontal, 30)
                .padding(.vertical, 26)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 1000, minHeight: 740)
        .environment(\.locale, usageStore.appLanguage.locale)
    }

    private var categoryIntro: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedCategory.label)
                .font(.title3.weight(.semibold))
            Text(categoryDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var categoryDescription: String {
        switch selectedCategory {
        case .accounts: "Choose authenticated accounts and manage provider sign-in. Up to 3 accounts can be saved for instant Rail switching."
        case .menuBar: "Choose which accounts appear in the macOS menu bar. This selection is independent from Rail display accounts."
        case .layout: "Control Rail size, placement, spacing, labels, and visible elements."
        case .shape: "Adjust the screen-edge profile, interior-facing corners, and continuous liquid silhouette."
        case .appearance: "Choose theme, material, opacity, surface treatment, and particle droplets."
        case .border: "Control the visible canonical border, glow, and edge color."
        case .data: "Choose quota sources, timer formatting, provider order, colors, and links."
        }
    }

    @ViewBuilder
    private var selectedSettingsPage: some View {
        switch selectedCategory {
        case .accounts:
            accountsSettingsPage
        case .menuBar:
            menuBarSettingsPage
        case .layout:
            layoutSettingsPage
        case .shape:
            shapeSettingsPage
        case .appearance:
            appearanceSettingsPage
        case .border:
            borderSettingsPage
        case .data:
            dataSettingsPage
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("UsageDock Settings")
                    .font(.title2.weight(.semibold))
                Text("Accounts, display, appearance, and live quota sources")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await usageStore.refreshLiveUsage() }
            } label: {
                Label(usageStore.isRefreshing ? "Refreshing…" : "Refresh Now", systemImage: "arrow.clockwise")
            }
            .disabled(usageStore.isRefreshing)
        }
    }

    private func settingsRow<Control: View>(
        _ label: LocalizedStringKey,
        value: String = "",
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            Text(label)
                .lineLimit(1)
                .frame(width: formLabelWidth, alignment: .leading)
            control()
                .frame(width: formControlWidth, alignment: .leading)
            Text(LocalizedStringKey(value))
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: formValueWidth, alignment: .trailing)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 32)
    }

    private func sliderRow(
        _ label: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        valueText: String
    ) -> some View {
        settingsRow(label, value: valueText) {
            Slider(value: value, in: range, step: step)
                .frame(maxWidth: .infinity)
        }
    }

    private func shapeAmountRow(_ label: LocalizedStringKey, value: Binding<Double>) -> some View {
        settingsRow(label, value: String(format: "%+.0f%%", value.wrappedValue * 100)) {
            HStack(spacing: 9) {
                Text("Inset")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: value, in: -1...1, step: 0.01)
                Text("Spread")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func screenEdgeShapeRow(_ label: LocalizedStringKey, value: Binding<Double>) -> some View {
        settingsRow(label, value: String(format: "%+.0f%%", value.wrappedValue * 100)) {
            HStack(spacing: 9) {
                Text("Bubble")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: value, in: -1...1, step: 0.01)
                Text("Spread")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func valleyDepthRow(_ label: LocalizedStringKey, value: Binding<Double>) -> some View {
        settingsRow(label, value: "\(Int((-min(value.wrappedValue, 0) * 100).rounded()))%") {
            HStack(spacing: 9) {
                Text("Deep")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: value, in: -1...0, step: 0.01)
                Text("Shallow")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func alignedDataControl<Control: View>(
        _ caption: LocalizedStringKey? = nil,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(spacing: 10) {
            Group {
                if let caption {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }
            .frame(width: dataCaptionWidth, alignment: .leading)

            control()
            Spacer(minLength: 0)
        }
    }

    private func paddingText(_ value: Double) -> String {
        "\(Int(value.rounded())) pt"
    }

    private var hourModeBinding: Binding<TimerFieldMode> {
        Binding(
            get: {
                guard usageStore.railShowHours else { return .hidden }
                return usageStore.railHourDigits == .two ? .two : .one
            },
            set: { mode in
                usageStore.railShowHours = mode != .hidden
                if mode != .hidden { usageStore.railHourDigits = mode == .two ? .two : .one }
            }
        )
    }

    private var minuteModeBinding: Binding<TimerFieldMode> {
        Binding(
            get: {
                guard usageStore.railShowMinutes else { return .hidden }
                return usageStore.railMinuteDigits == .two ? .two : .one
            },
            set: { mode in
                usageStore.railShowMinutes = mode != .hidden
                if mode != .hidden { usageStore.railMinuteDigits = mode == .two ? .two : .one }
            }
        )
    }

    private var borderCustomColorBinding: Binding<Color> {
        Binding(
            get: {
                ProviderBrand.color(hex: usageStore.railBorderCustomHex)
                    ?? ProviderBrand.border(theme: usageStore.theme)
            },
            set: { newColor in
                usageStore.railBorderCustomHex = ProviderBrand.hexString(from: newColor)
                usageStore.railBorderColorMode = .custom
            }
        )
    }

    private var accountsSettingsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            displayAccountSelectionSection

            ForEach(usageStore.providerOrder) { provider in
                ProviderSettingsSection(provider: provider, usageStore: usageStore)
            }

            Text(
                UsageDockDistributionPolicy.isPublicRelease
                    ? "Public builds register accounts only through authenticated provider logins. Cursor and Grok stay unavailable until a verified login and live-usage path exists."
                    : "Development-only test accounts remain available for local previewing, but Display Account switching accepts authenticated account sources only."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
    }

    private var displayAccountSelectionSection: some View {
        GroupBox("Display Accounts") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Save up to 3 authenticated accounts for instant Rail switching.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(usageStore.displayAccountIDs.count)/3 saved")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                let selectable = usageStore.displaySelectableAccounts()
                if selectable.isEmpty {
                    Label("No authenticated account sources are registered yet.", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(selectable) { account in
                        let authState = usageStore.displayAuthenticationState(for: account)
                        let saved = usageStore.isDisplayAccountCandidate(account.id)
                        HStack(spacing: 10) {
                            ProviderIcon(
                                provider: account.provider,
                                size: 18,
                                accentHex: account.accentHex ?? usageStore.providerAccentHex[account.provider]
                            )
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(account.provider.displayName) · \(account.name)")
                                    .font(.callout.weight(.medium))
                                Text(displayAuthText(authState))
                                    .font(.caption)
                                    .foregroundStyle(authState == .required ? .red : .secondary)
                            }
                            Spacer()

                            if saved {
                                Button {
                                    usageStore.selectDisplayAccount(account.id)
                                } label: {
                                    Label(
                                        usageStore.isActiveDisplayAccount(account.id) ? "Showing" : "Show Now",
                                        systemImage: usageStore.isActiveDisplayAccount(account.id) ? "checkmark.circle.fill" : "play.circle"
                                    )
                                }
                                .controlSize(.small)
                                .disabled(authState != .valid)
                            }

                            Button {
                                usageStore.setDisplayAccountCandidate(account.id, enabled: !saved)
                            } label: {
                                Label(saved ? "Remove" : "Save", systemImage: saved ? "minus.circle" : "plus.circle")
                            }
                            .controlSize(.small)
                            .disabled(!saved && !usageStore.canAddDisplayAccount(account.id))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                    }
                }

                Text("If authentication expires, the Rail stops showing that account instead of presenting stale usage. Re-authenticate in the provider section below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        }
    }

    private var menuBarSettingsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Menu Bar Display") {
                VStack(spacing: 14) {
                    settingsRow("Usage display") {
                        Toggle("Show usage in menu bar", isOn: $usageStore.menuBarUsageEnabled)
                            .toggleStyle(.switch)
                    }
                    settingsRow("Elements") {
                        HStack(spacing: 18) {
                            Toggle("Usage ring", isOn: $usageStore.menuBarShowRing)
                            Toggle("Percentage", isOn: $usageStore.menuBarShowPercentage)
                        }
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .disabled(!usageStore.menuBarUsageEnabled)
                    }
                }
                .padding(.vertical, 8)
            }

            GroupBox("Accounts to Show") {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Independent from Rail Display Accounts.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(usageStore.menuBarAccountIDs.count) selected")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    let selectable = usageStore.menuBarSelectableAccounts()
                    if selectable.isEmpty {
                        Label("No authenticated account sources are registered yet.", systemImage: "menubar.rectangle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(selectable) { account in
                            let authState = usageStore.displayAuthenticationState(for: account)
                            let selected = usageStore.isMenuBarAccountSelected(account.id)
                            HStack(spacing: 10) {
                                ProviderIcon(
                                    provider: account.provider,
                                    size: 18,
                                    accentHex: account.accentHex ?? usageStore.providerAccentHex[account.provider]
                                )
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(account.provider.displayName) · \(account.name)")
                                        .font(.callout.weight(.medium))
                                    Text(displayAuthText(authState))
                                        .font(.caption)
                                        .foregroundStyle(authState == .required ? .red : .secondary)
                                }
                                Spacer()
                                Toggle(
                                    "",
                                    isOn: Binding(
                                        get: { selected },
                                        set: { usageStore.setMenuBarAccountSelected(account.id, enabled: $0) }
                                    )
                                )
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    Text("If authentication expires, the account stays selected but its menu-bar value becomes -- until live usage is valid again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }
        }
    }

    private func displayAuthText(_ state: DisplayAccountAuthState) -> String {
        switch state {
        case .valid: "Authenticated · live usage available"
        case .checking: "Authentication pending · refresh to verify"
        case .required: "Authentication required"
        }
    }

    private var layoutSettingsPage: some View {
        GroupBox("Layout") {
            VStack(spacing: 14) {
                settingsRow("Language", value: usageStore.appLanguage.label) {
                    Picker("Language", selection: $usageStore.appLanguage) {
                        ForEach(UsageDockLanguage.allCases) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                settingsRow("Screen edge", value: placement.edge.label) {
                    Picker("Screen edge", selection: $placement.edge) {
                        ForEach(DockEdge.allCases) { edge in
                            Text(LocalizedStringKey(edge.label)).tag(edge)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                settingsRow("Value", value: usageStore.presentationMode.label) {
                    Picker("Value", selection: $usageStore.presentationMode) {
                        ForEach(UsagePresentationMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.label)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                Divider()
                sliderRow("Scale", value: $usageStore.railScale, range: 0.45...1.45, step: 0.01, valueText: "\(Int((usageStore.railScale * 100).rounded()))%")
                sliderRow("Position", value: $usageStore.railVerticalPosition, range: 0...1, step: 0.01, valueText: "\(Int((usageStore.railVerticalPosition * 100).rounded()))%")
                sliderRow("Inner padding Y", value: $usageStore.railInnerPaddingY, range: 0...48, step: 1, valueText: paddingText(usageStore.railInnerPaddingY))
                sliderRow("Screen-side padding", value: $usageStore.railScreenInnerPadding, range: 0...48, step: 1, valueText: paddingText(usageStore.railScreenInnerPadding))
                sliderRow("Window-side padding", value: $usageStore.railWindowInnerPadding, range: 0...48, step: 1, valueText: paddingText(usageStore.railWindowInnerPadding))
                sliderRow("Item spacing", value: $usageStore.railItemSpacing, range: 0...36, step: 1, valueText: "\(Int(usageStore.railItemSpacing.rounded())) pt")
                sliderRow("Icon size", value: $usageStore.railIconSize, range: 14...44, step: 1, valueText: "\(Int(usageStore.railIconSize.rounded())) pt")

                Divider()
                sliderRow("Percentage font", value: $usageStore.railPercentFontSize, range: 7...22, step: 0.5, valueText: String(format: "%.1f pt", usageStore.railPercentFontSize))
                sliderRow("Account / title font", value: $usageStore.railAccountLabelFontSize, range: 7...20, step: 0.5, valueText: String(format: "%.1f pt", usageStore.railAccountLabelFontSize))
                sliderRow("Remaining time font", value: $usageStore.railRemainingTimeFontSize, range: 6...20, step: 0.5, valueText: String(format: "%.1f pt", usageStore.railRemainingTimeFontSize))
                sliderRow("Title width", value: $usageStore.railTitleWidth, range: 36...160, step: 2, valueText: "\(Int(usageStore.railTitleWidth.rounded())) pt")
                sliderRow("Time width", value: $usageStore.railTimeWidth, range: 36...160, step: 2, valueText: "\(Int(usageStore.railTimeWidth.rounded())) pt")

                Divider()
                settingsRow("Visible elements") {
                    HStack(spacing: 18) {
                        Toggle("Percentage", isOn: $usageStore.railShowPercent)
                        Toggle("Usage ring", isOn: $usageStore.railShowRing)
                        Toggle("Timer", isOn: $usageStore.railShowRemainingTime)
                        Toggle("Title", isOn: $usageStore.railShowTitle)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                settingsRow("Interaction") {
                    HStack(spacing: 18) {
                        Toggle("Multiplier ×N", isOn: $usageStore.railShowMultiplier)
                        Toggle("Hover details", isOn: $usageStore.railHoverEnabled)
                            .disabled(usageStore.railVisualOnlyMode)
                        Toggle("Visual only", isOn: $usageStore.railVisualOnlyMode)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var shapeSettingsPage: some View {
        GroupBox("Shape") {
            VStack(spacing: 14) {
                screenEdgeShapeRow("Screen-edge shape", value: $usageStore.railScreenEdgeShape)
                valleyDepthRow("Attached-edge valley", value: $usageStore.railScreenEdgeCurvature)
                shapeAmountRow("Free-side shape", value: $usageStore.railInnerShape)
                Divider()
                shapeSlider("Interior corner radius", value: $usageStore.railCornerRadius, range: 4...48, suffix: "pt")
                shapeSlider("Curve depth", value: $usageStore.railScallopDepth, range: 0...42, suffix: "pt")
                Divider()
                FullRowDisclosure(
                    title: "Bubble / Hover Shape",
                    isExpanded: $advancedShapeExpanded,
                    onExpansionChanged: { [usageStore] expanded in
                        usageStore.settingsBubblePreviewRequested = SettingsHoverPreviewPolicy.shouldShow(
                            category: .shape,
                            bubbleExpanded: expanded
                        )
                    }
                ) {
                    VStack(spacing: 12) {
                        shapeSlider("Bubble radius", value: $usageStore.bubbleCornerRadius, range: 8...40, suffix: "pt")
                        shapeSlider("Bubble nub depth", value: $usageStore.bubblePointerDepth, range: 0...32, suffix: "pt")
                        shapeSlider("Bubble nub width", value: $usageStore.bubblePointerWidth, range: 6...56, suffix: "pt")
                    }
                }
            }
            .padding(.vertical, 8)
        }
        .onDisappear { [usageStore] in
            usageStore.settingsBubblePreviewRequested = false
        }
    }

    private var appearanceSettingsPage: some View {
        GroupBox("Appearance") {
            VStack(spacing: 14) {
                settingsRow("Theme", value: usageStore.theme.label) {
                    Picker("Theme", selection: $usageStore.theme) {
                        ForEach(UsageDockTheme.allCases) { theme in
                            Text(LocalizedStringKey(theme.label)).tag(theme)
                        }
                    }
                    .labelsHidden()
                }
                settingsRow("Material", value: usageStore.railMaterialMode.label) {
                    Picker("Material", selection: $usageStore.railMaterialMode) {
                        ForEach(RailMaterialMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.label)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                sliderRow("Background opacity", value: $usageStore.railBackgroundOpacity, range: 0...1, step: 0.01, valueText: "\(Int((usageStore.railBackgroundOpacity * 100).rounded()))%")
                settingsRow("Surface helpers") {
                    HStack(spacing: 18) {
                        Toggle("Backplate", isOn: $usageStore.railBackplateEnabled)
                        Toggle("Auto contrast", isOn: $usageStore.railAutoContrast)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }
                settingsRow("Reset time detail", value: usageStore.resetTimeDisplayMode.label) {
                    Picker("Reset time", selection: $usageStore.resetTimeDisplayMode) {
                        ForEach(ResetTimeDisplayMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.label)).tag(mode)
                        }
                    }
                    .labelsHidden()
                }
                if usageStore.railMaterialMode == .bar3D {
                    Text("3D Bar uses material-native highlights and shadows; Border controls are intentionally disabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Divider()
                settingsRow("Droplets", value: usageStore.railDropletsEnabled ? "On" : "Off") {
                    Toggle("Droplets", isOn: $usageStore.railDropletsEnabled)
                        .toggleStyle(.switch)
                }
                Text("Droplets controls attached drips, floating drips, and break particles. Stretch, neck pinch, break deformation, residue, snap-back, and wetting stay active.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 8)
        }
    }

    private var borderSettingsPage: some View {
        GroupBox("Border") {
            VStack(spacing: 14) {
                settingsRow("Edge style", value: usageStore.railEdgeStyle.label) {
                    Picker("Edge style", selection: $usageStore.railEdgeStyle) {
                        ForEach(RailEdgeStyle.allCases) { style in
                            Text(LocalizedStringKey(style.label)).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .disabled(usageStore.railMaterialMode == .bar3D)
                }
                settingsRow("Color", value: usageStore.railBorderColorMode.label) {
                    HStack(spacing: 10) {
                        Picker("Edge color", selection: $usageStore.railBorderColorMode) {
                            ForEach(RailEdgeColorMode.allCases) { mode in
                                Text(LocalizedStringKey(mode.label)).tag(mode)
                            }
                        }
                        .labelsHidden()
                        if usageStore.railBorderColorMode == .custom {
                            ColorPicker("Custom", selection: borderCustomColorBinding, supportsOpacity: false)
                                .labelsHidden()
                        }
                        Button("Reset") {
                            usageStore.railBorderColorMode = .automatic
                            usageStore.railBorderCustomHex = nil
                        }
                        .controlSize(.small)
                    }
                    .disabled(usageStore.railMaterialMode == .bar3D)
                }
                sliderRow("Width", value: $usageStore.railEdgeWidth, range: 0.25...4, step: 0.05, valueText: String(format: "%.2f pt", usageStore.railEdgeWidth))
                    .disabled(usageStore.railMaterialMode == .bar3D || usageStore.railEdgeStyle == .off)
                sliderRow("Opacity", value: $usageStore.railEdgeOpacity, range: 0...1, step: 0.01, valueText: "\(Int((usageStore.railEdgeOpacity * 100).rounded()))%")
                    .disabled(usageStore.railMaterialMode == .bar3D || usageStore.railEdgeStyle == .off)
                sliderRow("Glow", value: $usageStore.railGlowRadius, range: 0...32, step: 1, valueText: "\(Int(usageStore.railGlowRadius.rounded())) pt")
                    .disabled(usageStore.railMaterialMode == .bar3D || !(usageStore.railEdgeStyle == .soft || usageStore.railEdgeStyle == .neon || usageStore.railEdgeStyle == .glass))
                sliderRow("Glow intensity", value: $usageStore.railGlowOpacity, range: 0...1, step: 0.01, valueText: "\(Int((usageStore.railGlowOpacity * 100).rounded()))%")
                    .disabled(usageStore.railMaterialMode == .bar3D || !(usageStore.railEdgeStyle == .soft || usageStore.railEdgeStyle == .neon || usageStore.railEdgeStyle == .glass))
            }
            .padding(.vertical, 8)
        }
    }

    private var dataSettingsPage: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Rail Data & Timer") {
                VStack(spacing: 14) {
                    settingsRow("Percent source", value: usageStore.railPercentSource.label) {
                        quotaPicker("Percent", selection: $usageStore.railPercentSource, allowNone: false)
                    }
                    settingsRow("Outer ring source", value: usageStore.railOuterRingSource.label) {
                        quotaPicker("Outer ring", selection: $usageStore.railOuterRingSource, allowNone: true)
                    }
                    settingsRow("Inner ring source", value: usageStore.railInnerRingSource.label) {
                        quotaPicker("Inner ring", selection: $usageStore.railInnerRingSource, allowNone: true)
                    }
                    settingsRow("Timer source", value: usageStore.railTimeSource.label) {
                        quotaPicker("Timer", selection: $usageStore.railTimeSource, allowNone: false)
                    }
                    settingsRow("Day digits", value: usageStore.railDayDigits.label) {
                        alignedDataControl {
                            Picker("Day digits", selection: $usageStore.railDayDigits) {
                                ForEach(RailDigitWidth.allCases) { width in Text(width.label).tag(width) }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 142)
                        }
                    }
                    settingsRow("Hour", value: hourModeBinding.wrappedValue.label) {
                        alignedDataControl {
                            Picker("Hour", selection: hourModeBinding) {
                                ForEach(TimerFieldMode.allCases) { mode in Text(LocalizedStringKey(mode.label)).tag(mode) }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 192)
                        }
                    }
                    settingsRow("Minute", value: minuteModeBinding.wrappedValue.label) {
                        alignedDataControl {
                            Picker("Minute", selection: minuteModeBinding) {
                                ForEach(TimerFieldMode.allCases) { mode in Text(LocalizedStringKey(mode.label)).tag(mode) }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(width: 192)
                        }
                    }
                    settingsRow("Zero auto-hide") {
                        alignedDataControl {
                            HStack(spacing: 18) {
                                Toggle("Days", isOn: $usageStore.railAutoHideZeroDays)
                                Toggle("Hours", isOn: $usageStore.railAutoHideZeroHours)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            providerOrderSection
        }
    }

    private var displaySection: some View {
        GroupBox("Display") {
            VStack(spacing: 18) {
                settingsRow("Language", value: usageStore.appLanguage.label) {
                    Picker("Language", selection: $usageStore.appLanguage) {
                        ForEach(UsageDockLanguage.allCases) { language in
                            Text(language.label).tag(language)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }

                Divider()

                settingsRow("Visual only") {
                    Toggle("Click-through", isOn: $usageStore.railVisualOnlyMode)
                        .toggleStyle(.switch)
                        .help("Display only. Hover, click, drag, and context menus are disabled; pointer events pass through to the window below.")
                }

                Divider()

                settingsRow("Screen edge", value: placement.edge.label) {
                    Picker("Screen edge", selection: $placement.edge) {
                        ForEach(DockEdge.allCases) { edge in
                            Text(LocalizedStringKey(edge.label)).tag(edge)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                settingsRow("Value", value: usageStore.presentationMode.label) {
                    Picker("Value", selection: $usageStore.presentationMode) {
                        ForEach(UsagePresentationMode.allCases) { mode in
                            Text(LocalizedStringKey(mode.label)).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                Divider()

                sliderRow(
                    "Rail size",
                    value: $usageStore.railScale,
                    range: 0.45...1.45,
                    step: 0.01,
                    valueText: "\(Int((usageStore.railScale * 100).rounded()))%"
                )

                sliderRow(
                    "Icon size",
                    value: $usageStore.railIconSize,
                    range: 14...44,
                    step: 1,
                    valueText: "\(Int(usageStore.railIconSize.rounded())) pt"
                )

                Divider()

                sliderRow(
                    "Icon spacing",
                    value: $usageStore.railItemSpacing,
                    range: 0...36,
                    step: 1,
                    valueText: "\(Int(usageStore.railItemSpacing.rounded())) pt"
                )

                sliderRow(
                    "Vertical inner padding",
                    value: $usageStore.railInnerPaddingY,
                    range: 0...48,
                    step: 1,
                    valueText: paddingText(usageStore.railInnerPaddingY)
                )

                sliderRow(
                    "Screen-side inner padding",
                    value: $usageStore.railScreenInnerPadding,
                    range: 0...48,
                    step: 1,
                    valueText: paddingText(usageStore.railScreenInnerPadding)
                )

                sliderRow(
                    "Window-side inner padding",
                    value: $usageStore.railWindowInnerPadding,
                    range: 0...48,
                    step: 1,
                    valueText: paddingText(usageStore.railWindowInnerPadding)
                )

                sliderRow(
                    "Percentage font",
                    value: $usageStore.railPercentFontSize,
                    range: 7...22,
                    step: 0.5,
                    valueText: String(format: "%.1f pt", usageStore.railPercentFontSize)
                )

                sliderRow(
                    "Account / title font",
                    value: $usageStore.railAccountLabelFontSize,
                    range: 7...20,
                    step: 0.5,
                    valueText: String(format: "%.1f pt", usageStore.railAccountLabelFontSize)
                )

                sliderRow(
                    "Remaining time font",
                    value: $usageStore.railRemainingTimeFontSize,
                    range: 6...20,
                    step: 0.5,
                    valueText: String(format: "%.1f pt", usageStore.railRemainingTimeFontSize)
                )

                sliderRow(
                    "Title width",
                    value: $usageStore.railTitleWidth,
                    range: 36...160,
                    step: 2,
                    valueText: "\(Int(usageStore.railTitleWidth.rounded())) pt"
                )

                sliderRow(
                    "Time width",
                    value: $usageStore.railTimeWidth,
                    range: 36...160,
                    step: 2,
                    valueText: "\(Int(usageStore.railTimeWidth.rounded())) pt"
                )

                settingsRow("Show title", value: usageStore.railShowTitle ? "On" : "Off") {
                    Toggle("Show account title", isOn: $usageStore.railShowTitle)
                        .toggleStyle(.switch)
                }

                sliderRow(
                    "Vertical position",
                    value: $usageStore.railVerticalPosition,
                    range: 0...1,
                    step: 0.01,
                    valueText: "\(Int((usageStore.railVerticalPosition * 100).rounded()))%"
                )

                Divider()

                FullRowDisclosure(title: "Appearance & Shape", isExpanded: $appearanceExpanded) {
                    VStack(spacing: 12) {
                        settingsRow("Theme", value: usageStore.theme.label) {
                            Picker("Theme", selection: $usageStore.theme) {
                                ForEach(UsageDockTheme.allCases) { theme in
                                    Text(LocalizedStringKey(theme.label)).tag(theme)
                                }
                            }
                            .labelsHidden()
                        }

                        settingsRow("Reset time detail", value: usageStore.resetTimeDisplayMode.label) {
                            Picker("Reset time", selection: $usageStore.resetTimeDisplayMode) {
                                ForEach(ResetTimeDisplayMode.allCases) { mode in
                                    Text(LocalizedStringKey(mode.label)).tag(mode)
                                }
                            }
                            .labelsHidden()
                        }

                        sliderRow(
                            "Background opacity",
                            value: $usageStore.railBackgroundOpacity,
                            range: 0...1,
                            step: 0.01,
                            valueText: "\(Int((usageStore.railBackgroundOpacity * 100).rounded()))%"
                        )

                        settingsRow("Material", value: usageStore.railMaterialMode.label) {
                            Picker("Material", selection: $usageStore.railMaterialMode) {
                                ForEach(RailMaterialMode.allCases) { mode in
                                    Text(LocalizedStringKey(mode.label)).tag(mode)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                        }

                        if usageStore.railMaterialMode == .bar3D {
                            settingsRow("3D border") {
                                Text("Internal highlight / shadow depth is used; border controls are ignored.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        settingsRow("Surface helpers") {
                            HStack(spacing: 18) {
                                Toggle("Backplate", isOn: $usageStore.railBackplateEnabled)
                                Toggle("Auto contrast", isOn: $usageStore.railAutoContrast)
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }

                        screenEdgeShapeRow("Screen-edge side", value: $usageStore.railScreenEdgeShape)
                        valleyDepthRow("Attached-edge valley", value: $usageStore.railScreenEdgeCurvature)
                        shapeAmountRow("Inner / Free side", value: $usageStore.railInnerShape)

                        settingsRow("Edge style", value: usageStore.railEdgeStyle.label) {
                            Picker("Edge style", selection: $usageStore.railEdgeStyle) {
                                ForEach(RailEdgeStyle.allCases) { style in
                                    Text(LocalizedStringKey(style.label)).tag(style)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .disabled(usageStore.railMaterialMode == .bar3D)
                        }

                        settingsRow("Edge color", value: usageStore.railBorderColorMode.label) {
                            HStack(spacing: 10) {
                                Picker("Edge color", selection: $usageStore.railBorderColorMode) {
                                    ForEach(RailEdgeColorMode.allCases) { mode in
                                        Text(LocalizedStringKey(mode.label)).tag(mode)
                                    }
                                }
                                .labelsHidden()

                                if usageStore.railBorderColorMode == .custom {
                                    ColorPicker("Custom", selection: borderCustomColorBinding, supportsOpacity: false)
                                        .labelsHidden()
                                }

                                Button("Reset") {
                                    usageStore.railBorderColorMode = .automatic
                                    usageStore.railBorderCustomHex = nil
                                }
                                .controlSize(.small)
                            }
                            .disabled(usageStore.railMaterialMode == .bar3D)
                        }

                        if usageStore.railMaterialMode != .bar3D && usageStore.railEdgeStyle != .off {
                            sliderRow(
                                "Border width",
                                value: $usageStore.railEdgeWidth,
                                range: 0.25...4,
                                step: 0.05,
                                valueText: String(format: "%.2f pt", usageStore.railEdgeWidth)
                            )
                            sliderRow(
                                "Border opacity",
                                value: $usageStore.railEdgeOpacity,
                                range: 0...1,
                                step: 0.01,
                                valueText: "\(Int((usageStore.railEdgeOpacity * 100).rounded()))%"
                            )
                        }

                        if usageStore.railMaterialMode != .bar3D && (usageStore.railEdgeStyle == .soft || usageStore.railEdgeStyle == .neon || usageStore.railEdgeStyle == .glass) {
                            sliderRow(
                                "Glow radius",
                                value: $usageStore.railGlowRadius,
                                range: 0...32,
                                step: 1,
                                valueText: "\(Int(usageStore.railGlowRadius.rounded())) pt"
                            )
                            sliderRow(
                                "Glow intensity",
                                value: $usageStore.railGlowOpacity,
                                range: 0...1,
                                step: 0.01,
                                valueText: "\(Int((usageStore.railGlowOpacity * 100).rounded()))%"
                            )
                        }

                        FullRowDisclosure(title: "Advanced Shape", isExpanded: $advancedShapeExpanded) {
                            VStack(spacing: 12) {
                                shapeSlider("Corner radius", value: $usageStore.railCornerRadius, range: 4...48, suffix: "pt")
                                shapeSlider("Curve depth", value: $usageStore.railScallopDepth, range: 0...42, suffix: "pt")
                                shapeSlider("Bubble radius", value: $usageStore.bubbleCornerRadius, range: 8...40, suffix: "pt")
                                shapeSlider("Bubble nub depth", value: $usageStore.bubblePointerDepth, range: 0...32, suffix: "pt")
                                shapeSlider("Bubble nub width", value: $usageStore.bubblePointerWidth, range: 6...56, suffix: "pt")
                            }
                        }
                    }
                    .padding(.top, 8)
                }

                Divider()

                settingsRow("Visible elements") {
                    HStack(spacing: 18) {
                        Toggle("Percentage", isOn: $usageStore.railShowPercent)
                        Toggle("Usage ring", isOn: $usageStore.railShowRing)
                        Toggle("Timer", isOn: $usageStore.railShowRemainingTime)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                settingsRow("Interaction") {
                    HStack(spacing: 18) {
                        Toggle("Multiplier ×N", isOn: $usageStore.railShowMultiplier)
                        Toggle("Hover details", isOn: $usageStore.railHoverEnabled)
                            .disabled(usageStore.railVisualOnlyMode)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                }

                FullRowDisclosure(title: "Rail Data & Timer", isExpanded: $dataExpanded) {
                    VStack(spacing: 12) {
                        settingsRow("Percent source", value: usageStore.railPercentSource.label) {
                            quotaPicker("Percent", selection: $usageStore.railPercentSource, allowNone: false)
                        }

                        settingsRow("Outer ring source", value: usageStore.railOuterRingSource.label) {
                            quotaPicker("Outer ring", selection: $usageStore.railOuterRingSource, allowNone: true)
                        }

                        settingsRow("Inner ring source", value: usageStore.railInnerRingSource.label) {
                            quotaPicker("Inner ring", selection: $usageStore.railInnerRingSource, allowNone: true)
                        }

                        settingsRow("Timer source", value: usageStore.railTimeSource.label) {
                            quotaPicker("Timer", selection: $usageStore.railTimeSource, allowNone: false)
                        }

                        settingsRow("Day digits", value: usageStore.railDayDigits.label) {
                            alignedDataControl {
                                Picker("Day digits", selection: $usageStore.railDayDigits) {
                                    ForEach(RailDigitWidth.allCases) { width in
                                        Text(width.label).tag(width)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 142)
                            }
                        }

                        settingsRow("Hour", value: hourModeBinding.wrappedValue.label) {
                            alignedDataControl {
                                Picker("Hour", selection: hourModeBinding) {
                                    ForEach(TimerFieldMode.allCases) { mode in
                                        Text(LocalizedStringKey(mode.label)).tag(mode)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 192)
                            }
                        }

                        settingsRow("Minute", value: minuteModeBinding.wrappedValue.label) {
                            alignedDataControl {
                                Picker("Minute", selection: minuteModeBinding) {
                                    ForEach(TimerFieldMode.allCases) { mode in
                                        Text(LocalizedStringKey(mode.label)).tag(mode)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.segmented)
                                .frame(width: 192)
                            }
                        }

                        settingsRow("Zero auto-hide") {
                            alignedDataControl {
                                HStack(spacing: 18) {
                                    Toggle("Days", isOn: $usageStore.railAutoHideZeroDays)
                                    Toggle("Hours", isOn: $usageStore.railAutoHideZeroHours)
                                }
                                .toggleStyle(.switch)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
        }
    }

    private func quotaPicker(
        _ title: LocalizedStringKey,
        selection: Binding<RailQuotaSource>,
        allowNone: Bool
    ) -> some View {
        alignedDataControl(title) {
            Picker(title, selection: selection) {
                ForEach(RailQuotaSource.allCases.filter { allowNone || $0 != .none }) { source in
                    Text(LocalizedStringKey(source.label)).tag(source)
                }
            }
            .labelsHidden()
            .frame(width: 104)
        }
    }

    private func digitPicker(_ suffix: String, selection: Binding<RailDigitWidth>) -> some View {
        HStack(spacing: 4) {
            Picker(suffix, selection: selection) {
                ForEach(RailDigitWidth.allCases) { width in
                    Text(width.label).tag(width)
                }
            }
            .labelsHidden()
            .frame(width: 66)
            Text(suffix)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func shapeSlider(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        suffix: String,
        multiplier: Double = 1
    ) -> some View {
        sliderRow(
            title,
            value: value,
            range: range,
            step: range.upperBound <= 1 ? 0.01 : 1,
            valueText: "\(Int((value.wrappedValue * multiplier).rounded()))\(suffix)"
        )
    }

    private var providerOrderSection: some View {
        GroupBox("Provider Order, Colors & Links") {
            VStack(spacing: 6) {
                ForEach(Array(usageStore.providerOrder.enumerated()), id: \.element) { index, provider in
                    HStack(spacing: 10) {
                        ProviderIcon(
                            provider: provider,
                            size: 19,
                            accentHex: usageStore.providerAccentHex[provider]
                        )
                        Text(provider.displayName)
                            .frame(width: 90, alignment: .leading)

                        ColorPicker(
                            "Accent",
                            selection: providerColorBinding(provider),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        .frame(width: 30)

                        Button("Reset") {
                            usageStore.setProviderAccent(nil, for: provider)
                        }
                        .controlSize(.small)
                        .help("Use default provider color")

                        TextField("Web URL", text: providerURLBinding(provider))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 260)
                            .help("Clicking this provider/account on the rail opens this URL unless the account has its own override.")

                        Spacer()

                        Button {
                            usageStore.moveProvider(provider, direction: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == 0)
                        .help("Move provider up")

                        Button {
                            usageStore.moveProvider(provider, direction: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(index == usageStore.providerOrder.count - 1)
                        .help("Move provider down")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.secondary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            .padding(.vertical, 6)
        }
    }

    private func providerURLBinding(_ provider: ProviderID) -> Binding<String> {
        Binding(
            get: { usageStore.providerWebURL(for: provider) },
            set: { usageStore.setProviderWebURL($0, for: provider) }
        )
    }

    private func providerColorBinding(_ provider: ProviderID) -> Binding<Color> {
        Binding(
            get: {
                ProviderBrand.color(hex: usageStore.providerAccentHex[provider])
                    ?? ProviderBrand.glow(for: provider)
            },
            set: { newColor in
                usageStore.setProviderAccent(ProviderBrand.hexString(from: newColor), for: provider)
            }
        )
    }
}

private struct ProviderSettingsSection: View {
    let provider: ProviderID
    @ObservedObject var usageStore: UsageStore
    @State private var isExpanded: Bool

    init(provider: ProviderID, usageStore: UsageStore) {
        self.provider = provider
        _usageStore = ObservedObject(wrappedValue: usageStore)
        let key = "UsageDock.settings.providerCollapsed.\(provider.rawValue).v1"
        let collapsed = UserDefaults.standard.object(forKey: key) == nil
            ? false
            : UserDefaults.standard.bool(forKey: key)
        _isExpanded = State(initialValue: !collapsed)
    }

    private var collapseKey: String {
        "UsageDock.settings.providerCollapsed.\(provider.rawValue).v1"
    }

    private var summary: ProviderUsageSummary {
        usageStore.summary(for: provider)
    }

    private var providerAccounts: [UsageAccount] {
        usageStore.visibleAccounts(for: provider)
    }

    private var hasCurrentSession: Bool {
        providerAccounts.contains { $0.source == .currentSession }
    }

    var body: some View {
        GroupBox {
            if isExpanded {
                VStack(alignment: .leading, spacing: 18) {
                statusRow
                displayOptions
                aggregateSummary

                Divider()

                ForEach($usageStore.accounts) { $account in
                    if account.provider == provider && usageStore.isAccountVisibleInCurrentBuild(account) {
                        AccountEditor(
                            account: $account,
                            statusText: usageStore.accountStatusText(for: account),
                            presentationMode: usageStore.presentationMode,
                            canMoveUp: canMove(account.id, direction: -1),
                            canMoveDown: canMove(account.id, direction: 1),
                            canConnectCredentialFile: UsageDockDistributionPolicy.allowsCredentialFileRegistration && provider.supportsLiveUsage && provider != .antigravity && account.source != .synthetic,
                            supportsMultiplier: provider == .claude || provider == .codex,
                            multiplierDetectionText: usageStore.multiplierDetectionText(for: account.id),
                            onMoveUp: { usageStore.moveAccount(account.id, direction: -1) },
                            onMoveDown: { usageStore.moveAccount(account.id, direction: 1) },
                            onAutoDetectMultiplier: {
                                usageStore.detectPlanMultiplier(accountID: account.id)
                            },
                            onRegenerateSynthetic: {
                                usageStore.regenerateSyntheticAccount(id: account.id)
                            },
                            onSetSyntheticRemainingFull: {
                                usageStore.setSyntheticRemainingFull(id: account.id)
                            },
                            onConnectCredentialFile: { path in
                                usageStore.connectCredentialFile(accountID: account.id, path: path)
                                Task { await usageStore.refreshLiveUsage() }
                            },
                            onDisconnectCredentialFile: {
                                usageStore.disconnectCredentialFile(accountID: account.id)
                            },
                            onDelete: {
                                usageStore.removeAccount(id: account.id)
                            }
                        )
                    }
                }

                HStack(spacing: 10) {
                    if provider.supportsProfileLogin {
                        Button {
                            _ = usageStore.launchLoginProfile(provider: provider)
                        } label: {
                            Label(provider == .antigravity ? "Open Antigravity Login" : "Login New Profile", systemImage: "person.crop.circle.badge.plus")
                        }
                        .help(provider == .antigravity
                              ? "Opens the official agy login. Antigravity uses its native macOS Keychain session; UsageDock refreshes it automatically after sign-in."
                              : "Opens the official CLI in Terminal with a UsageDock-only HOME so profiles stay separated.")
                    }

                    if provider.supportsLiveUsage {
                        Button {
                            if usageStore.registerCurrentSessionAccount(provider: provider) {
                                Task { await usageStore.refreshLiveUsage() }
                            }
                        } label: {
                            Label("Use Current Login", systemImage: "person.crop.circle.badge.checkmark")
                        }
                        .disabled(hasCurrentSession || !usageStore.canRegisterCurrentSession(provider: provider))
                        .help(loginHelp)
                    }

                    if UsageDockDistributionPolicy.allowsDevelopmentAccounts {
                        if provider == .codex {
                            Menu {
                                Button("Codex ×1") { usageStore.addSyntheticAccount(provider: .codex, multiplier: 1) }
                                Button("Codex ×5") { usageStore.addSyntheticAccount(provider: .codex, multiplier: 5) }
                                Button("Codex ×20") { usageStore.addSyntheticAccount(provider: .codex, multiplier: 20) }
                            } label: {
                                Label("Add Synthetic", systemImage: "sparkles")
                            }
                        } else {
                            Button {
                                usageStore.addSyntheticAccount(provider: provider, multiplier: provider == .claude ? 20 : 1)
                            } label: {
                                Label(provider == .claude ? "Add Synthetic ×20" : "Add Synthetic", systemImage: "sparkles")
                            }
                        }

                        Button {
                            usageStore.addAccount(provider: provider)
                        } label: {
                            Label("Add Account", systemImage: "plus")
                        }
                    } else if !provider.supportsProfileLogin && !provider.supportsLiveUsage {
                        Label("Login unavailable", systemImage: "lock")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
                .padding(.horizontal, 6)
                .padding(.vertical, 12)
            }
        } label: {
            Button {
                withAnimation(.easeInOut(duration: 0.16)) { isExpanded.toggle() }
                UserDefaults.standard.set(!isExpanded, forKey: collapseKey)
            } label: {
                HStack(spacing: 9) {
                    ProviderIcon(
                        provider: provider,
                        size: 17,
                        accentHex: usageStore.providerAccentHex[provider]
                    )
                    Text(provider.displayName)
                        .font(.headline)
                    Spacer()
                    Text("\(providerAccounts.count) accounts")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text(pressureText)
                        .font(.headline.monospacedDigit())
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 28)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var statusRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 7, height: 7)
            Text(usageStore.statusText(for: provider))
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var displayOptions: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Rail mode")
                    .font(.subheadline.weight(.semibold))
                Text(usageStore.fusionEnabled(for: provider)
                     ? "Fusion ON: enabled accounts are combined into one ring."
                     : "Fusion OFF: every enabled account gets its own ring.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if provider == .claude || provider == .codex {
                Text(usageStore.displayMultiplier(for: provider).map { "×\($0)" } ?? "--")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            Toggle(
                "Fusion",
                isOn: Binding(
                    get: { usageStore.fusionEnabled(for: provider) },
                    set: { usageStore.setFusionEnabled($0, for: provider) }
                )
            )
            .toggleStyle(.switch)
            .controlSize(.small)
        }
        .padding(10)
        .background(.secondary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
    }

    private var aggregateSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Combined quota windows · \(usageStore.presentationMode.label)")
                .font(.subheadline.weight(.semibold))

            if summary.aggregates.isEmpty {
                Text("No live quota data")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(summary.aggregates) { aggregate in
                    let displayed = usageStore.displayPercent(aggregate.percentUsed)
                    HStack(spacing: 12) {
                        Text(aggregate.label)
                            .lineLimit(1)
                            .frame(width: 145, alignment: .leading)

                        ProgressView(value: displayed ?? 0)
                            .frame(maxWidth: .infinity)

                        Text(percentText(displayed))
                            .font(.callout.monospacedDigit())
                            .frame(width: 48, alignment: .trailing)

                        Text(qualityText(aggregate.quality))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 92, alignment: .leading)
                    }
                }
            }
        }
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
        case .idle: return .secondary
        }
    }

    private var loginHelp: String {
        switch provider {
        case .claude: return "Uses the existing Claude Code login. Sign in in Claude Code first."
        case .codex: return "Uses the existing Codex login. Run codex login first if needed."
        case .antigravity: return "Uses the official Antigravity CLI (agy) and its native Google/Keychain authentication. Gemini CLI credentials are not used."
        case .kimi: return "Uses the existing Kimi Code OAuth login. Sign in with Kimi Code first."
        case .cursor:
            return UsageDockDistributionPolicy.isPublicRelease
                ? "Cursor account registration is unavailable until UsageDock has a verified login and live quota source."
                : "Cursor is currently manual/synthetic in UsageDock; configure its web URL and quota rows without fabricating a live API."
        case .grok:
            return UsageDockDistributionPolicy.isPublicRelease
                ? "Grok account registration is unavailable until UsageDock has a verified login and live quota source."
                : "Grok is currently manual/synthetic in UsageDock; configure its web URL and quota rows without fabricating a live API."
        }
    }

    private func canMove(_ id: UUID, direction: Int) -> Bool {
        let ids = providerAccounts.map(\.id)
        guard let index = ids.firstIndex(of: id) else { return false }
        let destination = index + (direction < 0 ? -1 : 1)
        return ids.indices.contains(destination)
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }

    private func qualityText(_ quality: AggregationQuality) -> String {
        switch quality {
        case .exact: return "Exact total"
        case .unweightedAverage: return "Avg fallback"
        case .unavailable: return "Unavailable"
        }
    }
}

private struct AccountEditor: View {
    @Binding var account: UsageAccount
    let statusText: String
    let presentationMode: UsagePresentationMode
    let canMoveUp: Bool
    let canMoveDown: Bool
    let canConnectCredentialFile: Bool
    let supportsMultiplier: Bool
    let multiplierDetectionText: String?
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onAutoDetectMultiplier: () -> Void
    let onRegenerateSynthetic: () -> Void
    let onSetSyntheticRemainingFull: () -> Void
    let onConnectCredentialFile: (String) -> Void
    let onDisconnectCredentialFile: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Toggle("", isOn: $account.isEnabled)
                    .labelsHidden()
                    .help("Show this account on the rail and include it in Fusion")

                TextField("Account name", text: $account.name)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 210)

                Text(sourceLabel)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: Capsule())

                ColorPicker("Accent", selection: accountColorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 30)
                    .help("Account ring color")

                Button("Reset") {
                    account.accentHex = nil
                }
                .controlSize(.small)
                .help("Use provider color")

                Button(action: onMoveUp) {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
                .help("Move account up")

                Button(action: onMoveDown) {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
                .help("Move account down")

                Spacer()

                if canConnectCredentialFile && account.source != .currentSession {
                    Button {
                        chooseCredentialFile()
                    } label: {
                        Label(account.source == .credentialFile ? "Change File" : "Connect File", systemImage: "doc.badge.gearshape")
                    }
                    .controlSize(.small)

                    if account.source == .credentialFile {
                        Button("Disconnect", action: onDisconnectCredentialFile)
                            .controlSize(.small)
                    }
                }

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Remove account")
                .accessibilityLabel("Remove account")
            }

            HStack(spacing: 8) {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)

                if let credentialFileName {
                    Text(credentialFileName)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
            .padding(.leading, 30)

            HStack(spacing: 8) {
                Text("Web")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField("Use provider URL", text: accountWebURLBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 360)
                if account.webURL?.isEmpty == false {
                    Button("Use provider default") { account.webURL = nil }
                        .controlSize(.small)
                }
                Spacer()
            }
            .padding(.leading, 30)

            railDisplayControls
                .padding(.leading, 30)

            if supportsMultiplier {
                multiplierControls
                    .padding(.leading, 30)
            }

            if account.source == .synthetic {
                syntheticControls
                    .padding(.leading, 30)
            }

            if !account.buckets.isEmpty && account.source != .synthetic {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Quota rows")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach($account.buckets) { $bucket in
                        HStack(spacing: 8) {
                            Toggle("", isOn: $bucket.isEnabled)
                                .labelsHidden()
                                .controlSize(.mini)

                            Text(bucket.label)
                                .font(.caption.weight(.medium))
                                .frame(width: 100, alignment: .leading)
                                .lineLimit(1)

                            Text(percentText(displayPercent(bucket.resolvedPercentUsed)))
                                .font(.caption.monospacedDigit())
                                .frame(width: 44, alignment: .trailing)

                            Spacer()

                            Button {
                                moveBucket(bucket.id, direction: -1)
                            } label: {
                                Image(systemName: "chevron.up")
                            }
                            .buttonStyle(.borderless)
                            .disabled(account.buckets.first?.id == bucket.id)

                            Button {
                                moveBucket(bucket.id, direction: 1)
                            } label: {
                                Image(systemName: "chevron.down")
                            }
                            .buttonStyle(.borderless)
                            .disabled(account.buckets.last?.id == bucket.id)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(.leading, 30)
            }
        }
        .padding(14)
        .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var railDisplayControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rail display override")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                accountQuotaPicker("Percent", selection: $account.railPercentSource, allowNone: false)
                accountQuotaPicker("Outer", selection: $account.railOuterRingSource, allowNone: true)
                accountQuotaPicker("Inner", selection: $account.railInnerRingSource, allowNone: true)
                accountQuotaPicker("Timer", selection: $account.railTimeSource, allowNone: false)
                Spacer()
            }

            Text("Global follows the Display defaults. Override only this account when, for example, Codex should show 1w while Kimi shows 5h.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    private func accountQuotaPicker(
        _ title: String,
        selection: Binding<RailQuotaSource?>,
        allowNone: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                Text("Global").tag(Optional<RailQuotaSource>.none)
                ForEach(RailQuotaSource.allCases.filter { allowNone || $0 != .none }) { source in
                    Text(LocalizedStringKey(source.label)).tag(Optional<RailQuotaSource>.some(source))
                }
            }
            .labelsHidden()
            .frame(width: 104)
        }
    }

    private var syntheticControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Synthetic usage")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Synthetic usage", selection: syntheticModeBinding) {
                    ForEach(SyntheticUsageMode.allCases) { mode in
                        Text(LocalizedStringKey(mode.label)).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)

                if account.syntheticMode != .manual {
                    Button("Regenerate", action: onRegenerateSynthetic)
                        .controlSize(.small)
                }

                Button("Remaining 100%", action: onSetSyntheticRemainingFull)
                    .controlSize(.small)
            }

            if account.syntheticMode == .manual {
                ForEach($account.buckets) { $bucket in
                    HStack(spacing: 10) {
                        Toggle("", isOn: $bucket.isEnabled)
                            .labelsHidden()
                            .controlSize(.mini)

                        Text(bucket.label)
                            .font(.caption)
                            .frame(width: 70, alignment: .leading)
                        Slider(value: syntheticPercentBinding($bucket), in: 0...100, step: 1)
                            .frame(maxWidth: 260)
                        TextField("%", value: syntheticPercentIntegerBinding($bucket), format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 58)
                        Text("%")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            moveBucket(bucket.id, direction: -1)
                        } label: {
                            Image(systemName: "chevron.up")
                        }
                        .buttonStyle(.borderless)
                        .disabled(account.buckets.first?.id == bucket.id)

                        Button {
                            moveBucket(bucket.id, direction: 1)
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .buttonStyle(.borderless)
                        .disabled(account.buckets.last?.id == bucket.id)
                    }
                }
            } else {
                HStack(spacing: 8) {
                    ForEach(account.buckets) { bucket in
                        Text("\(bucket.label) \(percentText(displayPercent(bucket.resolvedPercentUsed)))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var multiplierControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("Plan")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Multiplier", value: multiplierBinding, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)

                Text("×")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Button("Auto", action: onAutoDetectMultiplier)
                    .controlSize(.small)
                    .disabled(account.source == .synthetic || account.source == .manual || account.source == nil)

                Text(account.multiplierMode == .automatic ? "Auto" : "Manual")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }

            if let multiplierDetectionText {
                Text(multiplierDetectionText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var syntheticModeBinding: Binding<SyntheticUsageMode> {
        Binding(
            get: { account.syntheticMode ?? .random },
            set: { mode in
                account.syntheticMode = mode
                if mode == .random { onRegenerateSynthetic() }
            }
        )
    }

    private func syntheticPercentBinding(_ bucket: Binding<UsageBucket>) -> Binding<Double> {
        Binding(
            get: { (bucket.wrappedValue.resolvedPercentUsed ?? 0) * 100 },
            set: { value in
                bucket.wrappedValue.used = nil
                bucket.wrappedValue.limit = nil
                bucket.wrappedValue.percentUsed = min(max(value / 100, 0), 1)
                account.syntheticMode = .manual
            }
        )
    }

    private func syntheticPercentIntegerBinding(_ bucket: Binding<UsageBucket>) -> Binding<Int> {
        Binding(
            get: { Int(((bucket.wrappedValue.resolvedPercentUsed ?? 0) * 100).rounded()) },
            set: { value in
                bucket.wrappedValue.used = nil
                bucket.wrappedValue.limit = nil
                bucket.wrappedValue.percentUsed = Double(min(max(value, 0), 100)) / 100
                account.syntheticMode = .manual
            }
        )
    }

    private var accountWebURLBinding: Binding<String> {
        Binding(
            get: { account.webURL ?? "" },
            set: { value in
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                account.webURL = trimmed.isEmpty ? nil : trimmed
            }
        )
    }

    private func moveBucket(_ id: UUID, direction: Int) {
        guard let index = account.buckets.firstIndex(where: { $0.id == id }) else { return }
        let destination = index + (direction < 0 ? -1 : 1)
        guard account.buckets.indices.contains(destination) else { return }
        account.buckets.swapAt(index, destination)
    }

    private var multiplierBinding: Binding<Int> {
        Binding(
            get: { max(account.planMultiplier ?? 1, 1) },
            set: { newValue in
                account.planMultiplier = min(max(newValue, 1), 999)
                account.multiplierMode = .manual
            }
        )
    }

    private var accountColorBinding: Binding<Color> {
        Binding(
            get: {
                ProviderBrand.color(hex: account.accentHex)
                    ?? ProviderBrand.glow(for: account.provider)
            },
            set: { newColor in
                account.accentHex = ProviderBrand.hexString(from: newColor)
            }
        )
    }

    private var sourceLabel: String {
        switch account.source {
        case .currentSession: return "Current login"
        case .credentialFile: return "Credential file"
        case .profile: return "UsageDock profile"
        case .manual: return "Account slot"
        case .synthetic: return "Account"
        case .mock: return "Mock"
        case nil: return "Legacy"
        }
    }

    private var credentialFileName: String? {
        guard account.source == .credentialFile || account.source == .profile, let path = account.credentialPath else { return nil }
        let url = URL(fileURLWithPath: path)
        return "…/\(url.deletingLastPathComponent().lastPathComponent)/\(url.lastPathComponent)"
    }

    private func chooseCredentialFile() {
        let panel = NSOpenPanel()
        panel.title = "Choose \(account.provider.displayName) credential JSON"
        panel.message = credentialHelpText
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]

        if panel.runModal() == .OK, let url = panel.url {
            onConnectCredentialFile(url.path)
        }
    }

    private var credentialHelpText: String {
        switch account.provider {
        case .claude:
            return "Choose a Claude Code .credentials.json from the account/profile you want to track."
        case .codex:
            return "Choose a Codex auth.json from the account/profile you want to track."
        case .antigravity:
            return "Direct Antigravity credential import is disabled until a provider-specific login boundary is verified."
        case .kimi:
            return "Choose a Kimi Code OAuth credential JSON from ~/.kimi-code/credentials or another Kimi Code profile."
        case .cursor, .grok:
            return "No live credential adapter is configured for this provider. Use manual or synthetic usage instead."
        }
    }

    private func displayPercent(_ used: Double?) -> Double? {
        guard let used else { return nil }
        let clamped = min(max(used, 0), 1)
        return presentationMode == .used ? clamped : 1 - clamped
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }
}

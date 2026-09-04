import AppKit
import Combine
import SwiftUI

@main
struct UsageDockApp: App {
    @StateObject private var usageStore: UsageStore
    @StateObject private var placement: PlacementStore
    private let panelController: DockPanelController
    private let settingsController: SettingsWindowController
    private let menuBarController: MenuBarStatusController

    init() {
        let usageStore = UsageStore()
        let placement = PlacementStore()
        let settingsController = SettingsWindowController(
            usageStore: usageStore,
            placement: placement
        )
        let panelController = DockPanelController(
            usageStore: usageStore,
            placement: placement,
            onOpenSettings: { settingsController.show() }
        )
        let menuBarController = MenuBarStatusController(
            usageStore: usageStore,
            placement: placement,
            onOpenSettings: { settingsController.show() }
        )

        _usageStore = StateObject(wrappedValue: usageStore)
        _placement = StateObject(wrappedValue: placement)
        self.panelController = panelController
        self.settingsController = settingsController
        self.menuBarController = menuBarController

        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.accessory)
            panelController.show()
            usageStore.startAutoRefresh()
        }
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class MenuBarStatusController: NSObject {
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private let usageStore: UsageStore
    private let placement: PlacementStore
    private let onOpenSettings: () -> Void
    private var cancellables = Set<AnyCancellable>()

    init(
        usageStore: UsageStore,
        placement: PlacementStore,
        onOpenSettings: @escaping () -> Void
    ) {
        self.usageStore = usageStore
        self.placement = placement
        self.onOpenSettings = onOpenSettings
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        configureStatusItem()
        configurePopover()
        observeUsageChanges()
        refreshStatusItem()
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "UsageDock"
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = NSSize(width: 390, height: 430)
        popover.contentViewController = NSHostingController(
            rootView: MenuBarPopoverContent(
                usageStore: usageStore,
                placement: placement,
                onOpenSettings: onOpenSettings
            )
            .environment(\.locale, usageStore.appLanguage.locale)
        )
    }

    private func observeUsageChanges() {
        usageStore.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async {
                    self?.refreshStatusItem()
                }
            }
            .store(in: &cancellables)
    }

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        let items = usageStore.menuBarUsageItems()
        let shouldRenderUsage = usageStore.menuBarUsageEnabled
            && !items.isEmpty
            && (usageStore.menuBarShowRing || usageStore.menuBarShowPercentage)

        guard shouldRenderUsage else {
            let image = NSImage(
                systemSymbolName: "gauge.with.dots.needle.67percent",
                accessibilityDescription: "UsageDock"
            )
            image?.isTemplate = true
            button.image = image
            button.title = ""
            button.setAccessibilityLabel("UsageDock")
            return
        }

        let label = MenuBarStatusLabel(
            items: items,
            showRing: usageStore.menuBarShowRing,
            showPercentage: usageStore.menuBarShowPercentage
        )
        let renderer = ImageRenderer(content: label.fixedSize())
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2

        if let image = renderer.nsImage {
            image.isTemplate = false
            button.image = image
            button.title = ""
            button.setAccessibilityLabel(accessibilityLabel(for: items))
        } else {
            let fallback = NSImage(
                systemSymbolName: "gauge.with.dots.needle.67percent",
                accessibilityDescription: "UsageDock"
            )
            fallback?.isTemplate = true
            button.image = fallback
            button.title = ""
        }
    }

    private func accessibilityLabel(for items: [MenuBarUsageItem]) -> String {
        let values = items.map { item in
            let percent = item.percent.map { "\(Int(($0 * 100).rounded())) percent" } ?? "unavailable"
            return "\(item.provider.displayName) \(item.accountName), \(percent)"
        }
        return "UsageDock, " + values.joined(separator: ", ")
    }

    @objc
    private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }
}

private struct MenuBarStatusLabel: View {
    let items: [MenuBarUsageItem]
    let showRing: Bool
    let showPercentage: Bool

    var body: some View {
        HStack(spacing: 5) {
            ForEach(items) { item in
                HStack(spacing: 2.5) {
                    if showRing {
                        CompactUsageRing(
                            percent: item.percent,
                            accent: accentColor(for: item),
                            diameter: 12,
                            lineWidth: 2
                        )
                    }
                    if showPercentage {
                        Text(percentText(item.percent))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .foregroundStyle(accentColor(for: item))
                    }
                }
            }
        }
        .frame(height: 18)
        .padding(.horizontal, 1)
    }

    private func accentColor(for item: MenuBarUsageItem) -> Color {
        ProviderBrand.glow(for: item.provider, customHex: item.accentHex, theme: .dark)
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }
}

private struct CompactUsageRing: View {
    let percent: Double?
    let accent: Color
    let diameter: CGFloat
    let lineWidth: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .stroke(accent.opacity(percent == nil ? 0.22 : 0.20), lineWidth: lineWidth)
            if let percent {
                Circle()
                    .trim(from: 0, to: min(max(percent, 0), 1))
                    .stroke(accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct MenuBarPopoverContent: View {
    @ObservedObject var usageStore: UsageStore
    @ObservedObject var placement: PlacementStore
    let onOpenSettings: () -> Void

    private var items: [MenuBarUsageItem] { usageStore.menuBarUsageItems() }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.65)

            ScrollView {
                VStack(spacing: 9) {
                    if items.isEmpty {
                        emptyState
                    } else {
                        ForEach(items) { item in
                            usageRow(item)
                        }
                    }
                }
                .padding(14)
            }
            .frame(minHeight: 190, maxHeight: 285)

            Divider().opacity(0.65)
            controls
        }
        .frame(width: 390)
        .background(.regularMaterial)
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .font(.system(size: 16, weight: .semibold))
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text("UsageDock")
                    .font(.system(size: 14, weight: .semibold))
                Text(usageStore.isRefreshing ? "Refreshing usage…" : "Live account usage")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await usageStore.refreshLiveUsage() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .disabled(usageStore.isRefreshing)
            .help("Refresh Now")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var emptyState: some View {
        VStack(spacing: 9) {
            Image(systemName: "menubar.rectangle")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(.secondary)
            Text("No menu-bar accounts selected")
                .font(.system(size: 13, weight: .semibold))
            Text("Choose accounts in Settings → Menu Bar. Rail display selection stays independent.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
            Button("Open Settings") { onOpenSettings() }
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private func usageRow(_ item: MenuBarUsageItem) -> some View {
        let accent = ProviderBrand.glow(for: item.provider, customHex: item.accentHex, theme: usageStore.theme)
        return HStack(spacing: 11) {
            ZStack {
                Circle().fill(accent.opacity(0.10))
                ProviderIcon(
                    provider: item.provider,
                    size: 20,
                    accentHex: item.accentHex,
                    theme: usageStore.theme
                )
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.accountName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Text(item.provider.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            CompactUsageRing(percent: item.percent, accent: accent, diameter: 30, lineWidth: 3.2)
            Text(percentText(item.percent))
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(item.percent == nil ? Color.secondary : accent)
                .frame(width: 42, alignment: .trailing)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(Color.primary.opacity(0.045))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(accent.opacity(0.13), lineWidth: 0.7)
                }
        )
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    placement.edge = placement.edge == .right ? .left : .right
                } label: {
                    Label(
                        placement.edge == .right ? "Move Left" : "Move Right",
                        systemImage: placement.edge == .right
                            ? "rectangle.lefthalf.inset.filled"
                            : "rectangle.righthalf.inset.filled"
                    )
                    .frame(maxWidth: .infinity)
                }

                Button {
                    onOpenSettings()
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                        .frame(maxWidth: .infinity)
                }
            }
            .controlSize(.small)

            HStack {
                Text("\(items.count) menu-bar account\(items.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit UsageDock") {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .padding(12)
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }
}

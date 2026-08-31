import AppKit
import SwiftUI

@main
struct UsageDockApp: App {
    @StateObject private var usageStore: UsageStore
    @StateObject private var placement: PlacementStore
    private let panelController: DockPanelController
    private let settingsController: SettingsWindowController

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

        _usageStore = StateObject(wrappedValue: usageStore)
        _placement = StateObject(wrappedValue: placement)
        self.panelController = panelController
        self.settingsController = settingsController

        DispatchQueue.main.async {
            NSApplication.shared.setActivationPolicy(.accessory)
            panelController.show()
            usageStore.startAutoRefresh()
        }
    }

    var body: some Scene {
        MenuBarExtra("UsageDock", systemImage: "gauge.with.dots.needle.67percent") {
            MenuBarContent(
                usageStore: usageStore,
                placement: placement,
                onOpenSettings: { settingsController.show() }
            )
            .environment(\.locale, usageStore.appLanguage.locale)
        }
        .menuBarExtraStyle(.menu)
    }
}

private struct MenuBarContent: View {
    @ObservedObject var usageStore: UsageStore
    @ObservedObject var placement: PlacementStore
    let onOpenSettings: () -> Void

    var body: some View {
        ForEach(usageStore.summaries()) { summary in
            HStack(spacing: 8) {
                ProviderIcon(provider: summary.provider, size: 14)
                Text(summary.provider.displayName)
                Spacer()
                Text(percentText(summary.pressurePercent))
                    .monospacedDigit()
            }
        }

        Divider()

        Button {
            Task { await usageStore.refreshLiveUsage() }
        } label: {
            Label(usageStore.isRefreshing ? "Refreshing…" : "Refresh Now", systemImage: "arrow.clockwise")
        }
        .disabled(usageStore.isRefreshing)

        Button {
            placement.edge = placement.edge == .right ? .left : .right
        } label: {
            Label(
                placement.edge == .right ? "Move to Left" : "Move to Right",
                systemImage: placement.edge == .right ? "rectangle.lefthalf.inset.filled" : "rectangle.righthalf.inset.filled"
            )
        }

        Button {
            onOpenSettings()
        } label: {
            Label("Settings…", systemImage: "slider.horizontal.3")
        }

        Divider()

        Button("Quit UsageDock") {
            NSApplication.shared.terminate(nil)
        }
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "--" }
        return "\(Int((value * 100).rounded()))%"
    }
}

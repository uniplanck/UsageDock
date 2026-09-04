import AppKit
import Combine
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private let windowSize = NSSize(width: 1040, height: 780)
    private let usageStore: UsageStore
    private var cancellables = Set<AnyCancellable>()

    init(usageStore: UsageStore, placement: PlacementStore) {
        self.usageStore = usageStore
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: windowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = usageStore.appLanguage.settingsWindowTitle
        window.minSize = NSSize(width: 1000, height: 660)
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: SettingsView(usageStore: usageStore, placement: placement)
        )

        super.init(window: window)
        window.delegate = self
        usageStore.$appLanguage
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak window] language in
                window?.title = language.settingsWindowTitle
            }
            .store(in: &cancellables)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        window.title = usageStore.appLanguage.settingsWindowTitle
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        usageStore.settingsBubblePreviewRequested = false
    }
}

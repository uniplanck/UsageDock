import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ProviderOpenTargetSettings: View {
    let provider: ProviderID
    @ObservedObject var usageStore: UsageStore
    @State private var runningApps: [ProviderAppSelection] = []
    @State private var invalidAppSelection = false

    private var preference: ProviderOpenPreference { usageStore.openPreference(for: provider) }

    private var resolvedApp: ProviderAppSelection? {
        if case .app(let app) = usageStore.openResolution(for: .provider(provider)) { return app }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("On click")
                Picker("On click", selection: Binding(
                    get: { preference.mode },
                    set: { usageStore.setOpenMode($0, for: provider) }
                )) {
                    Text("App").tag(ProviderOpenMode.app)
                    Text("Link").tag(ProviderOpenMode.link)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 180)
                Spacer(minLength: 0)
            }

            if preference.mode == .app {
                appSelection
                if invalidAppSelection {
                    statusLabel("Select a valid .app application with an executable.")
                } else if let status = usageStore.openStatus(for: provider) {
                    statusLabel(LocalizedStringKey(status.message))
                }
            } else if let status = usageStore.openStatus(for: provider) {
                statusLabel(LocalizedStringKey(status.message))
            }

            HStack(spacing: 12) {
                Text(preference.mode == .app ? "Fallback URL" : "Web URL")
                    .frame(width: 100, alignment: .leading)
                TextField(provider.defaultWebURL, text: Binding(
                    get: { usageStore.providerWebURL(for: provider) },
                    set: { usageStore.setProviderWebURL($0, for: provider) }
                ))
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel(Text("Web URL"))
                .help("Account URLs take priority. Empty or invalid URLs use the provider default.")
                Button("Use Default URL") {
                    usageStore.setProviderWebURL(provider.defaultWebURL, for: provider)
                }
                .controlSize(.small)
            }
        }
        .onChange(of: preference) { _, _ in invalidAppSelection = false }
        .onAppear(perform: refreshApps)
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            refreshApps()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            refreshApps()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshApps()
        }
    }

    private var appSelection: some View {
        let app = resolvedApp ?? preference.app
        return HStack(spacing: 12) {
            Group {
                if let resolvedApp {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: resolvedApp.path))
                        .resizable()
                } else {
                    Image(systemName: "app.dashed")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .scaledToFit()
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(app?.name ?? "\(provider.defaultAppName).app")
                    .lineLimit(1)
                    .help(app?.path ?? "\(provider.defaultAppName).app")
                Text(preference.app == nil ? "Default App" : "Selected App")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Menu("Choose App…") {
                Button("Use Default App") {
                    usageStore.setSelectedApp(nil, for: provider)
                    invalidAppSelection = false
                }
                Menu("Running Apps") {
                    if runningApps.isEmpty {
                        Text("No running apps available")
                    }
                    ForEach(runningApps) { app in
                        Button {
                            usageStore.setSelectedApp(app, for: provider)
                            invalidAppSelection = false
                        } label: {
                            Label {
                                Text(app.name)
                            } icon: {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: app.path))
                                    .resizable()
                                    .frame(width: 16, height: 16)
                            }
                        }
                        .help(app.path)
                    }
                }
                Divider()
                Button("Choose .app…", action: chooseApp)
            }
            .fixedSize()
        }
    }

    private func statusLabel(_ message: LocalizedStringKey) -> some View {
        Label(message, systemImage: "exclamationmark.triangle")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func refreshApps() {
        runningApps = usageStore.runningApplications()
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.title = usageStore.appLanguage.localized("Choose an Application")
        panel.prompt = usageStore.appLanguage.localized("Choose App")
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let app = usageStore.applicationSelection(at: url) else {
            invalidAppSelection = true
            return
        }
        usageStore.setSelectedApp(app, for: provider)
        invalidAppSelection = false
    }
}

import AppKit
import Foundation

enum ProviderOpenMode: String, Codable, CaseIterable {
    case app
    case link
}

struct ProviderAppSelection: Codable, Equatable, Identifiable {
    let bundleIdentifier: String?
    let path: String
    let name: String

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
}

struct ProviderOpenPreference: Codable, Equatable {
    var mode: ProviderOpenMode = .app
    /// nil means resolve the provider's default app at click time.
    var app: ProviderAppSelection?
}

enum ProviderOpenResolution: Equatable {
    case app(ProviderAppSelection)
    case link(URL, appUnavailable: Bool)
}

enum ProviderOpenStatus {
    case appUnavailable
    case appLaunchFailed
    case linkOpenFailed

    var message: String {
        switch self {
        case .appUnavailable: "App not found. Clicks open the link. Choose another app or use the default."
        case .appLaunchFailed: "App could not open. Using the link. Choose another app or try again."
        case .linkOpenFailed: "Link could not open. Check the URL and your default browser."
        }
    }
}

extension ProviderID {
    var defaultAppName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "ChatGPT"
        case .antigravity: "Antigravity"
        case .kimi: "Kimi Code"
        case .cursor: "Cursor"
        case .grok: "Grok Bot"
        }
    }
}

@MainActor
protocol ProviderAppLocating {
    func application(at url: URL) -> ProviderAppSelection?
    func application(bundleIdentifier: String) -> ProviderAppSelection?
    func application(named name: String) -> ProviderAppSelection?
    func runningApplications() -> [ProviderAppSelection]
}

@MainActor
struct ProviderOpenResolver {
    let locator: any ProviderAppLocating

    func resolve(
        provider: ProviderID,
        preference: ProviderOpenPreference,
        linkURL: URL
    ) -> ProviderOpenResolution {
        guard preference.mode == .app else { return .link(linkURL, appUnavailable: false) }

        if let selected = preference.app {
            // Honor the selected copy first, but never launch an unrelated app
            // that subsequently occupies the same path.
            if let app = locator.application(at: selected.url),
               selected.bundleIdentifier == nil || app.bundleIdentifier == selected.bundleIdentifier {
                return .app(app)
            }
            if let id = selected.bundleIdentifier,
               let app = locator.application(bundleIdentifier: id),
               app.bundleIdentifier == id {
                return .app(app)
            }
            // A missing explicit selection must not silently become another app.
        } else if let app = locator.application(named: provider.defaultAppName) {
            return .app(app)
        }
        return .link(linkURL, appUnavailable: true)
    }
}

@MainActor
final class WorkspaceProviderAppLocator: ProviderAppLocating {
    private let applicationDirectories: [URL]

    init(applicationDirectories: [URL]? = nil) {
        self.applicationDirectories = applicationDirectories ?? [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true)
        ]
    }

    func application(at url: URL) -> ProviderAppSelection? {
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              info["CFBundlePackageType"] as? String == "APPL",
              let executable = info["CFBundleExecutable"] as? String,
              FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/MacOS/\(executable)").path)
        else { return nil }

        return ProviderAppSelection(
            bundleIdentifier: info["CFBundleIdentifier"] as? String,
            path: url.standardizedFileURL.path,
            name: info["CFBundleDisplayName"] as? String
                ?? info["CFBundleName"] as? String
                ?? url.deletingPathExtension().lastPathComponent
        )
    }

    func application(bundleIdentifier: String) -> ProviderAppSelection? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else { return nil }
        return application(at: url)
    }

    func application(named name: String) -> ProviderAppSelection? {
        // Read identifiers from the installed bundles, including Grok Bot.app.
        // These products can be wrappers with identifiers unrelated to the brand.
        for directory in applicationDirectories {
            if let app = application(at: directory.appendingPathComponent("\(name).app")) { return app }
        }
        return runningApplications().first {
            $0.url.deletingPathExtension().lastPathComponent.caseInsensitiveCompare(name) == .orderedSame
                || $0.name.caseInsensitiveCompare(name) == .orderedSame
        }
    }

    func runningApplications() -> [ProviderAppSelection] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .compactMap { $0.bundleURL.flatMap(application(at:)) }
            .filter { seen.insert($0.path).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

@MainActor
protocol ProviderTargetOpening {
    func openApplication(at url: URL) async throws
    func openLink(_ url: URL) -> Bool
}

@MainActor
struct WorkspaceProviderTargetOpener: ProviderTargetOpening {
    func openApplication(at url: URL) async throws {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    func openLink(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }
}

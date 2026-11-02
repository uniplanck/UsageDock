import Foundation
import UserNotifications

enum ClaudeKeychainProbe {
    enum Result: Equatable {
        case success(Data)
        case interactionRequired
        case unavailable
    }

    /// Use the same read-only CLI path for refresh and explicit import. The
    /// runner is injectable so tests never need the real Keychain binary.
    static func check(
        service: String,
        run: (URL, [String], TimeInterval) -> ProviderKeychainReader.Result = {
            ProviderKeychainReader.run($0, $1, timeout: $2)
        }
    ) -> Result {
        let result = run(URL(fileURLWithPath: "/usr/bin/security"),
                         ["find-generic-password", "-s", service, "-w"], 5)
        switch result {
        case .exited(status: 0, data: let data): return .success(data)
        case .exited(status: 36, data: _), .exited(status: 51, data: _),
             .exited(status: 128, data: _), .timedOut: return .interactionRequired
        case .exited, .unavailable: return .unavailable
        }
    }
}

/// Uses injected callbacks in tests; the real notification APIs are never
/// invoked unless the app encounters an actual missing/blocked source.
@MainActor
final class KeychainWarningNotifier {
    private static let requestedKey = "UsageDock.keychainNotificationAuthorizationRequested.v1"
    private static let lastSentKey = "UsageDock.keychainNotificationLastSent.v1"
    private let defaults: UserDefaults
    private let now: () -> Date
    private let requestAuthorization: (@escaping (Bool) -> Void) -> Void
    private let deliver: () -> Void

    init(defaults: UserDefaults, now: @escaping () -> Date = Date.init,
         requestAuthorization: @escaping (@escaping (Bool) -> Void) -> Void = { completion in
             UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in completion(granted) }
         },
         deliver: @escaping () -> Void = {
             let content = UNMutableNotificationContent()
             content.title = "UsageDock: キーチェーンの許可が必要です"
             content.body = "Claude の資格情報を取得できません。UsageDock の設定で接続状態を確認してください。"
             UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil))
         }) {
        self.defaults = defaults
        self.now = now
        self.requestAuthorization = requestAuthorization
        self.deliver = deliver
    }

    func warn() {
        let timestamp = now().timeIntervalSince1970
        if defaults.object(forKey: Self.lastSentKey) != nil,
           timestamp - defaults.double(forKey: Self.lastSentKey) < 3_600 { return }
        defaults.set(timestamp, forKey: Self.lastSentKey)
        if defaults.bool(forKey: Self.requestedKey) {
            deliver()
        } else {
            defaults.set(true, forKey: Self.requestedKey)
            requestAuthorization { [deliver] granted in
                if granted { deliver() }
            }
        }
    }
}

import Foundation
import LocalAuthentication
import Security
import UserNotifications

enum ClaudeKeychainProbe {
    struct Result {
        let status: OSStatus
        let data: Data?
    }

    /// Called only by the explicit Settings button. Authentication UI is
    /// forbidden even there; the caller can persist only a minimal access copy.
    static func check(service: String,
                      copyMatching: (CFDictionary, UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus = SecItemCopyMatching) -> Result {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne,
            kSecUseAuthenticationContext: context
        ]
        var item: CFTypeRef?
        let status = copyMatching(query as CFDictionary, &item)
        return Result(status: status, data: status == errSecSuccess ? item as? Data : nil)
    }

    static func requiresInteraction(_ status: OSStatus) -> Bool {
        status == errSecInteractionNotAllowed || status == errSecAuthFailed
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

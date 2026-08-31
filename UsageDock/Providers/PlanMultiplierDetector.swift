import Foundation
import Security

struct PlanMultiplierDetection: Equatable {
    let multiplier: Int?
    let detail: String
}

enum ProviderPlanMultiplierDetector {
    static func detect(for account: UsageAccount) -> PlanMultiplierDetection {
        guard account.provider == .claude || account.provider == .codex else {
            return PlanMultiplierDetection(multiplier: nil, detail: "Automatic multiplier detection is available for Claude and Codex.")
        }
        guard account.source == .currentSession || account.source == .credentialFile else {
            return PlanMultiplierDetection(multiplier: nil, detail: "Connect or register a real provider login before using Auto.")
        }

        guard let data = credentialData(for: account) else {
            return PlanMultiplierDetection(multiplier: nil, detail: "Provider credential metadata could not be read.")
        }

        var strings = jsonStrings(in: data)
        if account.provider == .codex,
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let tokens = object["tokens"] as? [String: Any],
           let token = tokens["access_token"] as? String {
            strings.append(contentsOf: jwtStrings(token))
        }

        if let multiplier = explicitMultiplier(in: strings) {
            return PlanMultiplierDetection(
                multiplier: multiplier,
                detail: "Auto detected ×\(multiplier) from provider-owned plan metadata."
            )
        }

        if account.provider == .codex,
           let plan = strings.first(where: { value in
               let normalized = value.lowercased()
               return normalized == "free" || normalized == "plus" || normalized == "pro" || normalized == "prolite" || normalized.contains("team") || normalized.contains("business")
           }) {
            return PlanMultiplierDetection(
                multiplier: nil,
                detail: "Codex plan metadata is \(plan), but it does not encode a numeric × multiplier. Keep a manual value."
            )
        }

        return PlanMultiplierDetection(
            multiplier: nil,
            detail: "No trustworthy ×5/×20 value was encoded in the provider credential metadata."
        )
    }

    static func hasCurrentSession(for provider: ProviderID) -> Bool {
        switch provider {
        case .claude:
            guard let data = claudeCurrentCredentialData() else { return false }
            return jsonStrings(in: data).contains { !$0.isEmpty }
        case .codex:
            guard let data = fileData(".codex/auth.json"),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tokens = object["tokens"] as? [String: Any],
                  let token = tokens["access_token"] as? String else { return false }
            return !token.isEmpty
        case .kimi:
            return FileManager.default.fileExists(
                atPath: FileManager.default.homeDirectoryForCurrentUser
                    .appendingPathComponent(".kimi-code/credentials", isDirectory: true).path
            )
        case .antigravity, .cursor, .grok:
            return false
        }
    }

    private static func credentialData(for account: UsageAccount) -> Data? {
        if account.source == .credentialFile, let path = account.credentialPath {
            return try? Data(contentsOf: URL(fileURLWithPath: path))
        }
        switch account.provider {
        case .claude:
            return claudeCurrentCredentialData()
        case .codex:
            return fileData(".codex/auth.json")
        case .kimi, .antigravity, .cursor, .grok:
            return nil
        }
    }

    private static func claudeCurrentCredentialData() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Claude Code-credentials",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
           let data = result as? Data {
            return data
        }
        return fileData(".claude/.credentials.json")
    }

    private static func fileData(_ relativePath: String) -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(relativePath)
        return try? Data(contentsOf: url)
    }

    private static func explicitMultiplier(in values: [String]) -> Int? {
        let normalized = values.map { $0.lowercased().replacingOccurrences(of: "×", with: "x") }
        for value in normalized {
            if value.contains("20x") || value.contains("max_20") || value.contains("max-20") || value.contains("max 20") {
                return 20
            }
        }
        for value in normalized {
            if value.contains("5x") || value.contains("max_5") || value.contains("max-5") || value.contains("max 5") {
                return 5
            }
        }
        return nil
    }

    private static func jsonStrings(in data: Data) -> [String] {
        guard let value = try? JSONSerialization.jsonObject(with: data) else { return [] }
        return flattenStrings(value)
    }

    private static func flattenStrings(_ value: Any) -> [String] {
        if let string = value as? String { return [string] }
        if let dictionary = value as? [String: Any] {
            return dictionary.flatMap { key, child in [key] + flattenStrings(child) }
        }
        if let array = value as? [Any] {
            return array.flatMap(flattenStrings)
        }
        return []
    }

    private static func jwtStrings(_ token: String) -> [String] {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return [] }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload) else { return [] }
        return jsonStrings(in: data)
    }
}

import CryptoKit
import CoreFoundation
import Foundation
import Security

struct ClaudeUsageAdapter: UsageProviderAdapter {
    let provider: ProviderID = .claude
    let credentialPath: String?

    init(credentialPath: String? = nil) {
        self.credentialPath = credentialPath
    }

    func fetchAccounts() async throws -> [UsageAccount] {
        let resolver = ClaudeCredentialResolver.shared

        func requestUsage(accessToken: String) async throws -> (Data, URLResponse) {
            var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
            request.httpMethod = "GET"
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return try await URLSession.shared.data(for: request)
        }

        var token = try await resolver.accessToken(credentialPath: credentialPath)
        var (data, response) = try await requestUsage(accessToken: token)

        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            token = try await resolver.accessToken(
                credentialPath: credentialPath,
                forceRefresh: true,
                rejectedAccessToken: token
            )
            (data, response) = try await requestUsage(accessToken: token)
        }

        try HTTPUsageResponseValidator.validate(response: response, data: data, provider: .claude)

        return [
            UsageAccount(
                provider: .claude,
                name: "Current Session",
                source: .currentSession,
                buckets: try Self.parseUsage(data: data)
            )
        ]
    }

    static func parseUsage(data: Data) throws -> [UsageBucket] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAdapterError.invalidResponse("Claude usage response is not a JSON object.")
        }

        if let limits = root["limits"] as? [[String: Any]], !limits.isEmpty {
            let buckets = limits.compactMap(parseLimit)
            if !buckets.isEmpty { return buckets }
        }

        var buckets: [UsageBucket] = []
        if let value = root["five_hour"] as? [String: Any], let bucket = parseLegacyWindow(
            key: "five_hour",
            value: value,
            label: "5h",
            kind: .fiveHour,
            model: nil
        ) {
            buckets.append(bucket)
        }
        if let value = root["seven_day"] as? [String: Any], let bucket = parseLegacyWindow(
            key: "seven_day",
            value: value,
            label: "1w",
            kind: .weekly,
            model: nil
        ) {
            buckets.append(bucket)
        }

        for key in root.keys.sorted() where key.hasPrefix("seven_day_") && key != "seven_day_oauth_apps" {
            guard let value = root[key] as? [String: Any] else { continue }
            let suffix = String(key.dropFirst("seven_day_".count))
            let model = displayName(from: suffix)
            if let bucket = parseLegacyWindow(
                key: key,
                value: value,
                label: model,
                kind: .modelSpecific,
                model: model
            ) {
                buckets.append(bucket)
            }
        }

        guard !buckets.isEmpty else {
            throw UsageAdapterError.invalidResponse("Claude usage response contained no recognized quota windows.")
        }
        return buckets
    }

    private static func parseLegacyWindow(
        key: String,
        value: [String: Any],
        label: String,
        kind: UsageWindowKind,
        model: String?
    ) -> UsageBucket? {
        guard let utilization = normalizedPercent(value["utilization"] ?? value["percent"]) else { return nil }
        return UsageBucket(
            quotaID: "claude-\(slug(key))",
            label: label,
            kind: kind,
            model: model,
            percentUsed: utilization,
            resetsAt: UsageDateParser.date(from: value["resets_at"])
        )
    }

    private static func parseLimit(_ value: [String: Any]) -> UsageBucket? {
        guard let utilization = normalizedPercent(value["percent"] ?? value["utilization"]) else { return nil }
        let rawKind = (value["kind"] as? String) ?? ""
        let group = (value["group"] as? String) ?? ""
        let scope = value["scope"] as? [String: Any]
        let modelObject = scope?["model"] as? [String: Any]
        let model = modelObject?["display_name"] as? String

        let kind: UsageWindowKind
        let label: String
        if let model, !model.isEmpty {
            kind = .modelSpecific
            label = model
        } else if rawKind == "session" || group == "session" {
            kind = .fiveHour
            label = "5h"
        } else if rawKind.hasPrefix("weekly") || group == "weekly" {
            kind = .weekly
            label = "1w"
        } else {
            kind = .custom
            label = displayName(from: rawKind.isEmpty ? group : rawKind)
        }

        let identity = [rawKind, group, model ?? "all"].filter { !$0.isEmpty }.joined(separator: "-")
        return UsageBucket(
            quotaID: "claude-\(slug(identity.isEmpty ? label : identity))",
            label: label,
            kind: kind,
            model: model,
            percentUsed: utilization,
            resetsAt: UsageDateParser.date(from: value["resets_at"])
        )
    }

    private static func normalizedPercent(_ value: Any?) -> Double? {
        let raw: Double?
        switch value {
        case let number as NSNumber: raw = number.doubleValue
        case let string as String: raw = Double(string)
        default: raw = nil
        }
        guard let raw, raw >= 0 else { return nil }
        return min(raw > 1 ? raw / 100 : raw, 1)
    }

    private static func displayName(from raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private static func slug(_ raw: String) -> String {
        raw.lowercased().reduce(into: "") { result, char in
            let next: Character = (char.isLetter || char.isNumber) ? char : "-"
            if next != "-" || result.last != "-" { result.append(next) }
        }
    }
}

struct CodexUsageAdapter: UsageProviderAdapter {
    let provider: ProviderID = .codex
    let credentialPath: String?

    init(credentialPath: String? = nil) {
        self.credentialPath = credentialPath
    }

    func fetchAccounts() async throws -> [UsageAccount] {
        let credentials = try CodexCredentialResolver().credentials(credentialPath: credentialPath)
        var request = URLRequest(url: URL(string: "https://chatgpt.com/backend-api/wham/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let accountID = credentials.accountID, !accountID.isEmpty {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPUsageResponseValidator.validate(response: response, data: data, provider: .codex)

        return [
            UsageAccount(
                provider: .codex,
                name: "Current Session",
                source: .currentSession,
                buckets: try Self.parseUsage(data: data)
            )
        ]
    }

    static func parseUsage(data: Data) throws -> [UsageBucket] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAdapterError.invalidResponse("Codex usage response is not a JSON object.")
        }

        var buckets: [UsageBucket] = []
        if let rateLimit = root["rate_limit"] as? [String: Any] {
            buckets.append(contentsOf: parseWindows(rateLimit, identity: "general", model: nil))
        }

        if let additional = root["additional_rate_limits"] as? [[String: Any]] {
            for item in additional {
                guard let rateLimit = item["rate_limit"] as? [String: Any] else { continue }
                let model = (item["limit_name"] as? String) ?? (item["metered_feature"] as? String) ?? "Additional"
                buckets.append(contentsOf: parseWindows(rateLimit, identity: slug(model), model: model))
            }
        }

        guard !buckets.isEmpty else {
            throw UsageAdapterError.invalidResponse("Codex usage response contained no recognized quota windows.")
        }
        return buckets
    }

    private static func parseWindows(
        _ rateLimit: [String: Any],
        identity: String,
        model: String?
    ) -> [UsageBucket] {
        ["primary_window", "secondary_window"].compactMap { key in
            guard let window = rateLimit[key] as? [String: Any] else { return nil }
            return parseWindow(window, identity: identity, model: model)
        }
    }

    private static func parseWindow(
        _ window: [String: Any],
        identity: String,
        model: String?
    ) -> UsageBucket? {
        guard let usedPercent = numeric(window["used_percent"]), usedPercent >= 0 else { return nil }
        let seconds = numeric(window["limit_window_seconds"]).map(Int.init) ?? 0
        let kind = windowKind(seconds: seconds, modelSpecific: model != nil)
        let windowLabel = label(seconds: seconds)
        let displayLabel = model == nil ? windowLabel : "\(shortModelName(model!)) \(windowLabel)"

        return UsageBucket(
            quotaID: "codex-\(identity)-\(seconds)",
            label: displayLabel,
            kind: kind,
            model: model,
            percentUsed: min(usedPercent / 100, 1),
            resetsAt: epochDate(window["reset_at"])
        )
    }

    private static func numeric(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
    }

    private static func epochDate(_ value: Any?) -> Date? {
        guard let seconds = numeric(value), seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func windowKind(seconds: Int, modelSpecific: Bool) -> UsageWindowKind {
        if modelSpecific { return .modelSpecific }
        if (17_400...18_600).contains(seconds) { return .fiveHour }
        if seconds >= 6 * 24 * 60 * 60 { return .weekly }
        return .custom
    }

    private static func label(seconds: Int) -> String {
        if (17_400...18_600).contains(seconds) { return "5h" }
        if (6 * 24 * 60 * 60...8 * 24 * 60 * 60).contains(seconds) { return "1w" }
        if seconds > 0, seconds % 86_400 == 0 { return "\(seconds / 86_400)d" }
        if seconds > 0, seconds % 3_600 == 0 { return "\(seconds / 3_600)h" }
        if seconds > 0, seconds % 60 == 0 { return "\(seconds / 60)m" }
        return "Limit"
    }

    private static func shortModelName(_ model: String) -> String {
        if let last = model.split(separator: "-").last, last.count <= 10 {
            return String(last)
        }
        return model
    }

    private static func slug(_ raw: String) -> String {
        raw.lowercased().reduce(into: "") { result, char in
            let next: Character = (char.isLetter || char.isNumber) ? char : "-"
            if next != "-" || result.last != "-" { result.append(next) }
        }
    }
}

struct AntigravityUsageAdapter: UsageProviderAdapter {
    let provider: ProviderID = .antigravity
    let profileHomePath: String?

    init(profileHomePath: String? = nil) {
        self.profileHomePath = profileHomePath
    }

    func fetchAccounts() async throws -> [UsageAccount] {
        let output = try await Self.fetchUsageText(profileHomePath: profileHomePath)
        return [
            UsageAccount(
                provider: .antigravity,
                name: "Current Session",
                source: .currentSession,
                buckets: try Self.parseUsage(text: output)
            )
        ]
    }

    static func executableURL(profileHomePath: String? = nil) -> URL? {
        let fileManager = FileManager.default
        var candidates: [URL] = []
        if let profileHomePath, !profileHomePath.isEmpty {
            candidates.append(URL(fileURLWithPath: profileHomePath).appendingPathComponent(".local/bin/agy"))
        }
        candidates.append(fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/agy"))
        candidates.append(URL(fileURLWithPath: "/opt/homebrew/bin/agy"))
        candidates.append(URL(fileURLWithPath: "/usr/local/bin/agy"))
        return candidates.first(where: { fileManager.isExecutableFile(atPath: $0.path) })
    }

    static func parseUsage(text: String) throws -> [UsageBucket] {
        var buckets: [UsageBucket] = []
        let formatter = ISO8601DateFormatter()

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let columns = rawLine.split(separator: "\t", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard columns.count >= 4 else { continue }

            let model = columns[0]
            let limitName = columns[1].lowercased()
            let percentString = columns[2].replacingOccurrences(of: "%", with: "")
            guard let remainingPercent = Double(percentString) else { continue }

            let kind: UsageWindowKind
            let shortLabel: String
            if limitName.contains("five hour") || limitName.contains("5 hour") {
                kind = .fiveHour
                shortLabel = "5h"
            } else if limitName.contains("weekly") || limitName.contains("week") {
                kind = .weekly
                shortLabel = "1w"
            } else {
                continue
            }

            let remaining = min(max(remainingPercent / 100, 0), 1)
            buckets.append(
                UsageBucket(
                    quotaID: "antigravity-\(slug(model))-\(kind.rawValue)",
                    label: "\(model) · \(shortLabel)",
                    kind: kind,
                    model: model,
                    percentUsed: 1 - remaining,
                    resetsAt: formatter.date(from: columns[3])
                )
            )
        }

        guard !buckets.isEmpty else {
            throw UsageAdapterError.invalidResponse("Antigravity CLI returned no usable quota rows from /usage.")
        }
        return buckets
    }

    private static func fetchUsageText(profileHomePath: String?) async throws -> String {
        guard let executable = executableURL(profileHomePath: profileHomePath) else {
            throw UsageAdapterError.credentialsUnavailable("Antigravity CLI (agy) was not found. Install the official Antigravity CLI, then retry.")
        }

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = executable
            process.arguments = ["-p", "/usage", "--print-timeout", "20s"]
            process.standardOutput = stdout
            process.standardError = stderr

            // agy authenticates through its native macOS Keychain/session boundary. HOME
            // isolation is not a supported multi-profile contract, so quota reads must use
            // the same native session that the user actually authenticated.
            process.environment = ProcessInfo.processInfo.environment

            process.terminationHandler = { process in
                let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
                let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""
                let errorText = String(data: errorData, encoding: .utf8) ?? ""

                guard process.terminationStatus == 0 else {
                    let lower = errorText.lowercased()
                    if lower.contains("authentication required") || lower.contains("sign in") || lower.contains("login") {
                        continuation.resume(throwing: UsageAdapterError.authenticationExpired(
                            "Antigravity login is required. Open Antigravity Login and finish the official agy browser sign-in."
                        ))
                    } else {
                        let message = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
                        continuation.resume(throwing: UsageAdapterError.invalidResponse(
                            message.isEmpty ? "Antigravity CLI /usage failed." : message
                        ))
                    }
                    return
                }

                let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else {
                    continuation.resume(throwing: UsageAdapterError.invalidResponse("Antigravity CLI /usage returned an empty response."))
                    return
                }
                continuation.resume(returning: trimmed)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func slug(_ raw: String) -> String {
        raw.lowercased().reduce(into: "") { result, char in
            let next: Character = (char.isLetter || char.isNumber) ? char : "-"
            if next != "-" || result.last != "-" { result.append(next) }
        }
    }
}

struct GeminiUsageAdapter: UsageProviderAdapter {
    let provider: ProviderID = .antigravity
    let credentialPath: String?

    init(credentialPath: String? = nil) {
        self.credentialPath = credentialPath
    }

    func fetchAccounts() async throws -> [UsageAccount] {
        let credentials = try GeminiCredentialResolver().credentials(credentialPath: credentialPath)
        let baseURL = "https://cloudcode-pa.googleapis.com/v1internal"

        var loadRequest = URLRequest(url: URL(string: baseURL + ":loadCodeAssist")!)
        loadRequest.httpMethod = "POST"
        loadRequest.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        loadRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        loadRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        loadRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "metadata": [
                "ideType": "IDE_UNSPECIFIED",
                "platform": "PLATFORM_UNSPECIFIED",
                "pluginType": "GEMINI"
            ]
        ])

        let (loadData, loadResponse) = try await URLSession.shared.data(for: loadRequest)
        try HTTPUsageResponseValidator.validate(response: loadResponse, data: loadData, provider: .antigravity)
        guard
            let loadRoot = try JSONSerialization.jsonObject(with: loadData) as? [String: Any],
            let projectID = Self.projectID(from: loadRoot)
        else {
            throw UsageAdapterError.invalidResponse("Antigravity quota project could not be resolved.")
        }

        var quotaRequest = URLRequest(url: URL(string: baseURL + ":retrieveUserQuota")!)
        quotaRequest.httpMethod = "POST"
        quotaRequest.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        quotaRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        quotaRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        quotaRequest.httpBody = try JSONSerialization.data(withJSONObject: ["project": projectID])

        let (data, response) = try await URLSession.shared.data(for: quotaRequest)
        try HTTPUsageResponseValidator.validate(response: response, data: data, provider: .antigravity)

        return [
            UsageAccount(
                provider: .antigravity,
                name: "Current Session",
                source: .currentSession,
                buckets: try Self.parseUsage(data: data)
            )
        ]
    }

    static func parseUsage(data: Data) throws -> [UsageBucket] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAdapterError.invalidResponse("Antigravity quota response is not a JSON object.")
        }
        guard let rows = root["buckets"] as? [[String: Any]], !rows.isEmpty else {
            throw UsageAdapterError.invalidResponse("Antigravity quota response contained no quota buckets.")
        }

        let buckets = rows.compactMap { row -> UsageBucket? in
            let model = (row["modelId"] as? String) ?? "Antigravity"
            guard let remainingFraction = numeric(row["remainingFraction"]), remainingFraction >= 0 else { return nil }
            let normalizedRemaining = min(max(remainingFraction, 0), 1)
            let remainingAmount = numeric(row["remainingAmount"])
            let limit: Double?
            let used: Double?
            if let remainingAmount, normalizedRemaining > 0 {
                let computedLimit = remainingAmount / normalizedRemaining
                limit = computedLimit > 0 && computedLimit.isFinite ? computedLimit : nil
                used = limit.map { max($0 - remainingAmount, 0) }
            } else {
                limit = nil
                used = nil
            }

            return UsageBucket(
                quotaID: "gemini-\(slug(model))",
                label: shortModelName(model),
                kind: .modelSpecific,
                model: model,
                used: used,
                limit: limit,
                unit: limit == nil ? nil : "requests",
                percentUsed: 1 - normalizedRemaining,
                resetsAt: UsageDateParser.date(from: row["resetTime"])
            )
        }

        guard !buckets.isEmpty else {
            throw UsageAdapterError.invalidResponse("Antigravity quota response contained no usable quota buckets.")
        }
        return buckets.sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private static func projectID(from root: [String: Any]) -> String? {
        if let value = root["cloudaicompanionProject"] as? String, !value.isEmpty { return value }
        if let object = root["cloudaicompanionProject"] as? [String: Any] {
            if let value = object["id"] as? String, !value.isEmpty { return value }
            if let value = object["name"] as? String, !value.isEmpty { return value }
        }
        return nil
    }

    private static func shortModelName(_ model: String) -> String {
        let tail = model.split(separator: "/").last.map(String.init) ?? model
        return tail
            .replacingOccurrences(of: "gemini-", with: "", options: [.caseInsensitive, .anchored])
            .replacingOccurrences(of: "-", with: " ")
    }

    private static func numeric(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        default: return nil
        }
    }

    private static func slug(_ raw: String) -> String {
        raw.lowercased().reduce(into: "") { result, char in
            let next: Character = (char.isLetter || char.isNumber) ? char : "-"
            if next != "-" || result.last != "-" { result.append(next) }
        }
    }
}

struct KimiUsageFetch {
    var buckets: [UsageBucket]
    var notice: String?
}

struct KimiUsageAdapter: UsageProviderAdapter {
    let provider: ProviderID = .kimi
    let credentialPath: String?
    let desktopCredentialPath: String?
    let session: URLSession

    static let totalUnavailableNotice = "Kimi total usage is unavailable. Open Kimi and sign in to the same account. Showing Code quotas only."
    static let codeUnavailableNotice = "Kimi Code quotas could not be refreshed. Showing total usage only."

    init(credentialPath: String? = nil, desktopCredentialPath: String? = nil, session: URLSession = .shared) {
        self.credentialPath = credentialPath
        self.desktopCredentialPath = desktopCredentialPath
        self.session = session
    }

    func fetchAccounts() async throws -> [UsageAccount] {
        let outcome = try await fetchOutcome()
        return [UsageAccount(provider: .kimi, name: "Current Session", source: .currentSession, buckets: outcome.buckets)]
    }

    func fetchOutcome() async throws -> KimiUsageFetch {
        let credentials = try await KimiCredentialResolver().credentials(credentialPath: credentialPath)
        var buckets: [UsageBucket] = []
        var codeError: Error?
        do {
            guard let url = URL(string: credentials.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/usages") else {
                throw UsageAdapterError.invalidResponse("Kimi managed API base URL is invalid.")
            }
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            try HTTPUsageResponseValidator.validate(response: response, data: data, provider: .kimi)
            buckets = try Self.parseUsage(data: data)
        } catch {
            codeError = error
        }

        do {
            // The Code OAuth token cannot call the membership API. Read Kimi's
            // existing desktop session without copying or refreshing its secrets.
            let token = try KimiDesktopCredentialResolver().accessToken(
                codeAccessToken: credentials.accessToken,
                credentialPath: desktopCredentialPath
            )
            var request = URLRequest(url: URL(string: "https://www.kimi.com/apiv2/kimi.gateway.membership.v2.MembershipService/GetSubscription")!)
            request.httpMethod = "POST"
            request.httpBody = Data("{}".utf8)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            request.timeoutInterval = 20
            let (data, response) = try await session.data(for: request)
            try HTTPUsageResponseValidator.validate(response: response, data: data, provider: .kimi)
            buckets.insert(try Self.parseSubscription(data: data), at: 0)
        } catch {
            guard !buckets.isEmpty else { throw codeError ?? error }
            return KimiUsageFetch(buckets: buckets, notice: Self.totalUnavailableNotice)
        }
        return KimiUsageFetch(buckets: buckets, notice: codeError == nil ? nil : Self.codeUnavailableNotice)
    }

    static func parseSubscription(data: Data) throws -> UsageBucket {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let balances = root["balances"] as? [[String: Any]] else {
            throw UsageAdapterError.invalidResponse("Kimi subscription response contained no total usage balance.")
        }
        let totals = balances.filter {
            $0["feature"] as? String == "FEATURE_OMNI" &&
            $0["unit"] as? String == "UNIT_CREDIT" &&
            $0["type"] as? String == "SUBSCRIPTION"
        }
        guard totals.count == 1, let total = totals.first,
              let used = ratio(total["amountUsedRatio"]),
              let reset = UsageDateParser.date(from: total["expireTime"]) else {
            throw UsageAdapterError.invalidResponse("Kimi subscription response contained no unambiguous total usage and reset time.")
        }
        return UsageBucket(quotaID: "kimi-total", label: "Total", kind: .custom, percentUsed: used, resetsAt: reset)
    }

    static func parseUsage(data: Data) throws -> [UsageBucket] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAdapterError.invalidResponse("Kimi usage response is not a JSON object.")
        }

        let payload: [String: Any]
        if let dataObject = root["data"] as? [String: Any] {
            if let kind = dataObject["kind"] as? String, kind == "error" {
                let message = (dataObject["message"] as? String) ?? "Kimi usage service returned an error."
                throw UsageAdapterError.invalidResponse(message)
            }
            payload = dataObject
        } else {
            payload = root
        }

        var bucketsByID: [String: UsageBucket] = [:]

        if let usage = payload["usage"] as? [String: Any],
           let bucket = parseQuotaRow(usage, fallbackLabel: "1w", fallbackMinutes: 10_080) {
            bucketsByID[bucket.quotaID] = bucket
        }
        if let summary = payload["summary"] as? [String: Any],
           let bucket = parseQuotaRow(summary, fallbackLabel: "1w", fallbackMinutes: 10_080) {
            bucketsByID[bucket.quotaID] = bucket
        }

        if let limits = payload["limits"] as? [[String: Any]] {
            for (index, item) in limits.enumerated() {
                if let bucket = parseQuotaRow(item, fallbackLabel: "Limit \(index + 1)", fallbackMinutes: nil) {
                    bucketsByID[bucket.quotaID] = bucket
                }
            }
        }

        // These fractional pools retain precision lost by the older integer
        // limit/remaining fields (for example 0.01% weekly usage).
        if let usages = payload["usages"] as? [String: Any] {
            for (key, quotaID, label, kind) in [
                ("limit_5h", "kimi-300", "5h Code", UsageWindowKind.fiveHour),
                ("limit_7d", "kimi-weekly", "7d Code", UsageWindowKind.weekly)
            ] {
                guard let window = usages[key] as? [String: Any], let used = ratio(window["used_ratio"]) else { continue }
                bucketsByID[quotaID] = UsageBucket(
                    quotaID: quotaID, label: label, kind: kind, percentUsed: used,
                    resetsAt: UsageDateParser.date(from: window["reset_time"])
                )
            }
        }

        if let extra = payload["extra_usage"] as? [String: Any],
           let used = numeric(extra["monthly_used_cents"]),
           let limit = numeric(extra["monthly_charge_limit_cents"]),
           limit > 0 {
            bucketsByID["kimi-extra-usage"] = UsageBucket(
                quotaID: "kimi-extra-usage",
                label: "Extra",
                kind: .credits,
                used: used,
                limit: limit,
                unit: (extra["currency"] as? String) ?? "cents"
            )
        }

        let buckets = Array(bucketsByID.values).sorted { lhs, rhs in
            let left = rank(lhs.kind)
            let right = rank(rhs.kind)
            return left == right
                ? lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
                : left < right
        }

        guard !buckets.isEmpty else {
            throw UsageAdapterError.invalidResponse("Kimi usage response contained no recognized quota windows.")
        }
        return buckets
    }

    private static func parseQuotaRow(
        _ item: [String: Any],
        fallbackLabel: String,
        fallbackMinutes: Int?
    ) -> UsageBucket? {
        let detail = item["detail"] as? [String: Any]
        let source = detail ?? item
        guard let limit = numeric(source["limit"] ?? item["limit"]), limit > 0 else { return nil }
        let used = numeric(source["used"] ?? item["used"])
            ?? numeric(source["remaining"] ?? item["remaining"]).map { max(limit - $0, 0) }
        guard let used else { return nil }

        let minutes = windowMinutes(item["window"] as? [String: Any])
            ?? windowMinutes(source["window"] as? [String: Any])
            ?? fallbackMinutes
        let label = labelForWindow(minutes: minutes, fallback: displayName(item) ?? fallbackLabel)
        let kind = kindForWindow(minutes: minutes)
        let quotaID = minutes == 10_080
            ? "kimi-weekly"
            : "kimi-\(minutes.map(String.init) ?? slug(label))"
        let reset = UsageDateParser.date(from: source["reset_at"] ?? source["resetTime"] ?? item["reset_at"] ?? item["resetTime"])

        return UsageBucket(
            quotaID: quotaID,
            label: label,
            kind: kind,
            used: used,
            limit: limit,
            unit: "quota",
            resetsAt: reset
        )
    }

    private static func windowMinutes(_ window: [String: Any]?) -> Int? {
        guard let window, let duration = numeric(window["duration"]), duration > 0 else { return nil }
        let rawUnit = ((window["unit"] as? String) ?? (window["timeUnit"] as? String) ?? "").uppercased()
        let multiplier: Double
        if rawUnit.contains("WEEK") {
            multiplier = 10_080
        } else if rawUnit.contains("DAY") {
            multiplier = 1_440
        } else if rawUnit.contains("HOUR") {
            multiplier = 60
        } else {
            multiplier = 1
        }
        return Int((duration * multiplier).rounded())
    }

    private static func labelForWindow(minutes: Int?, fallback: String) -> String {
        guard let minutes else { return fallback }
        if (295...305).contains(minutes) { return "5h Code" }
        if (10_000...10_160).contains(minutes) { return "7d Code" }
        if minutes % 10_080 == 0 { return "\(minutes / 10_080)w" }
        if minutes % 1_440 == 0 { return "\(minutes / 1_440)d" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        return "\(minutes)m"
    }

    private static func kindForWindow(minutes: Int?) -> UsageWindowKind {
        guard let minutes else { return .custom }
        if (295...305).contains(minutes) { return .fiveHour }
        if (10_000...10_160).contains(minutes) { return .weekly }
        return .custom
    }

    private static func displayName(_ item: [String: Any]) -> String? {
        (item["title"] as? String) ?? (item["name"] as? String)
    }

    private static func numeric(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
    }

    private static func ratio(_ value: Any?) -> Double? {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        guard let number = numeric(value), number.isFinite, (0...1).contains(number) else { return nil }
        return number
    }

    private static func rank(_ kind: UsageWindowKind) -> Int {
        switch kind {
        case .fiveHour: 0
        case .weekly: 1
        case .modelSpecific: 2
        case .credits: 3
        case .custom: 4
        }
    }

    private static func slug(_ raw: String) -> String {
        raw.lowercased().reduce(into: "") { result, char in
            let next: Character = (char.isLetter || char.isNumber) ? char : "-"
            if next != "-" || result.last != "-" { result.append(next) }
        }
    }
}

struct GrokUsageFetch {
    var buckets: [UsageBucket]
    var notice: String?
}

struct GrokUsageAdapter: UsageProviderAdapter {
    let provider: ProviderID = .grok
    let credentialPath: String?
    let webSessionID: String?

    init(credentialPath: String? = nil, webSessionID: String? = nil) {
        self.credentialPath = credentialPath
        self.webSessionID = webSessionID
    }

    func fetchAccounts() async throws -> [UsageAccount] {
        let outcome = try await fetchOutcome()
        return [
            UsageAccount(
                provider: .grok,
                name: "Current Session",
                source: .currentSession,
                buckets: outcome.buckets
            )
        ]
    }

    /// Prefers the grok.com Settings → Usage reading. A web failure falls back
    /// to the CLI billing session and keeps a notice instead of hiding it.
    /// An undecodable web body never becomes 0%.
    func fetchOutcome() async throws -> GrokUsageFetch {
        var notice: String?
        if let webSessionID, let sessionID = UUID(uuidString: webSessionID) {
            let payload = await GrokWebSession.fetchCredits(sessionID: sessionID)
            switch payload.interpretation {
            case .usage(let reading):
                return GrokUsageFetch(buckets: GrokWebCredits.buckets(from: reading), notice: nil)
            case .needsReLogin(let message):
                notice = "\(message) Showing the CLI billing reading until then."
            case .undecodable(let message), .unavailable(let message):
                notice = "\(message) Showing the CLI billing reading until then."
            }
        }

        do {
            return GrokUsageFetch(buckets: try await fetchCLIBuckets(), notice: notice)
        } catch {
            if let notice {
                throw UsageAdapterError.authenticationExpired("\(notice) CLI billing also failed: \(error.localizedDescription)")
            }
            throw error
        }
    }

    private func fetchCLIBuckets() async throws -> [UsageBucket] {
        let resolver = GrokCredentialResolver()
        var session = try await resolver.credentials(credentialPath: credentialPath)
        var (data, response) = try await Self.requestBilling(session)
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            session = try await resolver.credentials(credentialPath: credentialPath, forceRefresh: true)
            (data, response) = try await Self.requestBilling(session)
        }
        try HTTPUsageResponseValidator.validate(response: response, data: data, provider: .grok)
        return try Self.parseUsage(data: data)
    }

    /// Official Grok CLI subscription pool (`Settings → Usage` / `/usage`).
    ///
    /// The CLI maps this payload in `credit_balance_from_config`: use
    /// `creditUsagePercent` (0–100) when present; otherwise `used / monthlyLimit`
    /// when that limit is positive; otherwise 0. The last branch is how `/usage`
    /// renders a proto3 response that omitted a zero percentage. UsageDock
    /// applies that 0 only when `currentPeriod` is present, so an empty body
    /// or the unformatted billing ledger is not shown as a subscription
    /// percentage. Product rows are shares of this same pool.
    static func parseUsage(data: Data) throws -> [UsageBucket] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAdapterError.invalidResponse("Grok billing response is not a JSON object.")
        }
        let config = (root["config"] as? [String: Any]) ?? root
        let window = periodWindow(config)
        var buckets: [UsageBucket] = []

        if let reading = subscriptionReading(config) {
            let display = reading.legacyMonthly && window.quotaID == "grok-usage"
                ? (quotaID: "grok-monthly", label: "Month", kind: UsageWindowKind.custom, resetsAt: window.resetsAt)
                : window
            buckets.append(
                UsageBucket(
                    quotaID: display.quotaID,
                    label: display.label,
                    kind: display.kind,
                    percentUsed: reading.percentUsed,
                    resetsAt: display.resetsAt
                )
            )
        }

        if let cap = cent(config["onDemandCap"] ?? config["on_demand_cap"]), cap > 0 {
            let used = cent(config["onDemandUsed"] ?? config["on_demand_used"]) ?? 0
            buckets.append(
                UsageBucket(
                    quotaID: "grok-extra",
                    label: "Extra",
                    kind: .credits,
                    used: max(used, 0),
                    limit: cap,
                    unit: "cents",
                    resetsAt: window.resetsAt
                )
            )
        }

        guard !buckets.isEmpty else {
            throw UsageAdapterError.invalidResponse(
                "Grok billing response did not include a usage percentage. UsageDock will not invent 0%."
            )
        }
        return buckets
    }

    /// Same precedence as the Grok CLI's `credit_balance_from_config`.
    /// An omitted percentage becomes 0 only for a credits config that included
    /// `currentPeriod` and has no positive monthly allowance to divide.
    private static func subscriptionReading(
        _ config: [String: Any]
    ) -> (percentUsed: Double, legacyMonthly: Bool)? {
        if let percent = numeric(config["creditUsagePercent"] ?? config["credit_usage_percent"]), percent >= 0 {
            return (min(percent, 100) / 100, false)
        }
        if let limit = cent(config["monthlyLimit"] ?? config["monthly_limit"]), limit > 0 {
            let used = max(cent(config["used"]) ?? 0, 0)
            return (min(used / limit, 1), true)
        }
        let period = (config["currentPeriod"] as? [String: Any]) ?? (config["current_period"] as? [String: Any])
        if period != nil {
            return (0, false)
        }
        return nil
    }

    private static func requestBilling(_ session: GrokCredentialStore.Session) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: GrokCredentialStore.billingURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue(GrokCredentialStore.tokenHeader, forHTTPHeaderField: "X-XAI-Token-Auth")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let userID = session.userID, !userID.isEmpty {
            request.setValue(userID, forHTTPHeaderField: "x-userid")
        }
        return try await URLSession.shared.data(for: request)
    }

    private static func periodWindow(
        _ config: [String: Any]
    ) -> (quotaID: String, label: String, kind: UsageWindowKind, resetsAt: Date?) {
        let period = (config["currentPeriod"] as? [String: Any]) ?? (config["current_period"] as? [String: Any])
        let type = ((period?["type"] as? String) ?? "").uppercased()
        let start = UsageDateParser.date(from: period?["start"] ?? config["billingPeriodStart"] ?? config["billing_period_start"])
        let end = UsageDateParser.date(from: period?["end"] ?? config["billingPeriodEnd"] ?? config["billing_period_end"])
        if type.contains("WEEK") || spans(start, end, minDays: 6, maxDays: 8) {
            return ("grok-weekly", "1w", .weekly, end)
        }
        if type.contains("MONTH") || spans(start, end, minDays: 27, maxDays: 32) {
            return ("grok-month", "Month", .custom, end)
        }
        return ("grok-usage", "Usage", .custom, end)
    }

    private static func spans(_ start: Date?, _ end: Date?, minDays: Double, maxDays: Double) -> Bool {
        guard let start, let end else { return false }
        let days = end.timeIntervalSince(start) / 86_400
        return days >= minDays && days <= maxDays
    }

    private static func cent(_ value: Any?) -> Double? {
        if let object = value as? [String: Any] {
            if object.isEmpty { return 0 }
            return numeric(object["val"])
        }
        return numeric(value)
    }

    private static func numeric(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: number.doubleValue
        case let string as String: Double(string)
        default: nil
        }
    }
}

enum GrokCredentialStore {
    static let billingURL = URL(string: "https://cli-chat-proxy.grok.com/v1/billing?format=credits")!
    static let tokenHeader = "xai-grok-cli"

    struct Session {
        var scope: String
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date?
        var issuer: String?
        var clientID: String?
        var userID: String?
    }

    static func containsSession(data: Data) -> Bool {
        (try? session(in: data).session) != nil
    }

    static func authURL(credentialPath: String?) -> URL {
        if let credentialPath, !credentialPath.isEmpty {
            return URL(fileURLWithPath: credentialPath)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".grok/auth.json")
    }

    static func load(credentialPath: String?) throws -> (root: [String: Any], session: Session) {
        let url = authURL(credentialPath: credentialPath)
        guard let data = try? Data(contentsOf: url) else {
            throw UsageAdapterError.credentialsUnavailable(
                "Grok CLI login was not found. Run grok login, then choose Use Current Login."
            )
        }
        return try session(in: data)
    }

    static func session(in data: Data) throws -> (root: [String: Any], session: Session) {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageAdapterError.credentialsUnavailable("Grok auth file is not a JSON object.")
        }

        let candidates: [(Session, Int)] = root.compactMap { scope, value in
            guard let entry = value as? [String: Any] else { return nil }
            guard let token = entry["key"] as? String, !token.isEmpty else { return nil }
            let mode = ((entry["auth_mode"] as? String) ?? "").lowercased()
            if mode == "web_login" || mode == "grok" || mode == "api_key" { return nil }
            if scope == "xai::api_key" || scope.hasSuffix("::api_key") { return nil }
            var rank = 0
            if scope.contains("accounts.x.ai") || scope.contains("auth.x.ai") { rank += 4 }
            if mode == "oidc" || mode == "external" { rank += 2 }
            guard rank > 0 else { return nil }
            return (
                Session(
                    scope: scope,
                    accessToken: token,
                    refreshToken: nonEmpty(entry["refresh_token"]),
                    expiresAt: UsageDateParser.date(from: entry["expires_at"]),
                    issuer: nonEmpty(entry["oidc_issuer"]),
                    clientID: nonEmpty(entry["oidc_client_id"]),
                    userID: nonEmpty(entry["user_id"])
                ),
                rank
            )
        }

        guard let best = candidates.max(by: { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
            return (lhs.0.expiresAt ?? .distantPast) < (rhs.0.expiresAt ?? .distantPast)
        }) else {
            throw UsageAdapterError.credentialsUnavailable(rejectionMessage(root: root))
        }
        return (root, best.0)
    }

    static func persistRefreshedSession(
        root: [String: Any],
        session: Session,
        accessToken: String,
        refreshToken: String?,
        expiresIn: Double?,
        url: URL,
        now: Date = Date()
    ) throws -> Session {
        var updatedRoot = root
        var entry = (updatedRoot[session.scope] as? [String: Any]) ?? [:]
        var updated = session
        updated.accessToken = accessToken
        entry["key"] = accessToken
        if let refreshToken, !refreshToken.isEmpty {
            updated.refreshToken = refreshToken
            entry["refresh_token"] = refreshToken
        }
        if let expiresIn, expiresIn > 0 {
            let expiry = now.addingTimeInterval(expiresIn)
            updated.expiresAt = expiry
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime]
            entry["expires_at"] = formatter.string(from: expiry)
        }
        updatedRoot[session.scope] = entry
        let encoded = try JSONSerialization.data(withJSONObject: updatedRoot, options: [.prettyPrinted, .sortedKeys])
        try encoded.write(to: url, options: .atomic)
        return updated
    }

    private static func rejectionMessage(root: [String: Any]) -> String {
        var sawAPIKey = false
        var sawDeprecated = false
        for (scope, value) in root {
            guard let entry = value as? [String: Any] else { continue }
            let mode = ((entry["auth_mode"] as? String) ?? "").lowercased()
            if mode == "api_key" || scope.hasSuffix("::api_key") { sawAPIKey = true }
            if mode == "web_login" || mode == "grok" { sawDeprecated = true }
        }
        if sawAPIKey {
            return "Grok consumer usage needs a grok login session. An xAI API key does not expose the SuperGrok or X subscription pool."
        }
        if sawDeprecated {
            return "This Grok login is out of date. Run grok login again, then refresh UsageDock."
        }
        return "Grok login session was not found. Run grok login, then choose Use Current Login."
    }

    private static func nonEmpty(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }
}

private struct GrokCredentialResolver {
    func credentials(credentialPath: String?, forceRefresh: Bool = false) async throws -> GrokCredentialStore.Session {
        let loaded = try GrokCredentialStore.load(credentialPath: credentialPath)
        let session = loaded.session
        let refreshSoon = session.expiresAt.map { $0.timeIntervalSinceNow <= 60 } ?? false
        guard forceRefresh || refreshSoon else { return session }

        guard canRefresh(session) else {
            let alreadyExpired = session.expiresAt.map { $0 <= Date() } ?? false
            if forceRefresh || alreadyExpired {
                throw UsageAdapterError.authenticationExpired(
                    "Grok login has expired. Run grok login again, then refresh UsageDock."
                )
            }
            return session
        }

        let url = GrokCredentialStore.authURL(credentialPath: credentialPath)
        guard FileManager.default.isWritableFile(atPath: url.path) else {
            throw UsageAdapterError.authenticationExpired(
                "Grok login has expired and UsageDock cannot update the Grok auth file. Run grok login again."
            )
        }
        return try await refresh(session, root: loaded.root, url: url)
    }

    private func canRefresh(_ session: GrokCredentialStore.Session) -> Bool {
        guard let issuer = session.issuer, let issuerURL = URL(string: issuer), issuerURL.scheme == "https" else {
            return false
        }
        guard session.clientID?.isEmpty == false, session.refreshToken?.isEmpty == false else { return false }
        return true
    }

    private func refresh(
        _ session: GrokCredentialStore.Session,
        root: [String: Any],
        url: URL
    ) async throws -> GrokCredentialStore.Session {
        guard
            let issuer = session.issuer,
            URL(string: issuer)?.scheme == "https",
            let clientID = session.clientID,
            let refreshToken = session.refreshToken
        else {
            throw UsageAdapterError.authenticationExpired(
                "Grok login has expired. Run grok login again, then refresh UsageDock."
            )
        }

        let trimmedIssuer = issuer.hasSuffix("/") ? String(issuer.dropLast()) : issuer
        guard let discoveryURL = URL(string: trimmedIssuer + "/.well-known/openid-configuration") else {
            throw UsageAdapterError.authenticationExpired(
                "Grok login could not be refreshed. Run grok login again, then refresh UsageDock."
            )
        }
        var discoveryRequest = URLRequest(url: discoveryURL)
        discoveryRequest.httpMethod = "GET"
        discoveryRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        let (discoveryData, discoveryResponse) = try await URLSession.shared.data(for: discoveryRequest)
        guard
            let discoveryHTTP = discoveryResponse as? HTTPURLResponse,
            (200..<300).contains(discoveryHTTP.statusCode),
            let discovery = try? JSONSerialization.jsonObject(with: discoveryData) as? [String: Any],
            let endpoint = discovery["token_endpoint"] as? String,
            let tokenURL = URL(string: endpoint),
            tokenURL.scheme == "https"
        else {
            throw UsageAdapterError.authenticationExpired(
                "Grok login could not be refreshed. Run grok login again, then refresh UsageDock."
            )
        }

        let body = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
            .sorted { $0.key < $1.key }
            .map { "\(formEncode($0.key))=\(formEncode($0.value))" }
            .joined(separator: "&")

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            let refreshed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = refreshed["access_token"] as? String,
            !accessToken.isEmpty
        else {
            throw UsageAdapterError.authenticationExpired(
                "Grok token refresh was rejected. Run grok login again, then refresh UsageDock."
            )
        }

        let expiresIn: Double?
        switch refreshed["expires_in"] {
        case let number as NSNumber: expiresIn = number.doubleValue
        case let string as String: expiresIn = Double(string)
        default: expiresIn = nil
        }

        return try GrokCredentialStore.persistRefreshedSession(
            root: root,
            session: session,
            accessToken: accessToken,
            refreshToken: refreshed["refresh_token"] as? String,
            expiresIn: expiresIn,
            url: url
        )
    }

    private func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

enum UsageAdapterError: LocalizedError {
    case credentialsUnavailable(String)
    case authenticationExpired(String)
    case httpFailure(provider: ProviderID, statusCode: Int, message: String?)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .credentialsUnavailable(let message): message
        case .authenticationExpired(let message): message
        case .httpFailure(let provider, let statusCode, let message):
            "\(provider.displayName) usage request failed (HTTP \(statusCode))\(message.map { ": \($0)" } ?? "")."
        case .invalidResponse(let message): message
        }
    }
}

/// Provider-owned items are read by the stable Apple-signed tool that created them.
/// Password bytes stay in a pipe; neither output nor errors are logged.
enum ProviderKeychainReader {
    static func payload(
        service: String,
        run: (URL, [String]) -> (status: Int32, data: Data)? = runSecurity
    ) -> Data? {
        guard let result = run(
            URL(fileURLWithPath: "/usr/bin/security"),
            ["find-generic-password", "-s", service, "-w"]
        ), result.status == 0 else { return nil }
        var data = result.data
        // security appends a newline to the password. Preserve the password itself.
        if data.last == 0x0A { data.removeLast() }
        return data.isEmpty ? nil : data
    }

    private static func runSecurity(_ executable: URL, _ arguments: [String]) -> (status: Int32, data: Data)? {
        let process = Process()
        let stdout = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        // A locked keychain must not leave a background read waiting indefinitely.
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        timeout.cancel()
        return (process.terminationStatus, data)
    }
}

/// Only this namespace may be modified by UsageDock. Never accept a provider service
/// name as a write target, even when credentials originated in a provider file.
enum UsageDockClaudeKeychain {
    static let service = "com.uniplanck.UsageDock.ClaudeCredentials"

    static func query(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
            kSecUseAuthenticationUI: kSecUseAuthenticationUIFail
        ]
    }

    static func read(account: String) -> Data? {
        var query = query(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func write(_ data: Data, account: String) throws {
        let query = query(account: account)
        let attributes: [CFString: Any] = [kSecValueData: data]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData] = data
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw UsageAdapterError.invalidResponse(
                "UsageDock could not save its Claude token cache. Unlock the login keychain and try again."
            )
        }
    }
}

final class ClaudeCredentialCache {
    private struct Envelope: Codable {
        let sourceFingerprint: String
        let data: Data
    }

    private struct Entry {
        let loadedAt: Date
        var record: ClaudeCredentialStore.CredentialRecord?
    }

    private let lock = NSLock()
    private var entries: [String: Entry] = [:]
    private let now: () -> Date
    private let readOwned: (String) -> Data?
    private let writeOwned: (Data, String) throws -> Void

    init(
        now: @escaping () -> Date = Date.init,
        readOwned: @escaping (String) -> Data? = UsageDockClaudeKeychain.read,
        writeOwned: @escaping (Data, String) throws -> Void = UsageDockClaudeKeychain.write
    ) {
        self.now = now
        self.readOwned = readOwned
        self.writeOwned = writeOwned
    }

    func record(
        sourceID: String,
        reload: Bool = false,
        readSource: () -> Data?
    ) -> ClaudeCredentialStore.CredentialRecord? {
        lock.lock()
        defer { lock.unlock() }
        let date = now()
        if let entry = entries[sourceID] {
            // Cache misses too. Repeated UI checks / HTTP 401s cannot hammer Keychain.
            let interval: TimeInterval = reload || entry.record == nil ? 30 : 300
            if date.timeIntervalSince(entry.loadedAt) < interval { return entry.record }
        }
        guard let sourceData = readSource() else {
            entries[sourceID] = Entry(loadedAt: date, record: nil)
            return nil
        }
        let target = ClaudeCredentialStore.PersistenceTarget(
            account: sourceID,
            sourceFingerprint: SHA256.hash(data: sourceData).map { String(format: "%02x", $0) }.joined()
        )
        let data: Data
        if let previous = entries[sourceID]?.record, previous.target == target {
            data = previous.data
        } else if let saved = readOwned(sourceID),
                  let envelope = try? JSONDecoder().decode(Envelope.self, from: saved),
                  envelope.sourceFingerprint == target.sourceFingerprint {
            data = envelope.data
        } else {
            // A Claude Code token rotation / re-login takes precedence over our cache.
            data = sourceData
        }
        let record = ClaudeCredentialStore.CredentialRecord(data: data, target: target)
        entries[sourceID] = Entry(loadedAt: date, record: record)
        return record
    }

    func persist(_ data: Data, to target: ClaudeCredentialStore.PersistenceTarget) throws {
        lock.lock()
        defer { lock.unlock() }
        // A rotation has already consumed the old refresh token. Keep the new bytes
        // usable in this process even if the keychain becomes locked after preflight.
        defer {
            if entries[target.account]?.record?.target == target {
                entries[target.account]?.record = ClaudeCredentialStore.CredentialRecord(data: data, target: target)
            }
        }
        let envelope = Envelope(sourceFingerprint: target.sourceFingerprint, data: data)
        try writeOwned(JSONEncoder().encode(envelope), target.account)
    }
}

enum ClaudeCredentialStore {
    struct PersistenceTarget: Equatable {
        let account: String
        let sourceFingerprint: String
    }

    struct CredentialRecord {
        let data: Data
        let target: PersistenceTarget
    }

    private static let cache = ClaudeCredentialCache()

    static func credentialRecords(credentialPath: String? = nil, reload: Bool = false) -> [CredentialRecord] {
        if let credentialPath {
            let credentialURL = URL(fileURLWithPath: credentialPath)
            let configDirectory = credentialURL.deletingLastPathComponent().path
            return [
                keychainRecord(service: keychainServiceName(configDirectory: configDirectory), reload: reload),
                fileRecord(url: credentialURL, reload: reload)
            ].compactMap { $0 }
        }

        let fileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        return [
            keychainRecord(service: "Claude Code-credentials", reload: reload),
            fileRecord(url: fileURL, reload: reload)
        ].compactMap { $0 }
    }

    static func credentialCandidates(credentialPath: String? = nil) -> [Data] {
        credentialRecords(credentialPath: credentialPath).map(\.data)
    }

    static func credentialData(credentialPath: String? = nil) -> Data? {
        credentialCandidates(credentialPath: credentialPath).first
    }

    static func keychainServiceName(configDirectory: String) -> String {
        let normalized = configDirectory.precomposedStringWithCanonicalMapping
        let digest = SHA256.hash(data: Data(normalized.utf8))
        let suffix = digest.prefix(4).map { String(format: "%02x", $0) }.joined()
        return "Claude Code-credentials-\(suffix)"
    }

    static func persist(_ data: Data, to target: PersistenceTarget) throws {
        try cache.persist(data, to: target)
    }

    static func mergedCredentialData(
        originalData: Data,
        refreshData: Data,
        now: Date = Date()
    ) throws -> (data: Data, accessToken: String) {
        guard
            var object = try JSONSerialization.jsonObject(with: originalData) as? [String: Any],
            var oauth = object["claudeAiOauth"] as? [String: Any],
            let refreshed = try JSONSerialization.jsonObject(with: refreshData) as? [String: Any],
            let accessToken = refreshed["access_token"] as? String,
            !accessToken.isEmpty
        else {
            throw UsageAdapterError.invalidResponse("Claude token refresh returned malformed credentials.")
        }

        oauth["accessToken"] = accessToken

        if let refreshToken = refreshed["refresh_token"] as? String, !refreshToken.isEmpty {
            oauth["refreshToken"] = refreshToken
        }

        if let expiresIn = numeric(refreshed["expires_in"]), expiresIn > 0 {
            oauth["expiresAt"] = Int((now.timeIntervalSince1970 + expiresIn) * 1000)
        }

        if let refreshTokenExpiresIn = numeric(refreshed["refresh_token_expires_in"]), refreshTokenExpiresIn > 0 {
            oauth["refreshTokenExpiresAt"] = Int((now.timeIntervalSince1970 + refreshTokenExpiresIn) * 1000)
        }

        if let scope = refreshed["scope"] as? String {
            oauth["scopes"] = scope.split(whereSeparator: \.isWhitespace).map(String.init)
        }

        object["claudeAiOauth"] = oauth
        let encoded = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        return (encoded, accessToken)
    }

    private static func keychainRecord(service: String, reload: Bool) -> CredentialRecord? {
        cache.record(sourceID: "keychain:\(service)", reload: reload) {
            ProviderKeychainReader.payload(service: service)
        }
    }

    private static func fileRecord(url: URL, reload: Bool) -> CredentialRecord? {
        cache.record(sourceID: "file:\(url.standardizedFileURL.path)", reload: reload) {
            try? Data(contentsOf: url)
        }
    }

    private static func numeric(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        default: return nil
        }
    }
}

actor ClaudeCredentialResolver {
    static let shared = ClaudeCredentialResolver()
    private let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    private let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private struct Pending {
        let id: UUID
        let forceRefresh: Bool
        let task: Task<String, Error>
    }
    private var pending: [String: Pending] = [:]
    private let records: (String?, Bool) -> [ClaudeCredentialStore.CredentialRecord]
    private let persist: (Data, ClaudeCredentialStore.PersistenceTarget) throws -> Void
    private let send: (URLRequest) async throws -> (Data, URLResponse)

    init(
        records: @escaping (String?, Bool) -> [ClaudeCredentialStore.CredentialRecord] = ClaudeCredentialStore.credentialRecords,
        persist: @escaping (Data, ClaudeCredentialStore.PersistenceTarget) throws -> Void = ClaudeCredentialStore.persist,
        send: @escaping (URLRequest) async throws -> (Data, URLResponse) = { try await URLSession.shared.data(for: $0) }
    ) {
        self.records = records
        self.persist = persist
        self.send = send
    }

    func accessToken(
        credentialPath: String? = nil,
        forceRefresh: Bool = false,
        rejectedAccessToken: String? = nil
    ) async throws -> String {
        let key = credentialPath.map { URL(fileURLWithPath: $0).standardizedFileURL.path } ?? "current-session"
        // Plan checks and overlapping usage requests share cache reads. Token refreshes
        // for one profile must also share a single rotation / persistence operation.
        if let current = pending[key] {
            let token = try await current.task.value
            if current.forceRefresh || !forceRefresh || (rejectedAccessToken != nil && token != rejectedAccessToken) {
                return token
            }
            // A normal lookup may have just returned the same token rejected by HTTP
            // 401. Join only a useful result; otherwise start the required refresh.
            if pending[key]?.id == current.id { pending[key] = nil }
            return try await accessToken(
                credentialPath: credentialPath,
                forceRefresh: forceRefresh,
                rejectedAccessToken: rejectedAccessToken
            )
        }
        let id = UUID()
        let task = Task {
            try await resolve(
                credentialPath: credentialPath,
                forceRefresh: forceRefresh,
                rejectedAccessToken: rejectedAccessToken
            )
        }
        pending[key] = Pending(id: id, forceRefresh: forceRefresh, task: task)
        defer { if pending[key]?.id == id { pending[key] = nil } }
        return try await task.value
    }

    private func resolve(
        credentialPath: String?,
        forceRefresh: Bool,
        rejectedAccessToken: String?
    ) async throws -> String {
        let records = records(credentialPath, forceRefresh)
        if credentialPath != nil, records.isEmpty {
            throw UsageAdapterError.credentialsUnavailable(
                "Claude profile credentials could not be read. Re-authenticate this UsageDock profile."
            )
        }

        var sawExpired = false
        var lastRefreshError: Error?

        for record in records {
            guard
                let object = try? JSONSerialization.jsonObject(with: record.data) as? [String: Any],
                let oauth = object["claudeAiOauth"] as? [String: Any],
                let token = oauth["accessToken"] as? String,
                !token.isEmpty
            else { continue }

            let expired = Self.isExpired(oauth["expiresAt"])
            if !expired && (!forceRefresh || (rejectedAccessToken != nil && token != rejectedAccessToken)) {
                return token
            }
            sawExpired = sawExpired || expired

            guard let refreshToken = oauth["refreshToken"] as? String, !refreshToken.isEmpty else {
                continue
            }

            do {
                // Refresh tokens may rotate. Prove we can persist before consuming one.
                try persist(record.data, record.target)
                return try await refresh(
                    record: record,
                    oauth: oauth,
                    refreshToken: refreshToken
                )
            } catch {
                lastRefreshError = error
            }
        }

        if let lastRefreshError {
            throw lastRefreshError
        }
        if sawExpired || forceRefresh {
            throw UsageAdapterError.authenticationExpired(
                "Claude login has expired and could not be refreshed automatically. Re-authenticate in Claude Code, then refresh UsageDock."
            )
        }
        throw UsageAdapterError.credentialsUnavailable("Claude OAuth credentials were not found. Sign in to Claude Code first.")
    }

    private func refresh(
        record: ClaudeCredentialStore.CredentialRecord,
        oauth: [String: Any],
        refreshToken: String
    ) async throws -> String {
        var payload: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID
        ]

        if let scopes = oauth["scopes"] as? [String], !scopes.isEmpty {
            payload["scope"] = scopes.joined(separator: " ")
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await send(request)
        guard let http = response as? HTTPURLResponse else {
            throw UsageAdapterError.invalidResponse("Claude token refresh returned a non-HTTP response.")
        }

        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 400 || http.statusCode == 401 {
                throw UsageAdapterError.authenticationExpired(
                    "Claude refresh token was rejected. Re-authenticate in Claude Code, then refresh UsageDock."
                )
            }
            throw UsageAdapterError.httpFailure(
                provider: .claude,
                statusCode: http.statusCode,
                message: "OAuth token refresh failed"
            )
        }

        let merged = try ClaudeCredentialStore.mergedCredentialData(
            originalData: record.data,
            refreshData: data
        )
        try persist(merged.data, record.target)
        return merged.accessToken
    }

    private static func isExpired(_ value: Any?) -> Bool {
        let raw: Double?
        switch value {
        case let number as NSNumber: raw = number.doubleValue
        case let string as String: raw = Double(string)
        default: raw = nil
        }
        guard let raw, raw > 0 else { return false }
        let seconds = raw > 100_000_000_000 ? raw / 1000 : raw
        return Date(timeIntervalSince1970: seconds) <= Date()
    }
}

private struct CodexCredentials {
    let accessToken: String
    let accountID: String?
}

private struct CodexCredentialResolver {
    func credentials(credentialPath: String? = nil) throws -> CodexCredentials {
        let url: URL
        if let credentialPath {
            url = URL(fileURLWithPath: credentialPath)
        } else {
            url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".codex/auth.json")
        }
        guard
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let tokens = object["tokens"] as? [String: Any],
            let accessToken = tokens["access_token"] as? String,
            !accessToken.isEmpty
        else {
            throw UsageAdapterError.credentialsUnavailable("Codex OAuth credentials were not found. Run codex login first.")
        }
        return CodexCredentials(
            accessToken: accessToken,
            accountID: tokens["account_id"] as? String
        )
    }
}

private struct GeminiCredentials {
    let accessToken: String
}

private struct GeminiCredentialResolver {
    func credentials(credentialPath: String? = nil) throws -> GeminiCredentials {
        let url: URL
        if let credentialPath {
            url = URL(fileURLWithPath: credentialPath)
        } else {
            url = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".gemini/oauth_creds.json")
        }

        guard
            let data = try? Data(contentsOf: url),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let accessToken = object["access_token"] as? String,
            !accessToken.isEmpty
        else {
            throw UsageAdapterError.credentialsUnavailable("Antigravity Google OAuth credentials were not found. Sign in with the isolated Google/Gemini CLI profile first.")
        }

        if let expiry = numeric(object["expiry_date"]), expiry > 0 {
            let seconds = expiry > 100_000_000_000 ? expiry / 1000 : expiry
            if Date(timeIntervalSince1970: seconds) <= Date() {
                throw UsageAdapterError.authenticationExpired("Antigravity Google login has expired. Re-authenticate the isolated profile, then refresh UsageDock.")
            }
        }

        return GeminiCredentials(accessToken: accessToken)
    }

    private func numeric(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        default: return nil
        }
    }
}

struct KimiDesktopCredentialResolver {
    func accessToken(codeAccessToken: String, credentialPath: String? = nil) throws -> String {
        let url = credentialPath.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(
                "Library/Application Support/kimi-desktop/daimon-share/daimon/config.json"
            )
        guard let data = try? Data(contentsOf: url) else {
            throw UsageAdapterError.credentialsUnavailable(KimiUsageAdapter.totalUnavailableNotice)
        }
        return try Self.parseAccessToken(data: data, codeAccessToken: codeAccessToken)
    }

    static func parseAccessToken(data: Data, codeAccessToken: String, now: Date = Date()) throws -> String {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let credentials = root["credentials"] as? [String: Any],
              let web = credentials["kimiWeb"] as? [String: Any],
              let token = web["accessToken"] as? String, !token.isEmpty,
              let webClaims = claims(token), let codeClaims = claims(codeAccessToken),
              let webUser = webClaims["sub"] as? String, !webUser.isEmpty,
              let codeUser = codeClaims["sub"] as? String, webUser == codeUser,
              let expiration = webClaims["exp"] as? NSNumber,
              expiration.doubleValue.isFinite, expiration.doubleValue > now.timeIntervalSince1970 else {
            // Never combine the current desktop user's plan with another CLI
            // profile, and never persist the desktop token in UsageDock settings.
            throw UsageAdapterError.credentialsUnavailable(KimiUsageAdapter.totalUnavailableNotice)
        }
        return token
    }

    private static func claims(_ token: String) -> [String: Any]? {
        let parts = token.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        var payload = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

private struct KimiCredentials {
    let accessToken: String
    let baseURL: String
}

private struct KimiCredentialResolver {
    private let oauthHost = "https://auth.kimi.com"
    private let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"

    func credentials(credentialPath: String? = nil) async throws -> KimiCredentials {
        let suppliedURL = credentialPath.map { URL(fileURLWithPath: $0) }
        let suppliedIsDirectory = suppliedURL.flatMap { url -> Bool? in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return nil }
            return isDirectory.boolValue
        } ?? false

        let home: URL
        if let suppliedURL, suppliedIsDirectory {
            home = suppliedURL.deletingLastPathComponent()
        } else if let suppliedURL {
            home = suppliedURL.deletingLastPathComponent().deletingLastPathComponent()
        } else {
            home = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".kimi-code", isDirectory: true)
        }

        let configURL = home.appendingPathComponent("config.toml")
        let config = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let parsed = parseManagedProviderConfig(config)
        let baseURL = parsed.baseURL ?? "https://api.kimi.com/coding/v1"

        let credentialURL: URL
        if let suppliedURL, suppliedIsDirectory,
           let profileCredential = try? FileManager.default.contentsOfDirectory(at: suppliedURL, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "json" }) {
            credentialURL = profileCredential
        } else if let suppliedURL {
            credentialURL = suppliedURL
        } else if let key = parsed.credentialKey, !key.isEmpty {
            let fileName = URL(fileURLWithPath: key).lastPathComponent + ".json"
            credentialURL = home.appendingPathComponent("credentials/\(fileName)")
        } else if let fallback = try? FileManager.default.contentsOfDirectory(
            at: home.appendingPathComponent("credentials", isDirectory: true),
            includingPropertiesForKeys: nil
        ).first(where: { $0.pathExtension == "json" && $0.lastPathComponent.hasPrefix("kimi-code") }) {
            credentialURL = fallback
        } else {
            throw UsageAdapterError.credentialsUnavailable("Kimi Code OAuth credentials were not found. Sign in to Kimi Code first.")
        }

        guard
            let data = try? Data(contentsOf: credentialURL),
            var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw UsageAdapterError.credentialsUnavailable("Kimi Code credential file could not be read.")
        }

        if isExpired(object["expires_at"]) {
            object = try await refreshCredentials(object, credentialURL: credentialURL)
        }

        guard let accessToken = object["access_token"] as? String, !accessToken.isEmpty else {
            throw UsageAdapterError.credentialsUnavailable("Kimi Code credential file contained no access token.")
        }

        return KimiCredentials(accessToken: accessToken, baseURL: baseURL)
    }

    private func refreshCredentials(_ current: [String: Any], credentialURL: URL) async throws -> [String: Any] {
        guard let refreshToken = current["refresh_token"] as? String, !refreshToken.isEmpty else {
            throw UsageAdapterError.authenticationExpired("Kimi access token expired and no refresh token is available. Log in to Kimi again.")
        }
        guard let url = URL(string: oauthHost + "/api/oauth/token") else {
            throw UsageAdapterError.invalidResponse("Kimi OAuth endpoint is invalid.")
        }

        let fields = [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken
        ]
        let body = fields
            .sorted { $0.key < $1.key }
            .map { "\(formEncode($0.key))=\(formEncode($0.value))" }
            .joined(separator: "&")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let refreshed = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = refreshed["access_token"] as? String, !accessToken.isEmpty else {
            throw UsageAdapterError.authenticationExpired("Kimi token refresh failed. Log in to Kimi again if this persists.")
        }

        var merged = current
        for (key, value) in refreshed { merged[key] = value }
        if refreshed["refresh_token"] == nil { merged["refresh_token"] = refreshToken }
        if let expiresIn = numeric(refreshed["expires_in"]), expiresIn > 0 {
            merged["expires_at"] = Int((Date().timeIntervalSince1970 + expiresIn) * 1000)
        }

        if let encoded = try? JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys]) {
            try? encoded.write(to: credentialURL, options: .atomic)
        }
        return merged
    }

    private func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func numeric(_ value: Any?) -> Double? {
        switch value {
        case let number as NSNumber: return number.doubleValue
        case let string as String: return Double(string)
        default: return nil
        }
    }

    private func parseManagedProviderConfig(_ config: String) -> (baseURL: String?, credentialKey: String?) {
        var section = ""
        var baseURL: String?
        var key: String?

        for rawLine in config.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("[") && line.hasSuffix("]") {
                section = line
                continue
            }
            guard let equal = line.firstIndex(of: "=") else { continue }
            let name = line[..<equal].trimmingCharacters(in: .whitespaces)
            let value = unquote(String(line[line.index(after: equal)...]).trimmingCharacters(in: .whitespaces))

            if section == "[providers.\"managed:kimi-code\"]", name == "base_url" {
                baseURL = value
            }
            if section == "[providers.\"managed:kimi-code\".oauth]", name == "key" {
                key = value
            }
        }
        return (baseURL, key)
    }

    private func unquote(_ value: String) -> String {
        guard value.count >= 2, value.first == "\"", value.last == "\"" else { return value }
        return String(value.dropFirst().dropLast())
    }

    private func isExpired(_ value: Any?) -> Bool {
        guard let value else { return false }
        if let number = value as? NSNumber {
            let raw = number.doubleValue
            let seconds = raw > 100_000_000_000 ? raw / 1000 : raw
            return seconds > 0 && Date(timeIntervalSince1970: seconds) <= Date()
        }
        if let string = value as? String {
            if let numeric = Double(string) {
                let seconds = numeric > 100_000_000_000 ? numeric / 1000 : numeric
                return seconds > 0 && Date(timeIntervalSince1970: seconds) <= Date()
            }
            if let date = UsageDateParser.date(from: string) {
                return date <= Date()
            }
        }
        return false
    }
}

private enum HTTPUsageResponseValidator {
    static func validate(response: URLResponse, data: Data, provider: ProviderID) throws {
        guard let http = response as? HTTPURLResponse else {
            throw UsageAdapterError.invalidResponse("\(provider.displayName) returned a non-HTTP response.")
        }
        guard (200...299).contains(http.statusCode) else {
            let message = errorMessage(data)
            if http.statusCode == 401 {
                throw UsageAdapterError.authenticationExpired(
                    "\(provider.displayName) login has expired. Re-authenticate in the official client, then refresh UsageDock."
                )
            }
            throw UsageAdapterError.httpFailure(provider: provider, statusCode: http.statusCode, message: message)
        }
    }

    private static func errorMessage(_ data: Data) -> String? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let error = root["error"] as? [String: Any], let message = error["message"] as? String { return message }
        if let message = root["message"] as? String { return message }
        return nil
    }
}

enum UsageDateParser {
    static func date(from value: Any?) -> Date? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        for candidate in candidates(for: string) {
            if let date = internetDate(candidate, fractional: true) { return date }
            if let date = internetDate(candidate, fractional: false) { return date }
        }
        return nil
    }

    private static func candidates(for string: String) -> [String] {
        guard let dot = string.firstIndex(of: ".") else { return [string] }
        let afterDot = string.index(after: dot)
        guard afterDot < string.endIndex else { return [string] }
        var end = afterDot
        while end < string.endIndex, string[end].isNumber {
            end = string.index(after: end)
        }
        let digits = string.distance(from: afterDot, to: end)
        guard digits > 3 else { return [string] }
        let trimmed = String(string[..<string.index(afterDot, offsetBy: 3)]) + String(string[end...])
        return [string, trimmed]
    }

    private static func internetDate(_ string: String, fractional: Bool) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = fractional
            ? [.withInternetDateTime, .withFractionalSeconds]
            : [.withInternetDateTime]
        return formatter.date(from: string)
    }
}

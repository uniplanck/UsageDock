import Foundation
import Security

struct ClaudeUsageAdapter: UsageProviderAdapter {
    let provider: ProviderID = .claude
    let credentialPath: String?

    init(credentialPath: String? = nil) {
        self.credentialPath = credentialPath
    }

    func fetchAccounts() async throws -> [UsageAccount] {
        let token = try ClaudeCredentialResolver().accessToken(credentialPath: credentialPath)
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
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

struct KimiUsageAdapter: UsageProviderAdapter {
    let provider: ProviderID = .kimi
    let credentialPath: String?

    init(credentialPath: String? = nil) {
        self.credentialPath = credentialPath
    }

    func fetchAccounts() async throws -> [UsageAccount] {
        let credentials = try await KimiCredentialResolver().credentials(credentialPath: credentialPath)
        guard let url = URL(string: credentials.baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/usages") else {
            throw UsageAdapterError.invalidResponse("Kimi managed API base URL is invalid.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        try HTTPUsageResponseValidator.validate(response: response, data: data, provider: .kimi)

        return [
            UsageAccount(
                provider: .kimi,
                name: "Current Session",
                source: .currentSession,
                buckets: try Self.parseUsage(data: data)
            )
        ]
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
        if (295...305).contains(minutes) { return "5h" }
        if (10_000...10_160).contains(minutes) { return "1w" }
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

private struct ClaudeCredentialResolver {
    func accessToken(credentialPath: String? = nil) throws -> String {
        let candidates: [Data]
        if let credentialPath {
            guard let data = try? Data(contentsOf: URL(fileURLWithPath: credentialPath)) else {
                throw UsageAdapterError.credentialsUnavailable("Claude credential file could not be read: \(credentialPath)")
            }
            candidates = [data]
        } else {
            candidates = [keychainPayload(), filePayload()].compactMap { $0 }
        }
        var sawExpired = false

        for data in candidates {
            guard
                let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let oauth = object["claudeAiOauth"] as? [String: Any],
                let token = oauth["accessToken"] as? String,
                !token.isEmpty
            else { continue }

            if let expiresAt = (oauth["expiresAt"] as? NSNumber)?.doubleValue,
               expiresAt > 0,
               Date(timeIntervalSince1970: expiresAt / 1000) <= Date() {
                sawExpired = true
                continue
            }
            return token
        }

        if sawExpired {
            throw UsageAdapterError.authenticationExpired("Claude login has expired. Re-authenticate in Claude Code, then refresh UsageDock.")
        }
        throw UsageAdapterError.credentialsUnavailable("Claude OAuth credentials were not found. Sign in to Claude Code first.")
    }

    private func keychainPayload() -> Data? {
        let query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: "Claude Code-credentials",
            kSecReturnData: true,
            kSecMatchLimit: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private func filePayload() -> Data? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/.credentials.json")
        return try? Data(contentsOf: url)
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

private enum UsageDateParser {
    static func date(from value: Any?) -> Date? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        return ISO8601DateFormatter().date(from: string)
    }
}

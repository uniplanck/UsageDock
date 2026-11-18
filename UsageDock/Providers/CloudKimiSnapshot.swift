import Foundation

/// The read key stays in the user's config file and the request; it is never
/// persisted in account metadata or included in error messages.
struct CloudKimiSnapshot {
    static let providerKey = "kimi_vivace"
    /// Info.plist key filled from the `USAGEDOCK_CLOUD_HOST` build setting (see project.yml).
    static let hostInfoPlistKey = "UsageDockCloudHost"
    static var defaultConfigURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".usage-widget/cloud.json")
    }
    /// Worker host baked into this build, or nil when the build setting is missing or malformed.
    static var configuredHost: String? {
        validatedHost(Bundle.main.object(forInfoDictionaryKey: hostInfoPlistKey) as? String)
    }

    struct Outcome {
        let buckets: [UsageBucket]
        let fetchedAt: Date
        let isFresh: Bool
    }

    enum Failure: LocalizedError {
        case unavailable
        var errorDescription: String? { "クラウド未取得" }
    }

    private struct Config: Decodable { let read_key: String }
    private struct Snapshot: Decodable {
        let version: Int
        let updated_epoch: Double
        let providers: [String: Provider]
    }
    private struct Provider: Decodable {
        let ok: Bool
        let stale: Bool
        let windows: [Window]
        let fetched_at: Double
    }
    private struct Window: Decodable {
        let key: String
        let used_percent: Double
        let window_seconds: Double
        let resets_at: Double?
    }

    /// Accepts only a bare DNS host name (ASCII letters, digits, hyphens and dots, at least two
    /// labels), so the read key is never sent with another scheme, port, path or user info.
    static func validatedHost(_ value: String?) -> String? {
        guard let host = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !host.isEmpty, host.utf8.count <= 253 else { return nil }
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else { return nil }
        for label in labels {
            guard !label.isEmpty, label.utf8.count <= 63, label.first != "-", label.last != "-",
                  label.unicodeScalars.allSatisfy({ hostLabelScalars.contains($0) }) else { return nil }
        }
        return host
    }
    private static let hostLabelScalars = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")

    static func parse(_ data: Data) throws -> Outcome {
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == 1, snapshot.updated_epoch.isFinite, snapshot.updated_epoch > 0,
              let provider = snapshot.providers[providerKey], provider.fetched_at.isFinite,
              provider.fetched_at > 0 else { throw Failure.unavailable }

        func bucket(_ key: String, seconds: Double, quotaID: String, label: String, kind: UsageWindowKind) throws -> UsageBucket {
            let matches = provider.windows.filter { $0.key == key }
            guard matches.count == 1, let window = matches.first,
                  window.window_seconds == seconds, window.used_percent.isFinite,
                  (0...100).contains(window.used_percent),
                  window.resets_at.map({ $0.isFinite && $0 > 0 }) ?? true else { throw Failure.unavailable }
            return UsageBucket(quotaID: quotaID, label: label, kind: kind,
                               percentUsed: window.used_percent / 100,
                               resetsAt: window.resets_at.map(Date.init(timeIntervalSince1970:)))
        }
        return try Outcome(buckets: [
            bucket("five_hour", seconds: 18_000, quotaID: "kimi-300", label: "5h", kind: .fiveHour),
            bucket("weekly", seconds: 604_800, quotaID: "kimi-weekly", label: "1w", kind: .weekly)
        ], fetchedAt: Date(timeIntervalSince1970: provider.fetched_at), isFresh: provider.ok && !provider.stale)
    }

    static func fetch(configURL: URL, session: URLSession? = nil,
                      host: String? = CloudKimiSnapshot.configuredHost) async throws -> Outcome {
        guard let cloudHost = validatedHost(host),
              let data = try? Data(contentsOf: configURL),
              let key = try? JSONDecoder().decode(Config.self, from: data).read_key,
              !key.isEmpty,
              let escaped = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed.subtracting(CharacterSet(charactersIn: "/?#"))),
              let url = URL(string: "https://" + cloudHost + "/u/" + escaped) else {
            throw Failure.unavailable
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 10
        let requestSession = session ?? URLSession(configuration: configuration)
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("usage-widget/1.0", forHTTPHeaderField: "User-Agent")
        do {
            let (payload, response) = try await requestSession.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw Failure.unavailable }
            return try parse(payload)
        } catch {
            // URLSession errors may contain the secret-bearing URL.
            throw Failure.unavailable
        }
    }
}

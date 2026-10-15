import AppKit
import Foundation
import os

/// Decodes the grok.com Settings → Usage payload.
///
/// The page reads `POST https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig`
/// as gRPC-web+proto with an empty data frame. Documented paths, from a captured
/// credits config, are `[1,1]` used percent, `[1,4]` period start, `[1,5]` reset,
/// and `[1,7]` product messages (enum at field 1, percent at field 2). The CLI
/// bearer token is refused here; the call is cookie-authenticated inside the
/// grok.com page.
///
/// A missing used-percent field is a decode failure. This type does not turn
/// that into 0%.
enum GrokWebCredits {
    static let endpoint = URL(string: "https://grok.com/grok_api_v2.GrokBuildBilling/GetGrokCreditsConfig")!
    static let usagePage = URL(string: "https://grok.com/?_s=usage")!

    struct Product: Equatable {
        var id: Int
        var name: String
        var percentUsed: Double
    }

    struct Reading: Equatable {
        var percentUsed: Double
        var resetsAt: Date?
        var periodStart: Date?
        var products: [Product]
    }

    enum Interpretation: Equatable {
        case usage(Reading)
        case needsReLogin(String)
        case undecodable(String)
        case unavailable(String)
    }

    struct Verdict {
        var interpretation: Interpretation
        var diagnostic: String
    }

    private static let logger = Logger(subsystem: "com.uniplanck.UsageDock", category: "GrokWeb")

    /// Product names observed on the web usage panel. Enums outside this list
    /// stay numeric so an unconfirmed value such as Grok Bot is not mislabeled.
    static func productName(for id: Int) -> String {
        switch id {
        case 1: "API"
        case 2: "Grok Build"
        case 3: "Other"
        case 4: "Chat"
        case 5: "Imagine"
        case 6: "Voice"
        default: "Product \(id)"
        }
    }

    static func interpret(
        body: Data,
        httpStatus: Int,
        contentType: String = "",
        headerGrpcStatus: Int? = nil
    ) -> Verdict {
        var lines: [String] = []
        lines.append("http_status: \(httpStatus)")
        if !contentType.isEmpty {
            lines.append("content_type: \(sanitize(contentType))")
        }
        lines.append("body_bytes: \(body.count)")
        if let headerGrpcStatus {
            lines.append("header_grpc_status: \(headerGrpcStatus)")
        }

        if httpStatus == 401 || httpStatus == 403 {
            let diagnostic = finish(lines + ["result: needs re-login (HTTP \(httpStatus))"])
            return Verdict(
                interpretation: .needsReLogin("Grok web login expired (HTTP \(httpStatus)). Sign in again on grok.com."),
                diagnostic: diagnostic
            )
        }
        if let headerGrpcStatus, isAuthGrpcStatus(headerGrpcStatus) {
            let diagnostic = finish(lines + ["result: needs re-login (grpc-status \(headerGrpcStatus))"])
            return Verdict(
                interpretation: .needsReLogin("Grok web login expired (grpc-status \(headerGrpcStatus)). Sign in again on grok.com."),
                diagnostic: diagnostic
            )
        }
        if bodyLooksLikeHTML(body) || contentType.lowercased().contains("text/html") {
            let diagnostic = finish(lines + ["result: needs re-login (HTML response)"])
            return Verdict(
                interpretation: .needsReLogin("Grok web login is not active. Sign in again on grok.com."),
                diagnostic: diagnostic
            )
        }

        let framed = unwrapFrames(body)
        lines.append(contentsOf: framed.notes)
        if let status = framed.grpcStatus {
            lines.append("trailer_grpc_status: \(status)")
            if let message = framed.grpcMessage, !message.isEmpty {
                lines.append("trailer_grpc_message: \(sanitize(message))")
            }
        }
        if framed.compressed {
            let diagnostic = finish(lines + ["result: undecodable (compressed grpc frame). UsageDock will not invent 0%."])
            return Verdict(
                interpretation: .undecodable("Grok web usage response was compressed and could not be decoded. UsageDock will not invent 0%."),
                diagnostic: diagnostic
            )
        }
        if let status = framed.grpcStatus, status != 0 {
            if isAuthGrpcStatus(status) {
                let diagnostic = finish(lines + ["result: needs re-login (trailer \(status))"])
                return Verdict(
                    interpretation: .needsReLogin("Grok web login expired (grpc-status \(status)). Sign in again on grok.com."),
                    diagnostic: diagnostic
                )
            }
            let diagnostic = finish(lines + ["result: undecodable (grpc-status \(status)). UsageDock will not invent 0%."])
            return Verdict(
                interpretation: .undecodable("Grok web usage failed with grpc-status \(status). UsageDock will not invent 0%."),
                diagnostic: diagnostic
            )
        }

        guard let message = framed.message else {
            let diagnostic = finish(lines + ["result: undecodable (no protobuf message). UsageDock will not invent 0%."])
            return Verdict(
                interpretation: .undecodable("Grok web usage response had no decodable protobuf message. UsageDock will not invent 0%."),
                diagnostic: diagnostic
            )
        }

        lines.append("fields:")
        lines.append(contentsOf: trace(message).map { "  \($0)" })

        guard let configValues = message[1], let config = configValues.compactMap(\.messageValue).first else {
            let diagnostic = finish(lines + ["result: undecodable (missing field 1). UsageDock will not invent 0%."])
            return Verdict(
                interpretation: .undecodable("Grok web usage response did not include a usage percentage. UsageDock will not invent 0%."),
                diagnostic: diagnostic
            )
        }
        guard let percentPoints = scalarNumber(config[1]) else {
            let diagnostic = finish(lines + ["result: undecodable (missing field 1.1). UsageDock will not invent 0%."])
            return Verdict(
                interpretation: .undecodable("Grok web usage response did not include a usage percentage. UsageDock will not invent 0%."),
                diagnostic: diagnostic
            )
        }
        guard percentPoints >= 0, percentPoints <= 100 else {
            let diagnostic = finish(lines + ["result: undecodable (field 1.1 = \(percentPoints) is outside 0...100). UsageDock will not invent 0%."])
            return Verdict(
                interpretation: .undecodable("Grok web usage percentage \(percentPoints) is outside 0...100. UsageDock will not invent 0%."),
                diagnostic: diagnostic
            )
        }

        let periodStart = timestamp(config[4])
        let resetsAt = timestamp(config[5])
        let products = products(in: config[7] ?? [])
        if resetsAt == nil {
            lines.append("reset: missing field 1.5")
        }
        let reading = Reading(
            percentUsed: percentPoints / 100,
            resetsAt: resetsAt,
            periodStart: periodStart,
            products: products
        )
        lines.append(String(format: "result: used %.4f, products %d", reading.percentUsed, products.count))
        return Verdict(interpretation: .usage(reading), diagnostic: finish(lines))
    }

    static func buckets(from reading: Reading) -> [UsageBucket] {
        var buckets = [
            UsageBucket(
                quotaID: "grok-weekly",
                label: "1w",
                kind: .weekly,
                percentUsed: reading.percentUsed,
                resetsAt: reading.resetsAt
            )
        ]
        for product in reading.products {
            buckets.append(
                UsageBucket(
                    quotaID: "grok-web-product-\(product.id)",
                    label: product.name,
                    kind: .custom,
                    model: product.name,
                    percentUsed: product.percentUsed,
                    resetsAt: reading.resetsAt
                )
            )
        }
        return buckets
    }

    private static func isAuthGrpcStatus(_ status: Int) -> Bool {
        status == 7 || status == 16
    }

    private static func finish(_ lines: [String]) -> String {
        let text = lines.joined(separator: "\n")
        logger.info("\(text, privacy: .public)")
        GrokWebDiagnostics.store(text)
        return text
    }

    private static func bodyLooksLikeHTML(_ body: Data) -> Bool {
        guard let prefix = String(data: body.prefix(64), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return prefix.hasPrefix("<!doctype") || prefix.hasPrefix("<html") || prefix.hasPrefix("<head")
    }

    private static func sanitize(_ value: String) -> String {
        let lowered = value.lowercased()
        if lowered.contains("cookie") || lowered.contains("token") || lowered.contains("bearer") || lowered.contains("authorization") || lowered.contains("sso") {
            return "[redacted]"
        }
        if value.count > 160 {
            return "[text \(value.count) chars]"
        }
        return value
    }

    // MARK: - gRPC-web

    private struct FramedBody {
        var message: [Int: [ProtoValue]]?
        var grpcStatus: Int?
        var grpcMessage: String?
        var compressed: Bool
        var notes: [String]
    }

    private static func unwrapFrames(_ body: Data, allowBase64: Bool = true) -> FramedBody {
        if allowBase64, let decoded = base64Body(body) {
            var framed = unwrapFrames(decoded, allowBase64: false)
            framed.notes.insert("body: base64 grpc-web", at: 0)
            return framed
        }

        var notes: [String] = []
        var dataFrames: [Data] = []
        var grpcStatus: Int?
        var grpcMessage: String?
        var compressed = false
        var offset = 0
        var frameCount = 0
        while offset + 5 <= body.count {
            let flag = body[offset]
            let length = Int(UInt32(body[offset + 1]) << 24 | UInt32(body[offset + 2]) << 16 | UInt32(body[offset + 3]) << 8 | UInt32(body[offset + 4]))
            let payloadStart = offset + 5
            guard length >= 0, payloadStart + length <= body.count else { break }
            let payload = body.subdata(in: payloadStart..<(payloadStart + length))
            offset = payloadStart + length
            frameCount += 1
            let trailer = flag & 0x80 != 0
            if flag & 0x01 != 0 {
                compressed = true
                notes.append("frame \(frameCount): compressed \(payload.count) bytes")
                continue
            }
            if trailer {
                let text = String(data: payload, encoding: .utf8) ?? ""
                notes.append("frame \(frameCount): trailer \(payload.count) bytes")
                for line in text.split(whereSeparator: \.isNewline) {
                    let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
                    guard parts.count == 2 else { continue }
                    if parts[0].caseInsensitiveCompare("grpc-status") == .orderedSame {
                        grpcStatus = Int(parts[1])
                    } else if parts[0].caseInsensitiveCompare("grpc-message") == .orderedSame {
                        grpcMessage = parts[1].removingPercentEncoding ?? parts[1]
                    }
                }
            } else {
                notes.append("frame \(frameCount): data \(payload.count) bytes")
                dataFrames.append(payload)
            }
        }

        if frameCount == 0 {
            if let message = parseMessage(body), !message.isEmpty {
                notes.append("body: raw protobuf, no grpc-web frame")
                return FramedBody(message: message, grpcStatus: grpcStatus, grpcMessage: grpcMessage, compressed: compressed, notes: notes)
            }
            notes.append("body: no grpc-web frame")
            return FramedBody(message: nil, grpcStatus: grpcStatus, grpcMessage: grpcMessage, compressed: compressed, notes: notes)
        }

        let message = dataFrames.compactMap { parseMessage($0) }.first { !$0.isEmpty }
        return FramedBody(message: message, grpcStatus: grpcStatus, grpcMessage: grpcMessage, compressed: compressed, notes: notes)
    }

    // MARK: - Protobuf

    private enum ProtoValue {
        case varint(UInt64)
        case fixed64(UInt64)
        case fixed32(UInt32)
        case message([Int: [ProtoValue]])
        case text(String)
        case bytes(Int)

        var messageValue: [Int: [ProtoValue]]? {
            if case .message(let value) = self { return value }
            return nil
        }
    }

    private static func parseMessage(_ data: Data) -> [Int: [ProtoValue]]? {
        var cursor = ProtoCursor(data: data)
        var fields: [Int: [ProtoValue]] = [:]
        while !cursor.isAtEnd {
            guard let key = cursor.readVarint() else { return nil }
            let field = Int(key >> 3)
            let wire = Int(key & 0x7)
            guard field > 0 else { return nil }
            let value: ProtoValue
            switch wire {
            case 0:
                guard let number = cursor.readVarint() else { return nil }
                value = .varint(number)
            case 1:
                guard let number = cursor.readFixed64() else { return nil }
                value = .fixed64(number)
            case 2:
                guard let payload = cursor.readLengthDelimited() else { return nil }
                value = lengthDelimited(payload)
            case 5:
                guard let number = cursor.readFixed32() else { return nil }
                value = .fixed32(number)
            default:
                return nil
            }
            fields[field, default: []].append(value)
        }
        return fields
    }

    private static func lengthDelimited(_ data: Data) -> ProtoValue {
        if let text = printableText(data), prefersText(text) {
            return .text(text)
        }
        if let message = parseMessage(data), !message.isEmpty {
            return .message(message)
        }
        if let text = printableText(data) {
            return .text(text)
        }
        return .bytes(data.count)
    }

    private static func printableText(_ data: Data) -> String? {
        guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return nil }
        let hasControl = text.unicodeScalars.contains { scalar in
            scalar.value < 32 && scalar.value != 9 && scalar.value != 10 && scalar.value != 13
        }
        return hasControl ? nil : text
    }

    private static func prefersText(_ text: String) -> Bool {
        if UsageDateParser.date(from: text) != nil { return true }
        if Double(text.replacingOccurrences(of: "%", with: "")) != nil { return true }
        return text.allSatisfy { character in
            character.isLetter || character.isNumber || character == " " || character == "_" || character == "-" || character == "."
        }
    }

    private static func scalarNumber(_ values: [ProtoValue]?) -> Double? {
        guard let values else { return nil }
        for value in values {
            switch value {
            case .varint(let number):
                return Double(number)
            case .fixed64(let bits):
                let number = Double(bitPattern: bits)
                if number.isFinite { return number }
            case .fixed32(let bits):
                let number = Double(Float(bitPattern: bits))
                if number.isFinite { return number }
            case .text(let text):
                let cleaned = text.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
                if let number = Double(cleaned) { return number }
            case .message, .bytes:
                continue
            }
        }
        return nil
    }

    private static func timestamp(_ values: [ProtoValue]?) -> Date? {
        guard let values else { return nil }
        for value in values {
            switch value {
            case .text(let text):
                if let date = UsageDateParser.date(from: text) { return date }
            case .varint(let number), .fixed64(let number):
                if let date = date(fromUnix: number) { return date }
            case .message(let fields):
                if let seconds = fields[1]?.first.flatMap(unsigned), let date = date(fromUnix: seconds) {
                    return date
                }
            case .fixed32, .bytes:
                continue
            }
        }
        return nil
    }

    private static func date(fromUnix number: UInt64) -> Date? {
        let seconds: TimeInterval
        if number >= 1_000_000_000_000 {
            seconds = TimeInterval(number) / 1000
        } else if number >= 1_000_000_000 {
            seconds = TimeInterval(number)
        } else {
            return nil
        }
        return Date(timeIntervalSince1970: seconds)
    }

    private static func products(in values: [ProtoValue]) -> [Product] {
        var products: [Product] = []
        for value in values {
            guard case .message(let fields) = value else { continue }
            guard let id64 = fields[1]?.first.flatMap(unsigned), id64 <= UInt64(Int.max) else { continue }
            guard let points = scalarNumber(fields[2]), points >= 0, points <= 100 else { continue }
            let id = Int(id64)
            products.append(Product(id: id, name: productName(for: id), percentUsed: points / 100))
        }
        return products
    }

    private static func trace(_ fields: [Int: [ProtoValue]], prefix: [Int] = []) -> [String] {
        var lines: [String] = []
        for key in fields.keys.sorted() {
            for value in fields[key] ?? [] {
                let path = (prefix + [key]).map(String.init).joined(separator: ".")
                switch value {
                case .varint(let number):
                    lines.append("\(path) varint \(number)")
                case .fixed64(let bits):
                    let number = Double(bitPattern: bits)
                    if number.isFinite {
                        lines.append("\(path) fixed64 \(number) bits \(bits)")
                    } else {
                        lines.append("\(path) fixed64 bits \(bits)")
                    }
                case .fixed32(let bits):
                    lines.append("\(path) fixed32 \(Double(Float(bitPattern: bits)))")
                case .text(let text):
                    lines.append("\(path) string \(sanitize(text))")
                case .bytes(let count):
                    lines.append("\(path) bytes \(count)")
                case .message(let nested):
                    lines.append("\(path) message")
                    lines.append(contentsOf: trace(nested, prefix: prefix + [key]))
                }
            }
        }
        return lines
    }

    private static func unsigned(_ value: ProtoValue) -> UInt64? {
        switch value {
        case .varint(let number), .fixed64(let number): number
        case .fixed32(let number): UInt64(number)
        default: nil
        }
    }

    private static func base64Body(_ body: Data) -> Data? {
        guard let text = String(data: body, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              text.count >= 8,
              text.unicodeScalars.allSatisfy({ $0.value >= 32 && $0.value < 127 || $0.value == 10 || $0.value == 13 }),
              let decoded = Data(base64Encoded: text, options: [.ignoreUnknownCharacters]),
              decoded.count >= 5
        else { return nil }
        return decoded
    }
}

private struct ProtoCursor {
    var data: Data
    var index = 0

    var isAtEnd: Bool { index >= data.count }

    mutating func readByte() -> UInt8? {
        guard index < data.count else { return nil }
        let byte = data[index]
        index += 1
        return byte
    }

    mutating func readVarint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        for _ in 0..<10 {
            guard let byte = readByte() else { return nil }
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }

    mutating func readFixed32() -> UInt32? {
        guard index + 4 <= data.count else { return nil }
        let value = UInt32(data[index])
            | UInt32(data[index + 1]) << 8
            | UInt32(data[index + 2]) << 16
            | UInt32(data[index + 3]) << 24
        index += 4
        return value
    }

    mutating func readFixed64() -> UInt64? {
        guard index + 8 <= data.count else { return nil }
        var value: UInt64 = 0
        for offset in 0..<8 {
            value |= UInt64(data[index + offset]) << UInt64(offset * 8)
        }
        index += 8
        return value
    }

    mutating func readLengthDelimited() -> Data? {
        guard let length = readVarint(), length <= UInt64(data.count - index) else { return nil }
        let size = Int(length)
        let payload = data.subdata(in: index..<(index + size))
        index += size
        return payload
    }
}

enum GrokWebDiagnostics {
    private static let defaultsKey = "UsageDock.grokWebDiagnostics.v1"
    private static let lock = NSLock()
    private static var memory = ""

    static var latest: String {
        lock.lock()
        defer { lock.unlock() }
        if !memory.isEmpty { return memory }
        return UserDefaults.standard.string(forKey: defaultsKey) ?? ""
    }

    static func store(_ text: String) {
        let clipped = String(text.prefix(20_000))
        lock.lock()
        memory = clipped
        lock.unlock()
        UserDefaults.standard.set(clipped, forKey: defaultsKey)
    }

    @discardableResult
    static func copyToPasteboard() -> Bool {
        let text = latest
        guard !text.isEmpty else { return false }
        NSPasteboard.general.clearContents()
        return NSPasteboard.general.setString(text, forType: .string)
    }
}

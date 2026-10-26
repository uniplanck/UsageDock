import Foundation

/// Shared reset countdown formatting, preserving each surface's precision and fields.
enum ResetCountdownFormatter {
    struct RailOptions {
        var dayDigits: RailDigitWidth = .one
        var hourDigits: RailDigitWidth = .one
        var minuteDigits: RailDigitWidth = .two
        var showHours = true
        var showMinutes = true
        var autoHideZeroDays = true
        var autoHideZeroHours = false
    }

    enum Style {
        case detail
        case rail(RailOptions)
    }

    static func string(
        until resetDate: Date?,
        now: Date = Date(),
        hideMinutesWhenDays: Bool,
        style: Style
    ) -> String? {
        guard let resetDate else { return nil }
        let remainingMinutes = resetDate.timeIntervalSince(now) / 60
        let totalMinutes: Int
        switch style {
        case .detail:
            totalMinutes = max(Int(ceil(remainingMinutes)), 0)
            if totalMinutes == 0 { return "<1m" }
        case .rail:
            guard resetDate > now else { return nil }
            totalMinutes = max(Int(remainingMinutes), 0)
        }

        let days = totalMinutes / 1_440
        let hours = (totalMinutes % 1_440) / 60
        let minutes = totalMinutes % 60
        let options: RailOptions
        switch style {
        case .detail:
            options = RailOptions(minuteDigits: .one, autoHideZeroHours: days == 0)
        case .rail(let railOptions):
            options = railOptions
        }

        var parts: [String] = []
        if !(options.autoHideZeroDays && days == 0) {
            parts.append("\(value(days, width: options.dayDigits))d")
        }
        if options.showHours && !(options.autoHideZeroHours && hours == 0) {
            parts.append("\(value(hours, width: options.hourDigits))h")
        }
        if !(hideMinutesWhenDays && days > 0),
           options.showMinutes || (days == 0 && hours == 0) {
            parts.append("\(value(minutes, width: options.minuteDigits))m")
        }
        // Preserve the rail's minute fallback when all other fields are hidden.
        if parts.isEmpty {
            parts.append("\(value(minutes, width: options.minuteDigits))m")
        }
        return parts.joined(separator: " ")
    }

    private static func value(_ value: Int, width: RailDigitWidth) -> String {
        width == .two ? String(format: "%02d", value) : "\(value)"
    }
}

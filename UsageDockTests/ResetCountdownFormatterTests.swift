import Foundation
import XCTest
@testable import UsageDock

final class ResetCountdownFormatterTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func text(
        _ seconds: TimeInterval,
        hideMinutes: Bool,
        style: ResetCountdownFormatter.Style = .detail
    ) -> String? {
        ResetCountdownFormatter.string(
            until: now.addingTimeInterval(seconds),
            now: now,
            hideMinutesWhenDays: hideMinutes,
            style: style
        )
    }

    func testDaysHideMinutesWhenEnabledOnBothSurfaces() {
        let seconds: TimeInterval = (2 * 1_440 + 5 * 60 + 12) * 60
        for style in [ResetCountdownFormatter.Style.detail, .rail(.init())] {
            XCTAssertEqual(text(seconds, hideMinutes: true, style: style), "2d 5h")
        }
    }

    func testDaysKeepMinutesWhenDisabledOnBothSurfaces() {
        let seconds: TimeInterval = (2 * 1_440 + 5 * 60 + 12) * 60
        for style in [ResetCountdownFormatter.Style.detail, .rail(.init())] {
            XCTAssertEqual(text(seconds, hideMinutes: false, style: style), "2d 5h 12m")
        }
    }

    func testZeroDaysKeepExistingHoursAndMinutes() {
        for hide in [false, true] {
            XCTAssertEqual(text(5 * 3_600 + 12 * 60, hideMinutes: hide), "5h 12m")
            XCTAssertEqual(text(5 * 3_600 + 12 * 60, hideMinutes: hide, style: .rail(.init())), "5h 12m")
            XCTAssertEqual(text(5 * 60, hideMinutes: hide), "5m")
            XCTAssertEqual(text(5 * 60, hideMinutes: hide, style: .rail(.init())), "0h 05m")
        }
    }

    func testVisibleZeroDayFieldDoesNotHideMinutes() {
        let options = ResetCountdownFormatter.RailOptions(autoHideZeroDays: false)
        for hide in [false, true] {
            XCTAssertEqual(text(5 * 3_600 + 12 * 60, hideMinutes: hide, style: .rail(options)), "0d 5h 12m")
        }
    }

    func testRailPreservesDigitWidthsAndHiddenHours() {
        var options = ResetCountdownFormatter.RailOptions(dayDigits: .two, hourDigits: .two)
        let seconds: TimeInterval = (2 * 1_440 + 5 * 60 + 7) * 60
        XCTAssertEqual(text(seconds, hideMinutes: true, style: .rail(options)), "02d 05h")
        XCTAssertEqual(text(seconds, hideMinutes: false, style: .rail(options)), "02d 05h 07m")
        options.showHours = false
        XCTAssertEqual(text(seconds, hideMinutes: true, style: .rail(options)), "02d")
        XCTAssertEqual(text(seconds, hideMinutes: false, style: .rail(options)), "02d 07m")
    }

    func testZeroHoursAndMinutesRespectExistingVisibility() {
        let seconds: TimeInterval = 2 * 86_400
        XCTAssertEqual(text(seconds, hideMinutes: true), "2d 0h")
        XCTAssertEqual(text(seconds, hideMinutes: false), "2d 0h 0m")
        let options = ResetCountdownFormatter.RailOptions(autoHideZeroHours: true)
        XCTAssertEqual(text(seconds, hideMinutes: true, style: .rail(options)), "2d")
        XCTAssertEqual(text(seconds, hideMinutes: false, style: .rail(options)), "2d 00m")
    }

    func testRailMinuteVisibilityAndUnderOneHourFallbackAreUnchanged() {
        let options = ResetCountdownFormatter.RailOptions(showHours: false, showMinutes: false)
        for hide in [false, true] {
            XCTAssertEqual(text(23 * 60, hideMinutes: hide, style: .rail(options)), "23m")
            XCTAssertEqual(text(2 * 86_400 + 12 * 60, hideMinutes: hide, style: .rail(options)), "2d")
        }
    }

    func testRailFloorsAndDetailCeilsAtDayBoundary() {
        for hide in [false, true] {
            XCTAssertEqual(text(86_399, hideMinutes: hide, style: .rail(.init())), "23h 59m")
        }
        XCTAssertEqual(text(86_399, hideMinutes: true), "1d 0h")
        XCTAssertEqual(text(86_399, hideMinutes: false), "1d 0h 0m")
    }

    func testSubMinuteAndExpiredBehaviorIsUnchanged() {
        for hide in [false, true] {
            XCTAssertEqual(text(30, hideMinutes: hide), "1m")
            XCTAssertEqual(text(30, hideMinutes: hide, style: .rail(.init())), "0h 00m")
            for seconds: TimeInterval in [0, -1, -3_600] {
                XCTAssertEqual(text(seconds, hideMinutes: hide), "<1m")
                XCTAssertNil(text(seconds, hideMinutes: hide, style: .rail(.init())))
            }
            for style in [ResetCountdownFormatter.Style.detail, .rail(.init())] {
                XCTAssertNil(ResetCountdownFormatter.string(until: nil, now: now, hideMinutesWhenDays: hide, style: style))
            }
        }
    }
}

@MainActor
final class ResetCountdownPreferenceTests: XCTestCase {
    func testDefaultIsOnInBothAppLanguages() {
        let suiteName = "UsageDockTests.ResetCountdown.Default.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let date = now.addingTimeInterval((2 * 1_440 + 5 * 60 + 12) * 60)

        XCTAssertTrue(store.hideMinutesWhenDays)
        for language in [UsageDockLanguage.english, .japanese] {
            store.appLanguage = language
            // Both languages currently use the same compact d/h/m notation.
            XCTAssertEqual(store.railRemainingTimeText(until: date, now: now), "2d 5h")
            XCTAssertEqual(store.remainingResetTimeText(until: date, now: now), "2d 5h")
        }
    }

    func testTogglePersistsBothValuesAndUpdatesBothSurfaces() {
        let suiteName = "UsageDockTests.ResetCountdown.Persistence.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = UsageStore(defaults: defaults)
        let now = Date(timeIntervalSince1970: 1_000_000)
        let date = now.addingTimeInterval((2 * 1_440 + 5 * 60 + 12) * 60)

        for hide in [false, true] {
            store.hideMinutesWhenDays = hide
            XCTAssertEqual(defaults.object(forKey: "UsageDock.hideMinutesWhenDays.v1") as? Bool, hide)
            let reloaded = UsageStore(defaults: defaults)
            XCTAssertEqual(reloaded.hideMinutesWhenDays, hide)
            for language in [UsageDockLanguage.english, .japanese] {
                reloaded.appLanguage = language
                let expected = hide ? "2d 5h" : "2d 5h 12m"
                XCTAssertEqual(store.railRemainingTimeText(until: date, now: now), expected)
                XCTAssertEqual(store.remainingResetTimeText(until: date, now: now), expected)
                XCTAssertEqual(reloaded.railRemainingTimeText(until: date, now: now), expected)
                XCTAssertEqual(reloaded.remainingResetTimeText(until: date, now: now), expected)
            }
        }
    }

    func testToggleLabelUsesExistingEnglishAndJapaneseLocalization() {
        let key = "Hide minutes when days are shown"
        XCTAssertEqual(UsageDockLanguage.english.localized(key), key)
        XCTAssertEqual(UsageDockLanguage.japanese.localized(key), "日数があるときは分を表示しない")
    }
}

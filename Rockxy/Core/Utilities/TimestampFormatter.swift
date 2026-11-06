import Foundation

/// Formats a capture timestamp as a time of day.
///
/// This is the single implementation behind every wall-clock time Rockxy shows, so the same
/// transaction never reads differently in the request list, the Diff candidate picker, the
/// WebSocket frame list, and the script console. A hardcoded `dateFormat` of `"HH:mm:ss"` is
/// locale-blind and ignores the user's 24-Hour Time preference: on `en_US` the request list
/// printed "21:19:10" for the row the Diff picker called "9:19:10 PM", and on `ko_KR` for the one
/// it called "오후 9:19:10". A fixed pattern belongs only in machine-readable output, where
/// `en_US_POSIX` pins it on purpose.
///
/// The formatters are cached: `DateFormatter` is expensive to build, and a WebSocket frame list
/// asks for one per visible row on every redraw.
enum TimestampFormatter {
    // MARK: Internal

    /// Hour, minute, and second in the user's locale and clock preference.
    static func timeOfDay(_ date: Date, locale: Locale = RockxyLocalization.locale) -> String {
        formatter(template: "jms", locale: locale).string(from: date)
    }

    /// As `timeOfDay(_:)`, plus milliseconds. WebSocket frames arrive milliseconds apart, so the
    /// frame list needs the sub-second digits to order them by eye.
    static func timeOfDayWithMilliseconds(_ date: Date, locale: Locale = RockxyLocalization.locale) -> String {
        formatter(template: "jmsSSS", locale: locale).string(from: date)
    }

    /// A date and/or time in one of the standard styles, in Rockxy's formatting locale.
    /// `Date.formatted(date:time:)` would use the Mac's language even after the user picks
    /// another one in Rockxy, so a Chinese interface printed "Sep 23, 2026 at 9:13 PM".
    static func string(
        _ date: Date,
        date dateStyle: Date.FormatStyle.DateStyle,
        time timeStyle: Date.FormatStyle.TimeStyle,
        locale: Locale = RockxyLocalization.locale
    ) -> String {
        date.formatted(Date.FormatStyle(date: dateStyle, time: timeStyle, locale: locale))
    }

    /// The abbreviated weekday ("Tue").
    static func weekday(_ date: Date, locale: Locale = RockxyLocalization.locale) -> String {
        date.formatted(Date.FormatStyle(locale: locale).weekday(.abbreviated))
    }

    /// How long ago a date was ("5 minutes ago"), relative to `now`.
    static func relative(
        _ date: Date,
        to now: Date = Date(),
        unitsStyle: RelativeDateTimeFormatter.UnitsStyle = .full,
        locale: Locale = RockxyLocalization.locale
    ) -> String {
        relativeString(for: date, relativeTo: now, unitsStyle: unitsStyle, locale: locale)
    }

    // MARK: Private

    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: DateFormatter] = [:]
    nonisolated(unsafe) private static var relativeCache: [String: RelativeDateTimeFormatter] = [:]

    /// Cached for the same reason the template formatters below are: callers sit in SwiftUI
    /// bodies that re-evaluate per captured frame, and an `NSFormatter` allocation per call
    /// also pays first-use locale and number setup. Keyed by locale and style because
    /// `RelativeDateTimeFormatter` resolves its wording from both, so a language change still
    /// takes effect.
    ///
    /// The string is produced INSIDE the lock, unlike the template formatters, which hand the
    /// `DateFormatter` back to the caller. `DateFormatter` is documented thread-safe for
    /// formatting; `RelativeDateTimeFormatter` carries no such guarantee, so handing one
    /// instance to several threads would be a data race. Serializing the call keeps the
    /// allocation saving without betting on an undocumented guarantee.
    private static func relativeString(
        for date: Date,
        relativeTo now: Date,
        unitsStyle: RelativeDateTimeFormatter.UnitsStyle,
        locale: Locale
    ) -> String {
        let key = "\(locale.identifier)|\(unitsStyle.rawValue)"
        lock.lock()
        defer { lock.unlock() }
        let formatter: RelativeDateTimeFormatter
        if let cached = relativeCache[key] {
            formatter = cached
        } else {
            formatter = RelativeDateTimeFormatter()
            formatter.locale = locale
            formatter.unitsStyle = unitsStyle
            relativeCache[key] = formatter
        }
        return formatter.localizedString(for: date, relativeTo: now)
    }

    /// A localized template, not a fixed pattern: `setLocalizedDateFormatFromTemplate` resolves
    /// the field order and the 12-/24-hour choice from the locale. Cached per template, locale,
    /// and hour cycle so a language change takes effect without rebuilding a formatter per row.
    /// The pattern is resolved once per formatter, and the Mac's live locale keeps its
    /// identifier when the 24-Hour Time setting flips, so the hour cycle is part of the key.
    private static func formatter(template: String, locale: Locale) -> DateFormatter {
        let key = "\(template)|\(locale.identifier)|\(locale.hourCycle)"
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[key] {
            return cached
        }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate(template)
        cache[key] = formatter
        return formatter
    }
}

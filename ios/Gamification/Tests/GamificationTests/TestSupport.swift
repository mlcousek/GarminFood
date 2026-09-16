import Foundation

/// Shared UTC calendar + date-construction helper for every test in this
/// target, so every test builds dates the same deterministic way
/// regardless of the machine/CI runner's local time zone.
enum TestClock {
    static var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Defaults to noon so a constructed "logged at this day" timestamp
    /// sits comfortably inside the nutrition day regardless of the 04:00
    /// boundary, unless a test is deliberately probing the boundary itself
    /// (in which case pass an explicit `hour`).
    static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }
}

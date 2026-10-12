import Foundation

/// A calendar day with no time and no time zone, written as YYYY-MM-DD.
public struct DateOnly: Equatable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int

    public init?(year: Int, month: Int, day: Int) {
        guard (1...9999).contains(year), (1...12).contains(month),
              (1...DateOnly.daysIn(month: month, year: year)).contains(day)
        else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    /// Strict: exactly four digits, two digits, two digits, joined by hyphens.
    public init?(_ string: String) {
        let bytes = Array(string.utf8)
        guard bytes.count == 10, bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-") else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for byte in bytes[range] {
                guard (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte) else { return nil }
                value = value * 10 + Int(byte - UInt8(ascii: "0"))
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The calendar day `date` falls on in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 1
        month = parts.month ?? 1
        day = parts.day ?? 1
    }

    public var description: String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    /// Noon on this day, so a time-zone or daylight-saving shift cannot move it to a neighbour.
    public func date(in calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    /// Whole days from this day to `other`; negative when `other` is earlier.
    public func days(until other: DateOnly) -> Int {
        other.dayNumber - dayNumber
    }

    public static func < (lhs: DateOnly, rhs: DateOnly) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 4, 6, 9, 11: return 30
        case 2:
            let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
            return leap ? 29 : 28
        default: return 31
        }
    }

    /// Days since a fixed origin in the Gregorian calendar (Howard Hinnant's days_from_civil).
    private var dayNumber: Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let dayOfYear = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        return era * 146097 + dayOfEra
    }
}

/// How a due date reads in the task row.
public enum DueFormatting {
    private static let months = [
        "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
    ]

    public static func label(for due: DateOnly, today: DateOnly) -> String {
        switch today.days(until: due) {
        case 0: return "Today"
        case 1: return "Tomorrow"
        case -1: return "Yesterday"
        default:
            let short = "\(months[due.month - 1]) \(due.day)"
            return due.year == today.year ? short : "\(short), \(due.year)"
        }
    }

    public static func isOverdue(_ due: DateOnly, today: DateOnly) -> Bool {
        due < today
    }
}

import Foundation
import Testing
@testable import CheckoffCore

func day(_ string: String) throws -> DateOnly {
    try #require(DateOnly(string))
}

@Suite struct DateOnlyTests {
    @Test func parsesAPlainDate() throws {
        let date = try day("2026-10-15")
        #expect(date.year == 2026)
        #expect(date.month == 10)
        #expect(date.day == 15)
        #expect(date.description == "2026-10-15")
    }

    @Test func padsShortNumbersWhenWritten() throws {
        let date = try #require(DateOnly(year: 2026, month: 3, day: 7))
        #expect(date.description == "2026-03-07")
    }

    @Test func rejectsDatesThatDoNotExist() {
        #expect(DateOnly("2026-13-01") == nil)
        #expect(DateOnly("2026-00-10") == nil)
        #expect(DateOnly("2026-02-30") == nil)
        #expect(DateOnly("2026-04-31") == nil)
        #expect(DateOnly("2026-02-29") == nil)  // 2026 is not a leap year
        #expect(DateOnly("2026-10-00") == nil)
    }

    @Test func acceptsLeapDayOnlyInLeapYears() {
        #expect(DateOnly("2028-02-29") != nil)
        #expect(DateOnly("2000-02-29") != nil)
        #expect(DateOnly("2100-02-29") == nil)  // century, not divisible by 400
    }

    @Test func rejectsAnythingNotWrittenAsYearMonthDay() {
        #expect(DateOnly("2026-1-5") == nil)
        #expect(DateOnly("10/15/2026") == nil)
        #expect(DateOnly("2026-10-15 ") == nil)
        #expect(DateOnly("tomorrow") == nil)
        #expect(DateOnly("") == nil)
    }

    @Test func ordersByCalendarDate() throws {
        #expect(try day("2026-10-15") < day("2026-10-16"))
        #expect(try day("2026-10-31") < day("2026-11-01"))
        #expect(try day("2026-12-31") < day("2027-01-01"))
        #expect(try !(day("2026-10-15") < day("2026-10-15")))
        #expect(try !(day("2027-01-01") < day("2026-12-31")))
    }

    @Test func countsDaysAcrossMonthAndYearEnds() throws {
        #expect(try day("2026-10-15").days(until: day("2026-10-15")) == 0)
        #expect(try day("2026-10-31").days(until: day("2026-11-01")) == 1)
        #expect(try day("2026-12-31").days(until: day("2027-01-01")) == 1)
        #expect(try day("2028-02-28").days(until: day("2028-03-01")) == 2)
        #expect(try day("2026-10-15").days(until: day("2026-10-10")) == -5)
    }

    @Test func convertsToAndFromADateInTheGivenCalendar() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Indianapolis"))
        let lateEvening = try #require(calendar.date(
            from: DateComponents(year: 2026, month: 10, day: 15, hour: 23, minute: 30)))
        #expect(DateOnly(lateEvening, calendar: calendar).description == "2026-10-15")
        let back = try day("2026-10-15").date(in: calendar)
        #expect(calendar.dateComponents([.year, .month, .day], from: back)
            == DateComponents(year: 2026, month: 10, day: 15))
    }
}

@Suite struct DueFormattingTests {
    @Test func namesTheDaysAroundToday() throws {
        let today = try day("2026-10-12")
        #expect(DueFormatting.label(for: today, today: today) == "Today")
        #expect(try DueFormatting.label(for: day("2026-10-13"), today: today) == "Tomorrow")
        #expect(try DueFormatting.label(for: day("2026-10-11"), today: today) == "Yesterday")
    }

    @Test func tomorrowWorksAcrossAYearEnd() throws {
        #expect(try DueFormatting.label(for: day("2027-01-01"), today: day("2026-12-31")) == "Tomorrow")
    }

    @Test func showsMonthAndDayInTheSameYear() throws {
        let today = try day("2026-10-12")
        #expect(try DueFormatting.label(for: day("2026-10-15"), today: today) == "Oct 15")
        #expect(try DueFormatting.label(for: day("2026-03-07"), today: today) == "Mar 7")
    }

    @Test func addsTheYearWhenItDiffers() throws {
        let today = try day("2026-10-12")
        #expect(try DueFormatting.label(for: day("2027-01-02"), today: today) == "Jan 2, 2027")
        #expect(try DueFormatting.label(for: day("2025-12-25"), today: today) == "Dec 25, 2025")
    }

    @Test func overdueMeansBeforeTodayOnly() throws {
        let today = try day("2026-10-12")
        #expect(try DueFormatting.isOverdue(day("2026-10-11"), today: today))
        #expect(!DueFormatting.isOverdue(today, today: today))
        #expect(try !DueFormatting.isOverdue(day("2026-10-13"), today: today))
    }
}

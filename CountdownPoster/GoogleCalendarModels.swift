import Foundation

enum RFC3339DateFormatter {
    private static let formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    static func date(from string: String) -> Date? {
        formatter.date(from: string)
            ?? fallbackFormatter.date(from: string)
            ?? dateOnlyFormatter.date(from: string)
    }
}

struct GoogleCalendarEventsResponse: Decodable {
    let items: [GoogleCalendarEvent]
}

struct GoogleCalendarEvent: Decodable {
    let id: String
    let summary: String?
    let description: String?
    let location: String?
    let start: GoogleCalendarDateValue
    let end: GoogleCalendarDateValue

    func calendarEvent() -> CalendarEvent? {
        guard let startAt = start.resolvedDate else {
            return nil
        }

        let endAt = end.resolvedDate ?? Calendar.current.date(byAdding: .hour, value: 1, to: startAt) ?? startAt
        return CalendarEvent(
            id: UUID(uuidString: stableUUIDString(from: id)) ?? UUID(),
            googleEventID: id,
            title: summary?.nonBlank ?? "無題の予定",
            detail: description ?? "",
            startAt: startAt,
            endAt: endAt,
            locationText: location?.nonBlank
        )
    }

    private func stableUUIDString(from source: String) -> String {
        let scalars = Array(source.utf8)
        let bytes = (0..<16).map { index -> UInt8 in
            scalars.isEmpty ? UInt8(index) : scalars[index % scalars.count] &+ UInt8(index * 17)
        }
        return String(
            format: "%02X%02X%02X%02X-%02X%02X-%02X%02X-%02X%02X-%02X%02X%02X%02X%02X%02X",
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5],
            bytes[6], bytes[7],
            bytes[8], bytes[9],
            bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        )
    }
}

struct GoogleCalendarDateValue: Decodable {
    let dateTime: String?
    let date: String?
    let timeZone: String?

    var resolvedDate: Date? {
        if let dateTime {
            return RFC3339DateFormatter.date(from: dateTime)
        }
        if let date {
            return RFC3339DateFormatter.date(from: date)
        }
        return nil
    }
}

import SwiftUI
import EventKit
import MapKit

// MARK: - Event

struct CalEvent: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    var lat: Double?
    var lon: Double?
    var notes: String?
    var url: URL?
    var calendarID: String
    var calendarTitle: String
    var color: Color
    var alarmMinutes: Int?
    var isRecurring: Bool
    var editable: Bool
    var ek: EKEvent?

    init(_ e: EKEvent) {
        let base = e.eventIdentifier ?? e.calendarItemIdentifier
        let occ: Date = e.occurrenceDate ?? e.startDate
        id = base + "|" + String(Int(occ.timeIntervalSince1970))
        title = (e.title?.isEmpty == false) ? e.title! : "Untitled"
        start = e.startDate
        end = e.endDate
        isAllDay = e.isAllDay
        location = e.location
        lat = e.structuredLocation?.geoLocation?.coordinate.latitude
        lon = e.structuredLocation?.geoLocation?.coordinate.longitude
        notes = e.notes
        url = e.url
        calendarID = e.calendar?.calendarIdentifier ?? ""
        calendarTitle = e.calendar?.title ?? ""
        color = Color(nsColor: e.calendar?.color ?? .systemTeal)
        if let a = e.alarms?.first, a.absoluteDate == nil { alarmMinutes = Int(-a.relativeOffset / 60) } else { alarmMinutes = nil }
        isRecurring = e.hasRecurrenceRules
        editable = e.calendar?.allowsContentModifications ?? false
        ek = e
    }

    /// In-memory event (demo / preview data).
    init(id: String = UUID().uuidString, title: String, start: Date, end: Date, allDay: Bool = false,
         calendar: EKCalendar, location: String? = nil, lat: Double? = nil, lon: Double? = nil,
         notes: String? = nil, alarmMinutes: Int? = 15) {
        self.id = id; self.title = title; self.start = start; self.end = end; isAllDay = allDay
        self.location = location; self.lat = lat; self.lon = lon; self.notes = notes; url = nil
        calendarID = calendar.calendarIdentifier; calendarTitle = calendar.title
        color = Color(cgColor: calendar.cgColor); self.alarmMinutes = alarmMinutes
        isRecurring = false; editable = true; ek = nil
    }

    static func == (a: CalEvent, b: CalEvent) -> Bool {
        a.id == b.id && a.title == b.title && a.start == b.start && a.end == b.end &&
        a.location == b.location && a.calendarID == b.calendarID && a.notes == b.notes &&
        a.isAllDay == b.isAllDay && a.alarmMinutes == b.alarmMinutes
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }
    var hasLocation: Bool { !(location ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var coordinate: CLLocationCoordinate2D? {
        guard let lat, let lon else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
    var isMultiDay: Bool { !Calendar.current.isDate(start, inSameDayAs: end.addingTimeInterval(-1)) }

    /// Video-call link found in url / location / notes.
    var meetingLink: URL? {
        let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "webex.com", "facetime.apple.com", "whereby.com"]
        if let url, hosts.contains(where: { url.host()?.contains($0) == true }) { return url }
        let text = [location, notes].compactMap { $0 }.joined(separator: " ")
        guard !text.isEmpty, let det = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for m in det.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            if let u = m.url, hosts.contains(where: { u.host()?.contains($0) == true }) { return u }
        }
        return nil
    }
}

// MARK: - To-do (EKReminder)

struct Todo: Identifiable, Equatable {
    var id: String
    var title: String
    var due: Date?
    var hasTime: Bool
    var notes: String?
    var listTitle: String
    var color: Color
    var isCompleted: Bool
    var priority: Int

    init(_ r: EKReminder) {
        id = r.calendarItemIdentifier
        title = r.title ?? ""
        if let dc = r.dueDateComponents {
            due = Calendar.current.date(from: dc)
            hasTime = dc.hour != nil
        } else { due = nil; hasTime = false }
        notes = r.notes
        listTitle = r.calendar?.title ?? ""
        color = Color(nsColor: r.calendar?.color ?? .systemTeal)
        isCompleted = r.isCompleted
        priority = r.priority
    }

    init(id: String = UUID().uuidString, title: String, due: Date?, hasTime: Bool, list: String, color: Color) {
        self.id = id; self.title = title; self.due = due; self.hasTime = hasTime
        notes = nil; listTitle = list; self.color = color; isCompleted = false; priority = 0
    }

    var isOverdue: Bool {
        guard let due else { return false }
        return hasTime ? due < Date() : due < Date().startOfDay
    }
}

// MARK: - Editor draft

enum Recurrence: String, CaseIterable, Identifiable {
    case none, daily, weekdays, weekly, biweekly, monthly, yearly, custom
    var id: String { rawValue }
    var label: String {
        switch self {
        case .none: "Never"
        case .daily: "Every day"
        case .weekdays: "Weekdays"
        case .weekly: "Every week"
        case .biweekly: "Every 2 weeks"
        case .monthly: "Every month"
        case .yearly: "Every year"
        case .custom: "Custom"
        }
    }
    var rules: [EKRecurrenceRule]? {
        switch self {
        case .none, .custom: return nil
        case .daily: return [EKRecurrenceRule(recurrenceWith: .daily, interval: 1, end: nil)]
        case .weekdays:
            let days = [2, 3, 4, 5, 6].compactMap { EKWeekday(rawValue: $0) }.map { EKRecurrenceDayOfWeek($0) }
            return [EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, daysOfTheWeek: days, daysOfTheMonth: nil,
                                     monthsOfTheYear: nil, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: nil)]
        case .weekly: return [EKRecurrenceRule(recurrenceWith: .weekly, interval: 1, end: nil)]
        case .biweekly: return [EKRecurrenceRule(recurrenceWith: .weekly, interval: 2, end: nil)]
        case .monthly: return [EKRecurrenceRule(recurrenceWith: .monthly, interval: 1, end: nil)]
        case .yearly: return [EKRecurrenceRule(recurrenceWith: .yearly, interval: 1, end: nil)]
        }
    }
    static func from(_ e: EKEvent?) -> Recurrence {
        guard let r = e?.recurrenceRules?.first else { return .none }
        switch (r.frequency, r.interval) {
        case (.daily, 1): return .daily
        case (.weekly, 1): return (r.daysOfTheWeek?.count ?? 0) == 5 ? .weekdays : ((r.daysOfTheWeek?.count ?? 0) > 1 ? .custom : .weekly)
        case (.weekly, 2): return .biweekly
        case (.monthly, 1): return .monthly
        case (.yearly, 1): return .yearly
        default: return .custom
        }
    }
}

struct EventDraft: Equatable {
    var ek: EKEvent?
    var sourceID: String?
    var title = ""
    var start: Date
    var end: Date
    var isAllDay = false
    var location = ""
    var mapItem: MKMapItem?
    var geo: CLLocation?
    var notes = ""
    var calendarID: String?
    var alertMinutes: Int? = 15
    var recurrence: Recurrence = .none
    var originalRecurrence: Recurrence = .none
    var originalLocation = ""

    var isNew: Bool { ek == nil && sourceID == nil }

    init(start: Date, end: Date) { self.start = start; self.end = end }

    init(event ev: CalEvent, keepReference: Bool = true) {
        ek = keepReference ? ev.ek : nil
        sourceID = keepReference ? ev.id : nil
        title = ev.title
        start = ev.start
        end = ev.end
        isAllDay = ev.isAllDay
        location = ev.location ?? ""
        originalLocation = keepReference ? location : ""
        if let lat = ev.lat, let lon = ev.lon { geo = CLLocation(latitude: lat, longitude: lon) }
        notes = ev.notes ?? ""
        calendarID = ev.calendarID
        alertMinutes = ev.alarmMinutes
        recurrence = keepReference ? Recurrence.from(ev.ek) : .none
        originalRecurrence = recurrence
    }

    static func == (a: EventDraft, b: EventDraft) -> Bool {
        a.title == b.title && a.start == b.start && a.end == b.end && a.location == b.location &&
        a.notes == b.notes && a.calendarID == b.calendarID && a.alertMinutes == b.alertMinutes &&
        a.recurrence == b.recurrence && a.isAllDay == b.isAllDay && a.ek === b.ek && a.sourceID == b.sourceID
    }
}

// MARK: - Alerts

enum AlertChoice {
    static let options: [Int?] = [nil, 0, 5, 10, 15, 30, 60, 120, 1440]
    static func label(_ m: Int?) -> String {
        guard let m else { return "No alert" }
        switch m {
        case 0: return "At time of event"
        case 1440: return "1 day before"
        case let x where x >= 60 && x % 60 == 0: return "\(x / 60) hour\(x == 60 ? "" : "s") before"
        default: return "\(m) min before"
        }
    }
}

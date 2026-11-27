import SwiftUI
import EventKit
import MapKit

/// Wraps EventKit. Everything here is the same data Apple Calendar & Reminders show,
/// so any account added in System Settings › Internet Accounts (iCloud, Google, Exchange…) syncs both ways.
@MainActor
final class CalendarStore: ObservableObject {
    let ek = EKEventStore()
    /// Launch with HAZE_DEMO=1 to run on sample data instead of your real calendars.
    static let demo = ProcessInfo.processInfo.environment["HAZE_DEMO"] != nil

    @Published private(set) var eventsAuthorized = false
    @Published private(set) var remindersAuthorized = false
    @Published private(set) var eventsDenied = false
    @Published private(set) var events: [CalEvent] = []
    @Published private(set) var todos: [Todo] = []
    @Published private(set) var calendars: [EKCalendar] = []
    @Published private(set) var lastSync = Date()
    @Published var hiddenCalendars: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "hiddenCalendars") ?? []) {
        didSet {
            UserDefaults.standard.set(Array(hiddenCalendars), forKey: "hiddenCalendars")
            reloadEvents()
        }
    }

    private var range = DateInterval(start: Date().addingTimeInterval(-86400 * 70), end: Date().addingTimeInterval(86400 * 130))
    private var lingering: [String: Todo] = [:]
    private var observer: NSObjectProtocol?

    init() {
        if Self.demo { seedDemo(); return }
        refreshAuth()
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: ek, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.reloadAll() }
        }
        reloadAll()
    }

    var needsOnboarding: Bool { !eventsAuthorized }

    func refreshAuth() {
        if Self.demo { return }
        let e = EKEventStore.authorizationStatus(for: .event)
        let r = EKEventStore.authorizationStatus(for: .reminder)
        eventsAuthorized = e == .fullAccess
        remindersAuthorized = r == .fullAccess
        eventsDenied = e == .denied || e == .restricted
    }

    func requestAccess() async {
        _ = try? await ek.requestFullAccessToEvents()
        _ = try? await ek.requestFullAccessToReminders()
        refreshAuth()
        reloadAll()
    }

    func reloadAll() {
        refreshAuth()
        reloadEvents()
        reloadTodos()
        lastSync = Date()
    }

    func refreshRemote() {
        ek.refreshSourcesIfNecessary()
        reloadAll()
    }

    // MARK: Events

    func ensureLoaded(around date: Date) {
        let lo = date.addingTimeInterval(-86400 * 45), hi = date.addingTimeInterval(86400 * 75)
        if lo < range.start || hi > range.end {
            let now = Date()
            range = DateInterval(start: min(date.addingTimeInterval(-86400 * 70), now.addingTimeInterval(-86400 * 10)),
                                 end: max(date.addingTimeInterval(86400 * 130), now.addingTimeInterval(86400 * 100)))
            reloadEvents()
        }
    }

    func reloadEvents() {
        if Self.demo { return }
        guard eventsAuthorized else { events = []; calendars = []; return }
        calendars = ek.calendars(for: .event).sorted {
            ($0.source?.title ?? "", $0.title) < ($1.source?.title ?? "", $1.title)
        }
        let visible = calendars.filter { !hiddenCalendars.contains($0.calendarIdentifier) }
        guard !visible.isEmpty else { events = []; return }
        let pred = ek.predicateForEvents(withStart: range.start, end: range.end, calendars: visible)
        events = ek.events(matching: pred).map(CalEvent.init).sorted { $0.start < $1.start }
    }

    var writableCalendars: [EKCalendar] { Self.demo ? calendars : calendars.filter { $0.allowsContentModifications } }
    var defaultCalendarID: String? {
        if Self.demo { return calendars.first?.calendarIdentifier }
        return ek.defaultCalendarForNewEvents?.calendarIdentifier ?? writableCalendars.first?.calendarIdentifier
    }

    func events(on day: Date) -> [CalEvent] {
        let s = day.startOfDay, e = s.adding(days: 1)
        return events.filter { $0.start < e && $0.end > s }
    }

    @discardableResult
    func save(_ d: EventDraft, span: EKSpan = .thisEvent) throws -> String {
        if Self.demo { return demoSave(d) }
        let e = d.ek ?? EKEvent(eventStore: ek)
        let trimmed = d.title.trimmingCharacters(in: .whitespacesAndNewlines)
        e.title = trimmed.isEmpty ? "New Event" : trimmed
        e.isAllDay = d.isAllDay
        e.startDate = d.isAllDay ? d.start.startOfDay : d.start
        let minEnd = d.isAllDay ? e.startDate.addingTimeInterval(3600) : d.start.addingTimeInterval(5 * 60)
        e.endDate = max(d.end, minEnd)
        e.notes = d.notes.isEmpty ? nil : d.notes

        if let item = d.mapItem {
            let s = EKStructuredLocation(mapItem: item)
            s.title = d.location
            e.structuredLocation = s
        } else if d.location != d.originalLocation || d.ek == nil {
            if d.location.isEmpty {
                e.location = nil
            } else if let geo = d.geo {
                let s = EKStructuredLocation(title: d.location)
                s.geoLocation = geo
                e.structuredLocation = s
            } else {
                e.location = d.location
            }
        }

        if let cid = d.calendarID, let cal = ek.calendar(withIdentifier: cid), cal.allowsContentModifications {
            e.calendar = cal
        } else if e.calendar == nil {
            e.calendar = ek.defaultCalendarForNewEvents ?? writableCalendars.first
        }

        e.alarms = nil
        if let m = d.alertMinutes { e.addAlarm(EKAlarm(relativeOffset: TimeInterval(-m * 60))) }

        if d.recurrence != d.originalRecurrence && d.recurrence != .custom {
            e.recurrenceRules = d.recurrence.rules
        }

        try ek.save(e, span: span, commit: true)
        reloadEvents()
        return CalEvent(e).id
    }

    /// Moves an event (keeping its duration). Returns the new occurrence id.
    @discardableResult
    func move(_ ev: CalEvent, to newStart: Date) throws -> String {
        if Self.demo, let i = events.firstIndex(where: { $0.id == ev.id }) {
            events[i].start = newStart
            events[i].end = newStart.addingTimeInterval(ev.duration)
            events.sort { $0.start < $1.start }
            return ev.id
        }
        guard let e = ev.ek else { return ev.id }
        let dur = ev.duration
        e.startDate = newStart
        e.endDate = newStart.addingTimeInterval(dur)
        try ek.save(e, span: .thisEvent, commit: true)
        reloadEvents()
        return CalEvent(e).id
    }

    func delete(_ ev: CalEvent, span: EKSpan = .thisEvent) throws {
        if Self.demo { events.removeAll { $0.id == ev.id }; return }
        guard let e = ev.ek else { return }
        try ek.remove(e, span: span, commit: true)
        reloadEvents()
    }

    // MARK: Reminders

    func reloadTodos() {
        if Self.demo { return }
        guard remindersAuthorized else { todos = []; return }
        let pred = ek.predicateForIncompleteReminders(withDueDateStarting: nil, ending: nil, calendars: nil)
        ek.fetchReminders(matching: pred) { [weak self] rems in
            let items = (rems ?? []).map(Todo.init)
            Task { @MainActor in self?.applyTodos(items) }
        }
    }

    private func applyTodos(_ items: [Todo]) {
        var all = items
        for (id, t) in lingering where !all.contains(where: { $0.id == id }) { all.append(t) }
        todos = all.sorted { a, b in
            switch (a.due, b.due) {
            case let (x?, y?): return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: return a.title < b.title
            }
        }
    }

    private func reminder(_ t: Todo) -> EKReminder? { ek.calendarItem(withIdentifier: t.id) as? EKReminder }

    func setCompleted(_ t: Todo, _ done: Bool) {
        if !Self.demo {
            guard let r = reminder(t) else { return }
            r.isCompleted = done
            try? ek.save(r, commit: true)
        }
        if let i = todos.firstIndex(where: { $0.id == t.id }) { todos[i].isCompleted = done }
        if done {
            var copy = t; copy.isCompleted = true
            lingering[t.id] = copy
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
                guard let self else { return }
                self.lingering[t.id] = nil
                withAnimation(Haze.spring) { self.todos.removeAll { $0.id == t.id && $0.isCompleted } }
            }
        } else {
            lingering[t.id] = nil
        }
    }

    func addTodo(_ title: String, due: Date?, hasTime: Bool) {
        if Self.demo {
            let c = calendars.first.map { Color(cgColor: $0.cgColor) } ?? Haze.mint
            applyTodos(todos + [Todo(title: title, due: due, hasTime: hasTime, list: "Reminders", color: c)])
            return
        }
        let r = EKReminder(eventStore: ek)
        r.title = title
        guard let cal = ek.defaultCalendarForNewReminders() ?? ek.calendars(for: .reminder).first(where: { $0.allowsContentModifications }) else { return }
        r.calendar = cal
        applyDue(r, due, hasTime: hasTime)
        try? ek.save(r, commit: true)
        reloadTodos()
    }

    func setDue(_ t: Todo, _ due: Date?, hasTime: Bool) {
        if Self.demo, let i = todos.firstIndex(where: { $0.id == t.id }) {
            var list = todos; list[i].due = due; list[i].hasTime = hasTime
            applyTodos(list); return
        }
        guard let r = reminder(t) else { return }
        applyDue(r, due, hasTime: hasTime)
        try? ek.save(r, commit: true)
        reloadTodos()
    }

    func snooze(_ t: Todo, by seconds: TimeInterval) {
        let base = max(Date(), t.due ?? Date())
        setDue(t, base.addingTimeInterval(seconds), hasTime: true)
    }

    func deleteTodo(_ t: Todo) {
        if Self.demo { withAnimation(Haze.spring) { todos.removeAll { $0.id == t.id } }; return }
        guard let r = reminder(t) else { return }
        try? ek.remove(r, commit: true)
        withAnimation(Haze.spring) { todos.removeAll { $0.id == t.id } }
    }

    private func applyDue(_ r: EKReminder, _ due: Date?, hasTime: Bool) {
        r.alarms = nil
        guard let due else { r.dueDateComponents = nil; return }
        let comps: Set<Calendar.Component> = hasTime ? [.year, .month, .day, .hour, .minute] : [.year, .month, .day]
        r.dueDateComponents = Calendar.current.dateComponents(comps, from: due)
        if hasTime { r.addAlarm(EKAlarm(absoluteDate: due)) }
    }
}

// MARK: - Demo data

extension CalendarStore {
    fileprivate func demoCalendar(_ title: String, _ hex: UInt32) -> EKCalendar {
        let c = EKCalendar(for: .event, eventStore: ek)
        c.title = title
        c.cgColor = CGColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255,
                            blue: CGFloat(hex & 255) / 255, alpha: 1)
        return c
    }

    fileprivate func seedDemo() {
        eventsAuthorized = true
        remindersAuthorized = true
        let finance = demoCalendar("Finance", 0x3E9CAE)
        let marketing = demoCalendar("Marketing", 0x9B7FD6)
        let design = demoCalendar("Design", 0xE0896A)
        let personal = demoCalendar("Personal", 0x4FA582)
        calendars = [finance, marketing, design, personal]

        let week = weekDays(containing: Date())
        func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date { week[0].adding(days: day).adding(minutes: h * 60 + m) }
        func ev(_ t: String, _ d: Int, _ h: Int, _ m: Int, _ dur: Int, _ cal: EKCalendar,
                place: String? = nil, _ lat: Double? = nil, _ lon: Double? = nil, notes: String? = nil) -> CalEvent {
            let s = at(d, h, m)
            return CalEvent(title: t, start: s, end: s.adding(minutes: dur), calendar: cal, location: place, lat: lat, lon: lon, notes: notes)
        }
        var list: [CalEvent] = [
            ev("Brunch with family", 0, 10, 30, 90, personal, place: "Zazie, Cole Valley", 37.7657, -122.4497),
            ev("Team kickoff", 1, 8, 0, 120, finance, notes: "Goals for December, owners, open questions."),
            ev("Credit simulation review", 1, 11, 0, 90, marketing),
            ev("Onboarding new team members", 2, 9, 15, 75, finance),
            ev("Lunch with Ana", 2, 12, 30, 60, personal, place: "Tartine Manufactory, 595 Alabama St", 37.7617, -122.4116),
            ev("Credit simulation presentation", 3, 8, 30, 120, marketing),
            ev("Brand moodboard", 3, 14, 0, 60, design),
            ev("Design review", 4, 9, 0, 60, design, place: "Figma HQ, 760 Market St", 37.7873, -122.4034),
            ev("Standup", 4, 10, 30, 30, finance, notes: "https://zoom.us/j/5550199"),
            ev("Quarterly planning", 4, 13, 0, 90, finance),
            ev("Budget sync", 5, 8, 0, 90, finance),
            ev("Yoga", 5, 12, 0, 60, personal, place: "Yoga Flow SF, 1560 Fillmore St", 37.7837, -122.4325),
            ev("Launch retro", 5, 15, 0, 60, marketing),
            ev("Farmers market", 6, 9, 30, 120, personal, place: "Ferry Building Marketplace", 37.7955, -122.3937),
            ev("Portfolio walkthrough", 8, 10, 0, 60, design),
            ev("Dentist", 9, 16, 30, 45, personal, place: "Smile Studio, 450 Sutter St", 37.7894, -122.4083),
            ev("Flight to New York", 11, 8, 0, 330, personal, place: "San Francisco International Airport", 37.6213, -122.3790),
        ]
        list.append(CalEvent(title: "Thanksgiving", start: Date().startOfDay, end: Date().startOfDay.adding(days: 1),
                             allDay: true, calendar: personal, alarmMinutes: nil))
        events = list.sorted { $0.start < $1.start }

        let now = Date()
        let mint = Color(cgColor: personal.cgColor), teal = Color(cgColor: finance.cgColor)
        todos = [
            Todo(title: "Send Q4 budget to Sarah", due: now.addingTimeInterval(25 * 60), hasTime: true, list: "Work", color: teal),
            Todo(title: "Book flights for December", due: now.startOfDay, hasTime: false, list: "Personal", color: mint),
            Todo(title: "Pick up flowers for dinner", due: now.startOfDay, hasTime: false, list: "Personal", color: mint),
            Todo(title: "Review the marketing deck", due: now.startOfDay.adding(days: 1), hasTime: false, list: "Work", color: teal),
            Todo(title: "Renew passport", due: now.startOfDay.adding(days: 6), hasTime: false, list: "Personal", color: mint),
        ]
    }

    fileprivate func demoSave(_ d: EventDraft) -> String {
        let cal = calendars.first { $0.calendarIdentifier == d.calendarID } ?? calendars[0]
        let title = d.title.trimmingCharacters(in: .whitespaces).isEmpty ? "New Event" : d.title
        var ev = CalEvent(id: d.sourceID ?? UUID().uuidString, title: title, start: d.start, end: max(d.end, d.start.adding(minutes: 15)),
                          allDay: d.isAllDay, calendar: cal, location: d.location.isEmpty ? nil : d.location,
                          lat: d.mapItem?.placemark.coordinate.latitude ?? d.geo?.coordinate.latitude,
                          lon: d.mapItem?.placemark.coordinate.longitude ?? d.geo?.coordinate.longitude,
                          notes: d.notes.isEmpty ? nil : d.notes, alarmMinutes: d.alertMinutes)
        ev.isRecurring = d.recurrence != .none
        events.removeAll { $0.id == ev.id }
        events.append(ev)
        events.sort { $0.start < $1.start }
        return ev.id
    }
}

// MARK: - Geocoding cache (for map previews / Places)

@MainActor
final class GeoCache: ObservableObject {
    static let shared = GeoCache()
    @Published private(set) var coords: [String: CLLocationCoordinate2D] = [:]
    private var inFlight: Set<String> = []
    private var failed: Set<String> = []

    func coordinate(for ev: CalEvent) -> CLLocationCoordinate2D? {
        if let c = ev.coordinate { return c }
        guard let loc = ev.location, !loc.isEmpty else { return nil }
        if let c = coords[loc] { return c }
        resolve(loc)
        return nil
    }

    func resolve(_ query: String) {
        guard !inFlight.contains(query), !failed.contains(query), coords[query] == nil else { return }
        inFlight.insert(query)
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        MKLocalSearch(request: req).start { [weak self] resp, _ in
            let c = resp?.mapItems.first?.placemark.coordinate
            Task { @MainActor in
                guard let self else { return }
                self.inFlight.remove(query)
                if let c { self.coords[query] = c } else { self.failed.insert(query) }
            }
        }
    }
}

// MARK: - Maps hand-off

@MainActor
enum MapsLink {
    static func apple(_ ev: CalEvent, directions: Bool = false) -> URL? {
        var c = URLComponents(string: "http://maps.apple.com/")!
        var q: [URLQueryItem] = []
        let name = ev.location ?? ev.title
        if let coord = ev.coordinate ?? GeoCache.shared.coords[ev.location ?? ""] {
            let ll = "\(coord.latitude),\(coord.longitude)"
            q.append(URLQueryItem(name: directions ? "daddr" : "ll", value: ll))
            q.append(URLQueryItem(name: "q", value: name))
        } else {
            q.append(URLQueryItem(name: directions ? "daddr" : "q", value: name))
        }
        c.queryItems = q
        return c.url
    }

    static func google(_ ev: CalEvent, directions: Bool = false) -> URL? {
        var c = URLComponents(string: directions ? "https://www.google.com/maps/dir/" : "https://www.google.com/maps/search/")!
        let dest: String
        if let coord = ev.coordinate ?? GeoCache.shared.coords[ev.location ?? ""] {
            dest = "\(coord.latitude),\(coord.longitude)"
        } else {
            dest = ev.location ?? ev.title
        }
        c.queryItems = [URLQueryItem(name: "api", value: "1"),
                        URLQueryItem(name: directions ? "destination" : "query", value: dest)]
        return c.url
    }

    static func open(_ url: URL?) { if let url { NSWorkspace.shared.open(url) } }
}

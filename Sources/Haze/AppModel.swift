import SwiftUI
import EventKit

// MARK: - Pages

enum Page: String, CaseIterable, Identifiable {
    case week, month, agenda, places, settings
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .week: "rectangle.split.3x1"
        case .month: "square.grid.3x3"
        case .agenda: "list.bullet.rectangle"
        case .places: "map"
        case .settings: "slider.horizontal.3"
        }
    }
    var title: String {
        switch self {
        case .week: "Week"
        case .month: "Month"
        case .agenda: "Agenda"
        case .places: "Places"
        case .settings: "Settings"
        }
    }
}

enum ComposerOrigin { case button, detail, grid }

struct DemoPlace: Equatable { let name: String; let lat: Double; let lon: Double }

struct Toast: Identifiable {
    let id = UUID()
    let text: String
    let icon: String
    let undo: (() -> Void)?
}

// MARK: - UI state

@MainActor
final class AppModel: ObservableObject {
    let store: CalendarStore

    @Published var page: Page = .week
    @Published var focusDate = Date() { didSet { store.ensureLoaded(around: focusDate) } }
    @Published var selectedEventID: String?
    @Published var composer: EventDraft?
    @Published var composerOrigin: ComposerOrigin = .button
    @Published var toast: Toast?
    @Published var navDirection: CGFloat = 1
    @Published var placeFocusID: String?

    // Week grid interaction state (shared so the demo autopilot can drive it too)
    @Published var focusedDay: Int?
    @Published var dragID: String?
    @Published var dragDay = 0
    @Published var dragMin = 0

    // Demo autopilot hooks
    @Published var demoTitle: String?
    @Published var demoPlace: DemoPlace?
    @Published var demoSaveTick = 0
    @Published var demoTodoText: String?
    @Published var demoTodoSubmit = 0
    @Published var demoSearch: String?
    @Published var demoPointer: CGPoint?

    init(store: CalendarStore) { self.store = store }

    var selectedEvent: CalEvent? {
        guard let id = selectedEventID else { return nil }
        return store.events.first { $0.id == id }
    }

    func setPage(_ p: Page) {
        guard p != page else { return }
        withAnimation(.spring(response: 0.55, dampingFraction: 0.84)) { page = p }
    }

    func shift(_ n: Int) {
        let comp: Calendar.Component = page == .month ? .month : .weekOfYear
        navDirection = n > 0 ? 1 : -1
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) {
            focusDate = Calendar.current.date(byAdding: comp, value: n, to: focusDate) ?? focusDate
        }
    }

    func goToday() {
        navDirection = focusDate < Date() ? 1 : -1
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { focusDate = Date() }
    }

    func reveal(_ date: Date) {
        navDirection = focusDate < date ? 1 : -1
        withAnimation(.spring(response: 0.55, dampingFraction: 0.86)) { focusDate = date }
    }

    func newEvent(at start: Date? = nil, allDay: Bool = false, origin: ComposerOrigin = .button) {
        let s = start ?? Date().nextQuarterHour
        var d = EventDraft(start: s, end: s.addingTimeInterval(3600))
        d.isAllDay = allDay
        let def = UserDefaults.standard.object(forKey: "defaultAlert") as? Int ?? 15
        d.alertMinutes = def < 0 ? nil : def
        d.calendarID = store.defaultCalendarID
        composerOrigin = origin
        withAnimation(.spring(response: 0.52, dampingFraction: 0.8)) { composer = d }
    }

    func edit(_ ev: CalEvent) {
        composerOrigin = .detail
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { composer = EventDraft(event: ev) }
    }

    func duplicate(_ ev: CalEvent) {
        var d = EventDraft(event: ev, keepReference: false)
        d.start = ev.start.adding(days: 1)
        d.end = ev.end.adding(days: 1)
        composerOrigin = .detail
        withAnimation(.spring(response: 0.5, dampingFraction: 0.82)) { composer = d }
    }

    func closeComposer() {
        withAnimation(.spring(response: 0.46, dampingFraction: 0.86)) { composer = nil }
    }

    func select(_ ev: CalEvent?) {
        withAnimation(.spring(response: 0.48, dampingFraction: 0.84)) { selectedEventID = ev?.id }
    }

    func deleteWithUndo(_ ev: CalEvent, span: EKSpan = .thisEvent) {
        let snapshot = EventDraft(event: ev, keepReference: false)
        do {
            try store.delete(ev, span: span)
            if selectedEventID == ev.id { select(nil) }
            toast("Deleted “\(ev.title)”", icon: "trash", undo: { [weak self] in
                guard let self else { return }
                if let id = try? self.store.save(snapshot) { self.select(self.store.events.first { $0.id == id }) }
            })
        } catch {
            toast("Couldn’t delete: \(error.localizedDescription)", icon: "exclamationmark.triangle")
        }
    }

    /// Moves an event by whole days / minutes, with undo.
    func commitMove(_ ev: CalEvent, days: Int, minutes: Int) {
        guard days != 0 || minutes != 0 else { return }
        let oldStart = ev.start
        let newStart = oldStart.adding(days: days).adding(minutes: minutes)
        do {
            let wasSelected = selectedEventID == ev.id
            let newID = try store.move(ev, to: newStart)
            if wasSelected { selectedEventID = newID }
            Haptic.thunk()
            toast("Moved to \(Fmt.weekdayShort.string(from: newStart)) \(Fmt.time(newStart))", icon: "arrow.up.and.down.and.arrow.left.and.right") { [weak self] in
                guard let self, let moved = self.store.events.first(where: { $0.id == newID }) else { return }
                if let back = try? self.store.move(moved, to: oldStart), self.selectedEventID == newID { self.selectedEventID = back }
            }
        } catch {
            toast("Couldn’t move: \(error.localizedDescription)", icon: "exclamationmark.triangle")
        }
    }

    func toast(_ text: String, icon: String = "checkmark", undo: (() -> Void)? = nil) {
        let t = Toast(text: text, icon: icon, undo: undo)
        withAnimation(.spring(response: 0.48, dampingFraction: 0.72)) { toast = t }
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            guard let self, self.toast?.id == t.id else { return }
            withAnimation(.easeOut(duration: 0.3)) { self.toast = nil }
        }
    }
}

// MARK: - Date helpers

extension Calendar {
    static var haze: Calendar {
        var c = Calendar.current
        c.firstWeekday = UserDefaults.standard.bool(forKey: "weekStartsMonday") ? 2 : 1
        return c
    }
}

extension Date {
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }
    func adding(days: Int) -> Date { Calendar.current.date(byAdding: .day, value: days, to: self) ?? self }
    func adding(minutes: Int) -> Date { addingTimeInterval(TimeInterval(minutes * 60)) }
    var minutesIntoDay: Double { timeIntervalSince(startOfDay) / 60 }
    func isSameDay(_ d: Date) -> Bool { Calendar.current.isDate(self, inSameDayAs: d) }
    var isToday: Bool { Calendar.current.isDateInToday(self) }
    var nextQuarterHour: Date {
        let m = Int(minutesIntoDay)
        let next = ((m / 15) + 1) * 15
        return startOfDay.adding(minutes: next)
    }
}

func weekDays(containing d: Date) -> [Date] {
    let cal = Calendar.haze
    let start = cal.dateInterval(of: .weekOfYear, for: d)?.start ?? d.startOfDay
    return (0..<7).map { start.adding(days: $0) }
}

func monthGrid(for d: Date) -> [Date] {
    let cal = Calendar.haze
    let first = cal.dateInterval(of: .month, for: d)?.start ?? d.startOfDay
    let start = cal.dateInterval(of: .weekOfYear, for: first)?.start ?? first
    return (0..<42).map { start.adding(days: $0) }
}

// MARK: - Formatting

enum Fmt {
    private static func make(_ template: String) -> DateFormatter {
        let f = DateFormatter(); f.setLocalizedDateFormatFromTemplate(template); return f
    }
    private static func fixed(_ format: String) -> DateFormatter {
        let f = DateFormatter(); f.dateFormat = format; return f
    }
    static let weekdayShort = fixed("EEE")
    static let monthName = fixed("LLLL")
    static let longDay = make("EEEEMMMMd")
    static let shortDay = make("EEEMMMd")
    static let monthDay = make("MMMd")
    private static let t24 = fixed("HH:mm")
    private static let t12 = fixed("h:mm a")

    static var use24h: Bool { UserDefaults.standard.object(forKey: "use24h") as? Bool ?? true }

    static func time(_ d: Date) -> String { (use24h ? t24 : t12).string(from: d) }
    static func range(_ a: Date, _ b: Date) -> String { "\(time(a)) – \(time(b))" }
    static func hourLabel(_ h: Int) -> String {
        if use24h { return String(format: "%02d:00", h) }
        let hh = h % 12 == 0 ? 12 : h % 12
        return "\(hh) \(h < 12 ? "AM" : "PM")"
    }
    static func duration(_ s: TimeInterval) -> String {
        let m = Int(s / 60)
        if m < 60 { return "\(m)m" }
        if m % 60 == 0 { return "\(m / 60)h" }
        return "\(m / 60)h \(m % 60)m"
    }
    static func countdown(to d: Date, now: Date = Date()) -> String {
        let s = d.timeIntervalSince(now)
        if abs(s) < 60 { return "now" }
        let m = Int(abs(s) / 60)
        let text: String
        if m < 60 { text = "\(m)m" }
        else if m < 60 * 24 { text = m % 60 == 0 ? "\(m / 60)h" : "\(m / 60)h \(m % 60)m" }
        else { let days = m / 1440; text = "\(days) day\(days == 1 ? "" : "s")" }
        return s > 0 ? "in \(text)" : "\(text) ago"
    }
    static func dueLabel(_ t: Todo) -> String? {
        guard let due = t.due else { return nil }
        let cal = Calendar.current
        var day: String
        if cal.isDateInToday(due) { day = "Today" }
        else if cal.isDateInTomorrow(due) { day = "Tomorrow" }
        else if cal.isDateInYesterday(due) { day = "Yesterday" }
        else { day = monthDay.string(from: due) }
        if t.hasTime { day += " · " + time(due) }
        return day
    }
}

// MARK: - Natural language dates ("lunch with Sam tomorrow 1pm")

enum NL {
    struct Match {
        let date: Date
        let duration: TimeInterval?
        let hasTime: Bool
        let range: Range<String.Index>
        let phrase: String
    }

    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)
    private static let timePattern = #"(\d{1,2}(:\d{2})?\s*(am|pm|a\.m\.|p\.m\.))|(\d{1,2}:\d{2})|noon|midnight|morning|afternoon|evening|tonight"#

    static func parse(_ s: String) -> Match? {
        guard let detector,
              let m = detector.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let d = m.date, let r = Range(m.range, in: s) else { return nil }
        let phrase = String(s[r])
        let hasTime = phrase.lowercased().range(of: timePattern, options: .regularExpression) != nil
        return Match(date: d, duration: m.duration > 0 ? m.duration : nil, hasTime: hasTime, range: r, phrase: phrase)
    }

    static func strip(_ s: String, phrase: String) -> String {
        guard let r = s.range(of: phrase) else { return s }
        var out = s.replacingCharacters(in: r, with: "")
        for tail in [" on", " at", " from", " by", " for"] where out.hasSuffix(tail) {
            out.removeLast(tail.count)
        }
        out = out.replacingOccurrences(of: "  ", with: " ")
        return out.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
    }
}

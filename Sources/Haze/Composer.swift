import SwiftUI
import MapKit
import EventKit

final class LocationCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var results: [MKLocalSearchCompletion] = []
    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
    }

    func update(_ q: String) {
        if q.trimmingCharacters(in: .whitespaces).count < 2 { results = [] } else { completer.queryFragment = q }
    }
    func clear() { results = [] }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let r = Array(completer.results.prefix(5))
        DispatchQueue.main.async { self.results = r }
    }
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {}
}

struct ComposerCard: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: CalendarStore
    let ns: Namespace.ID

    @State private var d: EventDraft
    @State private var baseStart: Date
    @State private var baseEnd: Date
    @State private var timesTouched = false
    @State private var nlPhrase: String?
    @State private var shown = false
    @State private var shake = 0
    @State private var errorText: String?
    @State private var applyFuture = false
    @StateObject private var completer = LocationCompleter()
    @FocusState private var focus: Field?

    enum Field { case title, location, notes }

    init(initial: EventDraft, ns: Namespace.ID) {
        _d = State(initialValue: initial)
        _baseStart = State(initialValue: initial.start)
        _baseEnd = State(initialValue: initial.end)
        self.ns = ns
    }

    private let placeholders = [
        "Coffee with Ana tomorrow 9am",
        "Design review Friday 2pm",
        "Dentist next Tuesday at 4:30pm",
        "Dinner at Nopa Saturday 8pm",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header.stagger(0, shown)
            titleField.stagger(1, shown)
            calendarChips.stagger(2, shown)
            timeSection.stagger(3, shown)
            locationSection.stagger(4, shown).zIndex(5)
            HStack(spacing: 10) {
                alertMenu
                repeatMenu
                Spacer()
            }
            .stagger(5, shown)
            notesField.stagger(6, shown)
            footer.stagger(7, shown)
        }
        .padding(30)
        .frame(width: 600)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous).fill(.regularMaterial)
                RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.white.opacity(0.78))
            }
            .matchedGeometryEffect(id: app.composerOrigin == .button ? "composer" : "composer-detached", in: ns)
            .shadow(color: .black.opacity(0.18), radius: 50, y: 30)
        }
        .overlay(RoundedRectangle(cornerRadius: 30, style: .continuous).strokeBorder(.white, lineWidth: 1).opacity(shown ? 1 : 0))
        .keyframeAnimator(initialValue: 0.0, trigger: shake) { v, x in v.offset(x: x) } keyframes: { _ in
            SpringKeyframe(-12, duration: 0.07)
            SpringKeyframe(10, duration: 0.07)
            SpringKeyframe(-6, duration: 0.07)
            SpringKeyframe(0, duration: 0.2)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.3).delay(0.12)) { shown = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { focus = .title }
        }
        .onChange(of: d.title) { _, t in liveParse(t) }
        .onChange(of: app.demoTitle) { _, t in if let t { d.title = t } }
        .onChange(of: app.demoPlace) { _, p in
            guard let p else { return }
            focus = nil
            withAnimation(Haze.spring) {
                d.location = p.name
                d.geo = CLLocation(latitude: p.lat, longitude: p.lon)
            }
        }
        .onChange(of: app.demoSaveTick) { _, _ in save() }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            Text(d.isNew ? "New Event" : "Edit Event").font(.display(13, .semibold)).foregroundStyle(Haze.mute)
                .textCase(.uppercase).tracking(1)
            Spacer()
            Text("esc").font(.system(size: 10.5, weight: .medium, design: .rounded)).foregroundStyle(Haze.mute)
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: 5).strokeBorder(Haze.mute.opacity(0.4)))
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .leading) {
                if d.title.isEmpty {
                    TypewriterPlaceholder(phrases: placeholders)
                        .font(.display(30, .medium))
                        .foregroundStyle(Haze.ink.opacity(0.22))
                        .allowsHitTesting(false)
                }
                TextField("", text: $d.title)
                    .textFieldStyle(.plain)
                    .font(.display(30, .medium))
                    .foregroundStyle(Haze.ink)
                    .focused($focus, equals: .title)
                    .onSubmit(save)
            }
            if let phrase = nlPhrase {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").symbolEffect(.bounce, value: phrase)
                    Text("Understood “\(phrase)”")
                }
                .font(.display(12, .semibold))
                .foregroundStyle(Haze.ink.opacity(0.75))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(LinearGradient(colors: [Haze.mint.opacity(0.22), Color(hex: 0xB9A7D8).opacity(0.25)],
                                                          startPoint: .leading, endPoint: .trailing)))
                .transition(.scale(scale: 0.5, anchor: .leading).combined(with: .opacity))
            }
        }
        .animation(Haze.bouncy, value: nlPhrase)
    }

    private var calendarChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.writableCalendars, id: \.calendarIdentifier) { cal in
                    let on = d.calendarID == cal.calendarIdentifier
                    let c = Color(nsColor: cal.color)
                    Button { withAnimation(Haze.snappy) { d.calendarID = cal.calendarIdentifier } } label: {
                        HStack(spacing: 6) {
                            Circle().fill(c).frame(width: 8, height: 8)
                                .scaleEffect(on ? 1.3 : 1)
                            Text(cal.title).font(.display(13, .medium)).foregroundStyle(Haze.ink.opacity(on ? 1 : 0.7))
                        }
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(on ? c.opacity(0.18) : Haze.ink.opacity(0.04)))
                        .overlay(Capsule().strokeBorder(on ? c.opacity(0.7) : .clear, lineWidth: 1.2))
                    }
                    .buttonStyle(PressStyle())
                }
            }
            .padding(2)
        }
    }

    private var startBinding: Binding<Date> {
        Binding(get: { d.start }, set: { new in
            timesTouched = true
            let dur = d.end.timeIntervalSince(d.start)
            d.start = new
            d.end = new.addingTimeInterval(max(dur, 300))
        })
    }
    private var endBinding: Binding<Date> {
        Binding(get: { d.end }, set: { timesTouched = true; d.end = $0 })
    }

    private var timeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Big human summary that animates digit-by-digit as times change
            HStack(spacing: 8) {
                Text(Fmt.longDay.string(from: d.start))
                if !d.isAllDay {
                    Text("·").foregroundStyle(Haze.faint)
                    Text(Fmt.range(d.start, d.end)).contentTransition(.numericText())
                }
            }
            .font(.display(17, .medium))
            .foregroundStyle(Haze.ink)
            .animation(Haze.spring, value: d.start)
            .animation(Haze.spring, value: d.end)

            HStack(spacing: 10) {
                DatePicker("", selection: startBinding, displayedComponents: d.isAllDay ? [.date] : [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field)
                Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Haze.mute)
                DatePicker("", selection: endBinding, in: d.start..., displayedComponents: d.isAllDay ? [.date] : [.date, .hourAndMinute])
                    .labelsHidden().datePickerStyle(.field)
                Spacer()
                Text("All-day").font(.display(13, .medium)).foregroundStyle(Haze.inkSoft)
                SpringToggle(isOn: d.isAllDay) { withAnimation(Haze.spring) { d.isAllDay.toggle(); timesTouched = true } }
            }
            if !d.isAllDay {
                HStack(spacing: 6) {
                    ForEach([15, 30, 45, 60, 90, 120], id: \.self) { m in
                        let on = Int(d.end.timeIntervalSince(d.start) / 60) == m
                        Button {
                            timesTouched = true
                            withAnimation(Haze.snappy) { d.end = d.start.adding(minutes: m) }
                        } label: {
                            Text(Fmt.duration(TimeInterval(m * 60)))
                                .font(.display(12, .medium))
                                .foregroundStyle(on ? .white : Haze.ink.opacity(0.75))
                                .padding(.horizontal, 10).padding(.vertical, 5)
                                .background(Capsule().fill(on ? Haze.ink : Haze.ink.opacity(0.05)))
                        }
                        .buttonStyle(PressStyle(scale: 0.88))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var locationBinding: Binding<String> {
        Binding(get: { d.location }, set: {
            d.location = $0
            d.mapItem = nil
            d.geo = nil
            completer.update($0)
        })
    }

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(focus == .location ? Haze.ink : Haze.mute)
                    .symbolEffect(.bounce, value: focus == .location)
                TextField("Add a place or address", text: locationBinding)
                    .textFieldStyle(.plain)
                    .font(.display(15))
                    .foregroundStyle(Haze.ink)
                    .focused($focus, equals: .location)
                if d.mapItem != nil || d.geo != nil {
                    Image(systemName: "checkmark.seal.fill").foregroundStyle(Haze.mint)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 14).frame(height: 42)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Haze.ink.opacity(focus == .location ? 0.06 : 0.035)))

            if focus == .location && !completer.results.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(completer.results.enumerated()), id: \.offset) { i, c in
                        Button { pick(c) } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(c.title).font(.display(14, .medium)).foregroundStyle(Haze.ink)
                                if !c.subtitle.isEmpty {
                                    Text(c.subtitle).font(.display(12)).foregroundStyle(Haze.mute)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12).padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(HoverRow())
                        .transition(.offset(y: -6).combined(with: .opacity))
                    }
                }
                .padding(4)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white))
                .shadow(color: .black.opacity(0.08), radius: 12, y: 6)
                .transition(.scale(scale: 0.96, anchor: .top).combined(with: .opacity))
            }

            if let coord = d.mapItem?.placemark.coordinate ?? d.geo?.coordinate {
                Map(initialPosition: .region(MKCoordinateRegion(center: coord, latitudinalMeters: 700, longitudinalMeters: 700)),
                    interactionModes: []) {
                    Marker(d.location, coordinate: coord).tint(Haze.ink)
                }
                .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                .frame(height: 90)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .id("\(coord.latitude),\(coord.longitude)")
                .transition(.scale(scale: 0.9, anchor: .top).combined(with: .opacity))
            }
        }
        .animation(Haze.spring, value: completer.results.count)
        .animation(Haze.spring, value: d.mapItem)
        .animation(Haze.snappy, value: focus)
    }

    private func pick(_ c: MKLocalSearchCompletion) {
        let req = MKLocalSearch.Request(completion: c)
        let label = c.subtitle.isEmpty ? c.title : "\(c.title), \(c.subtitle)"
        d.location = label
        completer.clear()
        MKLocalSearch(request: req).start { resp, _ in
            DispatchQueue.main.async {
                if let item = resp?.mapItems.first {
                    d.mapItem = item
                    d.location = label
                }
                focus = nil
            }
        }
    }

    private var alertMenu: some View {
        Menu {
            ForEach(AlertChoice.options, id: \.self) { m in
                Button(AlertChoice.label(m)) { d.alertMinutes = m }
            }
        } label: {
            Label(AlertChoice.label(d.alertMinutes), systemImage: d.alertMinutes == nil ? "bell.slash" : "bell")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.display(13, .medium))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(Haze.ink.opacity(0.05)))
    }

    private var repeatMenu: some View {
        Menu {
            ForEach(Recurrence.allCases.filter { $0 != .custom }) { r in
                Button(r.label) { d.recurrence = r }
            }
        } label: {
            Label(d.recurrence == .none ? "Doesn’t repeat" : d.recurrence.label, systemImage: "repeat")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .font(.display(13, .medium))
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Capsule().fill(Haze.ink.opacity(0.05)))
    }

    private var notesField: some View {
        TextField("Notes, links, agenda…", text: $d.notes, axis: .vertical)
            .textFieldStyle(.plain)
            .font(.display(14))
            .foregroundStyle(Haze.inkSoft)
            .lineLimit(2...5)
            .focused($focus, equals: .notes)
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Haze.ink.opacity(0.035)))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let errorText {
                Text(errorText).font(.display(12.5, .medium)).foregroundStyle(Haze.coral)
                    .transition(.opacity)
            }
            HStack(spacing: 10) {
                if !d.isNew {
                    Button {
                        let ev: CalEvent? = store.events.first(where: { $0.id == d.sourceID })
                            ?? d.ek.flatMap { ek in store.events.first(where: { $0.ek === ek }) }
                        guard let ev else { return }
                        app.closeComposer()
                        app.deleteWithUndo(ev, span: applyFuture ? .futureEvents : .thisEvent)
                    } label: {
                        Text("Delete").font(.display(14, .medium)).foregroundStyle(Haze.coral)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    .buttonStyle(PressStyle())
                    if d.ek?.hasRecurrenceRules == true {
                        Text("Future events too").font(.display(12.5)).foregroundStyle(Haze.inkSoft)
                        SpringToggle(isOn: applyFuture) { applyFuture.toggle() }
                    }
                }
                Spacer()
                Button { app.closeComposer() } label: {
                    Text("Cancel").font(.display(14, .medium)).foregroundStyle(Haze.inkSoft)
                        .padding(.horizontal, 16).padding(.vertical, 10)
                }
                .buttonStyle(PressStyle())
                .keyboardShortcut(.cancelAction)

                Button(action: save) {
                    HStack(spacing: 8) {
                        Text(d.isNew ? "Add Event" : "Save").font(.display(14.5, .semibold))
                        Text("⌘↩").font(.system(size: 11, weight: .medium, design: .rounded)).opacity(0.6)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20).padding(.vertical, 11)
                    .background(Capsule().fill(Haze.ink))
                    .shadow(color: Haze.ink.opacity(0.3), radius: 10, y: 5)
                }
                .buttonStyle(PressStyle())
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    // MARK: Logic

    private func liveParse(_ t: String) {
        errorText = nil
        guard !timesTouched else { return }
        if let m = NL.parse(t) {
            let cal = Calendar.current
            var start: Date
            if m.hasTime {
                start = m.date
            } else {
                let tod = cal.dateComponents([.hour, .minute], from: baseStart)
                start = cal.date(bySettingHour: tod.hour ?? 9, minute: tod.minute ?? 0, second: 0, of: m.date) ?? m.date
            }
            let dur = m.duration ?? baseEnd.timeIntervalSince(baseStart)
            nlPhrase = m.phrase
            withAnimation(Haze.spring) {
                d.start = start
                d.end = start.addingTimeInterval(dur)
            }
        } else if nlPhrase != nil {
            nlPhrase = nil
            withAnimation(Haze.spring) { d.start = baseStart; d.end = baseEnd }
        }
    }

    private func save() {
        var draft = d
        if let p = nlPhrase, draft.title.contains(p) {
            let stripped = NL.strip(draft.title, phrase: p)
            if !stripped.isEmpty { draft.title = stripped }
        }
        if draft.title.trimmingCharacters(in: .whitespaces).isEmpty {
            errorText = "Give it a name first."
            shake += 1
            focus = .title
            return
        }
        if draft.end <= draft.start && !draft.isAllDay { draft.end = draft.start.adding(minutes: 30) }
        do {
            let id = try store.save(draft, span: applyFuture ? .futureEvents : .thisEvent)
            let calName = store.calendars.first { $0.calendarIdentifier == draft.calendarID }?.title ?? "Calendar"
            app.closeComposer()
            let visible = weekDays(containing: app.focusDate)
            if app.page == .week && !visible.contains(where: { $0.isSameDay(draft.start) }) { app.reveal(draft.start) }
            app.select(store.events.first { $0.id == id })
            app.toast(draft.isNew ? "Added to \(calName) · \(Fmt.shortDay.string(from: draft.start))" : "Saved changes", icon: draft.isNew ? "calendar.badge.plus" : "checkmark")
        } catch {
            errorText = error.localizedDescription
            shake += 1
        }
    }
}

// MARK: - Helpers

private struct Stagger: ViewModifier {
    let index: Int
    let shown: Bool
    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown ? 0 : 14)
            .animation(.spring(response: 0.5, dampingFraction: 0.8).delay(shown ? 0.1 + Double(index) * 0.035 : 0), value: shown)
    }
}

extension View {
    fileprivate func stagger(_ i: Int, _ shown: Bool) -> some View { modifier(Stagger(index: i, shown: shown)) }
}

/// Placeholder that types example events by itself.
struct TypewriterPlaceholder: View {
    let phrases: [String]
    @State private var shown = ""
    @State private var caret = true

    var body: some View {
        HStack(spacing: 1) {
            Text(shown)
            Rectangle().frame(width: 2, height: 28).opacity(caret ? 0.6 : 0)
        }
        .task {
            var i = 0
            while !Task.isCancelled {
                let p = phrases[i % phrases.count]
                for ch in p {
                    shown.append(ch)
                    try? await Task.sleep(for: .milliseconds(Int.random(in: 40...85)))
                }
                for _ in 0..<3 { caret.toggle(); try? await Task.sleep(for: .milliseconds(350)) }
                caret = true
                try? await Task.sleep(for: .milliseconds(900))
                while !shown.isEmpty {
                    shown.removeLast()
                    try? await Task.sleep(for: .milliseconds(18))
                }
                try? await Task.sleep(for: .milliseconds(300))
                i += 1
            }
        }
    }
}

// MARK: - Menu bar

struct MenuBarLabel: View {
    @ObservedObject var store: CalendarStore
    var body: some View {
        Image(systemName: "cloud.sun")
    }
}

struct MenuBarAgenda: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var app: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let today = store.events(on: Date())
        let dueToday = store.todos.filter { !$0.isCompleted && ($0.due.map { $0 < Date().startOfDay.adding(days: 1) } ?? false) }
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(Fmt.longDay.string(from: Date())).font(.display(12, .medium)).foregroundStyle(Haze.mute)
                Text("Today").font(.display(26, .medium)).foregroundStyle(Haze.ink)
            }
            if today.isEmpty {
                Text("No events today.").font(.display(13)).foregroundStyle(Haze.mute)
            }
            ForEach(today.prefix(8)) { ev in
                HStack(spacing: 10) {
                    Capsule().fill(ev.color).frame(width: 3, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(ev.title).font(.display(13, .medium)).foregroundStyle(Haze.ink).lineLimit(1)
                        Text(ev.isAllDay ? "All day" : Fmt.range(ev.start, ev.end)).font(.display(11)).foregroundStyle(Haze.mute)
                    }
                    Spacer()
                }
                .opacity(ev.end < Date() ? 0.5 : 1)
            }
            if !dueToday.isEmpty {
                Label("\(dueToday.count) to-do\(dueToday.count == 1 ? "" : "s") due today", systemImage: "checklist")
                    .font(.display(12.5, .medium)).foregroundStyle(Haze.inkSoft)
            }
            Divider()
            HStack {
                Button("Open Haze") { show() }
                Spacer()
                Button("New Event") { show(); app.newEvent() }
            }
            .buttonStyle(.borderless)
            .font(.display(13, .medium))
        }
        .padding(16)
        .frame(width: 300)
    }

    private func show() {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

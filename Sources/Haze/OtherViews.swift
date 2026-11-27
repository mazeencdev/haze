import SwiftUI
import MapKit
import EventKit

// MARK: - Month (with dock-style magnification under the cursor)

struct MonthView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: CalendarStore
    @AppStorage("weekStartsMonday") private var weekStartsMonday = false
    @State private var pointer: CGPoint?

    var body: some View {
        let grid = monthGrid(for: app.focusDate)
        let month = Calendar.current.component(.month, from: app.focusDate)
        VStack(spacing: 8) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(Fmt.weekdayShort.string(from: grid[i]).uppercased())
                        .font(.display(13)).tracking(0.5)
                        .foregroundStyle(Haze.mute)
                        .frame(maxWidth: .infinity)
                }
            }
            GeometryReader { geo in
                let cw = geo.size.width / 7, ch = geo.size.height / 6
                ZStack(alignment: .topLeading) {
                    ForEach(0..<42, id: \.self) { i in
                        let r = i / 7, c = i % 7
                        let center = CGPoint(x: (CGFloat(c) + 0.5) * cw, y: (CGFloat(r) + 0.5) * ch)
                        let mag = magnification(center)
                        MonthCell(date: grid[i], inMonth: Calendar.current.component(.month, from: grid[i]) == month,
                                  events: store.events(on: grid[i]), delay: Double(r + c) * 0.022, lift: mag)
                            .frame(width: cw - 8, height: ch - 8)
                            .scaleEffect(1 + mag * 0.09)
                            .zIndex(mag)
                            .offset(x: CGFloat(c) * cw + 4, y: CGFloat(r) * ch + 4)
                            .onTapGesture(count: 2) { app.newEvent(at: grid[i].startOfDay.adding(minutes: 9 * 60), origin: .grid) }
                            .onTapGesture {
                                app.reveal(grid[i])
                                app.setPage(.week)
                            }
                    }
                }
                .id(Calendar.current.dateInterval(of: .month, for: app.focusDate)?.start)
                .transition(.drift(app.navDirection * 40))
                .contentShape(Rectangle())
                .onContinuousHover(coordinateSpace: .local) { phase in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                        switch phase {
                        case .active(let p): pointer = p
                        case .ended: pointer = nil
                        }
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    private func magnification(_ c: CGPoint) -> Double {
        guard let p = app.demoPointer ?? pointer else { return 0 }
        let d = hypot(p.x - c.x, p.y - c.y)
        return max(0, 1 - Double(d) / 190)
    }
}

private struct MonthCell: View {
    let date: Date
    let inMonth: Bool
    let events: [CalEvent]
    let delay: Double
    let lift: Double
    @State private var shown = false

    var body: some View {
        let today = date.isToday
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ZStack {
                    if today { Circle().fill(Haze.ink).frame(width: 28, height: 28) }
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.display(14, today ? .semibold : .medium))
                        .foregroundStyle(today ? .white : Haze.ink)
                }
                .frame(width: 28, height: 28)
                Spacer()
                if events.count > 3 {
                    Text("+\(events.count - 3)").font(.display(10, .semibold)).foregroundStyle(Haze.mute)
                }
            }
            ForEach(events.prefix(3)) { ev in
                HStack(spacing: 5) {
                    Circle().fill(ev.color).frame(width: 5, height: 5)
                    Text(ev.title).font(.display(10.5, .medium)).foregroundStyle(Haze.ink.opacity(0.85)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.22 + lift * 0.45)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.45 + lift * 0.4), lineWidth: 1))
        .shadow(color: .black.opacity(lift * 0.12), radius: 14 * lift, y: 8 * lift)
        .opacity(inMonth ? 1 : 0.38)
        .scaleEffect(shown ? 1 : 0.85)
        .opacity(shown ? 1 : 0)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(delay)) { shown = true } }
    }
}

// MARK: - Agenda with search

struct AgendaView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: CalendarStore
    @State private var query = ""
    @FocusState private var searchFocused: Bool

    private var groups: [(day: Date, events: [CalEvent])] {
        let now = Date()
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = store.events.filter { ev in
            if q.isEmpty { return ev.end >= now.startOfDay && ev.start < now.adding(days: 60) }
            return [ev.title, ev.location ?? "", ev.notes ?? "", ev.calendarTitle].joined(separator: " ").lowercased().contains(q)
        }
        let dict = Dictionary(grouping: list) { $0.start.startOfDay }
        return dict.keys.sorted().map { ($0, dict[$0]!.sorted { $0.start < $1.start }) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Haze.mute)
                    .symbolEffect(.wiggle, value: searchFocused)
                TextField("Search events, places, notes…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.display(15))
                    .foregroundStyle(Haze.ink)
                    .focused($searchFocused)
                if !query.isEmpty {
                    Button { withAnimation { query = "" } } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Haze.mute) }
                        .buttonStyle(.plain).transition(.scale.combined(with: .opacity))
                }
            }
            .onChange(of: app.demoSearch) { _, q in if let q { searchFocused = true; query = q } }
            .padding(.horizontal, 16).frame(height: 44)
            .background(Capsule().fill(Color.white.opacity(searchFocused ? 0.6 : 0.35)))
            .overlay(Capsule().strokeBorder(.white.opacity(0.8), lineWidth: 1))
            .scaleEffect(searchFocused ? 1.01 : 1)
            .animation(Haze.snappy, value: searchFocused)
            .animation(Haze.snappy, value: query.isEmpty)

            if groups.isEmpty {
                EmptyState(icon: query.isEmpty ? "sun.haze" : "magnifyingglass",
                           title: query.isEmpty ? "Nothing scheduled" : "No matches",
                           subtitle: query.isEmpty ? "Enjoy the quiet — or press ⌘N." : "Try a different word.")
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(Array(groups.enumerated()), id: \.element.day) { gi, g in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 8) {
                                    Text(Fmt.longDay.string(from: g.day)).font(.display(15, .semibold)).foregroundStyle(Haze.ink)
                                    if g.day.isToday {
                                        Text("Today").font(.display(11, .semibold)).foregroundStyle(.white)
                                            .padding(.horizontal, 8).padding(.vertical, 2).background(Capsule().fill(Haze.ink))
                                    }
                                }
                                ForEach(Array(g.events.enumerated()), id: \.element.id) { i, ev in
                                    AgendaRow(ev: ev, delay: Double(min(gi * 3 + i, 18)) * 0.03)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 20)
                }
                .id(query.isEmpty ? "all" : "search")
            }
        }
    }
}

private struct AgendaRow: View {
    @EnvironmentObject var app: AppModel
    let ev: CalEvent
    let delay: Double
    @State private var shown = false
    @State private var hover = false

    var body: some View {
        let selected = app.selectedEventID == ev.id
        HStack(spacing: 14) {
            VStack(alignment: .trailing, spacing: 2) {
                Text(ev.isAllDay ? "all-day" : Fmt.time(ev.start)).font(.display(13, .medium)).foregroundStyle(Haze.ink)
                if !ev.isAllDay { Text(Fmt.duration(ev.duration)).font(.display(11)).foregroundStyle(Haze.mute) }
            }
            .frame(width: 70, alignment: .trailing)
            Capsule().fill(ev.color).frame(width: 3, height: hover ? 38 : 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(ev.title).font(.display(15, .medium)).foregroundStyle(Haze.ink).lineLimit(1)
                HStack(spacing: 10) {
                    Text(ev.calendarTitle).font(.display(11.5, .medium)).foregroundStyle(ev.color)
                    if ev.hasLocation {
                        Label(ev.location ?? "", systemImage: "mappin").labelStyle(TightLabel())
                            .font(.display(11.5)).foregroundStyle(Haze.mute).lineLimit(1)
                    }
                }
            }
            Spacer()
            if hover && ev.hasLocation {
                Button { MapsLink.open(MapsLink.apple(ev)) } label: {
                    Image(systemName: "map").font(.system(size: 12)).foregroundStyle(Haze.ink)
                        .frame(width: 30, height: 30).background(Circle().fill(.white.opacity(0.7)))
                }
                .buttonStyle(PressStyle()).transition(.scale.combined(with: .opacity))
                .help("Open in Maps")
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(selected ? 0.8 : (hover ? 0.5 : 0.28))))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? ev.color.opacity(0.6) : .white.opacity(0.6), lineWidth: 1))
        .offset(x: hover ? 6 : 0)
        .offset(y: shown ? 0 : 18)
        .opacity(shown ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture { app.select(ev) }
        .simultaneousGesture(TapGesture(count: 2).onEnded { if ev.editable { app.edit(ev) } })
        .onHover { h in withAnimation(Haze.snappy) { hover = h } }
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(delay)) { shown = true } }
    }
}

struct EmptyState: View {
    let icon: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 42, weight: .ultraLight))
                .foregroundStyle(Haze.ink.opacity(0.6))
                .phaseAnimator([0.0, -8.0]) { v, y in v.offset(y: y) } animation: { _ in .easeInOut(duration: 2.2) }
            Text(title).font(.display(20, .medium)).foregroundStyle(Haze.ink)
            Text(subtitle).font(.display(14)).foregroundStyle(Haze.mute)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Places (map of where you're going)

struct PlacesView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: CalendarStore
    @ObservedObject private var geo = GeoCache.shared
    @State private var camera: MapCameraPosition = .automatic
    @State private var focusID: String?

    private var located: [CalEvent] {
        let now = Date()
        return store.events.filter { $0.hasLocation && $0.end >= now.adding(days: -7) && $0.start < now.adding(days: 45) }
    }

    var body: some View {
        HStack(spacing: 16) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 8) {
                    if located.isEmpty {
                        Text("Add a location to an event and it lands here.")
                            .font(.display(14)).foregroundStyle(Haze.mute).padding(.top, 20)
                    }
                    ForEach(located) { ev in
                        placeRow(ev)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(width: 270)

            ZStack(alignment: .bottom) {
                Map(position: $camera) {
                    ForEach(located) { ev in
                        if let c = geo.coordinate(for: ev) {
                            Annotation(ev.title, coordinate: c, anchor: .bottom) {
                                MapPin(ev: ev, focused: focusID == ev.id)
                                    .onTapGesture { fly(ev) }
                            }
                            .annotationTitles(.hidden)
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic, emphasis: .muted, pointsOfInterest: .excludingAll, showsTraffic: false))
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 1))

                if let ev = located.first(where: { $0.id == focusID }) {
                    HStack(spacing: 8) {
                        OutlinePill(title: "Apple Maps", icon: "map", filled: true) { MapsLink.open(MapsLink.apple(ev)) }
                        OutlinePill(title: "Google Maps", icon: "globe") { MapsLink.open(MapsLink.google(ev)) }
                        OutlinePill(title: "Directions", icon: "arrow.triangle.turn.up.right.diamond") { MapsLink.open(MapsLink.apple(ev, directions: true)) }
                    }
                    .padding(8)
                    .glass(radius: 30, tint: 0.6, spotlight: false)
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Haze.spring, value: focusID)
        }
        .padding(.bottom, 6)
        .onChange(of: app.placeFocusID) { _, id in
            if let id, let ev = located.first(where: { $0.id == id }) { fly(ev) }
        }
    }

    private func placeRow(_ ev: CalEvent) -> some View {
        let f = focusID == ev.id
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Circle().fill(ev.color).frame(width: 7, height: 7)
                Text(Fmt.shortDay.string(from: ev.start) + (ev.isAllDay ? "" : " · " + Fmt.time(ev.start)))
                    .font(.display(11.5, .medium)).foregroundStyle(Haze.mute)
            }
            Text(ev.title).font(.display(14.5, .medium)).foregroundStyle(Haze.ink).lineLimit(1)
            Text(ev.location ?? "").font(.display(12)).foregroundStyle(Haze.inkSoft.opacity(0.8)).lineLimit(2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(f ? 0.8 : 0.3)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(f ? ev.color.opacity(0.6) : .white.opacity(0.6), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { fly(ev) }
    }

    private func fly(_ ev: CalEvent) {
        focusID = ev.id
        app.select(ev)
        guard let c = geo.coordinate(for: ev) else { return }
        // swoop: pull back, then dive in with pitch
        withAnimation(.easeInOut(duration: 0.6)) {
            camera = .camera(MapCamera(centerCoordinate: c, distance: 40_000, heading: 0, pitch: 0))
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            withAnimation(.easeInOut(duration: 1.4)) {
                camera = .camera(MapCamera(centerCoordinate: c, distance: 1800, heading: 25, pitch: 55))
            }
        }
    }
}

private struct MapPin: View {
    let ev: CalEvent
    let focused: Bool
    var body: some View {
        VStack(spacing: 2) {
            Text(ev.isAllDay ? ev.title : Fmt.time(ev.start))
                .font(.display(11, .semibold)).foregroundStyle(Haze.ink).lineLimit(1)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(.white))
                .shadow(color: .black.opacity(0.15), radius: 6, y: 3)
            ZStack {
                if focused {
                    Circle().stroke(ev.color, lineWidth: 2).frame(width: 30, height: 30)
                        .phaseAnimator([0.5, 1.4]) { v, s in v.scaleEffect(s).opacity(1.5 - s) } animation: { _ in .easeOut(duration: 1.2) }
                }
                Circle().fill(ev.color).frame(width: 14, height: 14)
                    .overlay(Circle().stroke(.white, lineWidth: 3))
            }
        }
        .scaleEffect(focused ? 1.2 : 1, anchor: .bottom)
        .animation(Haze.bouncy, value: focused)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @EnvironmentObject var store: CalendarStore
    @AppStorage("weekStartsMonday") private var weekStartsMonday = false
    @AppStorage("use24h") private var use24h = true
    @AppStorage("liveSky") private var liveSky = true
    @AppStorage("hourHeight") private var hourHeight: Double = 72
    @AppStorage("defaultAlert") private var defaultAlert = 15

    private var sources: [(String, [EKCalendar])] {
        let d = Dictionary(grouping: store.calendars) { $0.source?.title ?? "Other" }
        return d.keys.sorted().map { ($0, d[$0]!) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    card("Calendars") {
                        ForEach(sources, id: \.0) { src, cals in
                            Text(src).font(.display(12, .semibold)).foregroundStyle(Haze.mute).padding(.top, 6)
                            ForEach(cals, id: \.calendarIdentifier) { cal in
                                let on = !store.hiddenCalendars.contains(cal.calendarIdentifier)
                                HStack {
                                    Circle().fill(Color(nsColor: cal.color)).frame(width: 10, height: 10)
                                    Text(cal.title).font(.display(14, .medium)).foregroundStyle(Haze.ink)
                                    Spacer()
                                    SpringToggle(isOn: on, tint: Color(nsColor: cal.color)) {
                                        if on { store.hiddenCalendars.insert(cal.calendarIdentifier) }
                                        else { store.hiddenCalendars.remove(cal.calendarIdentifier) }
                                    }
                                }
                            }
                        }
                    }
                    card("Sync with Google") {
                        Text("Haze reads the calendars macOS knows about. Add your Google account in Internet Accounts and its calendars appear here instantly — edits sync both ways.")
                            .font(.display(13)).foregroundStyle(Haze.inkSoft).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            OutlinePill(title: "Internet Accounts", icon: "person.crop.circle.badge.plus", filled: true) {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension")!)
                            }
                            OutlinePill(title: "Sync now", icon: "arrow.triangle.2.circlepath") { store.refreshRemote() }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 18) {
                    card("Preferences") {
                        row("Week starts on Monday") { SpringToggle(isOn: weekStartsMonday) { weekStartsMonday.toggle() } }
                        row("24-hour time") { SpringToggle(isOn: use24h) { use24h.toggle() } }
                        row("Living sky background") { SpringToggle(isOn: liveSky) { liveSky.toggle() } }
                        row("Default alert") {
                            Menu(AlertChoice.label(defaultAlert < 0 ? nil : defaultAlert)) {
                                ForEach(AlertChoice.options, id: \.self) { m in
                                    Button(AlertChoice.label(m)) { defaultAlert = m ?? -1 }
                                }
                            }
                            .menuStyle(.borderlessButton).fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Grid density").font(.display(14, .medium)).foregroundStyle(Haze.ink)
                            Slider(value: $hourHeight, in: 52...120).tint(Haze.ink)
                        }
                    }
                    card("Shortcuts") {
                        shortcut("⌘N", "New event")
                        shortcut("⌘T", "Jump to today")
                        shortcut("⌘← / ⌘→", "Previous / next")
                        shortcut("⌘1 – ⌘5", "Switch views")
                        shortcut("⌘E / ⌘⌫", "Edit / delete selected")
                        shortcut("Double-click", "Create at that time")
                        shortcut("Drag", "Move an event (snaps to 15 min)")
                        shortcut("Click a day", "Focus that day in the week")
                    }
                }
            }
            .padding(.bottom, 20)
        }
    }

    private func card<C: View>(_ title: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.display(18, .semibold)).foregroundStyle(Haze.ink)
            content()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 22, style: .continuous).fill(Color.white.opacity(0.35)))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(.white.opacity(0.7), lineWidth: 1))
    }

    private func row<C: View>(_ label: String, @ViewBuilder _ trailing: () -> C) -> some View {
        HStack { Text(label).font(.display(14, .medium)).foregroundStyle(Haze.ink); Spacer(); trailing() }
    }

    private func shortcut(_ k: String, _ d: String) -> some View {
        HStack {
            Text(k).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(Haze.ink)
                .padding(.horizontal, 8).padding(.vertical, 3)
                .background(RoundedRectangle(cornerRadius: 7).fill(.white.opacity(0.7)))
            Text(d).font(.display(13)).foregroundStyle(Haze.inkSoft)
        }
    }
}

/// Toggle whose knob squashes and stretches as it travels.
struct SpringToggle: View {
    let isOn: Bool
    var tint: Color = Haze.ink
    let action: () -> Void
    @State private var pressing = false

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? tint.opacity(0.85) : Haze.ink.opacity(0.12)).frame(width: 42, height: 24)
            Capsule().fill(.white)
                .frame(width: pressing ? 26 : 20, height: 20)
                .shadow(color: .black.opacity(0.15), radius: 2, y: 1)
                .padding(2)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.62), value: isOn)
        .animation(.spring(response: 0.2, dampingFraction: 0.7), value: pressing)
        .contentShape(Capsule())
        .onTapGesture { action() }
        .onLongPressGesture(minimumDuration: 10, pressing: { pressing = $0 }, perform: {})
    }
}

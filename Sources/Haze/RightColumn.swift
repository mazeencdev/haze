import SwiftUI
import MapKit
import EventKit

struct RightColumn: View {
    @EnvironmentObject var app: AppModel

    var body: some View {
        VStack(spacing: 22) {
            UpNextCard()
            ZStack(alignment: .top) {
                if let ev = app.selectedEvent {
                    EventDetailCard(ev: ev)
                        .id(ev.id)
                        .transition(.asymmetric(insertion: .offset(x: 40).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                                                removal: .focusPull))
                } else {
                    TodoCard()
                        .transition(.focusPull)
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Up Next (the reference's "Task Reminder", made live)

private enum UpNextItem {
    case todo(Todo), event(CalEvent)
    var key: String {
        switch self {
        case .todo(let t): "t" + t.id
        case .event(let e): "e" + e.id
        }
    }
}

struct UpNextCard: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: CalendarStore
    @State private var celebrating = false
    @State private var showSnooze = false

    private func upNext(_ now: Date) -> UpNextItem? {
        let todo = store.todos
            .filter { !$0.isCompleted && $0.hasTime && $0.due != nil && $0.due! < now.adding(days: 3) }
            .min { $0.due! < $1.due! }
        let ev = store.events
            .filter { !$0.isAllDay && $0.end > now && $0.start < now.adding(days: 14) }
            .min { $0.start < $1.start }
        switch (todo, ev) {
        case let (t?, e?): return t.due! <= e.start ? .todo(t) : .event(e)
        case let (t?, nil): return .todo(t)
        case let (nil, e?): return .event(e)
        default: return nil
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let item = upNext(ctx.date)
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Up Next").font(.display(16, .semibold)).foregroundStyle(Haze.ink)
                    Spacer()
                    if let item { countdown(item, ctx.date) }
                }
                ZStack(alignment: .topLeading) {
                    content(item, ctx.date)
                        .id(item?.key ?? "none")
                        .transition(.asymmetric(insertion: .offset(y: 24).combined(with: .opacity).combined(with: .modifier(active: BlurModifier(radius: 8), identity: BlurModifier(radius: 0))),
                                                removal: .offset(y: -24).combined(with: .opacity)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
                if let item { buttons(item) }
            }
            .animation(Haze.spring, value: item?.key)
        }
        .padding(26)
        .glass(radius: 26, tint: 0.26)
    }

    private func countdown(_ item: UpNextItem, _ now: Date) -> some View {
        let target: Date
        var live = false
        switch item {
        case .todo(let t): target = t.due ?? now
        case .event(let e): target = e.start; live = e.start <= now
        }
        let overdue = target < now && !live
        let text = live ? "happening now" : Fmt.countdown(to: target, now: now)
        return HStack(spacing: 6) {
            if live {
                Circle().fill(Haze.coral).frame(width: 6, height: 6)
                    .phaseAnimator([1.0, 0.3]) { v, o in v.opacity(o) } animation: { _ in .easeInOut(duration: 0.8) }
            }
            Text(text).contentTransition(.numericText())
        }
        .font(.display(12, .semibold))
        .foregroundStyle(overdue || live ? Haze.coral : Haze.inkSoft)
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Capsule().fill(Color.white.opacity(0.4)))
        .animation(Haze.snappy, value: text)
    }

    @ViewBuilder
    private func content(_ item: UpNextItem?, _ now: Date) -> some View {
        switch item {
        case .none:
            VStack(alignment: .leading, spacing: 6) {
                Text("All clear.").font(.display(30)).foregroundStyle(Haze.ink.opacity(0.72))
                Text("Nothing due in the next few days.").font(.display(14)).foregroundStyle(Haze.mute)
            }
        case .todo(let t):
            VStack(alignment: .leading, spacing: 6) {
                Text(t.title).font(.display(30)).foregroundStyle(Haze.ink.opacity(0.72)).lineLimit(3)
                    .strikethrough(celebrating, color: Haze.ink.opacity(0.5))
                Text("\(t.listTitle) · \(Fmt.dueLabel(t) ?? "")").font(.display(13, .medium)).foregroundStyle(t.color)
            }
        case .event(let e):
            VStack(alignment: .leading, spacing: 6) {
                Text(e.title).font(.display(30)).foregroundStyle(Haze.ink.opacity(0.72)).lineLimit(3)
                HStack(spacing: 8) {
                    Text(Fmt.range(e.start, e.end)).foregroundStyle(Haze.inkSoft)
                    Text(e.calendarTitle).foregroundStyle(e.color)
                }
                .font(.display(13, .medium))
                if e.hasLocation {
                    Label(e.location ?? "", systemImage: "mappin").labelStyle(TightLabel())
                        .font(.display(12.5)).foregroundStyle(Haze.mute).lineLimit(1)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { app.select(e) }
        }
    }

    @ViewBuilder
    private func buttons(_ item: UpNextItem) -> some View {
        HStack(spacing: 10) {
            switch item {
            case .todo(let t):
                OutlinePill(title: "Snooze", icon: "moon.zzz") { showSnooze = true }
                    .popover(isPresented: $showSnooze, arrowEdge: .bottom) { snoozeMenu(t) }
                CompleteButton(done: celebrating) {
                    withAnimation(Haze.bouncy) { celebrating = true }
                    Haptic.thunk()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) {
                        store.setCompleted(t, true)
                        celebrating = false
                    }
                }
            case .event(let e):
                if let link = e.meetingLink {
                    OutlinePill(title: "Join call", icon: "video", filled: true) { NSWorkspace.shared.open(link) }
                }
                if e.hasLocation {
                    OutlinePill(title: "Directions", icon: "arrow.triangle.turn.up.right.diamond") {
                        MapsLink.open(MapsLink.apple(e, directions: true))
                    }
                }
                OutlinePill(title: "Details", icon: "text.alignleft") { app.select(e) }
            }
        }
    }

    private func snoozeMenu(_ t: Todo) -> some View {
        let tonight = Date().startOfDay.adding(minutes: 20 * 60)
        let tomorrow = Date().startOfDay.adding(days: 1).adding(minutes: 9 * 60)
        let options: [(String, () -> Void)] = [
            ("10 minutes", { store.snooze(t, by: 600) }),
            ("1 hour", { store.snooze(t, by: 3600) }),
            ("This evening", { store.setDue(t, max(tonight, Date().addingTimeInterval(1800)), hasTime: true) }),
            ("Tomorrow morning", { store.setDue(t, tomorrow, hasTime: true) }),
        ]
        return VStack(alignment: .leading, spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                Button {
                    options[i].1()
                    showSnooze = false
                    app.toast("Snoozed · \(options[i].0)", icon: "moon.zzz")
                } label: {
                    Text(options[i].0).font(.display(14, .medium)).foregroundStyle(Haze.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(HoverRow())
            }
        }
        .padding(8)
        .frame(width: 200)
    }
}

struct HoverRow: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { HoverRowBody(configuration: configuration) }
    private struct HoverRowBody: View {
        let configuration: Configuration
        @State private var hover = false
        var body: some View {
            configuration.label
                .background(RoundedRectangle(cornerRadius: 8).fill(Haze.ink.opacity(hover ? 0.07 : 0)))
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .onHover { hover = $0 }
        }
    }
}

/// "Mark as Completed" that morphs into a filled check.
private struct CompleteButton: View {
    let done: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if done {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                        .transition(.scale(scale: 0.2).combined(with: .opacity))
                }
                Text(done ? "Done" : "Mark as Completed").font(.display(13.5, .medium))
                    .contentTransition(.interpolate)
            }
            .foregroundStyle(done ? .white : Haze.ink.opacity(0.85))
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background(Capsule().fill(done ? Haze.mint : Color.white.opacity(0.18)))
            .overlay(Capsule().strokeBorder(done ? .clear : Haze.ink.opacity(0.16), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - To-do list

private enum TodoFilter: String, CaseIterable { case today = "Today", upcoming = "Upcoming", all = "All" }

struct TodoCard: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var app: AppModel
    @State private var filter: TodoFilter = .today
    @State private var newTitle = ""
    @FocusState private var adding: Bool
    @Namespace private var tabNS

    private var filtered: [Todo] {
        let endOfToday = Date().startOfDay.adding(days: 1)
        switch filter {
        case .today: return store.todos.filter { t in (t.due.map { $0 < endOfToday } ?? false) }
        case .upcoming: return store.todos.filter { t in (t.due.map { $0 >= endOfToday } ?? false) }
        case .all: return store.todos
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("To-do list").font(.display(30, .medium)).foregroundStyle(Haze.ink)
                Text("\(filtered.filter { !$0.isCompleted }.count)")
                    .font(.display(13, .semibold)).foregroundStyle(Haze.inkSoft)
                    .contentTransition(.numericText())
                    .padding(.horizontal, 9).padding(.vertical, 2)
                    .background(Capsule().fill(Haze.ink.opacity(0.07)))
                Spacer()
            }

            HStack(spacing: 4) {
                ForEach(TodoFilter.allCases, id: \.self) { f in
                    Button { withAnimation(Haze.spring) { filter = f } } label: {
                        Text(f.rawValue).font(.display(13, .medium))
                            .foregroundStyle(filter == f ? Haze.ink : Haze.mute)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background {
                                if filter == f {
                                    Capsule().fill(Color.white).shadow(color: .black.opacity(0.06), radius: 4, y: 2)
                                        .matchedGeometryEffect(id: "tab", in: tabNS)
                                }
                            }
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(3)
            .background(Capsule().fill(Haze.ink.opacity(0.05)))

            if !store.remindersAuthorized {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Connect Reminders to see your to-dos here.").font(.display(14)).foregroundStyle(Haze.inkSoft)
                    OutlinePill(title: "Connect Reminders", icon: "checklist", filled: true) {
                        Task { await store.requestAccess() }
                    }
                }
            } else {
                addRow
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(filtered) { t in
                            TodoRow(todo: t)
                                .transition(.asymmetric(insertion: .offset(y: -16).combined(with: .opacity),
                                                        removal: .offset(x: 60).combined(with: .opacity).combined(with: .scale(scale: 0.9, anchor: .leading))))
                        }
                        if filtered.isEmpty {
                            HStack(spacing: 10) {
                                Image(systemName: "sparkles").foregroundStyle(Haze.mint)
                                    .symbolEffect(.pulse)
                                Text(filter == .today ? "Nothing left for today." : "Nothing here.")
                                    .font(.display(15)).foregroundStyle(Haze.mute)
                            }
                            .padding(.top, 6)
                        }
                    }
                    .padding(.vertical, 4)
                    .animation(Haze.spring, value: filtered.map(\.id))
                }
                .id(filter)
                .transition(.focusPull)
            }
        }
        .padding(28)
        .frame(maxHeight: .infinity, alignment: .top)
        .glass(radius: 26, tint: 0.74)
        .onChange(of: app.demoTodoText) { _, t in
            if let t { adding = true; newTitle = t }
        }
        .onChange(of: app.demoTodoSubmit) { _, _ in commit(); adding = false }
    }

    private var addRow: some View {
        let parsed = NL.parse(newTitle)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(adding ? .white : Haze.ink.opacity(0.5))
                    .frame(width: 22, height: 22)
                    .background(RoundedRectangle(cornerRadius: 7).fill(adding ? Haze.ink : Haze.ink.opacity(0.06)))
                    .rotationEffect(.degrees(adding ? 90 : 0))
                TextField("Add a to-do — try “call mom tomorrow 5pm”", text: $newTitle)
                    .textFieldStyle(.plain)
                    .font(.display(15))
                    .foregroundStyle(Haze.ink)
                    .focused($adding)
                    .onSubmit(commit)
            }
            if let p = parsed {
                HStack(spacing: 5) {
                    Image(systemName: "calendar.badge.clock")
                    Text(p.hasTime ? "\(Fmt.shortDay.string(from: p.date)) · \(Fmt.time(p.date))" : Fmt.shortDay.string(from: p.date))
                }
                .font(.display(11.5, .semibold))
                .foregroundStyle(Haze.ink.opacity(0.7))
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(Capsule().fill(Haze.mint.opacity(0.18)))
                .padding(.leading, 34)
                .transition(.scale(scale: 0.6, anchor: .leading).combined(with: .opacity))
            }
        }
        .animation(Haze.bouncy, value: parsed?.phrase)
        .animation(Haze.snappy, value: adding)
    }

    private func commit() {
        let text = newTitle.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        if let p = NL.parse(text) {
            let title = NL.strip(text, phrase: p.phrase)
            store.addTodo(title.isEmpty ? text : title, due: p.date, hasTime: p.hasTime)
        } else {
            let due: Date? = filter == .today ? Date().startOfDay : nil
            store.addTodo(text, due: due, hasTime: false)
        }
        newTitle = ""
        Haptic.tick()
    }
}

private struct TodoRow: View {
    @EnvironmentObject var store: CalendarStore
    let todo: Todo
    @State private var hover = false

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            AnimatedCheckbox(checked: todo.isCompleted, tint: todo.color) {
                store.setCompleted(todo, !todo.isCompleted)
            }
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                Text(todo.title)
                    .font(.display(16))
                    .foregroundStyle(Haze.ink.opacity(todo.isCompleted ? 0.38 : 0.8))
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .overlay(alignment: .topLeading) {
                        GeometryReader { g in
                            Capsule().fill(Haze.ink.opacity(0.55))
                                .frame(width: todo.isCompleted ? g.size.width : 0, height: 1.5)
                                .offset(y: 11)
                        }
                        .animation(.easeInOut(duration: 0.35).delay(0.12), value: todo.isCompleted)
                    }
                if let due = Fmt.dueLabel(todo) {
                    HStack(spacing: 0) {
                        Text("Due : ").foregroundStyle(Haze.inkSoft)
                        Text(due).fontWeight(.semibold).foregroundStyle(todo.isOverdue ? Haze.coral : Haze.ink)
                    }
                    .font(.display(12.5))
                    .padding(.horizontal, 12).padding(.vertical, 5)
                    .overlay(Capsule().strokeBorder(Haze.ink.opacity(0.14), lineWidth: 1))
                }
            }
            Spacer(minLength: 0)
            Menu {
                Button("Due today") { store.setDue(todo, Date().startOfDay, hasTime: false) }
                Button("Due tomorrow") { store.setDue(todo, Date().startOfDay.adding(days: 1), hasTime: false) }
                Button("Due next week") { store.setDue(todo, Date().startOfDay.adding(days: 7), hasTime: false) }
                Button("Clear due date") { store.setDue(todo, nil, hasTime: false) }
                Divider()
                Button("Delete", role: .destructive) { store.deleteTodo(todo) }
            } label: {
                Image(systemName: "ellipsis").font(.system(size: 13, weight: .semibold)).foregroundStyle(Haze.ink)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .opacity(hover ? 1 : 0)
        }
        .contentShape(Rectangle())
        .onHover { h in withAnimation(Haze.snappy) { hover = h } }
    }
}

/// Checkbox that draws its tick and throws a little burst of confetti.
struct AnimatedCheckbox: View {
    let checked: Bool
    var tint: Color = Haze.mint
    let action: () -> Void
    @State private var burst = 0

    private struct BurstV { var dist: CGFloat = 0; var opacity: Double = 0 }

    var body: some View {
        Button {
            if !checked { Haptic.tick() }
            action()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Haze.ink.opacity(checked ? 0 : 0.25), lineWidth: 1.5)
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Haze.ink)
                    .scaleEffect(checked ? 1 : 0.2)
                    .opacity(checked ? 1 : 0)
                CheckShape()
                    .trim(from: 0, to: checked ? 1 : 0)
                    .stroke(.white, style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(width: 11, height: 8)
                    .animation(.easeOut(duration: 0.28).delay(0.1), value: checked)
                ForEach(0..<8, id: \.self) { i in
                    let angle = Double(i) / 8 * 2 * .pi
                    Circle().fill(i % 2 == 0 ? tint : Haze.ink.opacity(0.6))
                        .frame(width: i % 2 == 0 ? 4 : 3, height: i % 2 == 0 ? 4 : 3)
                        .keyframeAnimator(initialValue: BurstV(), trigger: burst) { v, b in
                            v.offset(x: cos(angle) * b.dist, y: sin(angle) * b.dist).opacity(b.opacity)
                        } keyframes: { _ in
                            KeyframeTrack(\.dist) {
                                LinearKeyframe(4, duration: 0.01)
                                SpringKeyframe(22, duration: 0.5, spring: .snappy)
                            }
                            KeyframeTrack(\.opacity) {
                                LinearKeyframe(1, duration: 0.01)
                                LinearKeyframe(1, duration: 0.2)
                                LinearKeyframe(0, duration: 0.3)
                            }
                        }
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 22, height: 22)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressStyle(scale: 0.8))
        .animation(.spring(response: 0.35, dampingFraction: 0.55), value: checked)
        .onChange(of: checked) { _, now in if now { burst += 1 } }
    }
}

struct CheckShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.midY))
        p.addLine(to: CGPoint(x: r.minX + r.width * 0.38, y: r.maxY))
        p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        return p
    }
}

// MARK: - Event detail

struct EventDetailCard: View {
    @EnvironmentObject var app: AppModel
    @ObservedObject private var geo = GeoCache.shared
    let ev: CalEvent
    @State private var askSpan = false
    @State private var dissolving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                HStack(spacing: 6) {
                    Circle().fill(ev.color).frame(width: 8, height: 8)
                    Text(ev.calendarTitle).font(.display(12.5, .semibold)).foregroundStyle(ev.color)
                }
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(ev.color.opacity(0.12)))
                Spacer()
                Button { app.select(nil) } label: {
                    Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(Haze.ink)
                        .frame(width: 28, height: 28).background(Circle().fill(Haze.ink.opacity(0.06)))
                }
                .buttonStyle(PressStyle(scale: 0.8))
            }

            Text(ev.title).font(.display(28, .medium)).foregroundStyle(Haze.ink).lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 7) {
                info("calendar", Fmt.longDay.string(from: ev.start))
                if !ev.isAllDay {
                    info("clock", "\(Fmt.range(ev.start, ev.end))  ·  \(Fmt.duration(ev.duration))")
                } else {
                    info("sun.max", "All day")
                }
                if ev.isRecurring { info("repeat", "Repeats") }
                if let m = ev.alarmMinutes { info("bell", AlertChoice.label(m)) }
            }

            if ev.hasLocation { locationBlock }

            if let link = ev.meetingLink {
                OutlinePill(title: "Join call", icon: "video.fill", filled: true) { NSWorkspace.shared.open(link) }
            }

            if let notes = ev.notes, !notes.isEmpty {
                ScrollView(showsIndicators: false) {
                    Text(notes).font(.display(13.5)).foregroundStyle(Haze.inkSoft)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 110)
            }

            Spacer(minLength: 0)

            if ev.editable {
                HStack(spacing: 10) {
                    OutlinePill(title: "Edit", icon: "pencil", filled: true) { app.edit(ev) }
                    OutlinePill(title: "Duplicate", icon: "plus.square.on.square") { app.duplicate(ev) }
                    Spacer()
                    Button { ev.isRecurring ? (askSpan = true) : dissolve(.thisEvent) } label: {
                        Image(systemName: "trash").font(.system(size: 13, weight: .medium)).foregroundStyle(Haze.coral)
                            .frame(width: 38, height: 38).background(Circle().fill(Haze.coral.opacity(0.1)))
                    }
                    .buttonStyle(PressStyle(scale: 0.8))
                    .help("Delete")
                }
            } else {
                Text("Read-only calendar").font(.display(12)).foregroundStyle(Haze.mute)
            }
        }
        .padding(26)
        .frame(maxHeight: .infinity, alignment: .top)
        .glass(radius: 26, tint: 0.72)
        .scaleEffect(dissolving ? 0.9 : 1)
        .blur(radius: dissolving ? 16 : 0)
        .opacity(dissolving ? 0 : 1)
        .rotation3DEffect(.degrees(dissolving ? 8 : 0), axis: (x: 1, y: 0, z: 0))
        .confirmationDialog("Delete recurring event?", isPresented: $askSpan) {
            Button("Delete only this event", role: .destructive) { dissolve(.thisEvent) }
            Button("Delete all future events", role: .destructive) { dissolve(.futureEvents) }
        }
    }

    private func dissolve(_ span: EKSpan) {
        Haptic.thunk()
        withAnimation(.easeIn(duration: 0.32)) { dissolving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) { app.deleteWithUndo(ev, span: span) }
    }

    private func info(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 12)).frame(width: 16).foregroundStyle(Haze.mute)
            Text(text).font(.display(14, .medium)).foregroundStyle(Haze.inkSoft)
        }
    }

    @ViewBuilder
    private var locationBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack {
                if let c = geo.coordinate(for: ev) {
                    Map(initialPosition: .region(MKCoordinateRegion(center: c, latitudinalMeters: 900, longitudinalMeters: 900)),
                        interactionModes: []) {
                        Marker(ev.title, coordinate: c).tint(ev.color)
                    }
                    .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                    .transition(.opacity)
                } else {
                    Shimmer()
                }
            }
            .frame(height: 130)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 1))
            .animation(.easeInOut(duration: 0.5), value: geo.coordinate(for: ev) != nil)
            .onTapGesture { MapsLink.open(MapsLink.apple(ev)) }

            Label(ev.location ?? "", systemImage: "mappin.and.ellipse").labelStyle(TightLabel())
                .font(.display(13)).foregroundStyle(Haze.inkSoft).lineLimit(2)
                .textSelection(.enabled)

            HStack(spacing: 8) {
                MiniPill(title: "Apple Maps", icon: "map") { MapsLink.open(MapsLink.apple(ev)) }
                MiniPill(title: "Google Maps", icon: "globe.americas") { MapsLink.open(MapsLink.google(ev)) }
                MiniPill(title: "Route", icon: "arrow.triangle.turn.up.right.diamond") { MapsLink.open(MapsLink.google(ev, directions: true)) }
            }
        }
    }
}


struct MiniPill: View {
    let title: String
    let icon: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 10.5, weight: .semibold))
                Text(title).font(.display(12, .medium))
            }
            .foregroundStyle(Haze.ink.opacity(0.85))
            .padding(.horizontal, 10).padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(0.6)))
            .overlay(Capsule().strokeBorder(Haze.ink.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(PressStyle())
    }
}

/// Loading placeholder with a sweeping sheen.
struct Shimmer: View {
    var body: some View {
        TimelineView(.animation) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            GeometryReader { g in
                ZStack {
                    Color.white.opacity(0.35)
                    LinearGradient(colors: [.clear, .white.opacity(0.7), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: g.size.width * 0.5)
                        .offset(x: (CGFloat(t) * 2 - 1) * g.size.width)
                }
            }
        }
    }
}

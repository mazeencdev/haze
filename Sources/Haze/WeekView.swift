import SwiftUI

private struct Placed: Identifiable {
    let ev: CalEvent
    let day: Int
    let col: Int
    let cols: Int
    let s: Date
    let e: Date
    var id: String { ev.id + "#\(day)" }
}

private struct Slot: Equatable { let day: Int; let minute: Int }
private typealias ColFrame = (x: CGFloat, w: CGFloat)

struct WeekView: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: CalendarStore
    @AppStorage("hourHeight") private var hourHeight: Double = 72
    @AppStorage("weekStartsMonday") private var weekStartsMonday = false
    @AppStorage("use24h") private var use24h = true

    @State private var ghost: Slot?

    private var focusedDay: Int? {
        get { app.focusedDay }
        nonmutating set { app.focusedDay = newValue }
    }
    private var dragID: String? {
        get { app.dragID }
        nonmutating set { app.dragID = newValue }
    }
    private var dragDay: Int {
        get { app.dragDay }
        nonmutating set { app.dragDay = newValue }
    }
    private var dragMin: Int {
        get { app.dragMin }
        nonmutating set { app.dragMin = newValue }
    }

    private let gutter: CGFloat = 64

    private var days: [Date] { weekDays(containing: app.focusDate) }
    private var hh: CGFloat { CGFloat(hourHeight) }

    private func frames(_ width: CGFloat) -> [ColFrame] {
        let weights: [CGFloat] = (0..<7).map { i in
            guard let f = focusedDay else { return 1 }
            return i == f ? 3.4 : 0.6
        }
        let total = weights.reduce(0, +)
        var x: CGFloat = 0
        return weights.map { w in
            let cw = width * w / total
            defer { x += cw }
            return (x, cw)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let gridW = max(100, geo.size.width - gutter)
            let cols = frames(gridW)
            VStack(spacing: 0) {
                header(cols)
                allDayRow(cols)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 0) {
                            HourRail(hh: hh, showNow: days.contains { $0.isToday })
                                .frame(width: gutter)
                            ZStack(alignment: .topLeading) {
                                gridLines(cols, width: gridW)
                                interactionLayer(cols)
                                ghostView(cols)
                                eventsLayer(cols)
                                    .id(days[0])
                                    .transition(.drift(app.navDirection * 50))
                                NowLine(days: days, cols: cols, hh: hh, width: gridW)
                            }
                            .frame(width: gridW, height: hh * 24, alignment: .topLeading)
                            .coordinateSpace(name: "grid")
                        }
                        .padding(.top, 10)
                        .padding(.bottom, 20)
                    }
                    .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                                                 .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                                         startPoint: .top, endPoint: .bottom))
                    .onAppear {
                        let h = (days.contains { $0.isToday } && !CalendarStore.demo) ? max(0, Calendar.current.component(.hour, from: Date()) - 2) : 7
                        DispatchQueue.main.async { proxy.scrollTo(h, anchor: .top) }
                    }
                }
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.82), value: focusedDay)
    }

    // MARK: Header

    private func header(_ cols: [ColFrame]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            ForEach(0..<7, id: \.self) { i in
                DayHeader(date: days[i], index: i, focused: focusedDay == i,
                          count: store.events(on: days[i]).count)
                    .frame(width: cols[i].w)
                    .contentShape(Rectangle())
                    .onTapGesture { focusedDay = focusedDay == i ? nil : i }
                    .help(focusedDay == i ? "Back to week" : "Focus this day")
            }
        }
        .id(days[0])
        .padding(.bottom, 6)
    }

    // MARK: All-day

    @ViewBuilder
    private func allDayRow(_ cols: [ColFrame]) -> some View {
        let perDay: [[CalEvent]] = days.map { d in store.events(on: d).filter { $0.isAllDay || $0.isMultiDay } }
        if perDay.contains(where: { !$0.isEmpty }) {
            HStack(alignment: .top, spacing: 0) {
                Text("all-day").font(.display(11, .medium)).foregroundStyle(Haze.mute)
                    .frame(width: gutter, alignment: .leading).padding(.top, 5)
                ForEach(0..<7, id: \.self) { i in
                    VStack(spacing: 3) {
                        ForEach(perDay[i].prefix(2)) { ev in
                            Text(ev.title)
                                .font(.display(11, .medium)).lineLimit(1)
                                .foregroundStyle(Haze.ink)
                                .padding(.horizontal, 8).padding(.vertical, 3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Capsule().fill(ev.color.opacity(app.selectedEventID == ev.id ? 0.35 : 0.18)))
                                .onTapGesture { app.select(ev) }
                        }
                        if perDay[i].count > 2 {
                            Text("+\(perDay[i].count - 2)").font(.display(10, .medium)).foregroundStyle(Haze.mute)
                        }
                    }
                    .padding(.horizontal, 3)
                    .frame(width: cols[i].w, alignment: .top)
                }
            }
            .padding(.bottom, 6)
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    // MARK: Grid

    private func gridLines(_ cols: [ColFrame], width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<24, id: \.self) { h in
                Rectangle().fill(Color.white.opacity(h % 2 == 0 ? 0.22 : 0.12))
                    .frame(width: width, height: 1)
                    .offset(y: CGFloat(h) * hh)
            }
            ForEach(0..<7, id: \.self) { i in
                if days[i].isToday {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.16))
                        .frame(width: cols[i].w, height: hh * 24)
                        .offset(x: cols[i].x)
                }
                if i > 0 {
                    Rectangle().fill(Color.white.opacity(0.55))
                        .frame(width: 1, height: hh * 24)
                        .offset(x: cols[i].x)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func slot(at p: CGPoint, _ cols: [ColFrame]) -> Slot? {
        guard p.y >= 0, p.y < hh * 24 else { return nil }
        guard let d = cols.lastIndex(where: { $0.x <= p.x }) else { return nil }
        let m = Int((p.y / hh * 60 / 30).rounded(.down)) * 30
        return Slot(day: d, minute: min(m, 23 * 60 + 30))
    }

    private func interactionLayer(_ cols: [ColFrame]) -> some View {
        Color.clear
            .contentShape(Rectangle())
            .onContinuousHover(coordinateSpace: .local) { phase in
                switch phase {
                case .active(let p):
                    let s = slot(at: p, cols)
                    if s != ghost { withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) { ghost = s } }
                case .ended:
                    withAnimation(.easeOut(duration: 0.2)) { ghost = nil }
                }
            }
            .gesture(SpatialTapGesture(count: 2).onEnded { v in
                guard let s = slot(at: v.location, cols) else { return }
                app.newEvent(at: days[s.day].startOfDay.adding(minutes: s.minute), origin: .grid)
            })
            .simultaneousGesture(TapGesture().onEnded { app.select(nil) })
    }

    @ViewBuilder
    private func ghostView(_ cols: [ColFrame]) -> some View {
        if let g = ghost, dragID == nil, g.day < cols.count {
            let f = cols[g.day]
            HStack(spacing: 4) {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                Text(Fmt.time(days[g.day].startOfDay.adding(minutes: g.minute))).font(.display(11, .medium))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(Haze.ink.opacity(0.55))
            .padding(.horizontal, 10).padding(.top, 8)
            .frame(width: max(0, f.w - 8), height: hh - 3, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.18)))
            .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Haze.ink.opacity(0.18), style: StrokeStyle(lineWidth: 1, dash: [4, 4])))
            .offset(x: f.x + 4, y: CGFloat(g.minute) / 60 * hh + 1.5)
            .allowsHitTesting(false)
            .transition(.opacity)
            .help("Double-click to add")
        }
    }

    // MARK: Events

    private func placed() -> [Placed] {
        var out: [Placed] = []
        for (i, day) in days.enumerated() {
            let ds = day.startOfDay, de = ds.adding(days: 1)
            typealias Item = (ev: CalEvent, s: Date, e: Date)
            let dayEvents: [CalEvent] = store.events.filter { (e: CalEvent) -> Bool in
                !e.isAllDay && !e.isMultiDay && e.start < de && e.end > ds
            }
            var items: [Item] = dayEvents.map { (e: CalEvent) -> Item in (ev: e, s: max(e.start, ds), e: min(e.end, de)) }
            items.sort { (a: Item, b: Item) -> Bool in
                if a.s != b.s { return a.s < b.s }
                return a.e > b.e
            }
            var cluster: [(item: Item, col: Int)] = []
            var colEnds: [Date] = []
            var clusterEnd = Date.distantPast
            func flush() {
                for c in cluster {
                    out.append(Placed(ev: c.item.ev, day: i, col: c.col, cols: colEnds.count, s: c.item.s, e: c.item.e))
                }
                cluster = []; colEnds = []; clusterEnd = .distantPast
            }
            for it in items {
                if !cluster.isEmpty && it.s >= clusterEnd { flush() }
                // visual minimum height means short events should be treated as at least 25 min
                let visualEnd = max(it.e, it.s.addingTimeInterval(25 * 60))
                if let c = colEnds.firstIndex(where: { $0 <= it.s }) {
                    colEnds[c] = visualEnd; cluster.append((it, c))
                } else {
                    colEnds.append(visualEnd); cluster.append((it, colEnds.count - 1))
                }
                clusterEnd = max(clusterEnd, visualEnd)
            }
            flush()
        }
        return out
    }

    private func eventsLayer(_ cols: [ColFrame]) -> some View {
        let items = placed()
        return ZStack(alignment: .topLeading) {
            ForEach(items) { p in
                card(p, cols)
            }
        }
    }

    private func card(_ p: Placed, _ cols: [ColFrame]) -> some View {
        let f = cols[p.day]
        let inner = max(0, f.w - 8)
        let w = inner / CGFloat(p.cols)
        var x = f.x + 4 + w * CGFloat(p.col)
        var width = max(0, w - (p.cols > 1 ? 3 : 0))
        var y = CGFloat(p.s.minutesIntoDay) / 60 * hh + 1.5
        let h = max(26, CGFloat(p.e.timeIntervalSince(p.s)) / 3600 * hh - 3)
        let dragging = dragID == p.id
        var label: String?
        if dragging {
            if dragDay != p.day {
                x = cols[dragDay].x + 4
                width = max(0, cols[dragDay].w - 8)
            }
            y += CGFloat(dragMin) / 60 * hh
            let ns = p.ev.start.adding(days: dragDay - p.day).adding(minutes: dragMin)
            label = (dragDay != p.day ? Fmt.weekdayShort.string(from: ns) + " " : "") + Fmt.time(ns)
        }
        return EventCard(ev: p.ev, size: CGSize(width: width, height: h),
                         selected: app.selectedEventID == p.ev.id, lifted: dragging, liftLabel: label)
            .offset(x: x, y: y)
            .zIndex(dragging ? 10 : (app.selectedEventID == p.ev.id ? 2 : 1))
            .onTapGesture { app.select(p.ev) }
            .simultaneousGesture(TapGesture(count: 2).onEnded { if p.ev.editable { app.edit(p.ev) } })
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        guard p.ev.editable else { return }
                        if dragID != p.id {
                            dragDay = p.day; dragMin = 0
                            withAnimation(Haze.snappy) { dragID = p.id }
                        }
                        let cx = f.x + 4 + w * CGFloat(p.col) + w / 2 + v.translation.width
                        let td = min(6, max(0, cols.lastIndex(where: { $0.x <= cx }) ?? p.day))
                        var m = Int((v.translation.height / hh * 60 / 15).rounded()) * 15
                        let startMin = Int(p.ev.start.minutesIntoDay)
                        m = min(max(m, -startMin), 24 * 60 - 15 - startMin)
                        if td != dragDay || m != dragMin {
                            Haptic.tick()
                            withAnimation(.spring(response: 0.2, dampingFraction: 0.78)) { dragDay = td; dragMin = m }
                        }
                    }
                    .onEnded { _ in commitDrag(p) }
            )
    }

    private func commitDrag(_ p: Placed) {
        var t = Transaction(); t.disablesAnimations = true
        withTransaction(t) {
            if dragID == p.id { app.commitMove(p.ev, days: dragDay - p.day, minutes: dragMin) }
            dragID = nil; dragMin = 0
        }
    }
}

// MARK: - Pieces

private struct DayHeader: View {
    let date: Date
    let index: Int
    let focused: Bool
    let count: Int
    @State private var shown = false
    @State private var hover = false

    var body: some View {
        let today = date.isToday
        let past = date < Date().startOfDay
        VStack(spacing: 10) {
            Text(Fmt.weekdayShort.string(from: date).uppercased())
                .font(.display(13, today ? .semibold : .regular))
                .tracking(0.5)
                .foregroundStyle(today ? Haze.ink : Haze.mute.opacity(0.9))
            ZStack {
                if today {
                    Circle().fill(Haze.ink).frame(width: 34, height: 34)
                        .shadow(color: Haze.ink.opacity(0.3), radius: 8, y: 4)
                }
                Text("\(Calendar.current.component(.day, from: date))")
                    .font(.display(16, today ? .semibold : .medium))
                    .foregroundStyle(today ? .white : Haze.ink)
            }
            .frame(height: 34)
            .scaleEffect(hover ? 1.12 : 1)
            HStack(spacing: 3) {
                ForEach(0..<min(count, 4), id: \.self) { _ in
                    Circle().fill(Haze.ink.opacity(0.35)).frame(width: 3.5, height: 3.5)
                }
            }
            .frame(height: 4)
            .opacity(hover || focused ? 1 : 0)
        }
        .opacity(past && !today ? 0.42 : 1)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(focused ? 0.35 : 0))
        )
        .offset(y: shown ? 0 : -14)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.7).delay(Double(index) * 0.04)) { shown = true }
        }
        .onHover { h in withAnimation(Haze.bouncy) { hover = h } }
    }
}

private struct HourRail: View {
    let hh: CGFloat
    let showNow: Bool

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            let nowH = Calendar.current.component(.hour, from: ctx.date)
            let nowY = CGFloat(ctx.date.minutesIntoDay) / 60 * hh
            ZStack(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<24, id: \.self) { h in
                        let near = showNow && h == nowH
                        Text(Fmt.hourLabel(h))
                            .font(.display(13.5, near ? .semibold : .regular))
                            .foregroundStyle(near ? Haze.ink : Haze.inkSoft.opacity(0.75))
                            .offset(y: -9)
                            .opacity(showNow && abs(CGFloat(h) * hh - nowY) < 22 ? 0 : 1)
                            .frame(height: hh, alignment: .topLeading)
                            .id(h)
                    }
                }
                if showNow {
                    Text(Fmt.time(ctx.date))
                        .font(.display(11.5, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Haze.ink))
                        .offset(x: -4, y: nowY - 10)
                        .contentTransition(.numericText())
                }
            }
        }
    }
}

private struct NowLine: View {
    let days: [Date]
    let cols: [ColFrame]
    let hh: CGFloat
    let width: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { ctx in
            if let i = days.firstIndex(where: { $0.isSameDay(ctx.date) }) {
                let y = CGFloat(ctx.date.minutesIntoDay) / 60 * hh
                ZStack(alignment: .topLeading) {
                    Rectangle().fill(Haze.ink.opacity(0.18)).frame(width: width, height: 1).offset(y: y)
                    Rectangle().fill(Haze.ink).frame(width: cols[i].w, height: 2).offset(x: cols[i].x, y: y - 0.5)
                    Circle().fill(Haze.ink.opacity(0.18)).frame(width: 22, height: 22)
                        .phaseAnimator([0.6, 1.15]) { v, s in v.scaleEffect(s).opacity(1.3 - Double(s)) } animation: { _ in .easeInOut(duration: 1.4) }
                        .offset(x: cols[i].x - 11, y: y - 11)
                    Circle().fill(Haze.ink).frame(width: 9, height: 9)
                        .offset(x: cols[i].x - 4.5, y: y - 4.5)
                }
                .allowsHitTesting(false)
            }
        }
    }
}

// MARK: - Event card

struct EventCard: View {
    let ev: CalEvent
    let size: CGSize
    let selected: Bool
    var lifted = false
    var liftLabel: String? = nil
    @State private var pointer: CGPoint?

    var body: some View {
        let past = ev.end < Date()
        let tilt = tiltAngles()
        content
            .padding(.horizontal, 10)
            .padding(.vertical, size.height < 40 ? 4 : 9)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .clipped()
            .background {
                let shape = RoundedRectangle(cornerRadius: size.height < 40 ? 11 : 17, style: .continuous)
                ZStack {
                    shape.fill(Color.white.opacity(selected || lifted ? 0.94 : 0.62))
                    shape.fill(LinearGradient(colors: [ev.color.opacity(0.16), ev.color.opacity(0.0)],
                                              startPoint: .topLeading, endPoint: .center))
                    shape.strokeBorder(selected ? ev.color.opacity(0.75) : Color.white.opacity(0.9), lineWidth: selected ? 1.5 : 1)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let liftLabel {
                    Text(liftLabel)
                        .font(.display(11, .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Haze.ink))
                        .fixedSize()
                        .offset(x: 8, y: -14)
                        .contentTransition(.numericText())
                        .transition(.scale(scale: 0.4, anchor: .bottomLeading).combined(with: .opacity))
                }
            }
            .scaleEffect(lifted ? 1.05 : (pointer != nil ? 1.025 : 1))
            .rotation3DEffect(.degrees(tilt.x), axis: (x: 1, y: 0, z: 0), perspective: 0.5)
            .rotation3DEffect(.degrees(tilt.y), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .rotationEffect(.degrees(lifted ? -1.5 : 0))
            .shadow(color: ev.color.opacity(lifted ? 0.28 : (pointer != nil || selected ? 0.16 : 0.0)),
                    radius: lifted ? 24 : 12, y: lifted ? 16 : 6)
            .opacity(past && !selected && !lifted ? 0.7 : 1)
            .animation(Haze.snappy, value: lifted)
            .animation(Haze.snappy, value: selected)
            .onContinuousHover(coordinateSpace: .local) { phase in
                withAnimation(.easeOut(duration: 0.18)) {
                    switch phase {
                    case .active(let p): pointer = p
                    case .ended: pointer = nil
                    }
                }
            }
            .contentShape(Rectangle())
            .help("\(ev.title)\n\(Fmt.range(ev.start, ev.end))\(ev.hasLocation ? "\n" + (ev.location ?? "") : "")")
    }

    @ViewBuilder
    private var content: some View {
        let h = size.height
        if h < 40 {
            HStack(spacing: 6) {
                Text(ev.title).font(.display(11.5, .medium)).foregroundStyle(Haze.ink).lineLimit(1)
                Spacer(minLength: 0)
                Text(Fmt.time(ev.start)).font(.display(10)).foregroundStyle(Haze.mute).lineLimit(1)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(ev.title)
                    .font(.display(12.5, .medium))
                    .foregroundStyle(Haze.ink)
                    .lineLimit(max(1, Int((h - 46) / 17)))
                    .fixedSize(horizontal: false, vertical: true)
                if h >= 62 {
                    Text(ev.calendarTitle).font(.display(10, .demiBoldish)).foregroundStyle(ev.color).lineLimit(1)
                        .padding(.top, 4)
                }
                if h >= 78 {
                    Text(Fmt.range(ev.start, ev.end)).font(.display(10)).foregroundStyle(Haze.mute).lineLimit(1)
                        .padding(.top, 2)
                }
                if h >= 112, ev.hasLocation {
                    Label(ev.location ?? "", systemImage: "mappin")
                        .font(.display(10)).foregroundStyle(Haze.mute).lineLimit(1)
                        .labelStyle(TightLabel())
                }
            }
        }
    }

    private func tiltAngles() -> (x: Double, y: Double) {
        guard let p = pointer, !lifted, size.width > 0, size.height > 0 else { return (0, 0) }
        let dx = Double(p.x / size.width - 0.5)
        let dy = Double(p.y / size.height - 0.5)
        return (-dy * 9, dx * 9)
    }
}

struct TightLabel: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) { configuration.icon; configuration.title }
    }
}

extension Font.Weight {
    static let demiBoldish = Font.Weight.semibold
}

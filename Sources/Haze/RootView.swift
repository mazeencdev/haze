import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: CalendarStore
    @EnvironmentObject var app: AppModel
    @Namespace private var ns

    var body: some View {
        ZStack {
            SkyBackground()

            if store.needsOnboarding {
                OnboardingView()
                    .transition(.focusPull)
            } else {
                HStack(alignment: .top, spacing: 22) {
                    MainPanel(ns: ns)
                    RightColumn()
                        .frame(width: 368)
                }
                .padding(.horizontal, 26)
                .padding(.top, 38)
                .padding(.bottom, 26)
                .transition(.focusPull)
            }

            if let draft = app.composer {
                Rectangle()
                    .fill(.ultraThinMaterial)
                    .opacity(0.55)
                    .background(Color(hex: 0x1B2433).opacity(0.10))
                    .ignoresSafeArea()
                    .onTapGesture { app.closeComposer() }
                    .transition(.opacity)
                    .zIndex(5)

                ComposerCard(initial: draft, ns: ns)
                    .id(draft.ek?.calendarItemIdentifier ?? "new")
                    .zIndex(6)
                    .transition(app.composerOrigin == .button ? .opacity : .focusPull)
            }

            VStack {
                Spacer()
                if let t = app.toast {
                    ToastView(toast: t)
                        .id(t.id)
                        .transition(.asymmetric(insertion: .move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.8)),
                                                removal: .drift(0).combined(with: .scale(scale: 0.9))))
                }
            }
            .padding(.bottom, 30)
            .zIndex(10)
        }
        .frame(minWidth: 1180, minHeight: 760)
        .animation(Haze.spring, value: store.needsOnboarding)
        .onExitCommand { if app.composer != nil { app.closeComposer() } else { app.select(nil) } }
        .task { await DemoDirector.runIfRequested(app: app) }
    }
}

// MARK: - Living sky background (mesh gradient that drifts and follows the time of day)

struct SkyBackground: View {
    @AppStorage("liveSky") private var liveSky = true

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !liveSky)) { ctx in
            let t = ctx.date.timeIntervalSinceReferenceDate
            ZStack {
                MeshGradient(width: 3, height: 3, points: points(t), colors: SkyPalette.colors(for: ctx.date),
                             smoothsColors: true)
                // soft drifting orbs give depth behind the glass
                Circle()
                    .fill(Color.white.opacity(0.35))
                    .frame(width: 520, height: 520)
                    .blur(radius: 120)
                    .offset(x: CGFloat(sin(t * 0.05)) * 260 - 120, y: CGFloat(cos(t * 0.04)) * 140 - 200)
                Circle()
                    .fill(SkyPalette.accent(for: ctx.date).opacity(0.45))
                    .frame(width: 620, height: 620)
                    .blur(radius: 140)
                    .offset(x: CGFloat(cos(t * 0.03)) * 300 + 380, y: CGFloat(sin(t * 0.045)) * 160 + 260)
            }
        }
        .ignoresSafeArea()
    }

    private func points(_ t: Double) -> [SIMD2<Float>] {
        func w(_ a: Double, _ s: Double) -> Float { Float(sin(t * s + a) * 0.09) }
        return [
            [0, 0], [0.5 + w(0, 0.21), 0], [1, 0],
            [0, 0.5 + w(1, 0.17)], [0.5 + w(2, 0.13), 0.5 + w(3, 0.19)], [1, 0.5 + w(4, 0.15)],
            [0, 1], [0.5 + w(5, 0.11), 1], [1, 1],
        ]
    }
}

enum SkyPalette {
    /// HAZE_SKY_HOUR pins the sky to a time of day (handy for screenshots).
    static let pinnedHour = ProcessInfo.processInfo.environment["HAZE_SKY_HOUR"].flatMap(Int.init)
    static func hour(_ date: Date) -> Int { pinnedHour ?? Calendar.current.component(.hour, from: date) }

    static func colors(for date: Date) -> [Color] {
        let h = hour(date)
        let hexes: [UInt32]
        switch h {
        case 5..<11:  // dawn – aqua and apricot
            hexes = [0x9CC8CF, 0xB7D6D8, 0xDCE6E2, 0xC3D9DA, 0xEDE9E1, 0xE9D2C4, 0xDDE3E0, 0xEAD9CF, 0xD8B8A8]
        case 11..<16: // day – the reference teal mist
            hexes = [0x6FA6B2, 0x86B5BE, 0xA6C3C8, 0x9EBFC4, 0xCBD6D5, 0xA39C99, 0xC7CAC6, 0xB9B2AE, 0x8F7975]
        case 16..<20: // golden hour
            hexes = [0x8FB0BD, 0xC7B9B3, 0xE3B79E, 0xB7C3C6, 0xE9D7CA, 0xD9A08A, 0xD7D0CB, 0xD8B4A4, 0xB07F74]
        default:      // night – pale lavender slate, still a light theme
            hexes = [0x8E9BB8, 0xA7AFC6, 0xB9B7CB, 0xAEB6C8, 0xD0D0DC, 0xB3A6B8, 0xC6C8D3, 0xBDB4C2, 0x9C8C9E]
        }
        return hexes.map { Color(hex: $0) }
    }
    static func accent(for date: Date) -> Color {
        switch hour(date) {
        case 5..<11: Color(hex: 0xF3C9B0)
        case 11..<16: Color(hex: 0xC59E94)
        case 16..<20: Color(hex: 0xF0A77F)
        default: Color(hex: 0xB9A7D8)
        }
    }
}

// MARK: - Main glass panel

struct MainPanel: View {
    @EnvironmentObject var app: AppModel
    let ns: Namespace.ID

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Sidebar()
                .padding(.vertical, 16)
                .padding(.leading, 14)
                .padding(.trailing, 6)

            VStack(alignment: .leading, spacing: 0) {
                HeaderView(ns: ns)
                    .padding(.bottom, 14)

                ZStack {
                    switch app.page {
                    case .week: WeekView().transition(.focusPull)
                    case .month: MonthView().transition(.focusPull)
                    case .agenda: AgendaView().transition(.focusPull)
                    case .places: PlacesView().transition(.focusPull)
                    case .settings: SettingsView().transition(.focusPull)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.top, 30)
            .padding(.leading, 34)
            .padding(.trailing, 26)
            .padding(.bottom, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glass(radius: 30, tint: 0.22)
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @EnvironmentObject var app: AppModel
    @EnvironmentObject var store: CalendarStore
    @Namespace private var sel
    @State private var hovered: Page?

    var body: some View {
        VStack(spacing: 14) {
            ForEach(Page.allCases) { p in
                let active = app.page == p
                Button { app.setPage(p) } label: {
                    ZStack {
                        if active {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.5))
                                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.8), lineWidth: 1))
                                .shadow(color: .black.opacity(0.06), radius: 8, y: 4)
                                .matchedGeometryEffect(id: "sel", in: sel)
                        } else if hovered == p {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(Color.white.opacity(0.2))
                                .transition(.opacity)
                        }
                        Image(systemName: p.icon)
                            .font(.system(size: 17, weight: .regular))
                            .foregroundStyle(active ? Haze.ink : Haze.inkSoft.opacity(0.7))
                            .symbolEffect(.bounce.down, value: active)
                            .rotationEffect(.degrees(hovered == p && !active ? -8 : 0))
                    }
                    .frame(width: 58, height: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle(scale: 0.88))
                .help(p.title)
                .onHover { h in withAnimation(Haze.snappy) { hovered = h ? p : (hovered == p ? nil : hovered) } }
            }
            Spacer()
            SyncDot()
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.72), value: app.page)
    }
}

/// A breathing dot that ripples whenever data syncs.
struct SyncDot: View {
    @EnvironmentObject var store: CalendarStore
    @State private var ripple = 0

    var body: some View {
        Button { store.refreshRemote() } label: {
            ZStack {
                Circle().fill(Haze.mint.opacity(0.25)).frame(width: 22, height: 22)
                    .keyframeAnimator(initialValue: 1.0, trigger: ripple) { v, s in v.scaleEffect(s).opacity(2 - s) } keyframes: { _ in
                        LinearKeyframe(1.0, duration: 0.01)
                        SpringKeyframe(1.9, duration: 0.7)
                        LinearKeyframe(1.0, duration: 0.01)
                    }
                Circle().fill(Haze.mint).frame(width: 7, height: 7)
                    .phaseAnimator([1.0, 0.55]) { v, o in v.opacity(o) } animation: { _ in .easeInOut(duration: 1.6) }
            }
            .frame(width: 40, height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Synced \(Fmt.time(store.lastSync)) · click to sync now")
        .onChange(of: store.lastSync) { _, _ in ripple += 1 }
    }
}

// MARK: - Header

struct HeaderView: View {
    @EnvironmentObject var app: AppModel
    let ns: Namespace.ID

    private var title: String {
        switch app.page {
        case .week, .month: Fmt.monthName.string(from: weekAnchor)
        default: app.page.title
        }
    }
    private var weekAnchor: Date {
        // In week view, title the month that owns most of the visible days
        app.page == .week ? weekDays(containing: app.focusDate)[3] : app.focusDate
    }
    private var subtitle: String {
        switch app.page {
        case .week, .month: String(Calendar.current.component(.year, from: weekAnchor))
        case .agenda: "Next 60 days"
        case .places: "Where you’re headed"
        case .settings: "Make it yours"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            YearLabel(text: subtitle)
            HStack(alignment: .center) {
                LetterTitle(text: title)
                Spacer(minLength: 16)
                if app.page == .week || app.page == .month {
                    NavCluster()
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                NewEventButton(ns: ns)
            }
        }
        .animation(Haze.spring, value: app.page)
    }
}

struct YearLabel: View {
    let text: String
    var body: some View {
        Group {
            if let n = Int(text) {
                Text(String(n)).contentTransition(.numericText(value: Double(n)))
            } else {
                Text(text).id(text).transition(.drift(8))
            }
        }
        .font(.display(21, .medium))
        .foregroundStyle(Haze.ink.opacity(0.85))
        .animation(Haze.spring, value: text)
    }
}

/// Month name where each letter falls into place, and waves when you hover it.
struct LetterTitle: View {
    let text: String
    @State private var wave = 0

    var body: some View {
        ZStack(alignment: .leading) {
            HStack(spacing: -1.5) {
                ForEach(Array(text.enumerated()), id: \.offset) { i, ch in
                    Letter(char: ch, index: i, wave: wave)
                }
            }
            .id(text)
            .transition(.asymmetric(insertion: .identity,
                                    removal: .modifier(active: BlurModifier(radius: 10), identity: BlurModifier(radius: 0))
                                        .combined(with: .opacity).combined(with: .offset(y: -24))))
        }
        .frame(height: 96, alignment: .leading)
        .animation(.easeOut(duration: 0.28), value: text)
        .onHover { if $0 { wave += 1 } }
    }

    private struct Letter: View {
        let char: Character
        let index: Int
        let wave: Int
        @State private var shown = false

        var body: some View {
            Text(String(char))
                .font(.display(84, .medium))
                .foregroundStyle(Haze.ink)
                .keyframeAnimator(initialValue: 0.0, trigger: wave) { v, y in v.offset(y: y) } keyframes: { _ in
                    LinearKeyframe(0, duration: 0.01 + Double(index) * 0.045)
                    SpringKeyframe(-12, duration: 0.18, spring: .snappy)
                    SpringKeyframe(0, duration: 0.5, spring: .bouncy)
                }
                .offset(y: shown ? 0 : 46)
                .rotationEffect(.degrees(shown ? 0 : 8), anchor: .bottomLeading)
                .blur(radius: shown ? 0 : 8)
                .opacity(shown ? 1 : 0)
                .onAppear {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.7).delay(Double(index) * 0.035)) { shown = true }
                }
        }
    }
}

struct NavCluster: View {
    @EnvironmentObject var app: AppModel
    @State private var nudge: CGFloat = 0

    var body: some View {
        HStack(spacing: 2) {
            arrow("chevron.left", -1)
            Button { app.goToday() } label: {
                Text("Today").font(.display(13.5, .medium)).foregroundStyle(Haze.ink)
                    .padding(.horizontal, 12).frame(height: 36).contentShape(Rectangle())
            }
            .buttonStyle(PressStyle())
            arrow("chevron.right", 1)
        }
        .padding(.horizontal, 6)
        .background(Capsule().fill(Color.white.opacity(0.35)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.75), lineWidth: 1))
        .padding(.trailing, 12)
    }

    private func arrow(_ name: String, _ dir: Int) -> some View {
        Button { app.shift(dir) } label: {
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Haze.ink.opacity(0.8))
                .frame(width: 32, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(ArrowStyle(dir: CGFloat(dir)))
    }

    /// Arrows dart in their direction when pressed.
    struct ArrowStyle: ButtonStyle {
        let dir: CGFloat
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .offset(x: configuration.isPressed ? dir * 4 : 0)
                .scaleEffect(configuration.isPressed ? 0.85 : 1)
                .animation(.spring(response: 0.22, dampingFraction: 0.5), value: configuration.isPressed)
        }
    }
}

/// White pill whose shape morphs into the event composer.
struct NewEventButton: View {
    @EnvironmentObject var app: AppModel
    let ns: Namespace.ID
    @State private var hover = false

    private var morphing: Bool { app.composer != nil && app.composerOrigin == .button }

    var body: some View {
        ZStack {
            if !morphing {
                Button { app.newEvent() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .semibold))
                            .rotationEffect(.degrees(hover ? 90 : 0))
                        Text("New Event").font(.display(15, .medium))
                    }
                    .foregroundStyle(Haze.ink)
                    .padding(.horizontal, 22)
                    .frame(height: 48)
                    .background {
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(Color.white)
                            .matchedGeometryEffect(id: "composer", in: ns)
                            .shadow(color: .black.opacity(hover ? 0.12 : 0.06), radius: hover ? 16 : 8, y: hover ? 8 : 3)
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(PressStyle())
                .onHover { h in withAnimation(Haze.bouncy) { hover = h } }
                .transition(.opacity)
            } else {
                Color.clear.frame(width: 133, height: 48)
            }
        }
        .help("New event (⌘N)")
    }
}

// MARK: - Toast

struct ToastView: View {
    @EnvironmentObject var app: AppModel
    let toast: Toast
    @State private var progress: CGFloat = 1

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: toast.icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Haze.ink)
                .symbolEffect(.bounce, value: progress < 1)
            Text(toast.text).font(.display(14, .medium)).foregroundStyle(Haze.ink).lineLimit(1)
            if let undo = toast.undo {
                Button {
                    undo()
                    withAnimation(Haze.spring) { app.toast = nil }
                } label: {
                    Text("Undo").font(.display(13.5, .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 6)
                        .background(Capsule().fill(Haze.ink))
                }
                .buttonStyle(PressStyle())
            }
        }
        .padding(.leading, 18).padding(.trailing, toast.undo == nil ? 20 : 8).padding(.vertical, 8)
        .background(alignment: .bottomLeading) {
            GeometryReader { g in
                Capsule().fill(Haze.ink.opacity(0.12)).frame(width: g.size.width * progress, height: 2)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .padding(.horizontal, 18)
            }
        }
        .glass(radius: 24, tint: 0.7, spotlight: false)
        .onAppear { withAnimation(.linear(duration: 5)) { progress = 0 } }
    }
}

// MARK: - Onboarding

struct OnboardingView: View {
    @EnvironmentObject var store: CalendarStore
    @State private var working = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("Welcome to").font(.display(20, .medium)).foregroundStyle(Haze.mute)
            LetterTitle(text: "Haze")
            Text("A calmer calendar that lives on top of Apple Calendar and Reminders — so iCloud, Google and Exchange accounts all sync automatically.")
                .font(.display(17)).foregroundStyle(Haze.inkSoft).fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 10) {
                row("calendar", "Read & edit your events")
                row("checklist", "Show your reminders as a to-do list")
                row("map", "Open locations in Apple Maps or Google Maps")
            }
            .padding(.vertical, 6)

            HStack(spacing: 12) {
                if store.eventsDenied {
                    OutlinePill(title: "Open Privacy Settings", icon: "lock.open", filled: true) {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }
                    OutlinePill(title: "I’ve allowed it", icon: "arrow.clockwise") { store.reloadAll() }
                } else {
                    OutlinePill(title: working ? "Connecting…" : "Connect Calendars", icon: "link", filled: true) {
                        working = true
                        Task { await store.requestAccess(); working = false }
                    }
                }
            }
            if store.eventsDenied {
                Text("Access was turned off. Enable Haze under Privacy & Security › Calendars (and Reminders), then come back.")
                    .font(.display(13)).foregroundStyle(Haze.mute)
            }
        }
        .padding(44)
        .frame(width: 560)
        .glass(radius: 34, tint: 0.45)
    }

    private func row(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 22).foregroundStyle(Haze.ink)
            Text(text).font(.display(15, .medium)).foregroundStyle(Haze.ink.opacity(0.85))
        }
    }
}

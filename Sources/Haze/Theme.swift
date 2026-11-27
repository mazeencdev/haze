import SwiftUI
import AppKit

// MARK: - Palette

enum Haze {
    static let ink      = Color(red: 0.08, green: 0.11, blue: 0.20)   // deep navy, like the reference title
    static let inkSoft  = Color(red: 0.22, green: 0.27, blue: 0.35)
    static let mute     = Color(red: 0.42, green: 0.49, blue: 0.55)
    static let faint    = Color(red: 0.60, green: 0.67, blue: 0.71)
    static let hairline = Color.white.opacity(0.55)
    static let coral    = Color(red: 0.86, green: 0.42, blue: 0.36)
    static let mint     = Color(red: 0.30, green: 0.66, blue: 0.56)

    static let spring      = Animation.spring(response: 0.5, dampingFraction: 0.82)
    static let snappy      = Animation.spring(response: 0.32, dampingFraction: 0.78)
    static let bouncy      = Animation.spring(response: 0.45, dampingFraction: 0.62)
}

// MARK: - Type

extension Font {
    /// Geometric display face (Avenir Next) – closest system match to the reference's Jakarta-style sans.
    static func display(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        let name: String
        switch weight {
        case .bold, .heavy, .black: name = "AvenirNext-Bold"
        case .semibold: name = "AvenirNext-DemiBold"
        case .medium: name = "AvenirNext-Medium"
        case .light, .thin, .ultraLight: name = "AvenirNext-UltraLight"
        default: name = "AvenirNext-Regular"
        }
        return .custom(name, size: size)
    }
}

// MARK: - Frosted glass with a cursor-following specular highlight

struct GlassModifier: ViewModifier {
    var radius: CGFloat = 28
    var tint: Double = 0.30
    var spotlight: Bool = true
    var shadow: Bool = true
    @State private var pointer: CGPoint? = nil

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(.ultraThinMaterial)
                    shape.fill(Color.white.opacity(tint))
                    shape.fill(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.0)],
                                              startPoint: .top, endPoint: .center))
                    if spotlight {
                        GeometryReader { _ in
                            Circle()
                                .fill(RadialGradient(colors: [.white.opacity(0.55), .white.opacity(0)],
                                                     center: .center, startRadius: 0, endRadius: 240))
                                .frame(width: 480, height: 480)
                                .position(pointer ?? CGPoint(x: -400, y: -400))
                                .opacity(pointer == nil ? 0 : 1)
                                .blendMode(.plusLighter)
                        }
                        .clipShape(shape)
                        .allowsHitTesting(false)
                    }
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(colors: [.white.opacity(0.95), .white.opacity(0.25), .white.opacity(0.6)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1)
                    .allowsHitTesting(false)
            }
            .shadow(color: .black.opacity(shadow ? 0.09 : 0), radius: 40, x: 0, y: 24)
            .shadow(color: .black.opacity(shadow ? 0.04 : 0), radius: 6, x: 0, y: 2)
            .onContinuousHover(coordinateSpace: .local) { phase in
                guard spotlight else { return }
                withAnimation(.easeOut(duration: 0.35)) {
                    switch phase {
                    case .active(let p): pointer = p
                    case .ended: pointer = nil
                    }
                }
            }
    }
}

extension View {
    func glass(radius: CGFloat = 28, tint: Double = 0.30, spotlight: Bool = true, shadow: Bool = true) -> some View {
        modifier(GlassModifier(radius: radius, tint: tint, spotlight: spotlight, shadow: shadow))
    }
}

// MARK: - Buttons

/// Squishes on press, lifts on hover.
struct PressStyle: ButtonStyle {
    var scale: CGFloat = 0.93
    func makeBody(configuration: Configuration) -> some View {
        PressBody(configuration: configuration, scale: scale)
    }
    private struct PressBody: View {
        let configuration: Configuration
        let scale: CGFloat
        @State private var hover = false
        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? scale : (hover ? 1.03 : 1))
                .brightness(hover ? 0.02 : 0)
                .animation(Haze.snappy, value: configuration.isPressed)
                .animation(Haze.snappy, value: hover)
                .onHover { hover = $0 }
        }
    }
}

/// Outlined capsule button like "Snooze" / "Mark as Completed" in the reference.
struct OutlinePill: View {
    let title: String
    var icon: String? = nil
    var filled = false
    var tint: Color = Haze.ink
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .semibold)) }
                Text(title).font(.display(13.5, .medium))
            }
            .foregroundStyle(filled ? .white : tint.opacity(0.85))
            .padding(.horizontal, 18).padding(.vertical, 10)
            .background {
                Capsule().fill(filled ? AnyShapeStyle(tint) : AnyShapeStyle(Color.white.opacity(0.18)))
            }
            .overlay { Capsule().strokeBorder(filled ? .clear : Haze.ink.opacity(0.16), lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(PressStyle())
    }
}

// MARK: - Transitions

struct BlurModifier: ViewModifier {
    var radius: CGFloat
    func body(content: Content) -> some View { content.blur(radius: radius) }
}

extension AnyTransition {
    /// A "focus pull": content arrives out of focus and slightly scaled.
    static var focusPull: AnyTransition {
        .modifier(active: BlurModifier(radius: 14), identity: BlurModifier(radius: 0))
            .combined(with: .opacity)
            .combined(with: .scale(scale: 0.97))
    }
    static func drift(_ dx: CGFloat) -> AnyTransition {
        .modifier(active: BlurModifier(radius: 10), identity: BlurModifier(radius: 0))
            .combined(with: .opacity)
            .combined(with: .offset(x: dx))
    }
}

// MARK: - Haptics

enum Haptic {
    static func tick() { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    static func thunk() { NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now) }
}

// MARK: - Color helpers

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

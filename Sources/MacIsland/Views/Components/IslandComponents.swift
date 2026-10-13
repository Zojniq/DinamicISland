import SwiftUI

// MARK: - Shape

/// Notch silhouette: concave "shoulders" at the top that melt into the screen bezel,
/// and convex rounded corners at the bottom. Radii are animatable for smooth morphing.
struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = min(topRadius, rect.width / 4)
        let b = min(bottomRadius, rect.height / 2, rect.width / 4)
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.closeSubpath()
        return p
    }
}

// MARK: - Animations

/// All island motion in one place so the "feel" can be tuned coherently.
enum IslandAnimation {
    /// Shape morph between states. Expanding is bouncier (iOS "pop"), collapsing is
    /// near-critically damped so it settles into the notch without overshooting past it.
    static func morph(to state: IslandState) -> Animation {
        switch state {
        case .expanded: return .spring(response: 0.42, dampingFraction: 0.74, blendDuration: 0)
        case .compact:  return .spring(response: 0.38, dampingFraction: 0.80, blendDuration: 0)
        case .minimal:  return .spring(response: 0.34, dampingFraction: 0.88, blendDuration: 0)
        }
    }

    /// Content appears slightly after the shape starts growing, so it never looks clipped.
    static let contentIn: Animation = .spring(response: 0.36, dampingFraction: 0.86, blendDuration: 0).delay(0.07)
    /// Content leaves quickly, before the shape has shrunk around it.
    static let contentOut: Animation = .easeIn(duration: 0.12)
    /// Swapping one compact live activity for another (timer ⇄ media).
    static let activitySwap: Animation = .spring(response: 0.38, dampingFraction: 0.82, blendDuration: 0)
}

// MARK: - Transitions

/// iOS-style "materialise": blur + fade + slight scale from the notch.
private struct BlurFadeModifier: ViewModifier {
    let isActive: Bool

    func body(content: Content) -> some View {
        content
            .blur(radius: isActive ? 8 : 0)
            .opacity(isActive ? 0 : 1)
            .scaleEffect(isActive ? 0.9 : 1, anchor: .top)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition {
        .modifier(active: BlurFadeModifier(isActive: true), identity: BlurFadeModifier(isActive: false))
    }

    /// Delayed blur-in, quick blur-out.
    static var islandContent: AnyTransition {
        .asymmetric(
            insertion: .blurFade.animation(IslandAnimation.contentIn),
            removal: .blurFade.animation(IslandAnimation.contentOut)
        )
    }
}

// MARK: - Controls

/// Press feedback without hover states (SwiftUI `onHover` is unreliable in a
/// non-key, non-activating panel because its tracking areas require an active app).
struct IslandButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.84 : 1)
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.spring(response: 0.22, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct IslandIconButton: View {
    let systemName: String
    var size: CGFloat = 12
    var frame: CGFloat = 24
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .semibold))
                .frame(width: frame, height: frame)
        }
        .buttonStyle(IslandButtonStyle())
    }
}

// MARK: - Card

extension View {
    /// Subtle glass card used for widgets inside the expanded island.
    func islandCard(cornerRadius: CGFloat = 14) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Progress ring

struct ProgressRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 3

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        // Interpolate across the 1s tick so the ring sweeps continuously.
        .animation(.linear(duration: 1), value: progress)
    }
}

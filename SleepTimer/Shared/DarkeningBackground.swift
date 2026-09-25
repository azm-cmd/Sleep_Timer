import SwiftUI

/// A slow, continuous environmental darkening — never a discrete theme swap.
///
/// `progress` is 0 at the start of a timer (more visible depth in the gradient)
/// and 1 once it has fully elapsed (very dark, still readable). Passing a
/// constant 0 gives the calm "idle" backdrop used on the setup screen.
struct DarkeningBackground: View {
    var progress: Double

    private var clamped: Double { min(1, max(0, progress)) }

    private var topColor: Color {
        Color(hue: 0.62, saturation: 0.55, brightness: lerp(0.34, 0.06, clamped))
    }

    private var bottomColor: Color {
        Color(hue: 0.73, saturation: 0.5, brightness: lerp(0.13, 0.015, clamped))
    }

    private var glowOpacity: Double {
        lerp(0.12, 0.0, clamped)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [topColor, bottomColor], startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [Color.white.opacity(glowOpacity), .clear],
                center: .top,
                startRadius: 0,
                endRadius: 480
            )
        }
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.5), value: clamped)
    }

    private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
        a + (b - a) * t
    }
}

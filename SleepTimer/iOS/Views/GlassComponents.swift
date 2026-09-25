import SwiftUI

/// One of the four 2x2 grid presets on the setup screen.
struct PresetButton: View {
    let minutes: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(minutes)")
                    .font(.system(size: 32, weight: .semibold, design: .rounded))
                Text("min")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 92)
        }
        .buttonStyle(.glass)
        .tint(isSelected ? Color.cyan : nil)
    }
}

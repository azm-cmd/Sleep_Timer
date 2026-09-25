import SwiftUI

struct CustomAddSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int = 10
    let onAdd: (Int) -> Void

    var body: some View {
        VStack(spacing: 22) {
            Capsule()
                .fill(Color.white.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            Text("Add Time")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            Stepper(value: $minutes, in: 1...120) {
                Text("\(minutes) min")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 40)

            Button {
                onAdd(minutes)
                dismiss()
            } label: {
                Text("Add \(minutes) Minutes")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(.cyan)
            .padding(.horizontal, 28)

            Spacer(minLength: 8)
        }
        .presentationBackground(.ultraThinMaterial)
        .preferredColorScheme(.dark)
    }
}

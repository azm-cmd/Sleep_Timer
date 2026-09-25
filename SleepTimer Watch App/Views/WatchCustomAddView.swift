import SwiftUI

struct WatchCustomAddView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Double = 10
    let onAdd: (Int) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text("\(Int(minutes)) min")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
                .foregroundStyle(.white)
                .focusable(true)
                .digitalCrownRotation(
                    $minutes,
                    from: 1,
                    through: 60,
                    by: 1,
                    sensitivity: .medium,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )

            Button {
                onAdd(Int(minutes))
                dismiss()
            } label: {
                Text("Add")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(.cyan)
        }
        .padding()
    }
}

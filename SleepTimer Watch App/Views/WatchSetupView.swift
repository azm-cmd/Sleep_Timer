import SwiftUI

struct WatchSetupView: View {
    @EnvironmentObject private var manager: SleepTimerManager
    @State private var selectedMinutes: Double = 30

    private let presets = [15, 30, 45, 60]
    private let maxMinutes: Double = 180

    var body: some View {
        ZStack {
            DarkeningBackground(progress: 0)

            ScrollView {
                VStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(Color.white.opacity(0.15), lineWidth: 6)
                        Circle()
                            .trim(from: 0, to: CGFloat(min(1, selectedMinutes / maxMinutes)))
                            .stroke(Color.cyan, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.snappy, value: selectedMinutes)

                        VStack(spacing: 0) {
                            Text("\(Int(selectedMinutes))")
                                .font(.system(size: 32, weight: .bold, design: .rounded))
                                .contentTransition(.numericText())
                                .foregroundStyle(.white)
                            Text("minutes")
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.5))
                        }
                    }
                    .frame(width: 104, height: 104)
                    .focusable(true)
                    .digitalCrownRotation(
                        $selectedMinutes,
                        from: 1,
                        through: maxMinutes,
                        by: 1,
                        sensitivity: .medium,
                        isContinuous: false,
                        isHapticFeedbackEnabled: true
                    )
                    .padding(.top, 2)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(presets, id: \.self) { minutes in
                            Button {
                                selectedMinutes = Double(minutes)
                            } label: {
                                Text("\(minutes)m")
                                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                                    .frame(maxWidth: .infinity, minHeight: 30)
                            }
                            .buttonStyle(.glass)
                            .tint(Int(selectedMinutes) == minutes ? Color.cyan : nil)
                        }
                    }

                    Button {
                        manager.start(duration: selectedMinutes * 60)
                    } label: {
                        Text("Start")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.cyan)
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 8)
            }
        }
    }
}

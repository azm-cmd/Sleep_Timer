import SwiftUI

struct SetupView: View {
    @EnvironmentObject private var manager: SleepTimerManager
    @State private var selectedMinutes: Int = 30

    private let presets = [15, 30, 45, 60]

    var body: some View {
        ZStack {
            DarkeningBackground(progress: 0)

            VStack(spacing: 34) {
                Spacer(minLength: 12)

                VStack(spacing: 6) {
                    Text("Sleep Timer")
                        .font(.system(size: 28, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Drift off to sound, wake to silence")
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }

                GlassEffectContainer {
                    LazyVGrid(
                        columns: [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)],
                        spacing: 16
                    ) {
                        ForEach(presets, id: \.self) { minutes in
                            PresetButton(minutes: minutes, isSelected: selectedMinutes == minutes) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                    selectedMinutes = minutes
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 28)

                MinuteDialView(selectedMinutes: $selectedMinutes)
                    .padding(.horizontal, 8)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.5)) {
                        manager.start(duration: TimeInterval(selectedMinutes * 60))
                    }
                } label: {
                    Text("Start")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(.cyan)
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
            }
        }
    }
}

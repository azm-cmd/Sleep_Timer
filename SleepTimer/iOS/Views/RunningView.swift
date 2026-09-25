import SwiftUI

struct RunningView: View {
    @EnvironmentObject private var manager: SleepTimerManager
    @State private var showingCustomAdd = false

    var body: some View {
        ZStack {
            DarkeningBackground(progress: manager.progress)

            VStack(spacing: 44) {
                Spacer()

                VStack(spacing: 10) {
                    Text("FALLING ASLEEP TO")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.4))

                    Text(TimeFormatting.countdown(manager.remaining))
                        .font(.system(size: 84, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: manager.remaining)
                        .minimumScaleFactor(0.5)
                        .lineLimit(1)
                        .padding(.horizontal, 24)
                }

                Spacer()

                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        Button {
                            withAnimation(.snappy) {
                                manager.addTime(5 * 60)
                            }
                        } label: {
                            Label("+5 min", systemImage: "plus")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.glass)

                        Button {
                            showingCustomAdd = true
                        } label: {
                            Label("Custom", systemImage: "ellipsis")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 4)
                        }
                        .buttonStyle(.glass)
                    }

                    Button(role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            manager.cancel()
                        }
                    } label: {
                        Text("Cancel")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                    }
                    .buttonStyle(.glass)
                    .tint(.red)
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
            }
        }
        .sheet(isPresented: $showingCustomAdd) {
            CustomAddSheet { minutes in
                withAnimation(.snappy) {
                    manager.addTime(TimeInterval(minutes * 60))
                }
            }
            .presentationDetents([.height(300)])
        }
    }
}

import SwiftUI

struct WatchRunningView: View {
    @EnvironmentObject private var manager: SleepTimerManager
    @State private var showingCustomAdd = false

    var body: some View {
        ZStack {
            DarkeningBackground(progress: manager.progress)

            VStack(spacing: 12) {
                Text(TimeFormatting.countdown(manager.remaining))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy, value: manager.remaining)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Button {
                        withAnimation(.snappy) {
                            manager.addTime(5 * 60)
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.glass)

                    Button {
                        showingCustomAdd = true
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .buttonStyle(.glass)

                    Button(role: .destructive) {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            manager.cancel()
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.glass)
                    .tint(.red)
                }
            }
            .padding(.horizontal, 8)
        }
        .sheet(isPresented: $showingCustomAdd) {
            WatchCustomAddView { minutes in
                withAnimation(.snappy) {
                    manager.addTime(TimeInterval(minutes * 60))
                }
            }
        }
    }
}

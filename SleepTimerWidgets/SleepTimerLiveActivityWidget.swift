import ActivityKit
import WidgetKit
import SwiftUI

/// The Lock Screen / Dynamic Island presentation for a running sleep timer.
/// Pure display + the three controls (+5 min, +10 min, Cancel) - all state
/// lives in `SleepTimerManager` on the app side; this extension never reads
/// or writes `SleepTimerState` directly, and the countdown itself is
/// rendered by the system from `context.state.startDate...endDate` via
/// `Text(timerInterval:)`, so nothing here needs a per-second refresh.
struct SleepTimerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: SleepTimerActivityAttributes.self) { context in
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color(red: 0.11, green: 0.125, blue: 0.32))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("Sleep Timer")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                    } icon: {
                        Image(systemName: "moon.stars.fill")
                    }
                    .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: context.state.startDate...context.state.endDate, countsDown: true)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.trailing)
                }

                DynamicIslandExpandedRegion(.bottom) {
                    LiveActivityControls()
                }
            } compactLeading: {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text(timerInterval: context.state.startDate...context.state.endDate, countsDown: true)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .frame(width: 44)
            } minimal: {
                Image(systemName: "moon.stars.fill")
                    .foregroundStyle(.white)
            }
            .keylineTint(.indigo)
        }
    }
}

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<SleepTimerActivityAttributes>

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "moon.stars.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white.opacity(0.85))

                VStack(alignment: .leading, spacing: 2) {
                    Text("SLEEP TIMER")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(.white.opacity(0.55))
                    Text(timerInterval: context.state.startDate...context.state.endDate, countsDown: true)
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 0)
            }

            LiveActivityControls()
        }
        .padding(16)
    }
}

/// The +5 min / +10 min / Cancel row, shared by the Lock Screen banner and
/// the Dynamic Island's expanded presentation.
private struct LiveActivityControls: View {
    var body: some View {
        HStack(spacing: 8) {
            Button(intent: AddFiveMinutesLiveActivityIntent()) {
                Text("+5 min")
                    .frame(maxWidth: .infinity)
            }
            Button(intent: AddTenMinutesLiveActivityIntent()) {
                Text("+10 min")
                    .frame(maxWidth: .infinity)
            }
            Button(intent: CancelSleepTimerLiveActivityIntent()) {
                Text("Cancel")
                    .frame(maxWidth: .infinity)
            }
            .tint(.red)
        }
        .font(.system(size: 13, weight: .semibold, design: .rounded))
        .buttonStyle(.bordered)
        .tint(.indigo)
        .foregroundStyle(.white)
    }
}

@main
struct SleepTimerWidgetsBundle: WidgetBundle {
    var body: some Widget {
        SleepTimerLiveActivityWidget()
    }
}

import ActivityKit
import WidgetKit
import SwiftUI

struct LiveActivityProbeWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ProbeActivityAttributes.self) { context in
            VStack(spacing: 8) {
                Text("Live Activity Probe")
                    .font(.headline)
                Text("Tap count: \(context.state.tapCount)")
                    .font(.system(.title2, design: .monospaced))
            }
            .padding()
            .activityBackgroundTint(Color.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    Text("Probe: \(context.state.tapCount)")
                        .font(.system(.body, design: .monospaced))
                }
            } compactLeading: {
                Text("P")
            } compactTrailing: {
                Text("\(context.state.tapCount)")
            } minimal: {
                Text("P")
            }
        }
    }
}

@main
struct LiveActivityProbeWidgetBundle: WidgetBundle {
    var body: some Widget {
        LiveActivityProbeWidget()
    }
}

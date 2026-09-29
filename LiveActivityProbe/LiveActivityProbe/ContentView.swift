import ActivityKit
import SwiftUI

/// The entire point of this app: one button, one Live Activity, nothing
/// else. If this doesn't work when sideloaded, it isn't Sleep Timer's code —
/// it's something about this signing setup / device / Apple ID.
struct ContentView: View {
    @State private var activity: Activity<ProbeActivityAttributes>?
    @State private var statusLines: [String] = ["Nothing tried yet."]
    @State private var tapCount = 0

    var body: some View {
        VStack(spacing: 24) {
            Text("Live Activity Probe")
                .font(.title2.bold())

            Text("areActivitiesEnabled: \(ActivityAuthorizationInfo().areActivitiesEnabled ? "true" : "false")")
                .font(.system(.body, design: .monospaced))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(statusLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.gray.opacity(0.12)))

            Button("Start Test Live Activity") {
                startActivity()
            }
            .buttonStyle(.borderedProminent)

            if activity != nil {
                Button("Bump Value") { bumpActivity() }
                    .buttonStyle(.bordered)

                Button("End Activity", role: .destructive) { endActivity() }
                    .buttonStyle(.bordered)
            }

            Spacer()

            Text("After tapping Start: check the Lock Screen and Dynamic Island (if your device has one). Whatever text appears above is the literal result — not a guess.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func log(_ line: String) {
        statusLines.append(line)
    }

    private func startActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            log("FAILED: areActivitiesEnabled is false. Live Activities are off system-wide or for this app — check Settings.")
            return
        }

        if let existing = Activity<ProbeActivityAttributes>.activities.first {
            activity = existing
            log("Reconnected to an existing activity (id: \(existing.id)).")
            return
        }

        do {
            tapCount = 1
            let content = ActivityContent(state: ProbeActivityAttributes.ContentState(tapCount: tapCount), staleDate: nil)
            let newActivity = try Activity.request(attributes: ProbeActivityAttributes(), content: content)
            activity = newActivity
            log("SUCCESS: Activity.request returned an activity (id: \(newActivity.id)). If nothing shows on the Lock Screen/Dynamic Island despite this, the app-side API call is not the problem.")
        } catch {
            log("FAILED: Activity.request threw: \(String(describing: error))")
        }
    }

    private func bumpActivity() {
        guard let activity else { return }
        tapCount += 1
        let content = ActivityContent(state: ProbeActivityAttributes.ContentState(tapCount: tapCount), staleDate: nil)
        Task {
            await activity.update(content)
            log("Sent update: tapCount = \(tapCount)")
        }
    }

    private func endActivity() {
        guard let activity else { return }
        Task {
            await activity.end(nil, dismissalPolicy: .immediate)
            log("Ended activity.")
            self.activity = nil
        }
    }
}

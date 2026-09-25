import SwiftUI
import UIKit

/// First-launch setup flow explaining automatic media pause, and the same
/// flow re-openable later from SetupView's info button. Shown as a sheet
/// over the existing Setup screen, never replacing it — the main timer UI
/// is untouched by this feature.
///
/// Flow: Welcome → How It Works → Notifications → Set Up → Test → Done.
///
/// The mechanism, in full: with the app open, Sleep Timer pauses media
/// directly when a timer ends. Locked or backgrounded, it can't reach into
/// other apps itself, so it relies on a Personal Automation the person
/// creates once in Shortcuts, triggered by Sleep Timer's own completion
/// notification (a "Notification" automation trigger scoped to this app —
/// see README.md's "Setting up automatic media pause" section). iOS has no
/// API for a third-party app to install that automation on someone's
/// behalf, so "Set Up" walks through creating it by hand; what Sleep Timer
/// *can* do automatically — open Shortcuts, and expose its own pause action
/// as an App Shortcut with zero setup (see SleepTimerAppShortcuts.swift) —
/// it already does.
struct OnboardingView: View {
    var isReplay: Bool = false
    var onFinished: () -> Void

    @State private var step: Step = .welcome

    private enum Step: Int, CaseIterable {
        case welcome, howItWorks, notifications, setUp, test, done
    }

    var body: some View {
        ZStack {
            DarkeningBackground(progress: 0)

            VStack(spacing: 24) {
                HStack {
                    ProgressDots(current: step.rawValue, total: Step.allCases.count)
                    Spacer()
                    if !isReplay {
                        Button("Skip") { onFinished() }
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                }

                Group {
                    switch step {
                    case .welcome:
                        WelcomeStep(onContinue: advance)
                    case .howItWorks:
                        HowItWorksStep(onContinue: advance)
                    case .notifications:
                        NotificationPermissionStep(onContinue: advance)
                    case .setUp:
                        SetUpStep(onContinue: advance)
                    case .test:
                        TestStep(onContinue: advance)
                    case .done:
                        DoneStep(onFinish: onFinished)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(.horizontal, 28)
            .padding(.top, 20)
            .padding(.bottom, 24)
        }
    }

    private func advance() {
        withAnimation(.easeInOut(duration: 0.4)) {
            step = Step(rawValue: step.rawValue + 1) ?? .done
        }
    }
}

private struct ProgressDots: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(Color.white.opacity(index == current ? 0.9 : 0.25))
                    .frame(width: index == current ? 18 : 6, height: 6)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: current)
    }
}

private struct OnboardingPrimaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.glassProminent)
        .tint(.cyan)
    }
}

private struct OnboardingSecondaryButton: View {
    let title: String
    var action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.55))
    }
}

// MARK: - Steps

private struct WelcomeStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 56))
                .foregroundStyle(.white.opacity(0.85))

            VStack(spacing: 10) {
                Text("Welcome to Sleep Timer")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Fall asleep to music, a podcast, or an audiobook — Sleep Timer pauses playback automatically when your timer ends.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Spacer()
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
    }
}

private struct HowItWorksStep: View {
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 10) {
                Text("How Automatic Pause Works")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("There are two situations, handled two different ways.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                InfoRow(icon: "app.badge.fill", text: "App open: Sleep Timer pauses your media itself, the instant the countdown reaches zero.")
                InfoRow(icon: "lock.fill", text: "Phone locked or app backgrounded: Sleep Timer can't reach other apps while suspended. Its notification is what triggers a one-time Shortcuts automation that pauses for you.")
                InfoRow(icon: "checkmark.seal.fill", text: "You'll turn on notifications and set that automation up next — about a minute, once.")
            }

            Spacer()
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
    }
}

private struct InfoRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 22)
            Text(text)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}

private struct NotificationPermissionStep: View {
    let onContinue: () -> Void

    @StateObject private var viewModel = NotificationPermissionViewModel()
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "bell.badge.fill")
                .font(.system(size: 48))
                .foregroundStyle(.cyan)

            VStack(spacing: 10) {
                Text("Allow Notifications")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("Required for background pause: while your phone is locked, Sleep Timer's notification is what wakes the Shortcuts automation that pauses your media.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            statusBadge

            Spacer()

            VStack(spacing: 12) {
                OnboardingPrimaryButton(title: primaryTitle, action: primaryAction)
                if viewModel.status != .authorized {
                    OnboardingSecondaryButton(title: "Continue Without Notifications", action: onContinue)
                }
            }
        }
        .onAppear { viewModel.refreshStatus() }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch viewModel.status {
        case .authorized:
            Label("Notifications Enabled", systemImage: "checkmark.circle.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.green)
        case .denied:
            Label("Notifications Off", systemImage: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.orange)
        case .notDetermined:
            EmptyView()
        }
    }

    private var primaryTitle: String {
        switch viewModel.status {
        case .authorized: return "Continue"
        case .denied: return "Open Settings"
        case .notDetermined: return "Allow Notifications"
        }
    }

    private func primaryAction() {
        switch viewModel.status {
        case .authorized:
            onContinue()
        case .denied:
            if let url = URL(string: UIApplication.openSettingsURLString) {
                openURL(url)
            }
        case .notDetermined:
            viewModel.requestPermission()
        }
    }
}

private struct SetUpStep: View {
    let onContinue: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var didOpenShortcuts = false

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)

            VStack(spacing: 8) {
                Text("Set Up the Automation")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("A one-time Personal Automation — not something you run yourself. iOS doesn't let apps install this for you, so Sleep Timer opens Shortcuts and you finish it, once.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 9) {
                StepRow(number: 1, text: "Tap Automation, then the + button.")
                StepRow(number: 2, text: "Choose \u{201C}Create Personal Automation.\u{201D}")
                StepRow(number: 3, text: "Scroll down and choose \u{201C}Notification.\u{201D}")
                StepRow(number: 4, text: "Set App to \u{201C}Sleep Timer.\u{201D} Leave the other fields blank.")
                StepRow(number: 5, text: "Tap Next, Add Action, search \u{201C}Play/Pause,\u{201D} and set it to Pause on iPhone.")
                StepRow(number: 6, text: "Turn off \u{201C}Ask Before Running.\u{201D} If shown, turn on \u{201C}Allow Running When Locked.\u{201D}")
                StepRow(number: 7, text: "Tap Done.")
            }

            Spacer(minLength: 8)

            OnboardingPrimaryButton(title: didOpenShortcuts ? "Continue" : "Open Shortcuts") {
                if didOpenShortcuts {
                    onContinue()
                } else if let url = URL(string: "shortcuts://") {
                    openURL(url)
                    didOpenShortcuts = true
                }
            }
        }
    }
}

private struct StepRow: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(Color.white.opacity(0.15)))
            Text(text)
                .font(.system(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
        }
    }
}

private struct TestStep: View {
    let onContinue: () -> Void

    @State private var didTest = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            VStack(spacing: 8) {
                Text("Test Setup")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Confirm the automation actually runs before trusting it overnight.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                StepRow(number: 1, text: "Play some music or a podcast.")
                StepRow(number: 2, text: "Start a short Sleep Timer, then lock your phone.")
                StepRow(number: 3, text: "Wait for it to end. Your media should already be paused when you check — no unlocking or opening the app needed.")
            }

            Button {
                MediaController().pauseCurrentMedia()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    didTest = true
                }
            } label: {
                Label(
                    didTest ? "In-App Pause Works" : "Also Test In-App Pause",
                    systemImage: didTest ? "checkmark.circle.fill" : "pause.circle.fill"
                )
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glass)
            .tint(didTest ? .green : nil)
            .foregroundStyle(.white)

            Spacer(minLength: 8)
            OnboardingPrimaryButton(title: "Continue", action: onContinue)
        }
    }
}

private struct DoneStep: View {
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 56))
                .foregroundStyle(.cyan)

            VStack(spacing: 10) {
                Text("You're All Set")
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Sleep Timer will pause your media automatically whenever a timer ends. Reopen this guide anytime from the info button on the main screen.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Spacer()
            OnboardingPrimaryButton(title: "Done", action: onFinish)
        }
    }
}

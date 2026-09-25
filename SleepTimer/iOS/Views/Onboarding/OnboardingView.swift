import SwiftUI

/// First-launch setup flow explaining automatic media pause, and the same
/// flow re-openable later from SetupView's info button. Shown as a sheet
/// over the existing Setup screen, never replacing it — the main timer UI
/// is untouched by this feature.
///
/// Flow: Welcome → How It Works → Set Up → Test → Done. "Set Up" is honest
/// about what iOS actually allows here (see SleepTimerAppShortcuts.swift
/// and README.md): there is no API for a third-party app to install a
/// Shortcuts automation, and no "app sent a notification" trigger exists
/// for Shortcuts to react to in the first place, so the last step is
/// necessarily manual. What Sleep Timer *can* do automatically — make its
/// pause action available in Shortcuts via an App Shortcut, with zero setup
/// — it already has, by the time this view ever appears.
struct OnboardingView: View {
    var isReplay: Bool = false
    var onFinished: () -> Void

    @State private var step: Step = .welcome

    private enum Step: Int, CaseIterable {
        case welcome, howItWorks, setUp, test, done
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
                Text("With the app open, Sleep Timer pauses your media the moment its countdown reaches zero.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 16) {
                InfoRow(icon: "lock.fill", text: "For nights your phone is locked, add a one-time Shortcuts automation.")
                InfoRow(icon: "clock.fill", text: "Pick a trigger like your usual bedtime, and have it run Sleep Timer's built-in \u{201C}Pause Current Media\u{201D} action.")
                InfoRow(icon: "checkmark.seal.fill", text: "It takes about a minute, and you only set it up once.")
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

private struct SetUpStep: View {
    let onContinue: () -> Void

    @Environment(\.openURL) private var openURL
    @State private var didOpenShortcuts = false

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 8)

            VStack(spacing: 8) {
                Text("Set Up in Shortcuts")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("iOS doesn't let apps install automations for you, so this last step is manual. Sleep Timer opens Shortcuts for you — the rest takes about a minute.")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            VStack(alignment: .leading, spacing: 10) {
                StepRow(number: 1, text: "Tap Automation, then the + button.")
                StepRow(number: 2, text: "Choose \u{201C}Create Personal Automation.\u{201D}")
                StepRow(number: 3, text: "Pick a trigger — Time of Day works well for a regular bedtime.")
                StepRow(number: 4, text: "Tap Add Action, search \u{201C}Sleep Timer,\u{201D} and choose \u{201C}Pause Current Media.\u{201D}")
                StepRow(number: 5, text: "Turn off \u{201C}Ask Before Running,\u{201D} then tap Done.")
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
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 10) {
                Text("Test It")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Play some music or a podcast, then tap the button below. It's the exact same pause Sleep Timer triggers automatically.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Button {
                MediaController().pauseCurrentMedia()
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    didTest = true
                }
            } label: {
                Label(
                    didTest ? "Paused" : "Pause Current Media Now",
                    systemImage: didTest ? "checkmark.circle.fill" : "pause.circle.fill"
                )
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }
            .buttonStyle(.glass)
            .tint(didTest ? .green : nil)
            .foregroundStyle(.white)

            Spacer()
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
                Text("Sleep Timer will pause your media automatically whenever a timer ends.")
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Spacer()
            OnboardingPrimaryButton(title: "Done", action: onFinish)
        }
    }
}

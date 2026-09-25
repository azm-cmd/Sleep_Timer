# Sleep Timer

A minimal, Liquid Glass sleep timer for iPhone and Apple Watch. Built for
people falling asleep to music, podcasts, or audiobooks who want a calm,
premium timer with no clutter.

## Requirements

- Xcode 16.2+ on macOS, with the iOS 26 and watchOS 26 SDKs
- iOS 26 / watchOS 26 deployment targets (for the SwiftUI Liquid Glass APIs:
  `.buttonStyle(.glass)`, `.buttonStyle(.glassProminent)`, `GlassEffectContainer`)

Open `SleepTimer.xcodeproj`, select the **SleepTimer** scheme to build/run the
iPhone app or the **SleepTimer Watch App** scheme for the Watch app. Both
schemes are checked in (`xcshareddata/xcschemes`), so they're available
immediately after cloning — no need to let Xcode auto-generate them first.
The **SleepTimer** scheme also runs the `SleepTimerTests` unit tests.

## Architecture

```
SleepTimer/
  Shared/                     platform-agnostic timer core (Foundation only)
    SleepTimerState.swift     absolute start/end date + derived remaining/progress
    SleepTimerManager.swift   @MainActor ObservableObject: start/add/cancel, persistence, 1s ticker
    TimeFormatting.swift      countdown string formatting
    DarkeningBackground.swift shared "sleepy" gradient background, driven by progress
  iOS/
    SleepTimerApp.swift, ContentView.swift
    Views/                    SetupView, MinuteDialView, RunningView, CustomAddSheet, GlassComponents
    Assets.xcassets
SleepTimer Watch App/
  SleepTimerWatchApp.swift, WatchContentView.swift
  Views/                      WatchSetupView, WatchRunningView, WatchCustomAddView
  Assets.xcassets
SleepTimerTests/
  SleepTimerManagerTests.swift
```

`Shared/` files are compiled into *both* app targets directly (not a separate
framework/package) — the simplest structure for two small app targets that
need to share pure logic.

### Timer correctness across backgrounding

`SleepTimerManager` never counts down an integer. `start(duration:)` and
`addTime(_:)` only ever write an absolute `endDate` into `SleepTimerState`,
which is immediately persisted to `UserDefaults` as JSON. Every view reads
`manager.remaining` / `manager.progress`, both computed as `endDate - now`
on every 1-second tick. On relaunch, `refreshFromPersistence()` re-derives
remaining time from that same absolute end date — so a stale in-memory value
is never trusted. This is exercised directly in
`SleepTimerManagerTests.testStateSurvivesReconstructionFromPersistence`,
which starts a timer, throws away the manager, constructs a brand new one
against the same `UserDefaults`, and asserts the remaining time is still
correct.

A local notification is scheduled for the timer's end date (via
`UNUserNotificationCenter`) so something alerts the person even if the app
is fully suspended when the timer finishes; it's cancelled on `cancel()` and
rescheduled on `addTime(_:)`.

iPhone and Watch each run this exact same manager independently against
their own local `UserDefaults` — per the brief, connectivity between the two
devices is explicitly *not* a dependency for the timer to work. Live
handoff/sync between a paired iPhone and Watch is a natural next step but is
intentionally out of scope for this pass.

### The minute dial (iPhone)

`MinuteDialView` is a from-scratch ruler control: a horizontal `ScrollView`
with `.scrollTargetBehavior(.viewAligned)` snapping to one-minute ticks,
centered via half-width leading/trailing padding. The large numeral is kept
out of the view hierarchy until `.onScrollPhaseChange` reports a real
user-driven phase (`.interacting`/`.decelerating`, as opposed to the
`.animating` phase produced by a programmatic scroll), at which point it
animates in from below with `.move(edge: .bottom).combined(with: .opacity)`.
Tapping a preset moves the ruler to match (so it stays visually in sync)
without revealing the numeral, since that wasn't direct interaction with the
dial.

### Darkening background

`DarkeningBackground(progress:)` interpolates gradient hue/brightness and a
top glow's opacity continuously from `progress` (0…1), animated with
`.easeInOut(duration: 1.5)` on every progress change — a slow, continuous
drift rather than a discrete theme swap. The setup screen uses a constant
`progress: 0`; the running screens drive it from `manager.progress`.

## What's implemented

- Presets (15/30/45/60), exact-minute dial, Start — iPhone
- Presets, Digital Crown minute selection, Start — Watch
- Running countdown, +5 min, custom add (sheet/crown), Cancel — both platforms
- Continuous background darkening tied to timer progress — both platforms
- Absolute-end-date timer math; state persists across background/lock/relaunch
- Unit tests for start/add/cancel/persistence/expiry
- Local notification on timer completion

## What's intentionally not implemented yet

- **Media playback pause** — explicitly deferred per the brief; will need
  `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` (or a Shortcuts-based
  approach) layered on top of `SleepTimerManager.complete()`.
- **Live iPhone↔Watch sync via WatchConnectivity** — each device is fully
  functional standalone today; wiring `WCSession` to mirror
  `SleepTimerManager.state` between devices is the natural next step.
- App icon artwork — the asset catalogs have empty `AppIcon` placeholders.

## Known limitation of this change

This was implemented in a Linux container with no Xcode or Swift toolchain
available, so **the project could not actually be compiled, run, or tested
here** — `xcodebuild` and `swift` are simply not present on this machine.
The `project.pbxproj` was generated programmatically and then opened,
structurally validated, and used to generate the two schemes above with the
[`xcodeproj`](https://github.com/CocoaPods/Xcodeproj) Ruby gem (the same
library CocoaPods/fastlane use to manipulate real Xcode projects), which
confirmed every target's source/resource file references resolve to real
files on disk and the Watch app is correctly embedded in the iPhone app.
That verifies the project's structure, not that the Swift code compiles.

**Before relying on this, please open it in Xcode on a Mac, build both
targets, and run the test target** — that is the one step that could not be
completed here. If anything doesn't compile, the most likely spots are
newer Liquid Glass API names (`.buttonStyle(.glass)`, `.glassProminent`,
`GlassEffectContainer`) or the watchOS `digitalCrownRotation` overload,
since those depend on the exact iOS/watchOS 26 SDK you have installed.

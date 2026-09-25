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

## Signing

All three targets use automatic signing (`CODE_SIGN_STYLE = Automatic`,
`ProvisioningStyle = Automatic`) with no `DEVELOPMENT_TEAM` baked in — that's
intentionally left for you to set per-machine. On first open, select each
target in **Signing & Capabilities** and choose your team; Xcode will
provision both the iPhone and Watch app automatically for a device build
(the bundle IDs — `com.azm.SleepTimer` and `com.azm.SleepTimer.watchkitapp` —
are placeholders, so if they collide with an existing App ID in your account,
change them there, in both targets, keeping the `.watchkitapp` suffix
relationship). No entitlements are required for anything currently
implemented (timer state uses local `UserDefaults`, completion alerts use
local — not remote/push — notifications).

## Architecture

```
SleepTimer/
  Shared/                     platform-agnostic timer core (Foundation only)
    SleepTimerState.swift     absolute start/end date + derived remaining/progress
    SleepTimerManager.swift   @MainActor ObservableObject: start/add/cancel, persistence, 1s ticker
    TimeFormatting.swift      countdown string formatting
    DarkeningBackground.swift shared "sleepy" gradient background, driven by progress
    MediaController.swift     MediaPausing abstraction; pauses system media via AVAudioSession
  iOS/
    SleepTimerApp.swift, ContentView.swift
    Views/                    SetupView, MinuteDialView, RunningView, FinishedView, CustomAddSheet, GlassComponents
    Assets.xcassets
SleepTimer Watch App/
  SleepTimerWatchApp.swift, WatchContentView.swift
  Views/                      WatchSetupView, WatchRunningView, WatchFinishedView, WatchCustomAddView
  Assets.xcassets
SleepTimerTests/
  SleepTimerManagerTests.swift
  MinuteDialMathTests.swift
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

`MinuteDialView` is a from-scratch ruler control driven by a plain
`DragGesture`, not `ScrollView`/`.scrollPosition(id:)` (an earlier version
used that API; it resolves position via a "nearest id to the anchor"
heuristic meant for snapping between a handful of large paged cards, which
misbehaved against ~176 closely-spaced tick views under real touch). The
selected minute is `committedMinutes - translation / stepWidth`, clamped to
the range — the same formula drives both the rendered tick position and the
selected value, so they can't disagree, and it's a deterministic, monotonic
function of finger displacement with no heuristic resolution step to
misfire. The core arithmetic lives in the pure, unit-tested `MinuteDialMath`
enum. The large numeral is kept out of the view hierarchy until a real drag
begins (`hasInteracted`), at which point it animates in from below with
`.move(edge: .bottom).combined(with: .opacity)`. Tapping a preset moves the
ruler to match (so it stays visually in sync) without revealing the
numeral, since that wasn't direct interaction with the dial — enforced by a
`@GestureState isDragging` guard so a preset's external write can't land
mid-gesture and corrupt that gesture's base value.

### Media pause on completion

`MediaController` (`MediaPausing` protocol + `MediaController`
implementation) is the only thing `SleepTimerManager.complete()` calls out
to, and the manager depends on the protocol, not the concrete type, so tests
inject a spy instead of touching real audio hardware.

`MPRemoteCommandCenter` — the API most associated with "media remote
control" — turns out not to be sufficient by itself: it only lets an app
*receive* remote-control events already routed to whichever app owns "Now
Playing" status; there's no public API for one app to *send* a pause
command into a different app's session, and Sleep Timer isn't a media
player with a Now Playing session of its own. The mechanism that actually
works generically, without targeting or knowing about any specific app, is
`AVAudioSession` interruption: briefly activating our own session with the
`.playback` category asks iOS to interrupt whatever else is currently
playing — the same system-level contract that silences background music for
a phone call or a Siri request, and every App Store-compliant playback app
must honor it. Deactivating again *without* `.notifyOthersOnDeactivation`
keeps the interrupted app paused rather than inviting it to resume
immediately.

**Honest limitation:** there is no Apple-supported way for a normal app
(no special entitlement, no continuous background audio session) to
guarantee this runs at the *exact* moment the timer hits zero while the
phone is locked and the app is fully suspended — `BGTaskScheduler` is
opportunistic and not time-precise, and a local notification firing in the
background does not hand the app execution time to act on it. In practice
the pause fires: immediately, if the app is in the foreground when the
timer reaches zero (the common case — falling asleep with the app open);
and as soon as the app is reopened or reactivated afterward, if the timer
expired while backgrounded or the process was killed entirely — every
expiry path (live tick, foreground reactivation, and cold relaunch) now
funnels through the same `complete()`, so the pause is always attempted
exactly once per completed timer, just not necessarily at the literal
instant of expiry if nobody touched the phone before then. The already-
existing local notification still fires at the correct time regardless, so
the person is alerted even before that catch-up happens.

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
- Unit tests for start/add/cancel/persistence/expiry, and for the dial's
  drag-to-minute arithmetic
- Local notification on timer completion
- System media pause on completion (see "Media pause on completion" above),
  and a calm "Good Night" finished state instead of a stuck 00:00

## What's intentionally not implemented yet

- **Live iPhone↔Watch sync via WatchConnectivity** — each device is fully
  functional standalone today; wiring `WCSession` to mirror
  `SleepTimerManager.state` between devices is the natural next step.
- **Per-app / streaming-service-specific media integration** — deliberately
  out of scope; the pause mechanism is generic and app-agnostic by design
  (see above), not a Spotify/Apple Music/Podcasts-specific integration.

## App icons

The current icon is the supplied hourglass/moon artwork (a single 840×840
source with a transparent background, hard rounded corners and a soft glow
already baked in by its own design). Apple's App Icon slots reject any
alpha channel, and pasting it as-is onto a plain white or black square would
have looked visibly "tacked on" against the artwork's own glow — so instead
the source is alpha-composited onto a solid deep-indigo background
(`#1C2052`, sampled from the artwork's own edge tones so the fill reads as
part of the design, not a patch) before being resized. That composite is
done once at 1024×1024 (upscaled from the 840px source with Lanczos
resampling, since 1024 is required for the App Store marketing icon and no
larger source was provided), and every smaller slot is downscaled from that
same 1024 master rather than re-derived from progressively smaller copies.

`SleepTimer/iOS/Assets.xcassets/AppIcon.appiconset` keeps the full 21-slot
legacy icon set (iPhone, iPad, CarPlay, and the 1024×1024 marketing icon),
each slot filled with the correctly-sized render rather than one image
stretched to fit. `SleepTimer Watch App`'s single-size `AppIcon.appiconset`
(watchOS 9+ apps only need one 1024×1024 "universal" source) uses the same
1024 master. Legibility at the smallest real sizes (20×20, 29×29) was
checked directly — the hourglass-and-moon silhouette still reads clearly.

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

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

#### Background execution: what's actually possible (investigated, not assumed)

Confirmed by hands-on testing (foreground: pauses correctly; locked/
backgrounded: notification arrives on time, pause doesn't happen until the
app is reopened) and then researched properly rather than patched around.
Every mechanism iOS actually offers for "run my code later, in the
background":

- **App lifecycle: locking the screen *is* backgrounding, for this app.**
  Apple's documented app lifecycle treats the Sleep/Wake button and Home
  button the same way: both move the app from foreground to background.
  There's no special case for "still frontmost but the screen is off" — a
  plain app with no active background mode gets backgrounded the moment the
  screen locks, then **suspended** shortly after (frozen: zero CPU time,
  nothing we schedule can run, full stop, until the app is foregrounded or
  killed). The only genuinely different state is the brief "background" one
  the app passes through *between* those two - the OS grants a short,
  undocumented-exact-length grace period to finish up (historically on the
  order of seconds to ~30s for apps that explicitly ask for it via
  `beginBackgroundTask`, which this app doesn't). Our 1-second Combine
  ticker could incidentally still fire during that narrow transient window,
  but that's a side effect, not something requested or reliable, and it
  cannot explain or fix a 30-minute-later completion. **Force-quitting the
  app is a different event again** (process terminated, not just frozen),
  but is handled the same way as any other cold start: `init()` already
  calls `restoreState()` then `checkForExpiry()`, so relaunching after the
  timer elapsed - locked, backgrounded, or force-quit, doesn't matter which
  - correctly detects the expiry and completes exactly once
  (`testColdRelaunchAfterExpiryCompletesAndPausesExactlyOnce`).

- **`BGTaskScheduler` (`BGAppRefreshTask` / `BGProcessingTask`) — not
  time-precise, not guaranteed to run at all.** Apple's own API contract
  for `BGTaskScheduler.submit(_:)` is explicit that `earliestBeginDate` is
  a floor, not a schedule: the system decides the actual run time (if any)
  using a budget it builds from the person's own usage pattern, battery
  level, and Low Power Mode - and it additionally requires **Background App
  Refresh** to be turned on for the app in Settings, which plenty of people
  disable. A once-a-night utility like this is close to the worst case for
  that budget (it heavily favors apps opened many times a day), so even a
  best-effort submission would be as likely to fire hours late, or not that
  night at all, as it would be to help. It cannot deliver "pauses at
  minute 30."

- **Local notifications — deliver on time, but don't hand the app any
  execution time.** Already implemented and confirmed working exactly as
  documented: `UNTimeIntervalNotificationTrigger` fires at the correct
  wall-clock time regardless of app state, because delivery is handled by
  the OS notification daemon, not the app process. But a notification
  simply *appearing* - whether the person looks at it or not - never runs
  app code. (A tap on a custom notification *action* button does briefly
  launch the app in the background to handle it - a real, Apple-documented
  mechanism - but that's a deliberate action the person has to take, not
  something that happens on its own, and it's a UI change this task
  explicitly doesn't make. Worth considering separately.)

- **`AVAudioSession` background audio mode — a real mechanism this app
  does not qualify to use.** Declaring `UIBackgroundModes: audio` and
  keeping an `AVAudioSession` active *is* how "keep running all night"
  apps do it (white-noise/rain-sound apps, meditation timers) - as long as
  they are actually delivering continuous audio the person asked for.
  Sleep Timer isn't a media player and has no audio content of its own to
  play; the only way to adopt this mode would be to play something -
  including silence - purely to keep the process alive, which
  [App Review Guideline 2.5.4](https://developer.apple.com/app-store/review/guidelines/)
  states directly: *"Multitasking apps may only use background services
  for their intended purposes."* That's not a gray area for an app whose
  entire feature is pausing *other* apps' audio, so this wasn't
  implemented, per the explicit constraint on this task.

- **`MPRemoteCommandCenter` — unrelated to this problem.** As established
  when the pause itself was implemented, it only lets an app *receive*
  commands already routed to it; it has no bearing on background execution
  timing either way.

- **Other mechanisms considered and ruled out for this app, for now:**
  silent/background remote push (`content-available`) *can* wake an app
  briefly, but needs a server we don't have, and delivery is explicitly
  best-effort, not guaranteed prompt, on Apple's side too - so it would add
  real infrastructure and a privacy question (sending timer state off-
  device) for a timing guarantee it still couldn't make. ActivityKit /
  Live Activities can show a live Lock Screen countdown but is a display
  mechanism, not a code-execution trigger - it wouldn't run the pause
  either. A Shortcuts personal automation (time-of-day trigger calling an
  App Intent) is genuinely more reliable for *fixed* recurring times, since
  it rides on the Shortcuts app's own scheduling rather than
  `BGTaskScheduler`'s budget - but it requires the person to manually set
  it up outside the app for each schedule, doesn't fit an ad-hoc "N minutes
  from now" timer well, and is a new feature surface, not a fix to this one.

**Conclusion: no.** There is no Apple-supported, App Store-legitimate
mechanism available to this app that makes "timer ends while locked →
media pauses automatically, with no need to reopen the app" reliably true.
That's a real platform restriction, not a gap in this implementation -
confirmed against Apple's own documented API contracts and App Review
guidelines, not assumed. Nothing was added to fake it, and the working
foreground behavior is untouched.

**What already happens, and why it's the correct behavior given the above:**
every expiry path - the live per-second tick, the app reactivating in the
foreground, and a cold relaunch after being force-quit - funnels through
the same `complete()`, so the pause is attempted exactly once per completed
timer: immediately if the app is in the foreground when the timer reaches
zero (the common case - falling asleep with the app open), and as soon as
the app is next opened or reactivated otherwise. The local notification
still lands at the exact right time regardless, so the person is alerted
even before that catch-up happens. This is already the best legitimate
combination of the mechanisms above, not a placeholder for something
better.

**Recommended next step, if this gap is worth closing further:** add a
custom action button (e.g. "Pause Now") to the completion notification via
`UNNotificationAction`/`UNNotificationCategory`. It's the one option above
that's fully legitimate, needs no new background mode or server, and turns
"unlock, open the app, wait for it to catch up" into "tap one button on the
lock screen without fully unlocking." It does not reach true zero-touch -
Apple gives no mechanism that does, for an app like this - so it wouldn't
fully satisfy "no need to reopen the app," only shorten and simplify what
reopening it requires. It's a UI change, so it's intentionally not part of
this investigation task.

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

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
The **SleepTimer** scheme also runs the `SleepTimerTests` unit tests. There's
a fourth target, **SleepTimerWidgets** (the Live Activity's widget
extension), but it has no scheme of its own — it builds and embeds
automatically as a dependency whenever you build/run **SleepTimer**, the
same way **SleepTimer Watch App** already does.

The deployment target (iOS 26 / watchOS 26) was already far above what any
of this pass's new APIs require, so it wasn't raised: `ActivityKit` needs
iOS 16.1+, interactive Live Activity buttons (`LiveActivityIntent`) need
iOS 17+, and `AppIntents`/`AppShortcutsProvider` need iOS 16+.

## Signing

All four targets use automatic signing (`CODE_SIGN_STYLE = Automatic`,
`ProvisioningStyle = Automatic`) with no `DEVELOPMENT_TEAM` baked in — that's
intentionally left for you to set per-machine. On first open, select each
target in **Signing & Capabilities** and choose your team; Xcode will
provision the iPhone app, Watch app, and widget extension automatically for
a device build (the bundle IDs — `com.azm.SleepTimer`,
`com.azm.SleepTimer.watchkitapp`, and `com.azm.SleepTimer.SleepTimerWidgets`
— are placeholders, so if they collide with an existing App ID in your
account, change them, keeping the child-of-`com.azm.SleepTimer` relationship
for the Watch app and widget extension). No entitlements are required for
anything implemented so far — timer state uses local `UserDefaults`,
completion alerts use local (not remote/push) notifications, and Live
Activities only need the `NSSupportsLiveActivities` Info.plist key (already
set on the SleepTimer target's build settings), not a capability toggle.

## Architecture

```
SleepTimer/
  Shared/                     platform-agnostic timer core (Foundation only)
    SleepTimerState.swift     absolute start/end date + derived remaining/progress
    SleepTimerManager.swift   @MainActor ObservableObject: start/add/cancel, persistence, 1s ticker
    TimeFormatting.swift      countdown string formatting
    DarkeningBackground.swift shared "sleepy" gradient background, driven by progress
    MediaController.swift     MediaPausing abstraction; pauses system media via AVAudioSession
    SleepTimerActivityAttributes.swift   ActivityKit ContentState (startDate/endDate) — iOS + widget ext. only
    SleepTimerActivityController.swift   ActivityControlling abstraction; #if canImport(ActivityKit)-guarded
    SleepTimerLiveActivityIntents.swift  +5/+10/Cancel LiveActivityIntents — iOS + widget ext. only
  iOS/
    SleepTimerApp.swift, ContentView.swift
    Views/                    SetupView, MinuteDialView, RunningView, FinishedView, CustomAddSheet, GlassComponents
    Views/Onboarding/         OnboardingView (Welcome → How It Works → Set Up → Test → Done)
    Intents/                  PauseCurrentMediaIntent, SleepTimerAppShortcuts (App Shortcuts registration)
    Assets.xcassets
SleepTimerWidgets/             widget extension target (Live Activity UI only, no app logic of its own)
  SleepTimerLiveActivityWidget.swift
  Info.plist
SleepTimer Watch App/
  SleepTimerWatchApp.swift, WatchContentView.swift
  Views/                      WatchSetupView, WatchRunningView, WatchFinishedView, WatchCustomAddView
  Assets.xcassets
SleepTimerTests/
  SleepTimerManagerTests.swift  (includes SpyMediaController, SpyActivityController)
  MinuteDialMathTests.swift
```

`Shared/` files are compiled into whichever targets need them, directly (not
a separate framework/package) — the simplest structure for a handful of
small targets sharing pure logic. Membership varies by file: everything
needed to compile `SleepTimerManager.swift` goes wherever *it* goes (iOS,
Watch, and now the widget extension, since its `LiveActivityIntent`s call
`SleepTimerManager.shared` directly); the two ActivityKit-specific files
(`SleepTimerActivityAttributes.swift`, `SleepTimerLiveActivityIntents.swift`)
only go where ActivityKit exists at all — iOS and the widget extension, not
Watch.

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
reopening it requires.

**Update:** that recommendation is now implemented, in a stronger form.
Rather than a single notification action, a running timer now shows a full
Live Activity with +5 min / +10 min / Cancel buttons directly on the Lock
Screen and in the Dynamic Island (see "Live Activity" below) — no
notification tap required first, and it works for extending the timer too,
not just cancelling. The underlying limitation from this section is
unchanged: tapping one of those buttons is still a deliberate action the
person takes, not something that happens with zero touch while asleep, and
the *automatic* pause at expiry still only fires when the app is next
foreground - this only makes the "something went wrong, let me fix it
without fully unlocking" path faster.

### Live Activity

A running timer shows a Live Activity on the Lock Screen and in the Dynamic
Island, with the countdown and +5 min / +10 min / Cancel controls. It's
implemented as its own small app-extension target, **SleepTimerWidgets**,
because that's the only way ActivityKit's Lock Screen/Dynamic Island UI can
be presented — WidgetKit extensions are how iOS renders that surface for
every app, not something drawn by the main app's own view hierarchy.

**No second timer.** The extension holds no timer state and runs no clock
of its own. `SleepTimerActivityAttributes.ContentState` carries only the
timer's existing `startDate`/`endDate`; the countdown is rendered by
`Text(timerInterval:countsDown:)`, a system view that live-updates itself
from those two dates, so nothing has to push per-second updates. The three
buttons are `LiveActivityIntent`s (`AddFiveMinutesLiveActivityIntent`,
`AddTenMinutesLiveActivityIntent`, `CancelSleepTimerLiveActivityIntent`) —
conforming to `LiveActivityIntent` rather than plain `AppIntent` is what
makes the system run their `perform()` in *the app's own process* rather
than the widget extension's (confirmed against Apple's own documentation:
*"When a person interacts with a button or toggle in your widget, the
system runs the `perform()` function in your app's process"*), so they call
straight into `SleepTimerManager.shared.addTime(_:)` / `.cancel()` — the
exact same methods RunningView's own +5 min/Custom/Cancel buttons call. The
intent *type* has to be compiled into the widget extension target too (so
its UI code can reference it to build the button), which is why
`SleepTimerManager.swift` and its own dependencies are shared into
`SleepTimerWidgets` as well — but there's exactly one implementation of
`addTime`/`cancel`/the absolute-`endDate` state, called from three places
(RunningView, the Live Activity, and — for `PauseCurrentMediaIntent`,
`MediaController` directly) rather than duplicated anywhere.

**Lifecycle**, via a new `ActivityControlling` abstraction (`SleepTimerManager`
depends on the protocol, `SleepTimerActivityController` is the ActivityKit
implementation, tests use a spy — same pattern as `MediaPausing`):
`start(duration:)` starts it, `addTime(_:)` updates its end date,
`cancel()` and natural completion (`complete()`) both end it. Relaunching
while a timer is still running (app force-quit, then reopened) re-syncs it:
`SleepTimerManager` checks `Activity<Attributes>.activities` for one left
over from the previous process and adopts it rather than creating a
duplicate, or starts a fresh one if none exists (e.g. Live Activities were
off when the timer began). Every call is best-effort and swallows its own
errors — Live Activities can be disabled system-wide or per-app in
Settings, and none of that may ever prevent the timer itself from starting,
extending, or completing, the same principle `MediaController` already
follows.

### Setting up automatic media pause (onboarding)

A first-launch flow (`OnboardingView`, also reachable later from the info
button on the setup screen) walks through Welcome → How It Works → Set Up →
Test → Done. Before building the "Set Up" step, two things were verified
against Apple's own documentation rather than assumed:

- **A third-party app cannot install a Shortcuts automation for someone.**
  There is no public API or URL scheme for it. `shortcuts://create-shortcut`
  opens the shortcut *editor* for a plain shortcut, requiring the person to
  review and save it themselves; there is nothing equivalent for
  *automations* (the trigger+action pairing under the Automation tab) at
  all — those can only be built by hand, in the Shortcuts app.
- **There is no "app sent a notification" automation trigger, at all,
  for anyone to use — with or without our involvement.** This is more
  fundamental than an installation restriction: even if a person builds a
  personal automation by hand, Shortcuts has no trigger type for "a
  specific app's notification arrived." (Checked against Apple's current
  Shortcuts trigger list; the closest built-in trigger is a *Message*
  received from a chosen sender matching text, which is a different
  feature entirely.) So the flow this feature was originally framed around
  — "timer ends → Sleep Timer notification → automation reacts to it" —
  isn't buildable in Shortcuts by anyone, not just by an app trying to set
  it up automatically.

What *is* fully automatic, and already true by the time onboarding ever
runs: `PauseCurrentMediaIntent` (wrapping the exact same
`MediaController.pauseCurrentMedia()` the timer uses) is registered via
`SleepTimerAppShortcuts: AppShortcutsProvider`, which means it appears in
Siri, Spotlight, and the Shortcuts app's per-app action list the moment the
app is installed — no button to tap, no setup screen, no permission prompt.
That's the one piece of "add Sleep Timer to Shortcuts" iOS lets an app do
for someone.

Given that, "Set Up" implements the closest legitimate flow rather than
inventing one: its primary button opens the Shortcuts app
(`shortcuts://`), and concise numbered steps cover the part that has to
stay manual — creating a personal automation (a **Time of Day** trigger is
the closest fit for "run this around my usual bedtime," since no better
trigger exists) that runs the now-discoverable "Pause Current Media"
action. "Test It" calls `MediaController().pauseCurrentMedia()` directly,
so the one genuinely uncertain part — whether the pause mechanism itself
works on your setup — can be checked immediately, independent of whether
Shortcuts automation is ever configured.

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
- Live Activity (Lock Screen + Dynamic Island) for a running timer, with
  working +5 min / +10 min / Cancel controls — iPhone only, per this pass
- "Pause Current Media" App Intent, discoverable via Siri/Spotlight/Shortcuts
  with zero setup (`SleepTimerAppShortcuts`)
- First-launch onboarding explaining automatic media pause, with an honest
  "Set Up in Shortcuts" flow and a "Test It" step, re-openable from an info
  button on the setup screen
- Unit tests for the Live Activity lifecycle (start/update/end sequencing)
  via a spy `ActivityControlling`, alongside the existing timer/media tests

## What's intentionally not implemented yet

- **Live iPhone↔Watch sync via WatchConnectivity** — each device is fully
  functional standalone today; wiring `WCSession` to mirror
  `SleepTimerManager.state` between devices is the natural next step.
- **Per-app / streaming-service-specific media integration** — deliberately
  out of scope; the pause mechanism is generic and app-agnostic by design
  (see above), not a Spotify/Apple Music/Podcasts-specific integration.
- **Watch app functionality for this pass's two features** — explicitly out
  of scope per the brief. The Live Activity specifically isn't a "not yet"
  either: ActivityKit's Lock Screen/Dynamic Island surface is an iPhone/
  iPad concept with no watchOS equivalent, so there's nothing to add there.
  `SleepTimerAppShortcuts`/`PauseCurrentMediaIntent` could be made available
  on watchOS too (App Intents is cross-platform) if that's ever wanted.

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

This project has been developed in a Linux container with no Xcode or Swift
toolchain available at any point, so **none of it has actually been
compiled, run, or tested on-device** — `xcodebuild` and `swift` are simply
not present on this machine. `project.pbxproj` is generated/edited
programmatically and then structurally validated with the
[`xcodeproj`](https://github.com/CocoaPods/Xcodeproj) Ruby gem (the same
library CocoaPods/fastlane use), which confirms every target's source/
resource references resolve to real files on disk and that targets embed
and depend on each other correctly. That verifies the project's structure,
not that the Swift code compiles or that any of it behaves correctly at
runtime — that has been true of every change in this repository's history,
not just this one.

This particular pass carries more of that risk than most before it: it adds
a **fourth Xcode target from scratch** (`SleepTimerWidgets`, an app
extension — assembled by hand with the `xcodeproj` gem's `new_target`
helper plus manually-configured build settings, embedding, and a physical
`Info.plist`, since there's no Xcode wizard available here to do it) and
uses three frameworks with no prior code in this repository to check
assumptions against: `ActivityKit`, `WidgetKit`, and `AppIntents`. The
`LiveActivityIntent`-runs-in-the-app's-process behavior this relies on was
verified against a direct quote from Apple's own documentation (see "Live
Activity" above) rather than assumed, and the Shortcuts capabilities
(and lack thereof) behind the onboarding flow were verified against
Apple's current documentation and Review Guidelines rather than assumed —
but "verified against docs" is not the same thing as "compiled and run,"
and for a target/extension relationship this is the one part of this
project that could not be cross-checked by opening a similar Xcode-
generated project for comparison the way the Watch target's embedding
could be earlier on.

**Before relying on this, please open it in Xcode on a Mac and build all
four targets, run the test target, and check Signing & Capabilities for
each target** (the widget extension is new and needs your team selected
too) — that is the one step that could never be completed here. If
anything doesn't compile or embed correctly, the most likely spots, in
rough order of how novel they are to this codebase: the hand-assembled
`SleepTimerWidgets` target's build settings or embed phase; the
`ActivityKit`/`WidgetKit` API surface in `SleepTimerLiveActivityWidget.swift`
and `SleepTimerActivityController.swift`; `AppIntents`/`AppShortcutsProvider`
usage in `PauseCurrentMediaIntent.swift`/`SleepTimerAppShortcuts.swift`;
and, as before, newer Liquid Glass API names or the watchOS
`digitalCrownRotation` overload, since all of these depend on the exact
iOS/watchOS 26 SDK you have installed.

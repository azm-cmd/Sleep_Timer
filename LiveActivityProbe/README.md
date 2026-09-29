# Live Activity Probe

A deliberately minimal, standalone app — unrelated to Sleep Timer's code —
used to isolate one question: **can a Live Activity render at all through
this specific sideloading setup** (Sideloadly, a free/personal-team Apple
ID, this device)?

## What it does

One screen, one button:

1. Shows `ActivityAuthorizationInfo().areActivitiesEnabled` directly.
2. "Start Test Live Activity" calls `Activity.request` with the simplest
   possible payload (a single `Int`) and prints the literal result on
   screen — either the activity's id, or the exact thrown error.
3. If it starts, "Bump Value" and "End Activity" let you confirm updates
   and cleanup also work.

The widget extension (`LiveActivityProbeWidget`) renders that `Int` on the
Lock Screen and in the Dynamic Island — nothing else.

## Why this exists

Sleep Timer's own Live Activity has been unable to appear on two different
sideloaded devices, despite: the widget extension being confirmed embedded
and correctly signed-adjacent (verified via a real macOS CI build), a
`CFBundleVersion` mismatch bug found and fixed, no crash logs on-device,
and `Activity.request` itself reporting success. That combination points at
something in the OS-level authorization to *launch* the widget extension
process — outside what either app's code can observe or control.

This probe removes every other variable. If it also fails the same way,
that's conclusive: the problem is in the signing/sideloading environment,
not in Sleep Timer. If it works, the two apps' setups need to be diffed.

## Building

`.github/workflows/build-live-activity-probe.yml` at the repo root
(`workflow_dispatch` only) builds and packages an unsigned
`LiveActivityProbe.ipa` the same way Sleep Timer's own workflow does,
including verifying the extension embeds and its `CFBundleVersion` matches
the app's before ever producing an IPA.

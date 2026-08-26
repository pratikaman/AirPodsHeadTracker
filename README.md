# HeadTracker

A tiny macOS app that shows your head orientation in real time from AirPods
motion sensors (AirPods Pro 3 and any other model that supports spatial-audio
head tracking), using Apple's public `CMHeadphoneMotionManager` API — no
reverse engineering involved.

## Requirements

- macOS 14 or later
- AirPods connected to this Mac and in your ears
- Xcode (or just Command Line Tools if you use `build.sh`)

## Run

**With Xcode:** open `HeadTracker.xcodeproj`, press ⌘R.

**Without Xcode:**

```bash
./build.sh && open build/HeadTracker.app
```

On first launch macOS asks for Motion & Fitness access — allow it, or the
stream never starts.

The project file is generated with [xcodegen](https://github.com/yonaskolb/XcodeGen)
from `project.yml`; if you change the file layout, re-run `xcodegen generate`.

## Using it

- The head model follows yours at ~25 Hz (the fixed rate Apple delivers).
- **Recenter (⌘R):** yaw has no absolute reference — whatever direction you
  faced when the stream started is "zero", and it drifts over time. Look at
  your screen and hit Recenter to re-zero.
- **Mirror:** on (default) behaves like a mirror; off shows your head as an
  observer facing you would see it.
- Pitch/yaw/roll readouts are relative to the same baseline.

## Troubleshooting

- **"Waiting for AirPods"** — the buds must be *connected to this Mac* (check
  the sound menu) and worn. If they auto-switched to your iPhone, the stream
  stops; play any audio on the Mac to pull them back.
- **Permission denied** — System Settings › Privacy & Security › Motion &
  Fitness, enable HeadTracker.
- **Angle signs feel backwards** — axis conventions differ subtly between
  AirPods models/firmware; flip the relevant sign in
  `MotionManager.handle(_:)`, it's display-only.

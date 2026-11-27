# Research notes — supplied reference packages

The uploaded `dynamicreal.zip` contains the author's `com.zidaneadam.island` 0.2.0 package, a DynamicSeth package directory, and a DynamicIslandPill package directory. The source repository was also reviewed at `Adam-Zidane/realisticdynamic`.

## What was actually inspected

- The existing Realistic Dynamic source (`Tweak.m`, `Makefile`, `Island.plist`) was read from the public GitHub repository.
- The uploaded Island 0.2.0 `.deb` package metadata and installed file layout were inspected.
- DynamicSeth and DynamicIslandPill preference plists and readable strings from their compiled dylibs were inspected. Their source code was not present in the upload, so this is feature-surface research, not a claim to have reverse-engineered their internal implementations.

## Reference feature surface

### Existing Island / repository implementation

The current repository source already contains a custom SpringBoard overlay, a compact/expanded Now Playing UI, MediaRemote integration, artwork tinting, playback controls, seek progress, charging, Low Power Mode, ringer state, notification previews, orientation handling, haptics, spring transitions, and an emergency disable file. The uploaded Island package metadata identifies the same package family and iOS 15+ rootless arm64 target.

### DynamicSeth package

Readable preference keys and strings show a wider activity surface, including Now Playing artwork glow and paused media, call presentation and call timing, incoming-call expansion, missed calls, timers, screen recording, screen mirroring, screenshots, volume/ringer presentation, flashlight-related options, notch presentation styles, morph/blur/edge effects, and diagnostics. Some of these are highly dependent on private SpringBoard internals and OS version.

### DynamicIslandPill package

Readable strings and its preference plist show configurable pill width, height, X/Y position, border width, unlock presentation styles, timer rings, battery indicators, music artwork/equalizer, recording state, and AirDrop progress. Its visible preferences include a conventional 126×37 default pill geometry.

## Design decisions in this implementation

- Retain a lightweight single SpringBoard overlay instead of installing multiple independent windows.
- Use MediaRemote dynamically rather than linking a private framework at build time.
- Use public CallKit, AVAudioSession, UIDevice, NSProcessInfo and UIScreen observation where possible.
- Make volume observation opt-in; do not change the user's volume or audio route.
- Do not attempt to suppress or replace Apple's incoming-call UI.
- Keep the overlay pass-through outside its own visible bounds.
- Include an emergency disable file to recover from a bad tweak build.

## Not yet implemented / not guaranteed

This first engineering release does not claim parity with every feature surfaced by the reference packages. Full AirDrop transfer progress, Face ID/unlock animation, flashlight beam animation, screenshot banners, detailed call controls, notification interception, and a true live timer countdown are not implemented. The timer bridge is best-effort because MobileTimer notification names differ by OS build. Those features should be added individually with device-specific testing rather than guessed private hooks.

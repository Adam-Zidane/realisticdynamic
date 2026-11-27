# Realistic Dynamic

**Author:** Zidane Adam  
**Package:** `com.zidaneadam.realisticdynamic`  
**Target:** Rootless Dopamine-compatible jailbreaks, iOS 15.0+, arm64

Realistic Dynamic is an original Dynamic Island-style activity surface for notch-less iPhones. It uses one SpringBoard overlay, adaptive compact/expanded layouts, artwork-aware music presentation, spring transitions, and capability-checked system integrations.

## Main implementation

The Theos build compiles **`Tweak.m`**. `Legacy-Tweak.xm` is retained only as a reference and is not compiled.

- Now Playing through dynamically resolved MediaRemote symbols: title, artist, artwork, play state, progress, play/pause, previous/next and seek.
- Compact and expanded music layouts, album artwork, animated equalizer and progress display.
- Charging, Low Power Mode and ringer/silent-state notifications.
- Notification previews through a guarded runtime hook; behavior can vary by iOS build.
- Call activity through public CallKit observation. The tweak never answers or ends calls.
- Screen capture / mirroring status through `UIScreen.isCaptured`.
- Optional volume HUD through the public `AVAudioSession.outputVolume` observation; it never changes volume or audio routing.
- Best-effort Clock timer event notifications; event names vary by iOS build.
- Tap to expand/collapse, long press to expand, swipe up to dismiss/collapse.
- Portrait-only overlay, configurable vertical position, optional haptics and subtle outline.
- Pass-through hit testing outside the pill.
- Emergency kill switch: create `/var/mobile/realisticdynamic_off` and respring.

## Device target

The source targets arm64 and iOS 15.0+. The iPhone 7 Plus is an arm64 device and iOS 15.8.6 meets the declared minimum. This is source-level compatibility, **not a claim of successful device testing**. UI scale, top position, SpringBoard behavior and private MediaRemote symbol availability must be validated on the actual phone.

## Build with GitHub Actions

1. If the importer is not already in your repository, first add `.github/workflows/import-source.yml` from this project and commit it. The example is also provided as `BOOTSTRAP_IMPORT.yml.example`.
2. Upload `RealisticDynamic-ZidaneAdam-1.1.0-source.zip` to the repository root and commit it.
3. The importer extracts the project files and commits them to `main`.
4. Open **Actions → build → Run workflow**.
5. Download the `RealisticDynamic-deb` artifact after a successful run.

The workflow builds a rootless package with Theos on macOS. It does not install the tweak on your phone.

## Install and recovery

Before installing, remove old overlapping island overlays, including the supplied Island / Island2 packages, DynamicSeth and DynamicIslandPill. Install the new `.deb` with Sileo or Zebra and respring.

If SpringBoard becomes unstable, create `/var/mobile/realisticdynamic_off` using Filza or SSH and respring. Remove the file to re-enable the tweak.

## Compatibility and honest limitations

- MediaRemote is private Apple functionality. It is loaded dynamically and may change across iOS releases.
- Notification interception depends on a SpringBoard class/method that may differ by iOS build.
- `UIScreen.isCaptured` reports recording or mirroring together; it cannot reliably distinguish them.
- Clock timer notifications are best-effort, not a guaranteed live countdown.
- Face ID / Dynamic Island hardware animations, AirDrop transfer progress, flashlight beam animations, screenshot banners, full Live Activities replication and Apple’s private Dynamic Island implementation are not implemented.
- Build success is not device validation. Test one feature at a time and keep the emergency disable file instructions available.

## Reference research

The supplied DynamicSeth and DynamicIslandPill packages were inspected for their preference surfaces and readable feature strings. Their compiled binaries are not included in this project and their private source implementation was not available. Realistic Dynamic implements its own UI and event handling; it does not bundle their binaries.


## Repository layout and build

The Theos project lives in `RealisticDynamic/`. The active tweak source is
`RealisticDynamic/Tweak.m`; the root-level `Tweak.xm` and `Legacy-Tweak.xm`
are retained only as legacy reference files and are not compiled.

The GitHub Actions build workflow explicitly runs Theos from `RealisticDynamic/`
and uploads the rootless `.deb` as `RealisticDynamic-rootless-deb`.


## Build workflow note

The build workflow now runs from `RealisticDynamic/`, where the 1.1.0 Theos
project and active `Tweak.m` live. Root-level `Tweak.xm` and `Legacy-Tweak.xm`
are archival copies and are not part of the package build.

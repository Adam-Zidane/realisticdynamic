# Realistic Dynamic

**Author:** Zidane Adam  
**Package:** `com.zidaneadam.realisticdynamic`  
**Target:** Rootless jailbreak, iOS 15.0+, arm64 (iPhone 7 Plus class devices)

Realistic Dynamic is an original Dynamic Island-style activity surface for iPhones without a physical Dynamic Island. It uses a lightweight SpringBoard overlay, adaptive compact/expanded layouts, spring transitions, artwork presentation, and capability-checked system integrations.

## Current implementation

- Now Playing via dynamically resolved MediaRemote symbols: title, artist, artwork, play state, progress, play/pause, previous/next and seek.
- Charging and battery percentage notification.
- Ringer / Silent Mode state changes.
- Low Power Mode changes.
- Screen recording state.
- Call activity via CallKit observer (status only; never answers or ends calls).
- Optional volume HUD observer (off by default).
- Clock timer event notification bridge (best-effort; iOS versions may emit different event names).
- Tap to expand/collapse, long press to expand, swipe up to dismiss/collapse.
- Portrait-only overlay, configurable vertical position, optional haptics and outline.
- Pass-through overlay hit testing so touches outside the pill continue to the app underneath.
- Emergency kill switch: `/var/mobile/realisticdynamic_off`.

## Build

This is a Theos project. On a Mac/Linux environment with Theos and an iOS SDK installed:

```sh
make clean package FINALPACKAGE=1
```

GitHub Actions builds the rootless `.deb` and publishes it as a workflow artifact. Upload the contents of this source archive into your repository (keep the `.github/workflows/build.yml` path), commit to `main`, then open **Actions → Build Realistic Dynamic**, wait for the run to finish, and download the `RealisticDynamic-deb` artifact.

## Install

Install the generated `.deb` using Sileo/Zebra on a rootless jailbreak. Remove the older Island/DynamicSeth/DynamicIslandPill overlay packages first: overlapping SpringBoard overlays can fight for touch handling and visual position. Respring after installation.

## Compatibility notes

- Designed for iOS 15+ rootless jailbreaks and arm64. It is not yet validated on every device/iOS build.
- MediaRemote is a private Apple framework, so its symbols are resolved dynamically and features gracefully degrade if unavailable.
- Timer notifications differ across iOS releases; timer activity is best-effort, not a guaranteed live countdown integration.
- Volume observation is disabled by default. If enabling it causes instability on a specific build, switch it off in Settings.
- This source is a first public engineering build. It must be compiled and device-tested before describing it as production-stable.

## Credits and research basis

The supplied DynamicSeth and DynamicIslandPill packages were inspected for their preference surfaces and exposed feature strings. This project independently implements its own view, event routing and MediaRemote bridge; it does not copy their compiled binaries or claim their private implementation details as known.

### Uploading from GitHub's web interface (no git client)

If your browser cannot upload folders, use `BOOTSTRAP_IMPORT.yml.example` as a one-time importer:

1. In your repository, create `.github/workflows/import-source.yml` and paste the contents of `BOOTSTRAP_IMPORT.yml.example`.
2. Upload `RealisticDynamic-1.0.0-source.zip` to the repository root and commit it.
3. The importer extracts the project files into the repository and commits them. The build workflow is then present.
4. Open **Actions → Build Realistic Dynamic → Run workflow** to build the `.deb`.

If GitHub blocks the importer from pushing, enable **Settings → Actions → General → Workflow permissions → Read and write permissions**, then retry.

# Research notes — supplied reference packages

## Sources inspected

- `dynamicreal.zip`: the author's Island 0.2.0 package plus DynamicSeth and DynamicIslandPill package directories.
- `realisticdynamic-main 2.zip`: repository source, build workflow, preferences and package metadata.
- Public GitHub repository: `https://github.com/Adam-Zidane/realisticdynamic`.

## Findings

### Existing Realistic Dynamic source

The archive contained two implementations. The original Makefile selected `Tweak.xm` (247 lines), while `Tweak.m` (about 899 lines) contained the more developed adaptive music UI, progress display, notification preview hook, charging, Low Power Mode and ringer handling. The updated Makefile now builds `Tweak.m`; `Legacy-Tweak.xm` remains uncompiled for reference.

The previous source also had a preference-domain mismatch: the richer source read `com.zidaneadam.island`, while the package and preference bundle use `com.zidaneadam.realisticdynamic`. This update aligns the domain and the preference notification name.

### DynamicSeth

Readable preference strings exposed feature concepts including artwork glow, paused media, incoming-call expansion, timers, screen recording/mirroring, screenshot notices, volume/ringer notices, flashlight-related options, notch styling, blur and morph effects. The original source code was not supplied, so these are feature-surface observations only.

### DynamicIslandPill

Its preference plist exposed width, height, X/Y position, border width, unlock presentation styles, timer rings, battery indicators, music artwork/equalizer, recording state and a 126×37 default pill geometry.

## Implementation decisions

- Keep one SpringBoard overlay; do not install multiple competing overlays.
- Use the richer in-repository Objective-C implementation as the active source.
- Resolve MediaRemote dynamically instead of hard-linking the private framework.
- Use public CallKit and UIScreen capture observation where possible.
- Keep the emergency disable file.
- Keep timer and notification integrations explicitly best-effort because they depend on OS-specific behavior.

## Not implemented / not guaranteed

Face ID / Dynamic Island hardware animations, full AirDrop transfer progress, flashlight beam animations, screenshot banners, full Live Activities replication and true Clock timer countdown are not implemented. They require separate research and device-specific validation rather than speculative private hooks.

# Changelog

## 1.1.0 — engineering update
- Build the richer `Tweak.m` implementation instead of the shorter legacy `Tweak.xm`.
- Align preferences with `com.zidaneadam.realisticdynamic`.
- Fix vertical-position preference mapping and idle-pill default behavior.
- Add paused-media visibility preference.
- Apply the optional subtle outline setting.
- Lower overlay window level to reduce interference with system alerts.
- Add CallKit call activity, screen-capture/mirroring notices and best-effort timer event notices.
- Add matching Settings toggles and document device-testing limitations.
- Align emergency disable path with `/var/mobile/realisticdynamic_off`.

## 1.3.0 — All Activities Update

- Retained existing Now Playing, CallKit, notification, charging, low-power, ringer, volume, screen-capture and Clock timer event integrations.
- Added screenshot confirmation using UIApplicationUserDidTakeScreenshotNotification.
- Added read-only flashlight state observation using AVCaptureDevice torchMode.
- Added battery percentage change notifications.
- Added configurable Music artwork/progress and expanded-player auto-collapse settings.
- Added double-tap play/pause gesture.
- Refreshes Now Playing metadata after transport commands.

Limitations: Clock timer notifications remain best-effort on iOS 15 builds; this does not implement a reliable live timer countdown or a system Stopwatch feed. Flashlight KVO and private SpringBoard notification hooks require device validation.


## 1.3.1
- Fix preference bundle linking by linking Preferences as a private framework instead of a public SDK framework.

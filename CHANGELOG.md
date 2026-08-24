# Changelog

All notable changes to Omaloom are documented here.

## 0.1.8 — 2026-08-23

### Fixed

- Constrain the Record setup column to the popup's available height and add vertical wheel/touch scrolling with an as-needed scrollbar.
- Keep webcam options, previews, status, and Start recording reachable on smaller laptop displays without changing the full-size dashboard layout.

## 0.1.7 — 2026-08-23

### Fixed

- Explicitly unmap Omaloom before launching the portal folder picker so the always-on-top setup panel cannot cover the dialog on smaller displays.
- Restore the setup panel after folder selection or cancellation.

## 0.1.6 — 2026-08-23

### Changed

- Require explicit portal-backed output-folder selection on first use instead of assuming or creating `~/Videos/Omaloom`.
- Keep Start disabled until the selected folder exists and passes Omaloom's output-directory safety validation.
- Preserve existing users' saved output folders, but fail closed if a saved folder is removed or becomes unsafe.

## 0.1.5 — 2026-08-23

### Fixed

- Let users change setup options, including Folder and Camera, while recording readiness is blocked by camera availability.
- Start the portal folder picker at the nearest existing parent when the configured/default recording folder does not exist yet, without creating folders or changing settings implicitly.

## 0.1.4 — 2026-08-23

### Performance

- Keep one FFmpeg microphone-meter process alive while setup is open, cutting first-level latency and eliminating repeated process/device initialization.
- Move secure output/state and audio preparation before webcam placement and countdown.
- Replace the fixed 800 ms recorder survival delay with bounded process/output readiness and reduce popup-unmap delays.
- Remove duplicate webcam placement, redundant camera ownership work, and the fixed one-second pre-countdown settle delay.

### Changed

- Keep setup closed during backend preparation, render only the dedicated countdown pane, and transition directly from `1` to confirmed `REC` without `GO` or settings flashes.
- Start countdown immediately after the webcam reaches its configured position while using countdown as camera warm-up time.

### Security

- Make Omarchy's fixed stop-state reservation strictly exclusive so concurrent starts cannot replace one another.
- Tie the persistent FFmpeg meter to its Python parent's lifetime and revalidate webcam mapping/liveness immediately before capture.
- Add regression coverage for concurrent state reservation, orphan prevention, fast-path ordering, and flash-free QML transitions.

## 0.1.3 — 2026-08-21

### Security

- Replace shell writes to predictable `/tmp/omarchy-screenrecord-filename` with a stdlib Python helper that validates ownership/type without following links and atomically reserves the fixed path mode `0600`.
- Preserve compatibility with Omarchy's stock top-center stop control while rejecting symlinks, FIFOs, unsafe ownership, hard-linked state files, and race replacement.
- Reserve unpredictable MP4 output paths with a stdlib Python helper in owner-only selected directories, rejecting unsafe group/world-writable output locations.
- Move debug/region/webcam PID state under a validated private per-user runtime directory and track only Omaloom's own validated mpv webcam overlay PID instead of broad process-name cleanup.
- Use a controlled command search path for recorder/helper subprocesses and fail closed when required commands are not found there, while retaining explicit development test overrides.
- Install idempotent startup cleanup traps before source selection/webcam/countdown so interrupted starts clean unretained webcam/output/state artifacts.
- Add proactive setup-time camera availability checks with inline busy warnings before Start while preserving backend ownership checks for races.
- Ignore symbolic links while scanning the selected recording library and reject symlink cleanup targets.

## 0.1.2 — 2026-08-21

### Fixed

- Harden webcam overlay startup when the selected V4L2 camera is already owned by another application.
- Capture mpv webcam startup stderr to a private runtime log, detect busy/in-use failures, and surface a clear structured error instead of silently continuing to countdown.
- Require a live mapped `WebcamOverlay` before resize, placement, and countdown.
- Clean temporary webcam logs and overlay/region state on failure without touching the application that owns the camera.

## 0.1.1 — 2026-08-21

### Security

- Force `Text.PlainText` on every QML text surface so crafted device names, paths, filenames, and backend feedback cannot trigger Qt rich-text resource loading.
- Add a regression test requiring plain-text enforcement for every future QML `Text` item.

## 0.1.0 — 2026-08-20

Initial public release.

### Added

- Region and current-monitor/fullscreen screen recording through Omarchy's `gpu-screen-recorder` pipeline.
- Source-first region flow with outside-only capture guide, webcam preparation, 5–1 countdown, `GO`, and `REC` states.
- Persistent output folder, system audio, microphone, webcam, device, webcam position, and webcam size settings.
- Setup-only live microphone waveform and webcam composition preview.
- Configurable webcam corner and size, anchored to the selected region or monitor.
- Local MP4 library with Open, Reveal, and Copy path actions.
- Portal-backed folder selection isolated from Quickshell.
- Multi-monitor geometry support including scaling, rotation, and negative coordinates.
- Clapperboard bar icon and responsive Record/Library dashboard.

### Scope

- Local files only; no cloud API, OAuth, uploads, or generated sharing links.
- Recording stop/finalization remains delegated to Omarchy's top-center recording control.

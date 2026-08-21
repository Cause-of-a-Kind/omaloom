# Changelog

All notable changes to Omaloom are documented here.

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

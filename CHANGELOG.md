# Changelog

All notable changes to Omaloom are documented here.

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

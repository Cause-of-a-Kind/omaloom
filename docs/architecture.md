# Omaloom architecture

Omaloom is a thin Omarchy Quattro plugin over Omarchy's existing screen recording stack.

```text
coak.omaloom
├── manifest.json          # plugin metadata and entrypoint wiring
├── bin/omaloom-recorder   # stable Omaloom CLI over `omarchy screenrecord`
├── bin/omaloom-settings      # atomic JSON persistence helper
├── bin/omaloom-folder-picker # isolated xdg-desktop-portal folder picker
├── bin/omaloom-geometry      # region/monitor guide mapping
├── bin/omaloom-devices       # capture device discovery and setup mic meter
└── qml/
    ├── OmaloomSettings.qml    # shared settings bridge
    ├── OmaloomRegionGuide.qml # outside-only recording guide overlay
    ├── Service.qml            # recording state and settings loader
    ├── Panel.qml           # recording controls and saved-file affordances
    └── BarWidget.qml       # compact idle/recording bar indicator
```

## Scope boundary

QML owns UI and state only. It does not encode media, talk to cloud APIs, or implement its own capture engine. For v1, all recordings are local MP4 files in a user-selected folder; synced-folder workflows are handled outside Omaloom by tools such as Dropbox, Syncthing, or Nextcloud.

## Recorder backend

`bin/omaloom-recorder` exposes the stable MVP interface:

```bash
omaloom-recorder start [--directory DIR] [--fullscreen] [--desktop-audio] [--microphone] [--microphone-device DEVICE] [--webcam] [--webcam-device DEVICE]
omaloom-recorder stop
omaloom-recorder status
```

Internally, `start` now uses a local two-phase flow copied from Omarchy's public capture behavior without editing `/usr/share/omarchy`:

1. Select the capture target first:
   - fullscreen/current-monitor: focused monitor, no interaction
   - non-fullscreen: `omarchy-capture-region smart --match-monitor`
2. Release setup-only device previews and prepare/place the recording webcam overlay when enabled.
3. Emit a 5-second countdown after the source and webcam overlay are ready.
4. Emit `starting`, allowing Quickshell to unmap the countdown popup.
5. Launch `gpu-screen-recorder` with Omarchy-compatible arguments, state files, and indicator refresh.

`stop` intentionally delegates back to Omarchy:

```bash
omarchy screenrecord --stop-recording
```

That preserves Omarchy's SIGINT save behavior, webcam cleanup, MP4 finalization, thumbnail notification, and the built-in recording indicator/stop control.

Output is newline-delimited JSON-ish events for QML parsing, for example:

```json
{"event":"source_selected","target":"region:1280x720+0+0"}
{"event":"countdown","seconds":"5"}
{"event":"starting"}
{"event":"recording_started","path":"/home/user/Videos/Omaloom/screenrecording.mp4","guide":{"type":"region","region":{"x":100,"y":100,"width":800,"height":450},"monitors":[{"name":"DP-1","x":0,"y":0,"width":2560,"height":1440,"scale":1}]}}
{"event":"saved","path":"/home/user/Videos/Omaloom/screenrecording.mp4"}
{"event":"status","state":"recording"}
{"event":"cancelled"}
{"event":"error","message":"..."}
```

## Persistent settings

Settings are shared through `~/.config/omaloom/settings.json` with these normalized keys:

- `outputDirectory` (string, default `~/Videos/Omaloom`)
- `fullscreenCurrentMonitor` (boolean, default `false`)
- `systemAudio` (boolean, default `true`)
- `microphone` (boolean, default `true`)
- `webcam` (boolean, default `false`)
- `microphoneDevice` (string PipeWire/Pulse source name, default `""` = default input)
- `webcamDevice` (string `/dev/video*` path, default `""` = first available camera)

`qml/OmaloomSettings.qml` is instantiated by the service, panel, and every bar widget. It watches the settings file and applies safe defaults when the file is absent, malformed, or contains malformed fields. Control changes update local UI state immediately and call `bin/omaloom-settings set KEY VALUE` with argv-based `Process` commands, never shell-concatenated JSON.

`bin/omaloom-settings` is the persistence boundary. It validates keys and values, parses and emits JSON with Python's `json` module, serializes writes with `flock`, writes a same-directory temporary file, fsyncs it, atomically replaces `settings.json`, and fsyncs the config directory. Because each `set` merges one field into the currently locked file, multiple per-monitor `BarWidget` instances converge on shared settings instead of overwriting one another with monitor-local snapshots.

`bin/omaloom-folder-picker` owns folder selection through `org.freedesktop.portal.FileChooser` with `directory=true`. It runs out-of-process via argv-only `Process` and returns only `{"path":"/local/folder"}` on success; cancellation emits nothing and errors are logged as nonfatal JSON on stderr. This isolates Quickshell from native GTK/GVFS dialog crashes while avoiding Qt Quick's large in-shell fallback dialog. The bar widget refuses to launch duplicate picker processes and updates `outputDirectory` only after parsing a successful local `file://` portal result.

`bin/omaloom-devices` discovers microphones with `pactl --format=json list sources` (excluding monitor sources) and cameras with Omarchy's `omarchy-capture-webcam-list`, falling back to `v4l2-ctl --list-devices`. It also provides a setup-only microphone meter using `ffmpeg` against the selected PipeWire/Pulse source. The bar widget creates a fresh meter process and waveform when setup opens, restarts it safely when the selected device changes, and destroys it when setup closes.

The webcam setup preview uses installed `QtMultimedia` (`MediaDevices`, `Camera`, `CaptureSession`, `VideoOutput`) inside the popup. A `Loader` creates the complete camera capture graph only while setup is open and webcam capture is enabled, then destroys it before selection/countdown. Destruction—not merely `Camera.active = false`—is required to release `/dev/video*` for the actual Omarchy-style mpv recording overlay. The backend prepares and places that overlay before the visible countdown, including anchoring it to a selected region. If a selected microphone/camera is disconnected, the UI labels it as disconnected where possible and the recorder falls back to default input or first available camera.

## Region recording guide

Region captures emit guide geometry only with `recording_started`, never at `source_selected`, so the guide appears only when the backend has actually started recording. Fullscreen/current-monitor targets do not emit guide data and therefore never show the overlay.

`bin/omaloom-geometry` maps the global logical `region:WxH+X+Y` target from Omarchy/slurp onto intersecting Hyprland monitors, preserving negative coordinates and monitor scale metadata. `qml/OmaloomRegionGuide.qml` creates click-through `PanelWindow` layer-shell surfaces for the relevant `Quickshell.screens`, then converts global logical monitor coordinates into each screen's local coordinate space.

The guide draws only outside the captured rectangle: subtle shading in the four outside bands plus one-pixel/thin accent strips just beyond each region edge. If a selected edge lies on a physical monitor edge, that side is omitted rather than drawn inward. The window `mask` is empty (`Region {}`), making the guide noninteractive/click-through. The owning bar widget hides the guide on saved/idle/error/cancel, before a new start, and on plugin destruction. If recording is stopped by Omarchy's top-center control, Omaloom removes the guide on the next status transition to idle.

## State and update model

The UI follows an Elm-style model/update/render direction: backend events update one explicit state, and the bar/popup render from that state. Backend polling must not temporarily reset a local pre-recording state merely because `gpu-screen-recorder` has not started yet.

Non-fullscreen flow:

```text
idle → selecting → preparing devices → countdown → starting → recording → idle
          ↘ cancelled → idle                                      ↘ error
```

Fullscreen/current-monitor flow skips interactive selection:

```text
idle → preparing devices → countdown → starting → recording → idle
```

Behavioral rules for the baseline:

- The setup popup closes before interactive source selection.
- Once selection completes, the popup reopens for the large countdown.
- The backend emits `starting`; the popup closes and is given time to unmap before capture starts.
- `REC` is an indicator only and never opens recording controls.
- Omarchy's top-center control owns stop for v1.
- Omarchy owns stop, finalization, thumbnail generation, notification, and webcam cleanup.

Future iterations may add richer preview controls and device-specific tuning, but should keep this shared settings file as the source of truth and preserve the default recording directory at `~/Videos/Omaloom`.

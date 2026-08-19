# Omaloom architecture

Omaloom is a thin Omarchy Quattro plugin over Omarchy's existing screen recording stack.

```text
coak.omaloom
├── manifest.json          # plugin metadata and entrypoint wiring
├── bin/omaloom-recorder   # stable Omaloom CLI over `omarchy screenrecord`
└── qml/
    ├── Service.qml        # recording state and future settings owner
    ├── Panel.qml          # recording controls and saved-file affordances
    └── BarWidget.qml      # compact idle/recording bar indicator
```

## Scope boundary

QML owns UI and state only. It does not encode media, talk to cloud APIs, or implement its own capture engine. For v1, all recordings are local MP4 files in a user-selected folder; synced-folder workflows are handled outside Omaloom by tools such as Dropbox, Syncthing, or Nextcloud.

## Recorder backend

`bin/omaloom-recorder` exposes the stable MVP interface:

```bash
omaloom-recorder start [--directory DIR] [--fullscreen] [--desktop-audio] [--microphone] [--webcam]
omaloom-recorder stop
omaloom-recorder status
```

Internally, `start` now uses a local two-phase flow copied from Omarchy's public capture behavior without editing `/usr/share/omarchy`:

1. Select the capture target first:
   - fullscreen/current-monitor: focused monitor, no interaction
   - non-fullscreen: `omarchy-capture-region smart --match-monitor`
2. Emit a 5-second countdown after the source is known.
3. Emit `starting`, allowing Quickshell to unmap the countdown popup.
4. Launch `gpu-screen-recorder` with Omarchy-compatible arguments, state files, and indicator refresh.

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
{"event":"recording_started","path":"/home/user/Videos/Omaloom/screenrecording.mp4"}
{"event":"saved","path":"/home/user/Videos/Omaloom/screenrecording.mp4"}
{"event":"status","state":"recording"}
{"event":"cancelled"}
{"event":"error","message":"..."}
```

## State and update model

The UI follows an Elm-style model/update/render direction: backend events update one explicit state, and the bar/popup render from that state. Backend polling must not temporarily reset a local pre-recording state merely because `gpu-screen-recorder` has not started yet.

Non-fullscreen flow:

```text
idle → selecting → countdown → starting → recording → idle
          ↘ cancelled → idle                  ↘ error
```

Fullscreen/current-monitor flow skips interactive selection:

```text
idle → countdown → starting → recording → idle
```

Behavioral rules for the baseline:

- The setup popup closes before interactive source selection.
- Once selection completes, the popup reopens for the large countdown.
- The backend emits `starting`; the popup closes and is given time to unmap before capture starts.
- `REC` is an indicator only and never opens recording controls.
- Omarchy's top-center control owns stop for v1.
- Omarchy owns stop, finalization, thumbnail generation, notification, and webcam cleanup.

Future iterations should persist settings at `~/.config/omaloom/settings.json` and keep the default recording directory at `~/Videos/Omaloom`.

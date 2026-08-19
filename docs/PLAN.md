# Omaloom v1 Build Plan

## Product direction

Omaloom (`coak.omaloom`) is a Cause of a Kind Omarchy Quattro plugin for fast, local-first screen recording.

V1 should be a polished native Omarchy front-end around Omarchy's existing recording stack, not a new media engine.

Core philosophy:

> Record locally. Own the files. Share however you choose.

For v1, sharing is folder-based only. If someone wants Dropbox, Syncthing, Nextcloud, etc., they choose that synced folder as the recording destination. No Dropbox API, OAuth, link creation, or public/private state in v1.

## Repository

Local path:

```text
/home/m/Code/cause-of-a-kind/omaloom
```

Future public repo:

```text
https://github.com/Cause-of-a-Kind/omaloom
```

Plugin id:

```text
coak.omaloom
```

## V1 scope

Must have:

- Valid Omarchy Quattro plugin manifest.
- `service`, `panel`, and `bar-widget` entry points.
- Persistent recording state in `Service.qml`.
- Native panel with recording options.
- Bar widget showing idle/recording state.
- Start recording through `bin/omaloom-recorder`; stop through Omarchy's top-center recording control for the v1 baseline.
- Choose/remember output folder.
- Fullscreen/current-monitor recording.
- Region recording via Omarchy's built-in selector.
- Microphone toggle.
- System audio toggle.
- Webcam toggle.
- Save MP4 locally.
- Show/copy/open/reveal the saved recording path.

Confirmed in baseline:

- Source selection before recording for non-fullscreen capture.
- Visible 5-second countdown after source selection.
- `REC` indicator that does not reopen setup controls.
- Stop through Omarchy's top-center recording control.

Nice but optional for v1:

- Recent recording list from a simple JSON file.
- Thumbnails.
- Filename pattern customization.

Not v1:

- Dropbox API.
- Share-link generation.
- Link revoke.
- OAuth/keyring.
- GStreamer compositor.
- Annotations.
- Custom source preview overlay.

## Architecture

```text
Quattro plugin
├── qml/Service.qml       # owns settings + recording state machine
├── qml/Panel.qml         # controls and saved-file actions
├── qml/BarWidget.qml     # compact bar indicator
└── bin/omaloom-recorder  # shell wrapper around `omarchy screenrecord`
```

QML must not do media encoding. The recorder backend is replaceable.

## Recorder backend v1

Omaloom uses a local two-phase start flow because Omarchy's stock command combines source selection and recorder startup. The wrapper selects the source with Omarchy's selector, emits countdown events, and then starts `gpu-screen-recorder` with Omarchy-compatible state and indicator behavior.

Stop remains delegated to Omarchy:

```bash
omarchy screenrecord --stop-recording
```

The wrapper should expose a stable Omaloom interface:

```bash
omaloom-recorder start [--directory DIR] [--fullscreen] [--desktop-audio] [--microphone] [--webcam]
omaloom-recorder stop
omaloom-recorder status
```

Return newline-delimited JSON where practical:

```json
{"event":"recording_started"}
{"event":"saved","path":"/home/m/Videos/Omaloom/file.mp4"}
{"event":"error","message":"..."}
```

## State machine

Use one explicit state:

```text
idle
selecting
countdown
recording
stopping
processing
saved
error
```

## Settings/files

Use:

```text
~/.config/omaloom/settings.json
~/Videos/Omaloom
```

Initial settings:

```json
{
  "defaultDirectory": "~/Videos/Omaloom",
  "recordFullscreen": false,
  "recordMicrophone": true,
  "recordSystemAudio": true,
  "recordWebcam": false
}
```

## Validation/dev loop

Validate plugin:

```bash
omarchy plugin validate /home/m/Code/cause-of-a-kind/omaloom
```

Install locally for testing:

```bash
rm -rf ~/.config/omarchy/plugins/coak.omaloom
rsync -a --delete /home/m/Code/cause-of-a-kind/omaloom/ ~/.config/omarchy/plugins/coak.omaloom/
omarchy-shell shell rescanPlugins
omarchy plugin enable coak.omaloom --section right
```

## First implementation target

1. Create minimal valid manifest and QML entrypoints.
2. Implement `bin/omaloom-recorder` start/stop/status wrapper.
3. Validate plugin.
4. Add docs/architecture.md and README.md.
5. If safe in this environment, install locally and enable the plugin.
6. Report exact commands run and remaining TODOs.

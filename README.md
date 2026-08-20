# Omaloom

Omaloom (`coak.omaloom`) is a Cause of a Kind Omarchy Quattro plugin for fast, local-first screen recording.

V1 is intentionally local-folder only: recordings are saved as MP4 files under `~/Videos/Omaloom` by default, or another folder you choose. The selected output directory and capture toggles are persisted in `~/.config/omaloom/settings.json`. There is no Dropbox API, OAuth, share-link generation, or cloud-specific behavior in this MVP.

## Confirmed baseline behavior

The current interaction is:

```text
Click Omaloom
→ choose output folder, current monitor/region, system audio, microphone input, and webcam camera options
→ click Start recording
→ for region capture, select the source or area
→ see a large 5, 4, 3, 2, 1 countdown
→ recording begins, region captures show an outside-only guide, and the bar shows REC
→ stop with Omarchy's top-center recording control
→ Omarchy finalizes and saves the MP4
```

For fullscreen/current-monitor capture, source selection is automatic and the countdown appears immediately. Region captures show a click-through guide around the selected geometry only after recording starts; no guide is shown for fullscreen/current-monitor capture. While recording, `REC` is an indicator only and does not reopen the setup panel. A dedicated Omaloom hotkey may be added later; it is intentionally outside this baseline.

## MVP contents

- `manifest.json` — Omarchy plugin manifest for `service`, `panel`, and `bar-widget` entrypoints.
- `bin/omaloom-recorder` — two-phase capture wrapper using Omarchy tools and `gpu-screen-recorder`.
- `bin/omaloom-settings` — safe JSON settings loader/updater for `~/.config/omaloom/settings.json`.
- `bin/omaloom-folder-picker` — external xdg-desktop-portal folder picker isolated from Quickshell.
- `bin/omaloom-geometry` — monitor/region mapping for outside-only recording guides.
- `bin/omaloom-devices` — microphone/camera discovery and setup-only mic level metering.
- `qml/Service.qml` — service skeleton that loads shared recording settings/state.
- `qml/Panel.qml` — panel entrypoint skeleton.
- `qml/OmaloomSettings.qml` — shared QML settings bridge used by service, panel, and bar widgets.
- `qml/OmaloomRegionGuide.qml` — click-through, outside-only region recording guide.
- `qml/BarWidget.qml` — setup popup, live previews, countdown, region guide owner, and recording indicator.

## Persistent settings

Omaloom stores normalized JSON at `~/.config/omaloom/settings.json`:

```json
{
  "fullscreenCurrentMonitor": false,
  "microphone": true,
  "microphoneDevice": "default_input",
  "outputDirectory": "/home/user/Videos/Omaloom",
  "systemAudio": true,
  "webcam": false,
  "webcamDevice": "/dev/video0"
}
```

Absent or malformed files and fields fall back to defaults. Writes are performed by `bin/omaloom-settings` with validated argv values, `json.dumps`, a file lock, and atomic `os.replace()` so multiple per-monitor bar widget instances converge on one shared settings file. The setup popup launches an external xdg-desktop-portal folder picker helper and includes selectors for available microphones and cameras. It shows an animated, level-responsive microphone waveform only while the popup is open and microphone capture is enabled. The microphone meter and embedded QtMultimedia camera capture graph are created when setup opens and destroyed when it closes, ensuring the selected devices are released before recording starts.

## Recorder CLI

```bash
bin/omaloom-recorder start --directory ~/Videos/Omaloom --fullscreen --desktop-audio --microphone --microphone-device default_input --webcam --webcam-device /dev/video0
bin/omaloom-recorder status
bin/omaloom-recorder stop
```

Without `--fullscreen`, Omarchy's built-in region/monitor selector runs before the countdown. The CLI emits newline-delimited events describing selection, countdown, startup, recording, cancellation, and errors.

## Validate

```bash
omarchy plugin validate .
python3 tests/test_omaloom_settings.py
python3 tests/test_omaloom_devices.py
python3 tests/test_omaloom_folder_picker.py
python3 tests/test_omaloom_geometry.py
```

## Local install for manual testing

```bash
rm -rf ~/.config/omarchy/plugins/coak.omaloom
rsync -a --delete ./ ~/.config/omarchy/plugins/coak.omaloom/
omarchy-shell shell rescanPlugins
omarchy plugin enable coak.omaloom --section right
```

Do not run these install commands from automation unless you intend to modify the local Omarchy shell config.

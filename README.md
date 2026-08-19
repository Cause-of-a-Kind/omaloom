# Omaloom

Omaloom (`coak.omaloom`) is a Cause of a Kind Omarchy Quattro plugin for fast, local-first screen recording.

V1 is intentionally local-folder only: recordings are saved as MP4 files under `~/Videos/Omaloom` by default, or another folder you choose. There is no Dropbox API, OAuth, share-link generation, or cloud-specific behavior in this MVP.

## Confirmed baseline behavior

The current interaction is:

```text
Click Omaloom
→ choose current monitor/region, system audio, microphone, and webcam options
→ click Start recording
→ for region capture, select the source or area
→ see a large 5, 4, 3, 2, 1 countdown
→ recording begins and the bar shows REC
→ stop with Omarchy's top-center recording control
→ Omarchy finalizes and saves the MP4
```

For fullscreen/current-monitor capture, source selection is automatic and the countdown appears immediately. While recording, `REC` is an indicator only and does not reopen the setup panel. A dedicated Omaloom hotkey may be added later; it is intentionally outside this baseline.

## MVP contents

- `manifest.json` — Omarchy plugin manifest for `service`, `panel`, and `bar-widget` entrypoints.
- `bin/omaloom-recorder` — two-phase capture wrapper using Omarchy tools and `gpu-screen-recorder`.
- `qml/Service.qml` — service skeleton for future persistent settings/state.
- `qml/Panel.qml` — panel entrypoint skeleton.
- `qml/BarWidget.qml` — working setup popup, countdown, and recording indicator.

## Recorder CLI

```bash
bin/omaloom-recorder start --directory ~/Videos/Omaloom --fullscreen --desktop-audio --microphone
bin/omaloom-recorder status
bin/omaloom-recorder stop
```

Without `--fullscreen`, Omarchy's built-in region/monitor selector runs before the countdown. The CLI emits newline-delimited events describing selection, countdown, startup, recording, cancellation, and errors.

## Validate

```bash
omarchy plugin validate .
```

## Local install for manual testing

```bash
rm -rf ~/.config/omarchy/plugins/coak.omaloom
rsync -a --delete ./ ~/.config/omarchy/plugins/coak.omaloom/
omarchy-shell shell rescanPlugins
omarchy plugin enable coak.omaloom --section right
```

Do not run these install commands from automation unless you intend to modify the local Omarchy shell config.

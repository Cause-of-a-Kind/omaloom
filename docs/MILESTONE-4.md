# Milestone 4: Configurable webcam composition

## Goal

Let users choose where the webcam overlay appears and how large it is, then preview that composition before recording without holding camera resources during capture startup.

## User experience

When **Webcam overlay** is enabled, the Record column shows:

- **Camera** selector for available `/dev/video*` devices.
- **Position** selector cycling `top-left`, `top-right`, `bottom-left`, `bottom-right`.
- **Size** selector cycling `small`, `medium`, `large`.
- A representative composition canvas using the popup's current monitor aspect ratio. The live camera tile appears at the selected corner and proportional size.

The canvas is explicitly representative before region selection. After region selection, the real mpv `WebcamOverlay` is positioned relative to the selected region (or current monitor for fullscreen/current-monitor capture).

## Persistence

`~/.config/omaloom/settings.json` stores validated enum fields:

```json
{
  "webcamPosition": "bottom-right",
  "webcamSize": "medium"
}
```

Malformed or absent values fall back to `bottom-right` and `medium`.

## Backend

`omaloom-recorder start` accepts:

```text
--webcam-position top-left|top-right|bottom-left|bottom-right
--webcam-size small|medium|large
```

Sequence:

1. Select source.
2. Emit region guide geometry when applicable.
3. Release setup-only QtMultimedia camera graph.
4. Launch mpv `WebcamOverlay`.
5. Call `omarchy-capture-webcam-resize SIZE`.
6. Run `bin/omaloom-webcam-placement apply` to place the overlay at the selected corner relative to the selected region/monitor.
7. Let the overlay settle for about one second.
8. Emit visible 5–1 countdown, then `GO`/recording.

`bin/omaloom-webcam-placement` contains testable geometry for scaled/rotated monitors, negative coordinates, margins, clamping, all corners, and region/monitor anchors. It dispatches `hyprctl` using argv arrays.

## Deferred

- Dragging the preview tile.
- Per-folder/per-profile webcam presets.
- Exact preview of an unknown future region before the user selects it.

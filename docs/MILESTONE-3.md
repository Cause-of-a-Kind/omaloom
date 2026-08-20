# Milestone 3: Saved recordings

## Goal

Turn a completed capture into an immediately useful local file workflow without adding cloud integration. After recording, Omaloom should make the latest MP4 easy to open, reveal, or copy, and should show a compact list of recent recordings from the selected output folder.

## User experience

When Omaloom is idle and the selected output folder contains recordings, the right **LIBRARY** column shows one compact scrollable list of MP4 files, newest first. Each row contains:

- filename and compact modified-time/size metadata
- **Open** — launch the MP4 with the desktop default application
- **Reveal** — show the file in the desktop file manager
- **Copy** — copy the absolute local path and show brief inline confirmation

The setup controls and full-width **Start recording** button remain the primary content in the RECORD column. There is no separate latest card and no recent-recordings accordion.

No saved-file controls are shown over an active recording. `REC` remains indicator-only, and Omarchy's top-center control remains the sole stop control.

## Data model

Do not introduce a history database in this milestone. The selected output directory is already the source of truth and survives shell restarts.

Add a helper with an argv-only interface:

```text
omaloom-recordings list --directory DIR [--limit N]
omaloom-recordings open PATH
omaloom-recordings reveal PATH
omaloom-recordings copy-path PATH
```

`list` returns validated JSON containing regular `.mp4` files sorted by modification time descending. `--limit 0` explicitly returns all recordings; positive limits cap rows for scripts. Each item contains only inexpensive filesystem metadata:

```json
{
  "recordings": [
    {
      "path": "/home/user/Videos/Omaloom/screenrecording-2026-08-20_12-21-05.mp4",
      "name": "screenrecording-2026-08-20_12-21-05.mp4",
      "modified": 1787228465,
      "size": 48210392
    }
  ]
}
```

Scanning the folder rather than relying on a transient `saved` event ensures the latest file survives a Quickshell/plugin restart and is visible from every monitor's widget instance. It also works when recording is stopped through Omarchy rather than through an Omaloom subprocess.

The first version scans only the currently selected output folder. Cross-folder history and a persistent recording index are deferred until there is a demonstrated need.

## Action boundary

All filesystem and desktop actions belong in `bin/omaloom-recordings`, not shell-concatenated QML commands.

- Paths are passed as individual argv values and must resolve to existing regular MP4 files.
- **Open** uses the desktop's default opener.
- **Reveal** uses the standard file-manager D-Bus interface where available, with opening the parent directory as a fallback.
- **Copy path** writes the exact absolute path to the Wayland clipboard without shell interpolation.
- Failures return structured JSON errors and remain nonfatal to the recorder UI.

## QML state

Add predictable saved-file state to the active bar popup:

```text
recordings: []
recordingsLoading: false
recordingsError: ""
actionFeedback: ""
```

Refresh recordings:

1. when the popup opens while not recording,
2. when the configured output directory changes,
3. shortly after recording transitions from active to idle,
4. after a saved-file action only when needed.

A short delayed refresh after stop avoids presenting a file while Omarchy is still finalizing it. Actions remain disabled while recording or while the list is loading. The directory scan on the next popup open is the authoritative recovery path if a stop transition is missed.

Keep the Elm-style direction:

```text
user/backend event → update explicit state → render controls
```

## Implementation phases

### Phase 1 — recording helper

- Add `bin/omaloom-recordings`.
- Implement directory validation, deterministic sorting, metadata output, and action commands.
- Add focused tests for empty/missing directories, ordering, limits, special characters, non-MP4 files, missing files, and action command failures.

### Phase 2 — library list

- Load recordings when setup opens.
- Add a compact scrollable library list with Open/Reveal/Copy actions on each row.
- Add concise success/error feedback and useful empty/loading/error states.
- Confirm state recovers after a shell restart.

### Phase 3 — bounded dashboard integration

- Keep library row height compact and list growth bounded by scrolling.
- Reuse the same safe actions; do not add deletion in this milestone.

### Phase 4 — stabilization and documentation

- Test stop through Omarchy's top-center control.
- Test output paths containing spaces and Unicode.
- Test a deleted/moved recording between list refresh and action.
- Verify multi-monitor widget instances converge by rescanning the same folder.
- Update README, architecture, and the v1 plan.

## Acceptance criteria

- The newest finalized MP4 appears after stopping a recording.
- The latest recording remains discoverable after restarting Quickshell.
- Open launches the selected MP4.
- Reveal opens its location in the file manager.
- Copy path places the exact absolute path on the clipboard.
- Recordings are ordered newest first; `--limit 0` returns all MP4s in the selected folder.
- Missing directories, empty folders, deleted files, and action failures do not crash or block recording.
- Saved-file controls never appear over active capture and do not change `REC` or stop behavior.
- No cloud API, sharing link, thumbnail generation, deletion, or custom media processing is introduced.

## Deferred

- Persistent cross-folder history
- Thumbnails generated by Omaloom
- Duration probing
- Rename and delete actions
- Cloud links and upload state
- Search, pagination, and filtering

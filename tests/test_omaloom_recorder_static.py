#!/usr/bin/env python3
import pathlib
import re

ROOT = pathlib.Path(__file__).resolve().parents[1]
RECORDER = ROOT / "bin" / "omaloom-recorder"


def test_recording_file_only_managed_by_state_helper():
    text = RECORDER.read_text(encoding="utf-8")
    assert '>"$RECORDING_FILE"' not in text
    assert '> "$RECORDING_FILE"' not in text
    assert re.search(r"\becho\s+.*RECORDING_FILE", text) is None
    assert '"$STATE_HELPER" reserve "$RECORDING_FILE"' in text
    assert '"$STATE_HELPER" read "$RECORDING_FILE"' in text
    assert '"$STATE_HELPER" remove "$RECORDING_FILE"' in text


def test_start_recording_installs_cleanup_trap_before_effects():
    text = RECORDER.read_text(encoding="utf-8")
    start = text.index("start_recording() {")
    trap = text.index("trap cleanup_start_on_exit EXIT", start)
    select = text.index('target=$(select_capture_target "$fullscreen")', start)
    webcam = text.index('start_webcam_overlay "$target"', start)
    countdown = text.index("\n  countdown", start)
    reserve = text.index('state_reserve "$filename"', start)
    assert trap < select < reserve < webcam < countdown
    cleanup_body = text[text.index("cleanup_start_on_exit() {"):text.index("is_recording() {")]
    assert "cleanup_webcam" in cleanup_body
    assert "state_remove_if_owned" in cleanup_body
    assert "output_remove_if_owned" in cleanup_body


def test_webcam_preparation_has_single_placement_and_no_settle_sleep():
    text = RECORDER.read_text(encoding="utf-8")
    webcam = text[text.index("start_webcam_overlay() {"):text.index("toggle_screenrecording_indicator() {")]
    assert "omarchy-capture-webcam-resize" not in webcam
    assert webcam.count('"$SCRIPT_DIR/omaloom-webcam-placement" apply') == 1
    assert "sleep 1" not in webcam
    assert "camera_busy=false" in webcam
    assert webcam.count('fuser "$webcam_device"') == 1


def test_countdown_fast_path_is_prepared_and_event_checked():
    text = RECORDER.read_text(encoding="utf-8")
    start = text[text.index("start_recording() {"):text.index("stop_recording() {")]
    prepared = start.index("profile recording_prepared")
    webcam_ready = start.index("profile capture_devices_ready")
    countdown = start.index("\n  countdown")
    spawned = start.index("profile recorder_spawned")
    pre_capture_camera_check = start.index('[[ $webcam == true ]] && ! webcam_overlay_ready')
    confirmed = start.index("profile recording_confirmed")
    assert prepared < webcam_ready < countdown < pre_capture_camera_check < spawned < confirmed
    assert "sleep 0.8" not in start
    assert "[[ ! -s $filename ]]" in start
    assert "sleep 0.12" in start


def test_recording_requires_preselected_existing_output_directory():
    text = RECORDER.read_text(encoding="utf-8")
    start = text[text.index("start_recording() {"):text.index("stop_recording() {")]
    assert 'local directory=""' in start
    assert 'fail "choose an output directory before recording"' in start
    assert 'fail "selected output directory does not exist:' in start
    assert "mkdir -p" not in start
    assert "DEFAULT_DIR" not in text


def test_webcam_cleanup_does_not_use_broad_pkill():
    text = RECORDER.read_text(encoding="utf-8")
    assert "pkill -f 'WebcamOverlay'" not in text
    assert 'pgrep -u "$UID"' in text


if __name__ == "__main__":
    test_recording_file_only_managed_by_state_helper()
    test_start_recording_installs_cleanup_trap_before_effects()
    test_webcam_preparation_has_single_placement_and_no_settle_sleep()
    test_countdown_fast_path_is_prepared_and_event_checked()
    test_recording_requires_preselected_existing_output_directory()
    test_webcam_cleanup_does_not_use_broad_pkill()
    print("recorder static tests passed")

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
    assert trap < select < webcam < countdown < reserve
    cleanup_body = text[text.index("cleanup_start_on_exit() {"):text.index("is_recording() {")]
    assert "cleanup_webcam" in cleanup_body
    assert "state_remove_if_owned" in cleanup_body
    assert "output_remove_if_owned" in cleanup_body


def test_webcam_cleanup_does_not_use_broad_pkill():
    text = RECORDER.read_text(encoding="utf-8")
    assert "pkill -f 'WebcamOverlay'" not in text
    assert 'pgrep -u "$UID"' in text


if __name__ == "__main__":
    test_recording_file_only_managed_by_state_helper()
    test_start_recording_installs_cleanup_trap_before_effects()
    test_webcam_cleanup_does_not_use_broad_pkill()
    print("recorder static tests passed")

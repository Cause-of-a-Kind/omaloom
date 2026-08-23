#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BAR = ROOT / "qml" / "BarWidget.qml"


def test_camera_availability_state_machine_and_poll_no_flicker():
    text = BAR.read_text(encoding="utf-8")
    assert 'property string webcamAvailabilityState: "disabled"' in text
    assert "webcamAvailabilityInFlight" in text
    assert 'webcamAvailabilityState = "starting"' in text
    assert 'webcamAvailabilityState = "ready"' in text
    assert 'webcamAvailabilityState = "busy"' in text
    assert 'webcamAvailabilityState = "error"' in text
    assert 'readonly property bool webcamBlocksStart: omaloomSettings.recordWebcam && webcamAvailabilityState !== "ready"' in text
    assert '[devicesHelper, "check-camera", device]' in text
    assert "running: root.opened && root.setupResourcesActive && omaloomSettings.recordWebcam" in text
    poll_block = text[text.index("function refreshWebcamAvailability") : text.index("function refreshDevices")]
    assert "if (reset || newTarget || webcamAvailabilityState === \"disabled\")" in poll_block
    assert "webcamAvailabilityState = \"starting\"" in poll_block


def test_camera_selection_toggle_loading_and_single_setup_status_text():
    text = BAR.read_text(encoding="utf-8")
    assert "property bool webcamDevicesLoaded: false" in text
    assert "webcamDevicesLoaded = false" in text
    assert "webcamDevicesLoaded = true" in text
    assert "onRecordWebcamChanged: root.resetWebcamAvailability()" in text
    assert "onWebcamDeviceChanged: root.resetWebcamAvailability()" in text
    assert "No camera found. Connect a camera or turn off webcam overlay." in text
    assert "text: root.displayedStatusText()" in text
    assert text.count("text: root.displayedStatusText()") == 1
    assert "root.webcamAvailabilityWarning" not in text
    assert "root.webcamAvailabilityBusy" not in text
    assert "root.lastMessage\n      color:" not in text


def test_preparation_and_starting_never_flash_setup_dashboard():
    text = BAR.read_text(encoding="utf-8")
    source_block = text[text.index('if (text.indexOf(\'"source_selected"\')'):text.index('else if (text.indexOf(\'"countdown"\')')]
    countdown_block = text[text.index('else if (text.indexOf(\'"countdown"\')'):text.index('else if (text.indexOf(\'"event":"starting"\')')]
    starting_block = text[text.index('else if (text.indexOf(\'"event":"starting"\')'):text.index('else if (text.indexOf(\'"recording_started"\')')]
    assert "root.open()" not in source_block
    assert "if (!root.opened) root.open()" in countdown_block
    assert starting_block.index("root.close()") < starting_block.index('state = "starting"')
    assert "visible: root.countdown || root.starting" in text
    assert "visible: !root.countdown && !root.starting" in text


def test_countdown_transitions_from_one_directly_to_confirmed_rec():
    text = BAR.read_text(encoding="utf-8")
    widget = text[text.index("WidgetButton {"):text.index("KeyboardPanel {")]
    assert 'root.countdown || root.starting ? String(root.countdownRemaining)' in widget
    assert 'root.recording ? "REC"' in widget
    assert '"GO"' not in text


def test_camera_busy_warning_and_structured_backend_error_reopen():
    text = BAR.read_text(encoding="utf-8")
    warning = "Camera is in use by another application. Close it or choose a different camera."
    assert warning in text
    update_error_block = text[text.index("else if (text.indexOf('\"error\"')") : text.index("implicitWidth:")]
    assert "webcamAvailabilityState" in update_error_block
    assert "root.open()" in update_error_block
    stderr_block = text[text.index("stderr: SplitParser", text.index("id: actionProcess")) : text.index("WidgetButton {")]
    assert "JSON.parse(text)" in stderr_block
    assert "webcamAvailabilityState" in stderr_block
    assert "root.open()" in stderr_block


if __name__ == "__main__":
    test_camera_availability_state_machine_and_poll_no_flicker()
    test_camera_selection_toggle_loading_and_single_setup_status_text()
    test_preparation_and_starting_never_flash_setup_dashboard()
    test_countdown_transitions_from_one_directly_to_confirmed_rec()
    test_camera_busy_warning_and_structured_backend_error_reopen()
    print("bar widget static tests passed")

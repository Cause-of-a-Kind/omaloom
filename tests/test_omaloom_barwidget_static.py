#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BAR = ROOT / "qml" / "BarWidget.qml"


def test_configuration_is_not_blocked_by_camera_recording_readiness():
    text = BAR.read_text(encoding="utf-8")
    assert "readonly property bool canConfigure:" in text
    assert "readonly property bool canStart: canConfigure && outputDirectoryReady && !webcamBlocksStart" in text
    assert "if (folderPickerProcess.running || folderPickerLaunchDelay.running || !canConfigure) return" in text
    folder = text[text.index('label: "Folder"'):text.index('label: "Current monitor / fullscreen"')]
    assert "enabled: root.canConfigure" in folder
    assert "enabled: root.canStart" not in folder
    assert text.count("enabled: root.canStart") == 1


def test_record_setup_scrolls_within_small_popup_height():
    text = BAR.read_text(encoding="utf-8")
    record = text[text.index("component RecordDashboardColumn:"):text.index("component LibraryDashboardColumn:")]
    assert "component RecordDashboardColumn: Item" in record
    assert "Flickable {" in record
    assert "contentHeight: recordColumn.implicitHeight" in record
    assert "interactive: contentHeight > height" in record
    assert "boundsBehavior: Flickable.StopAtBounds" in record
    assert "ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }" in record
    assert 'label: root.state === "error" || root.state === "saved" ? "Start again" : "Start recording"' in record


def test_folder_picker_launches_only_after_overlay_unmaps():
    text = BAR.read_text(encoding="utf-8")
    open_block = text[text.index("function openFolderPicker() {"):text.index("function launchFolderPicker() {")]
    launch_block = text[text.index("function launchFolderPicker() {"):text.index("function hideRegionGuide() {")]
    assert open_block.index("root.close()") < open_block.index("folderPickerLaunchDelay.restart()")
    assert "folderPickerProcess.running = true" not in open_block
    assert 'folderPickerProcess.command = [folderPicker, "--current", omaloomSettings.outputDirectory]' in launch_block
    assert "id: folderPickerLaunchDelay" in text
    assert "interval: 180" in text


def test_first_run_requires_valid_explicit_output_folder():
    text = BAR.read_text(encoding="utf-8")
    assert 'property string outputDirectoryState: "missing"' in text
    assert 'value: omaloomSettings.outputDirectory === "" ? "Choose a folder"' in text
    assert '[outputHelper, "validate-directory", directory]' in text
    assert 'return "Choose an output folder before recording."' in text
    assert "outputDirectoryReady" in text


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
    test_configuration_is_not_blocked_by_camera_recording_readiness()
    test_record_setup_scrolls_within_small_popup_height()
    test_folder_picker_launches_only_after_overlay_unmaps()
    test_first_run_requires_valid_explicit_output_folder()
    test_camera_availability_state_machine_and_poll_no_flicker()
    test_camera_selection_toggle_loading_and_single_setup_status_text()
    test_preparation_and_starting_never_flash_setup_dashboard()
    test_countdown_transitions_from_one_directly_to_confirmed_rec()
    test_camera_busy_warning_and_structured_backend_error_reopen()
    print("bar widget static tests passed")

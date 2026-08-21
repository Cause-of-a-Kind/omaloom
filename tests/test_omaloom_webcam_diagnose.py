#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "omaloom-webcam-diagnose"
loader = importlib.machinery.SourceFileLoader("omaloom_webcam_diagnose", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


def test_busy_logs_are_clear():
    assert module.message_for_log("ioctl VIDIOC_STREAMON failed: Device or resource busy") == "camera is already in use by another application"
    assert module.message_for_log("Resource temporarily unavailable") == "camera is already in use by another application"


def test_other_open_failures_are_useful():
    assert module.message_for_log("Cannot open video device /dev/video9") == "unable to start webcam overlay; camera could not be opened"
    assert module.message_for_log("ioctl(VIDIOC_QBUF): Inappropriate ioctl for device") == "unable to start webcam overlay; camera could not be opened"
    assert module.message_for_log("totally unrelated failure") == "unable to start webcam overlay"


def test_cli_reads_log_file():
    with tempfile.TemporaryDirectory() as tmp:
        log = pathlib.Path(tmp) / "webcam.log"
        log.write_text("Failed to open /dev/video0: Device or resource busy", encoding="utf-8")
        proc = subprocess.run([str(HELPER), str(log)], text=True, capture_output=True, check=True)
        assert proc.stdout.strip() == "camera is already in use by another application"


if __name__ == "__main__":
    test_busy_logs_are_clear()
    test_other_open_failures_are_useful()
    test_cli_reads_log_file()
    print("webcam diagnose tests passed")

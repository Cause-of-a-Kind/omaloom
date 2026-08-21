#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import json
import os
import pathlib
import stat
import subprocess
import tempfile
import types

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "omaloom-devices"
loader = importlib.machinery.SourceFileLoader("omaloom_devices", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


def load(command):
    proc = subprocess.run([str(HELPER), command], text=True, capture_output=True, check=True)
    return json.loads(proc.stdout)


def assert_device_list(devices):
    assert isinstance(devices, list)
    for device in devices:
        assert isinstance(device, dict)
        assert isinstance(device.get("id"), str)
        assert isinstance(device.get("label"), str)
        assert device["id"]
        assert device["label"]


def test_camera_availability_reports_busy_same_user_and_ignores_self_parent():
    with tempfile.TemporaryDirectory() as tmp:
        proc = pathlib.Path(tmp)
        dev = "/dev/video-test"
        for pid in (111, 222, 333):
            fd_dir = proc / str(pid) / "fd"
            fd_dir.mkdir(parents=True)
            (fd_dir / "5").symlink_to(dev)
        original_stat = module.os.stat
        original_uid = module.process_uid
        original_name = module.process_name
        try:
            module.os.stat = lambda path: types.SimpleNamespace(st_mode=stat.S_IFCHR | 0o600, st_rdev=99) if str(path) == dev else original_stat(path)
            module.process_uid = lambda pid: os.getuid()
            module.process_name = lambda pid: "ignored" if pid in (111, 222) else "camera-app"
            payload = module.camera_availability(dev, ignore_pids={111, 222}, proc_root=proc)
            assert payload["busy"] is True
            assert payload["available"] is False
            assert [owner["pid"] for owner in payload["owners"]] == [333]
            assert "Camera is in use" in payload["message"]
        finally:
            module.os.stat = original_stat
            module.process_uid = original_uid
            module.process_name = original_name


def test_camera_availability_fails_safely_for_invalid_device():
    payload = module.camera_availability("not-a-camera", ignore_pids=set(), proc_root=pathlib.Path("/proc"))
    assert payload["busy"] is True
    assert payload["available"] is False
    assert "error" in payload


def test_device_lists_are_json_arrays():
    microphones = load("list-microphones")
    webcams = load("list-webcams")
    assert_device_list(microphones)
    assert_device_list(webcams)
    assert microphones[0]["id"] == "default_input"


if __name__ == "__main__":
    test_camera_availability_reports_busy_same_user_and_ignores_self_parent()
    test_camera_availability_fails_safely_for_invalid_device()
    test_device_lists_are_json_arrays()
    print("device tests passed")

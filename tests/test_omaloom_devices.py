#!/usr/bin/env python3
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "omaloom-devices"


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


def test_device_lists_are_json_arrays():
    microphones = load("list-microphones")
    webcams = load("list-webcams")
    assert_device_list(microphones)
    assert_device_list(webcams)
    assert microphones[0]["id"] == "default_input"


if __name__ == "__main__":
    test_device_lists_are_json_arrays()
    print("device tests passed")

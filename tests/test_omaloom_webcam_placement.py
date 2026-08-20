#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import json
import pathlib
import subprocess
import types

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "omaloom-webcam-placement"
loader = importlib.machinery.SourceFileLoader("omaloom_webcam_placement", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)

MONITORS = [
    {"id": 1, "name": "LEFT", "x": -1280, "y": 0, "width": 1280, "height": 720, "scale": 1, "transform": 0},
    {"id": 2, "name": "MAIN", "x": 0, "y": 0, "width": 3840, "height": 2160, "scale": 1.5, "transform": 0},
    {"id": 3, "name": "ROT", "x": 2560, "y": 0, "width": 1920, "height": 1080, "scale": 1, "transform": 1},
]


def test_all_corners_for_region():
    anchor = {"x": 100, "y": 200, "width": 1000, "height": 800}
    small = module.placement(anchor, "small", "top-left")
    assert small["x"] == 140 and small["y"] == 240
    assert module.placement(anchor, "small", "top-right")["x"] == 100 + 1000 - small["width"] - 40
    assert module.placement(anchor, "small", "bottom-left")["y"] == 200 + 800 - small["height"] - 40
    br = module.placement(anchor, "small", "bottom-right")
    assert br["x"] > small["x"] and br["y"] > small["y"]


def test_size_ladder_matches_omarchy_anchor_height():
    anchor = {"x": 0, "y": 0, "width": 1920, "height": 1080}
    assert module.size_for(anchor, "small")["height"] == 194
    assert module.size_for(anchor, "medium")["height"] == 270
    assert module.size_for(anchor, "large")["height"] == 365


def test_compute_region_negative_and_monitor_scaled_rotated():
    rect = module.compute("region:400x300+-100+50", json.dumps(MONITORS), "medium", "bottom-right")
    assert rect["x"] < 260 and rect["y"] > 50

    mon = module.compute("monitor:MAIN", json.dumps(MONITORS), "large", "top-left", monitor_id=1)
    # An explicit capture target takes precedence if mpv initially maps on a
    # different monitor before Omaloom moves it into place.
    assert mon["x"] == 40 and mon["y"] == 40
    assert mon["height"] == 486  # 2160/1.5 * 27/80 rounded

    rot = module.anchor_for("monitor:ROT", MONITORS)
    assert rot["width"] == 1080 and rot["height"] == 1920


def test_dispatch_prefers_omarchy_lua_commands():
    calls = []
    original_run = module.subprocess.run
    try:
        module.subprocess.run = lambda argv, **kwargs: (calls.append(argv) or types.SimpleNamespace(returncode=0))
        module.dispatch_window("0xabc123", {"x": -120, "y": 50, "width": 160, "height": 180})
    finally:
        module.subprocess.run = original_run

    assert calls == [
        ["hyprctl", "dispatch", 'hl.dsp.window.resize({ window = "address:0xabc123", x = 160, y = 180 })'],
        ["hyprctl", "dispatch", 'hl.dsp.window.move({ window = "address:0xabc123", x = -120, y = 50 })'],
    ]


def test_cli_compute_json():
    proc = subprocess.run(
        [str(HELPER), "compute", "--target", "monitor:MAIN", "--size", "medium", "--position", "bottom-right", "--monitors-json", json.dumps(MONITORS)],
        text=True,
        capture_output=True,
        check=True,
    )
    payload = json.loads(proc.stdout)
    assert payload["width"] > 0 and payload["height"] > 0


if __name__ == "__main__":
    test_all_corners_for_region()
    test_size_ladder_matches_omarchy_anchor_height()
    test_compute_region_negative_and_monitor_scaled_rotated()
    test_dispatch_prefers_omarchy_lua_commands()
    test_cli_compute_json()
    print("webcam placement tests passed")

#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "omaloom-geometry"
loader = importlib.machinery.SourceFileLoader("omaloom_geometry", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)

MONITORS = [
    {"name": "LEFT", "x": -1280, "y": 0, "width": 1280, "height": 720, "scale": 1},
    {"name": "MAIN", "x": 0, "y": 0, "width": 3840, "height": 2160, "scale": 1.5},
    {"name": "TOP", "x": 0, "y": -900, "width": 1600, "height": 900, "scale": 1},
]


def test_parse_negative_region_target():
    assert module.parse_region_target("region:640x360+-1200+20") == {
        "x": -1200,
        "y": 20,
        "width": 640,
        "height": 360,
    }


def test_monitor_mapping_spans_negative_and_primary():
    guide = module.guide_for("region:400x300+-100+50", json.dumps(MONITORS))
    assert [monitor["name"] for monitor in guide["monitors"]] == ["LEFT", "MAIN"]
    assert guide["region"] == {"x": -100, "y": 50, "width": 400, "height": 300}


def test_monitor_dimensions_are_logical_and_transform_aware():
    monitors = module.normalized_monitors([
        {"name": "SCALED", "x": 0, "y": 0, "width": 3840, "height": 2160, "scale": 1.5, "transform": 0},
        {"name": "ROTATED", "x": 2560, "y": 0, "width": 1920, "height": 1080, "scale": 1, "transform": 1},
    ])
    assert monitors[0]["width"] == 2560
    assert monitors[0]["height"] == 1440
    assert monitors[1]["width"] == 1080
    assert monitors[1]["height"] == 1920


def test_source_selected_event_includes_guide_only_for_regions():
    region_event = module.source_selected_event("region:100x100+10+10", json.dumps(MONITORS))
    assert region_event["event"] == "source_selected"
    assert region_event["guide"]["type"] == "region"

    monitor_event = module.source_selected_event("monitor:DP-1", json.dumps(MONITORS))
    assert monitor_event == {"event": "source_selected", "target": "monitor:DP-1"}


def test_controlled_path_fails_closed_for_hyprctl_lookup():
    original = module.shutil.which
    module.shutil.which = lambda command, path=None: None
    try:
        try:
            module.load_hyprctl_monitors()
        except module.GeometryError as exc:
            assert "controlled PATH" in str(exc)
        else:
            raise AssertionError("bare hyprctl fallback should not be used")
    finally:
        module.shutil.which = original


def test_cli_outputs_machine_json():
    proc = subprocess.run(
        [str(HELPER), "guide", "region:100x100+10+10", "--monitors-json", json.dumps(MONITORS)],
        text=True,
        capture_output=True,
        check=True,
    )
    payload = json.loads(proc.stdout)
    assert payload["type"] == "region"
    assert payload["monitors"][0]["name"] == "MAIN"

    proc = subprocess.run(
        [str(HELPER), "source-selected", "region:100x100+10+10", "--monitors-json", json.dumps(MONITORS)],
        text=True,
        capture_output=True,
        check=True,
    )
    event = json.loads(proc.stdout)
    assert event["event"] == "source_selected"
    assert event["guide"]["region"] == {"x": 10, "y": 10, "width": 100, "height": 100}


if __name__ == "__main__":
    test_parse_negative_region_target()
    test_monitor_mapping_spans_negative_and_primary()
    test_monitor_dimensions_are_logical_and_transform_aware()
    test_source_selected_event_includes_guide_only_for_regions()
    test_controlled_path_fails_closed_for_hyprctl_lookup()
    test_cli_outputs_machine_json()
    print("geometry tests passed")

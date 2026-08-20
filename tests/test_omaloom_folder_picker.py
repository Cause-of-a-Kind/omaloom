#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "omaloom-folder-picker"

loader = importlib.machinery.SourceFileLoader("omaloom_folder_picker", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


def test_local_file_uri_decoding():
    assert module.local_path_from_uri("file:///home/m/Videos/Omaloom") == "/home/m/Videos/Omaloom"
    assert module.local_path_from_uri("file://localhost/tmp/a%20b") == "/tmp/a b"
    assert module.first_selected_path({"uris": ["file:///tmp/camera%20tests"]}) == "/tmp/camera tests"


def test_rejects_nonlocal_uri():
    try:
        module.local_path_from_uri("trash:///foo")
    except module.PickerError:
        pass
    else:
        raise AssertionError("non-file URI should be rejected")

    try:
        module.local_path_from_uri("file://remote.example/tmp")
    except module.PickerError:
        pass
    else:
        raise AssertionError("remote file URI should be rejected")


def test_decode_uri_cli_outputs_json():
    proc = subprocess.run(
        [str(HELPER), "--decode-uri", "file:///tmp/Omaloom%20Folder"],
        text=True,
        capture_output=True,
        check=True,
    )
    assert json.loads(proc.stdout) == {"path": "/tmp/Omaloom Folder"}


if __name__ == "__main__":
    test_local_file_uri_decoding()
    test_rejects_nonlocal_uri()
    test_decode_uri_cli_outputs_json()
    print("folder picker tests passed")

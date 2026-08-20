#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "omaloom-settings"


def run(home, *args):
    env = os.environ.copy()
    env["HOME"] = str(home)
    return subprocess.run([str(HELPER), *args], env=env, text=True, capture_output=True, check=True)


def test_absent_and_malformed_defaults_then_merge_set():
    with tempfile.TemporaryDirectory() as tmp:
        home = pathlib.Path(tmp)
        defaults = json.loads(run(home, "load").stdout)
        assert defaults == {
            "outputDirectory": str(home / "Videos" / "Omaloom"),
            "fullscreenCurrentMonitor": False,
            "systemAudio": True,
            "microphone": True,
            "webcam": False,
            "microphoneDevice": "",
            "webcamDevice": "",
        }

        settings_path = home / ".config" / "omaloom" / "settings.json"
        settings_path.parent.mkdir(parents=True, exist_ok=True)
        settings_path.write_text('{"systemAudio": "yes", broken', encoding="utf-8")
        assert json.loads(run(home, "load").stdout) == defaults

        after_audio = json.loads(run(home, "set", "systemAudio", "false").stdout)
        after_device = json.loads(run(home, "set", "microphoneDevice", "alsa_input.test").stdout)
        after_mic = json.loads(run(home, "set", "microphone", "false").stdout)
        assert after_audio["systemAudio"] is False
        assert after_device["microphoneDevice"] == "alsa_input.test"
        assert after_mic["systemAudio"] is False
        assert after_mic["microphone"] is False
        assert after_mic["microphoneDevice"] == "alsa_input.test"
        assert json.loads(settings_path.read_text(encoding="utf-8")) == after_mic


def test_rejects_unknown_key_without_shell_parsing():
    with tempfile.TemporaryDirectory() as tmp:
        home = pathlib.Path(tmp)
        env = os.environ.copy()
        env["HOME"] = str(home)
        proc = subprocess.run(
            [str(HELPER), "set", "bad;touch /tmp/nope", "true"],
            env=env,
            text=True,
            capture_output=True,
        )
        assert proc.returncode == 2
        assert not (home / ".config" / "omaloom" / "settings.json").exists()


if __name__ == "__main__":
    test_absent_and_malformed_defaults_then_merge_set()
    test_rejects_unknown_key_without_shell_parsing()
    print("settings tests passed")

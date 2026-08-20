#!/usr/bin/env python3
import json
import os
import pathlib
import subprocess
import tempfile
import time

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "omaloom-recordings"


def run(*args, env=None, check=True):
    merged = os.environ.copy()
    if env:
        merged.update(env)
    return subprocess.run([str(HELPER), *args], text=True, capture_output=True, env=merged, check=check)


def touch(path, text, mtime):
    path.write_text(text, encoding="utf-8")
    os.utime(path, (mtime, mtime))


def wait_for_text(path, timeout=2.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if path.exists():
            return path.read_text(encoding="utf-8")
        time.sleep(0.02)
    raise AssertionError(f"timed out waiting for {path}")


def argv_recorder_script(path, output):
    path.write_text(
        f"#!/usr/bin/env python3\nimport json,pathlib,sys\npathlib.Path({str(output)!r}).write_text(json.dumps(sys.argv, ensure_ascii=False), encoding='utf-8')\n",
        encoding="utf-8",
    )
    path.chmod(0o755)


def test_list_empty_missing_ordering_limit_and_special_names():
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        missing = root / "missing"
        assert json.loads(run("list", "--directory", str(missing)).stdout) == {"recordings": []}

        now = int(time.time())
        touch(root / "old.mp4", "a", now - 20)
        touch(root / "new space ☃.MP4", "bbb", now)
        touch(root / "middle.mp4", "cc", now - 10)
        touch(root / "ignore.txt", "no", now + 100)
        (root / "sub.mp4").mkdir()

        payload = json.loads(run("list", "--directory", str(root), "--limit", "2").stdout)
        assert [item["name"] for item in payload["recordings"]] == ["new space ☃.MP4", "middle.mp4"]
        assert payload["recordings"][0]["size"] == 3
        assert pathlib.Path(payload["recordings"][0]["path"]).is_absolute()

        all_payload = json.loads(run("list", "--directory", str(root), "--limit", "0").stdout)
        assert [item["name"] for item in all_payload["recordings"]] == ["new space ☃.MP4", "middle.mp4", "old.mp4"]


def test_missing_and_non_mp4_action_failures_are_structured():
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        missing = root / "missing.mp4"
        proc = run("open", str(missing), check=False)
        assert proc.returncode == 2
        assert "error" in json.loads(proc.stderr)

        txt = root / "not-video.txt"
        txt.write_text("x", encoding="utf-8")
        proc = run("copy-path", str(txt), check=False)
        assert proc.returncode == 2
        assert "error" in json.loads(proc.stderr)


def test_open_uses_fake_opener_argv_and_special_character_path():
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        video = root / "open target spaces ☃ 'quote'.mp4"
        video.write_text("video", encoding="utf-8")
        output = root / "open-argv.json"
        opener = root / "fake-open.py"
        argv_recorder_script(opener, output)

        proc = run("open", str(video), env={"OMALOOM_OPEN_COMMAND": str(opener)})
        assert json.loads(proc.stdout)["ok"] is True
        assert json.loads(wait_for_text(output)) == [str(opener), str(video.resolve())]


def test_reveal_falls_back_to_fake_opener_argv_and_parent_path():
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        video_dir = root / "folder with spaces ☃"
        video_dir.mkdir()
        video = video_dir / "clip.mp4"
        video.write_text("video", encoding="utf-8")
        output = root / "reveal-argv.json"
        revealer = root / "fake-reveal.py"
        argv_recorder_script(revealer, output)
        fake_gdbus = root / "gdbus"
        fake_gdbus.write_text("#!/usr/bin/env sh\nexit 1\n", encoding="utf-8")
        fake_gdbus.chmod(0o755)

        proc = run(
            "reveal",
            str(video),
            env={"OMALOOM_REVEAL_COMMAND": str(revealer), "PATH": str(root) + os.pathsep + os.environ.get("PATH", "")},
        )
        assert json.loads(proc.stdout)["ok"] is True
        assert json.loads(wait_for_text(output)) == [str(revealer), str(video_dir.resolve())]


def test_copy_path_uses_argv_command_and_exact_path():
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        recorder = root / "fake-copy.py"
        output = root / "copied.txt"
        recorder.write_text(
            "#!/usr/bin/env python3\nimport pathlib,sys\npathlib.Path(sys.argv[1]).write_text(sys.stdin.read(), encoding='utf-8')\n",
            encoding="utf-8",
        )
        recorder.chmod(0o755)
        video = root / "weird name ☃.mp4"
        video.write_text("video", encoding="utf-8")
        proc = run("copy-path", str(video), env={"OMALOOM_COPY_COMMAND": str(recorder) + " " + str(output)}, check=False)
        # The helper must not split or shell-parse override strings with spaces.
        assert proc.returncode == 2

        wrapper = root / "copy-wrapper.py"
        wrapper.write_text(
            f"#!/usr/bin/env python3\nimport pathlib,sys\npathlib.Path({str(output)!r}).write_text(sys.stdin.read(), encoding='utf-8')\n",
            encoding="utf-8",
        )
        wrapper.chmod(0o755)
        proc = run("copy-path", str(video), env={"OMALOOM_COPY_COMMAND": str(wrapper)})
        assert json.loads(proc.stdout)["ok"] is True
        assert output.read_text(encoding="utf-8") == str(video.resolve())


if __name__ == "__main__":
    test_list_empty_missing_ordering_limit_and_special_names()
    test_missing_and_non_mp4_action_failures_are_structured()
    test_open_uses_fake_opener_argv_and_special_character_path()
    test_reveal_falls_back_to_fake_opener_argv_and_parent_path()
    test_copy_path_uses_argv_command_and_exact_path()
    print("recordings tests passed")

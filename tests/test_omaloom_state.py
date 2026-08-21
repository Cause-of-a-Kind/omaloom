#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import os
import pathlib
import stat
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "omaloom-state"
loader = importlib.machinery.SourceFileLoader("omaloom_state", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


def run(*args, check=True):
    return subprocess.run([str(HELPER), *args], text=True, capture_output=True, check=check)


def test_symlink_rejected_and_target_unchanged():
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        target = root / "target"
        state = root / "state"
        target.write_text("unchanged", encoding="utf-8")
        state.symlink_to(target)
        proc = run("reserve", str(state), "/tmp/video.mp4", check=False)
        assert proc.returncode == 2
        assert target.read_text(encoding="utf-8") == "unchanged"
        assert state.is_symlink()


def test_fifo_rejected_without_blocking():
    with tempfile.TemporaryDirectory() as tmp:
        state = pathlib.Path(tmp) / "state"
        os.mkfifo(state)
        proc = run("reserve", str(state), "/tmp/video.mp4", check=False)
        assert proc.returncode == 2


def test_owned_stale_regular_replaced_mode_0600_read_remove():
    with tempfile.TemporaryDirectory() as tmp:
        state = pathlib.Path(tmp) / "state"
        state.write_text("/tmp/old.mp4\n", encoding="utf-8")
        os.chmod(state, 0o644)
        run("reserve", str(state), "/tmp/new space ☃.mp4")
        st = state.lstat()
        assert stat.S_IMODE(st.st_mode) == 0o600
        assert run("read", str(state)).stdout.strip() == "/tmp/new space ☃.mp4"
        run("remove", str(state))
        assert not state.exists()


def test_exclusive_create_fails_if_race_recreates_path():
    with tempfile.TemporaryDirectory() as tmp:
        state = pathlib.Path(tmp) / "state"
        state.write_text("/tmp/old.mp4\n", encoding="utf-8")
        original_unlink = module.os.unlink

        def racing_unlink(path):
            original_unlink(path)
            pathlib.Path(path).write_text("/tmp/race.mp4\n", encoding="utf-8")

        module.os.unlink = racing_unlink
        try:
            try:
                module.reserve(str(state), "/tmp/new.mp4")
            except module.StateError as exc:
                assert "appeared during reserve" in str(exc)
            else:
                raise AssertionError("reserve should fail on recreated path")
        finally:
            module.os.unlink = original_unlink
        assert state.read_text(encoding="utf-8") == "/tmp/race.mp4\n"


def test_read_remove_reject_nonregular_and_missing():
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        missing = root / "missing"
        assert run("read", str(missing), check=False).returncode == 2
        directory = root / "dir"
        directory.mkdir()
        assert run("remove", str(directory), check=False).returncode == 2


if __name__ == "__main__":
    test_symlink_rejected_and_target_unchanged()
    test_fifo_rejected_without_blocking()
    test_owned_stale_regular_replaced_mode_0600_read_remove()
    test_exclusive_create_fails_if_race_recreates_path()
    test_read_remove_reject_nonregular_and_missing()
    print("state tests passed")

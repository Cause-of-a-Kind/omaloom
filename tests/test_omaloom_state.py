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


def test_existing_owned_state_is_exclusive_and_unchanged():
    with tempfile.TemporaryDirectory() as tmp:
        state = pathlib.Path(tmp) / "state"
        state.write_text("/tmp/old.mp4\n", encoding="utf-8")
        os.chmod(state, 0o600)
        proc = run("reserve", str(state), "/tmp/new space ☃.mp4", check=False)
        assert proc.returncode == 2
        assert "already reserved" in proc.stderr
        assert state.read_text(encoding="utf-8") == "/tmp/old.mp4\n"


def test_new_reservation_is_mode_0600_readable_and_removable():
    with tempfile.TemporaryDirectory() as tmp:
        state = pathlib.Path(tmp) / "state"
        run("reserve", str(state), "/tmp/new space ☃.mp4")
        assert stat.S_IMODE(state.lstat().st_mode) == 0o600
        assert run("read", str(state)).stdout.strip() == "/tmp/new space ☃.mp4"
        run("remove", str(state))
        assert not state.exists()


def test_exclusive_create_fails_if_path_appears_during_open():
    with tempfile.TemporaryDirectory() as tmp:
        state = pathlib.Path(tmp) / "state"
        original_open = module.os.open
        raced = False

        def racing_open(path, flags, mode=0o777):
            nonlocal raced
            if not raced and str(path) == str(state):
                raced = True
                fd = original_open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                os.close(fd)
            return original_open(path, flags, mode)

        module.os.open = racing_open
        try:
            try:
                module.reserve(str(state), "/tmp/new.mp4")
            except module.StateError as exc:
                assert "appeared during reserve" in str(exc)
            else:
                raise AssertionError("reserve should fail on a raced path")
        finally:
            module.os.open = original_open
        assert state.exists()


def test_concurrent_reservations_have_exactly_one_winner():
    with tempfile.TemporaryDirectory() as tmp:
        state = pathlib.Path(tmp) / "state"
        contenders = [
            subprocess.Popen([str(HELPER), "reserve", str(state), f"/tmp/video-{i}.mp4"], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            for i in range(2)
        ]
        results = [proc.communicate()[0:2] + (proc.returncode,) for proc in contenders]
        assert sorted(result[2] for result in results) == [0, 2]
        assert run("read", str(state)).stdout.strip() in {"/tmp/video-0.mp4", "/tmp/video-1.mp4"}


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
    test_existing_owned_state_is_exclusive_and_unchanged()
    test_new_reservation_is_mode_0600_readable_and_removable()
    test_exclusive_create_fails_if_path_appears_during_open()
    test_concurrent_reservations_have_exactly_one_winner()
    test_read_remove_reject_nonregular_and_missing()
    print("state tests passed")

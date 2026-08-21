#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import os
import pathlib
import stat
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "omaloom-runtime"
loader = importlib.machinery.SourceFileLoader("omaloom_runtime", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


def test_runtime_dir_rejects_group_world_writable_and_symlink():
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        good = root / "good"
        good.mkdir()
        os.chmod(good, 0o700)
        assert module.validate_dir(str(good)) == str(good.resolve())
        bad = root / "bad"
        bad.mkdir()
        os.chmod(bad, 0o770)
        try:
            module.validate_dir(str(bad))
        except module.RuntimeError_:
            pass
        else:
            raise AssertionError("group-writable runtime dir should be rejected")
        link = root / "link"
        link.symlink_to(good, target_is_directory=True)
        try:
            module.validate_dir(str(link))
        except module.RuntimeError_:
            pass
        else:
            raise AssertionError("symlink runtime dir should be rejected")


def test_pid_file_rejects_symlink_fifo_and_mode_0600_write_failure_for_non_mpv():
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        target = root / "target"
        target.write_text("123\n", encoding="utf-8")
        link = root / "pid"
        link.symlink_to(target)
        try:
            module.validate_pid_file(str(link))
        except module.RuntimeError_:
            pass
        else:
            raise AssertionError("symlink pid file should be rejected")
        fifo = root / "fifo"
        os.mkfifo(fifo)
        try:
            module.validate_pid_file(str(fifo))
        except module.RuntimeError_:
            pass
        else:
            raise AssertionError("fifo pid file should be rejected")
        pidfile = root / "newpid"
        try:
            module.write_pid(str(pidfile), str(os.getpid()))
        except module.RuntimeError_:
            pass
        else:
            raise AssertionError("non-mpv pid should be rejected")
        assert not pidfile.exists()


if __name__ == "__main__":
    test_runtime_dir_rejects_group_world_writable_and_symlink()
    test_pid_file_rejects_symlink_fifo_and_mode_0600_write_failure_for_non_mpv()
    print("runtime tests passed")

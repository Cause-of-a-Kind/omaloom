#!/usr/bin/env python3
import importlib.machinery
import importlib.util
import json
import os
import pathlib
import stat
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
HELPER = ROOT / "bin" / "omaloom-output"
loader = importlib.machinery.SourceFileLoader("omaloom_output", str(HELPER))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


def cli_reserve(directory):
    return pathlib.Path(subprocess.run([str(HELPER), "reserve", str(directory)], text=True, capture_output=True, check=True).stdout.strip())


def test_validate_directory_cli_reports_existing_and_rejects_missing():
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        os.chmod(root, 0o755)
        proc = subprocess.run([str(HELPER), "validate-directory", str(root)], text=True, capture_output=True, check=True)
        payload = json.loads(proc.stdout)
        assert payload == {"valid": True, "requested": str(root), "directory": str(root.resolve())}
        missing = root / "not-created"
        failed = subprocess.run([str(HELPER), "validate-directory", str(missing)], text=True, capture_output=True)
        assert failed.returncode == 2
        assert not missing.exists()


def test_reserve_unique_mode_0600_and_remove():
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        os.chmod(root, 0o755)
        path1 = cli_reserve(root)
        path2 = cli_reserve(root)
        assert path1 != path2
        assert path1.name.startswith("screenrecording-") and path1.suffix == ".mp4"
        assert stat.S_IMODE(path1.lstat().st_mode) == 0o600
        module.remove(str(path1))
        assert not path1.exists()


def test_reject_final_group_world_writable_and_nonregular_remove():
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        os.chmod(root, 0o777)
        try:
            module.reserve(str(root))
        except module.OutputError:
            pass
        else:
            raise AssertionError("world writable final dir should be rejected")

        fifo = root / "x.mp4"
        os.mkfifo(fifo)
        try:
            module.remove(str(fifo))
        except module.OutputError:
            pass
        else:
            raise AssertionError("fifo remove should be rejected")

        target = root / "keep.mp4"
        target.write_text("unchanged", encoding="utf-8")
        link = root / "linked.mp4"
        link.symlink_to(target)
        try:
            module.remove(str(link))
        except module.OutputError:
            pass
        else:
            raise AssertionError("symlink remove should be rejected")
        assert target.read_text(encoding="utf-8") == "unchanged"


def test_reject_ancestor_group_world_writable_nonsticky():
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        os.chmod(root, 0o770)
        child = root / "child"
        child.mkdir()
        os.chmod(child, 0o700)
        try:
            module.validate_directory(str(child))
        except module.OutputError as exc:
            assert "unsafe writable output path component" in str(exc)
        else:
            raise AssertionError("group-writable non-sticky ancestor should be rejected")


def test_owned_mode_755_directory_ok_and_exclusive_existing_name_fails():
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        good = root / "good"
        good.mkdir()
        os.chmod(good, 0o755)
        assert module.validate_directory(str(good)) == good.resolve()

        original = module.secrets.token_hex
        module.secrets.token_hex = lambda n: "fixed"
        try:
            name = "screenrecording-" + module.time.strftime("%Y-%m-%d_%H-%M-%S") + "-fixed.mp4"
            target = good / "target"
            target.write_text("unchanged", encoding="utf-8")
            (good / name).symlink_to(target)
            try:
                module.reserve(str(good))
            except module.OutputError:
                pass
            else:
                raise AssertionError("reserve should fail when every unpredictable candidate already exists")
            assert target.read_text(encoding="utf-8") == "unchanged"
        finally:
            module.secrets.token_hex = original


if __name__ == "__main__":
    test_validate_directory_cli_reports_existing_and_rejects_missing()
    test_reserve_unique_mode_0600_and_remove()
    test_reject_final_group_world_writable_and_nonregular_remove()
    test_reject_ancestor_group_world_writable_nonsticky()
    test_owned_mode_755_directory_ok_and_exclusive_existing_name_fails()
    print("output tests passed")

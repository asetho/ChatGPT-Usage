#!/usr/bin/env python3
"""Exercise the real macOS replacement helper using disposable background app bundles."""
import pathlib
import plistlib
import shlex
import subprocess
import tempfile
import time
import uuid

ROOT = pathlib.Path(__file__).resolve().parents[2]
HELPER = ROOT / "CodexUsage/Resources/install-update.sh"


def bundle(path, marker):
    executable = path / "Contents/MacOS/Fixture"
    executable.parent.mkdir(parents=True)
    executable.write_text("#!/bin/sh\ntouch " + shlex.quote(str(marker)) + "\n")
    executable.chmod(0o700)
    (path / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleIdentifier": "test.chatgptusage.updater." + uuid.uuid4().hex,
        "CFBundleExecutable": "Fixture", "CFBundlePackageType": "APPL", "LSUIElement": True,
    }))


def wait_for(path):
    deadline = time.monotonic() + 10
    while not path.exists():
        if time.monotonic() > deadline:
            raise AssertionError("Missing marker: " + str(path))
        time.sleep(0.1)


def scenario(root, success):
    directory = root / ("success's folder" if success else "rollback folder")
    directory.mkdir()
    target = directory / "ChatGPT Usage.app"
    stage = directory / ".ChatGPTUsage-update-test.app"
    backup = directory / ".ChatGPTUsage-backup-test.app"
    transaction = directory / "transaction"
    transaction.mkdir()
    pending = directory / "pending.json"
    error = directory / "last-error.txt"
    restored = directory / "old-app-opened"
    bundle(target, restored)
    bundle(stage, transaction / ("launched" if success else "no-ack"))
    pending.write_text("fixture")
    parent = subprocess.Popen(["/bin/sleep", "60"])
    try:
        helper = subprocess.Popen(["/bin/sh", str(HELPER), str(parent.pid), str(target), str(stage),
                                   str(backup), str(transaction), str(pending), str(error)])
        wait_for(transaction / "ready")
        assert target.exists() and stage.exists() and not backup.exists(), "Replaced app before parent exited"
        parent.terminate()
        parent.wait()
        result = helper.wait(timeout=45)
        assert target.exists() and not backup.exists() and not pending.exists()
        if success:
            assert result == 0 and not error.exists() and not transaction.exists()
            assert not restored.exists(), "Opened previous app during successful update"
        else:
            assert result == 1 and "previous version was restored" in error.read_text()
            assert (transaction / "failed.app").exists()
            wait_for(restored)
        print("PASS: " + ("replace, restart and cleanup" if success else "failed launch restores and reopens previous app"))
    finally:
        if parent.poll() is None:
            parent.terminate()
            parent.wait()


with tempfile.TemporaryDirectory(prefix="chatgpt-usage-update-", dir=ROOT / "build") as temporary:
    root = pathlib.Path(temporary)
    scenario(root, True)
    scenario(root, False)

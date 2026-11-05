"""Real Quickshell FileView integration with temporary journals and fake effects.

Never instantiate Service, run desktop commands, or use the installed journal.
Exercise initial load/missing/invalid data, actual saved/saveFailed signals,
unchanged-text suppression, and revision-based acknowledgment. Check disk bytes
after Quickshell exits; this is not a crash/fsync or hardware durability test.
"""
from pathlib import Path
import shutil
import json
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="station-workspace-fileview-") as directory:
    root = Path(directory)
    probe = root / "Probe"
    probe.mkdir()
    shutil.copytree(repo / "lib", probe, dirs_exist_ok=True)
    for name in ("valid", "invalid", "missing", "failure"):
        (root / name).mkdir()
    baseline = dict(version=1, **{"from": {"outputs": ["A"]}}, to={"outputs": ["A"]},
                    station=3, windows=[dict(address="0x" + str(i), pid=i, initialClass="test",
                        station=i, output="A", to=i) for i in range(1, 5)])
    pending = dict(baseline, to={"outputs": ["A", "B"]}, windows=[dict(
        row, to=(row["station"] - 1) * 2 + 1) for row in baseline["windows"]])
    # Same schema emitted by the pinned pre-M5 functions, including recovery data.
    (root / "valid/workspace-map.json").write_text(json.dumps(dict(
        mapping={"outputs": ["A"]}, pending=pending, preview=baseline, revision=7)))
    (root / "invalid/workspace-map.json").write_text('{"mapping":{"outputs":[]}}')
    # A directory at the destination causes actual FileView save failure.
    (root / "failure/workspace-map.json").mkdir()
    qml = (repo / "test/qml/fixtures/workspace-fileview.qml").read_text()
    (root / "shell.qml").write_text(qml.replace("__TEMP_DIRECTORY__", json.dumps(str(root))))
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    environment = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
                       XDG_RUNTIME_DIR=str(runtime))
    environment.pop("WAYLAND_DISPLAY", None)
    result = subprocess.run(
        ["quickshell", "--no-color", "-p", str(root)],
        env=environment,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=15)
    print(result.stdout)
    if result.returncode or "WORKSPACE_FILEVIEW_PASS" not in result.stdout:
        raise SystemExit(1)
    journal = json.loads((root / "valid/workspace-map.json").read_text())
    assert (root / "valid/workspace-map.json").read_text() == json.dumps(journal, indent=2) + "\n"
    assert journal == dict(mapping={"outputs": ["A", "B"]}, pending=None, preview=None, revision=10), journal
    assert not (root / "missing/workspace-map.json").exists()
    assert (root / "invalid/workspace-map.json").read_text() == '{"mapping":{"outputs":[]}}'
    assert (root / "failure/workspace-map.json").is_dir()
    print("WORKSPACE_DISK_BYTES_PASS: committed map, revision 10; other fixtures preserved")

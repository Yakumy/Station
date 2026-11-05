"""Real display FileViews on temporary paths; Process/StdioCollector are doubled.

Only import qualification changes in the temporary production-owner copy.
No native Process can execute its command. No Service, compositor effect,
watchdog process, installed journal or user configuration is instantiated.
"""
from pathlib import Path
import shutil
import json
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="station-display-files-") as folder:
    root = Path(folder)
    probe = root / "Probe"
    effects = probe / "Effects"
    effects.mkdir(parents=True)
    shutil.copytree(repo / "lib", probe, dirs_exist_ok=True)
    owner = (repo / "lib/displays/DisplayController.qml").read_text()
    assert owner.count("  Process {") == 2 and owner.count("StdioCollector {") == 1
    owner = owner.replace("import Quickshell.Io", 'import Quickshell.Io as RealIo\nimport "../Effects" as FakeIo')
    owner = owner.replace("  FileView {", "  RealIo.FileView {")
    owner = owner.replace("  Process {", "  FakeIo.Process {").replace("StdioCollector {", "FakeIo.StdioCollector {")
    (probe / "displays/DisplayController.qml").write_text(owner)
    (effects / "Process.qml").write_text('''import QtQuick
Item {
  property var command: []
  property bool running: false
  property var stderr: null
  signal exited(int code)
  function finish(code) { running=false; exited(code) }
}
''')
    (effects / "StdioCollector.qml").write_text('''import QtQuick
QtObject {
  property bool waitForEnd: false
  property string text: ""
  signal streamFinished()
}
''')
    (root / "state").mkdir()
    (root / "blocked.candidate").mkdir()
    (root / "monitors.lua").write_text("-- original source\n")
    qml = (repo / "test/qml/fixtures/display-fileview.qml").read_text()
    (root / "shell.qml").write_text(qml.replace("__TEMP_DIRECTORY__", json.dumps(str(root))))
    runtime = root / "runtime"
    runtime.mkdir(mode=0o700)
    environment = dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="",
                       XDG_RUNTIME_DIR=str(runtime))
    environment.pop("WAYLAND_DISPLAY", None)
    process = subprocess.Popen(["quickshell", "--no-color", "-p", str(root)], env=environment,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        # The native watcher observes this external edit. A timeout also covers
        # failure before the handshake; the helper never touches desktop paths.
        import threading
        timer = threading.Timer(12, process.kill)
        timer.start()
        lines = []
        for line in process.stdout:
            lines.append(line)
            if "DISPLAY_EDIT_SOURCE" in line:
                (root / "monitors.lua").write_text("-- newer personal source\n")
        result = process.wait(timeout=2)
        output = "".join(lines)
        print(output)
        if result or "DISPLAY_FILEVIEW_PASS" not in output:
            raise SystemExit(1)
    finally:
        timer.cancel()
        if process.poll() is None:
            process.kill()
            process.wait()
    candidate = (root / "state/monitors.lua.candidate").read_text()
    assert candidate.endswith("-- newer personal source\n")
    assert candidate.index("-- >>> station") < candidate.index("-- newer personal source")
    assert (root / "state/monitors-block.plain.lua.candidate").is_file()
    assert (root / "monitors.lua").read_text() == "-- newer personal source\n"
    assert (root / "blocked.candidate").is_dir()
    assert not (root / "state/monitors-block.plain.lua").exists()
    assert not (root / "state/preview.token").exists()
    print("DISPLAY_DISK_BYTES_PASS: source preserved, candidates saved, no transaction executed")

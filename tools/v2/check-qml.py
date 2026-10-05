"""Compile Station or the M0 fixture against installed qs.Ui without installing it.

Requires the session's Wayland backend (KeyboardPanel cannot compile offscreen).
No Panel/Service objects are instantiated; no desktop config is changed.
"""
from pathlib import Path
import os
import subprocess
import sys
import tempfile

fixture = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else Path(__file__).resolve().parent / "m0-plugin"
label = "STATION" if (fixture / "manifest.json").exists() and '"id": "yakumy.station"' in (fixture / "manifest.json").read_text() else "M0"
with tempfile.TemporaryDirectory(prefix="station-qml-") as directory:
    root = Path(directory)
    for name in ("Commons", "Ui"):
        (root / name).symlink_to(Path("/usr/share/omarchy/shell") / name,
                                target_is_directory=True)
    (root / "Probe").symlink_to(fixture, target_is_directory=True)
    component_names = ["Panel.qml", "Service.qml"]
    if (fixture / "lib").is_dir():
        component_names += ["lib/" + path.name for path in sorted((fixture / "lib").glob("*.qml"))]
    (root / "shell.qml").write_text('''import QtQuick
import Quickshell
ShellRoot {
  Component.onCompleted: {
    for (var name of ''' + repr(component_names).replace("'", '"') + ''') {
      var c = Qt.createComponent("Probe/" + name)
      if (c.status !== Component.Ready) {
        console.error("''' + label + '''_COMPILE_FAILED " + c.errorString())
        return
      }
    }
    console.log("''' + label + '''_COMPONENTS_READY")
  }
}
''')
    environment = dict(os.environ, QT_QPA_PLATFORM="wayland")
    process = subprocess.Popen(["quickshell", "--no-color", "-p", str(root)],
                               env=environment, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    try:
        try:
            output, _ = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            process.terminate()
            output, _ = process.communicate(timeout=5)
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()
    print(output)
    if f"{label}_COMPONENTS_READY" not in output or f"{label}_COMPILE_FAILED" in output:
        raise SystemExit(1)

"""Exercise the production migration owner with offscreen Qt and fake effects.

FileView acknowledgments are controlled here. check-workspace-fileview.py tests
the real FileView separately against temporary files. Neither runs Service or
dispatches compositor commands.
"""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="station-workspace-owner-") as directory:
    root = Path(directory)
    probe = root / "Probe"
    probe.mkdir()
    for name in ("WorkspaceController.qml", "Grid.js", "Hypr.js"):
        (probe / name).write_text((repo / "lib" / name).read_text())
    io = root / "Quickshell" / "Io"
    io.mkdir(parents=True)
    (io / "qmldir").write_text("module Quickshell.Io\nFileView 1.0 FileView.qml\n")
    (io / "FileView.qml").write_text('''import QtQuick
Item {
  property string path: ""
  property bool atomicWrites: false
  property bool printErrors: false
  property string readText: ""
  property var writes: []
  property int reloads: 0
  signal loaded()
  signal loadFailed()
  signal saved()
  signal saveFailed()
  function text() { return readText }
  function setText(value) { writes.push(value) }
  function reload() { reloads++ }
}
''')
    (root / "tst_workspace.qml").write_text(
        (repo / "tools/v2/fixtures/tst-workspace-owner.qml").read_text())
    result = subprocess.run(
        ["/usr/lib/qt6/bin/qmltestrunner", "-import", str(root), "-input", str(root)],
        env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME=""),
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    raise SystemExit(result.returncode)

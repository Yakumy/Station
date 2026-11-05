"""Instantiate the production panel on both service paths with fake effects.

Uses installed host components and an isolated preview window. All control
Processes are qualified to inert doubles. No Service or desktop command runs.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="station-panel-composition-") as folder:
    root = Path(folder)
    for name in ("Commons", "Ui"):
        (root / name).symlink_to(Path("/usr/share/omarchy/shell") / name, target_is_directory=True)
    shutil.copytree(repo / "lib", root / "Station")
    (root / "assets").symlink_to(repo / "assets", target_is_directory=True)
    for path in (root / "Station").rglob("*.qml"):
        source = path.read_text()
        if re.search(r"(?<![\w.])Color\.", source):
            if "import qs.Commons as Commons" not in source:
                source = "import qs.Commons as Commons\n" + source
            source = re.sub(r"(?<![\w.])Color\.", "Commons.Color.", source)
        path.write_text(source)
    fake = root / "FakeIo"
    fake.mkdir()
    (fake / "Process.qml").write_text('''import QtQuick
Item {
  property var command: []
  property bool running: false
  property QtObject stdout
  signal exited(int exitCode, int exitStatus)
}
''')
    (fake / "StdioCollector.qml").write_text('''import QtQuick
QtObject { property bool waitForEnd; property string text; signal streamFinished() }
''')
    controls = root / "Station/displays/DisplayControls.qml"
    source = controls.read_text().replace('import Quickshell.Io', 'import "../../FakeIo" as FakeIo')
    assert len(re.findall(r'\bProcess \{', source)) == 3
    assert len(re.findall(r'\bStdioCollector \{', source)) == 3
    source = re.sub(r'\b(Process|StdioCollector) \{', r'FakeIo.\1 {', source)
    controls.write_text(source)
    (root / "shell.qml").write_text((repo / "test/qml/fixtures/panel-composition.qml").read_text())
    result = subprocess.run(["quickshell", "--no-color", "-p", str(root)],
                            env=dict(os.environ, QT_QPA_PLATFORM="wayland"), text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
    print(result.stdout)
    if "PANEL_COMPOSITION_PASS" not in result.stdout or any(token in result.stdout for token in
            ("ERROR", "ReferenceError", "TypeError", "Binding loop", "Unable to assign", "PANEL_COMPOSITION_FAIL")):
        raise SystemExit(1)

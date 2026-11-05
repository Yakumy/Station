"""Exercise widget-owned panel/session/control QML with fake external ports.

Native Qt timers/signals run offscreen. No Service or native Process is loaded.
The production composition facades are copied into the fixture for port checks.
"""
from pathlib import Path
import os
import re
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="station-panel-session-") as directory:
    root = Path(directory)
    probe = root / "Probe"
    probe.mkdir()
    for name in ("PanelSession.qml", "DisplayControls.qml", "Tabs.js", "PanelPosition.js", "KeybindingsTab.qml",
                 "BindingKeyPicker.qml", "ChoiceChip.qml", "InlineDropdown.qml", "Binds.js"):
        (probe / name).write_text((repo / "lib" / name).read_text())
    for path in probe.glob("*.qml"):
        source = path.read_text()
        if re.search(r"(?<![\w.])Color\.", source):
            source = "import qs.Commons as Commons\n" + source
            path.write_text(re.sub(r"(?<![\w.])Color\.", "Commons.Color.", source))
    shell = root / "Quickshell"
    shell.mkdir()
    (shell / "qmldir").write_text("module Quickshell\nsingleton Quickshell 1.0 Quickshell.qml\n")
    (shell / "Quickshell.qml").write_text('''pragma Singleton
import QtQuick
QtObject { property var screens: [] }
''')
    io = shell / "Io"
    io.mkdir()
    (io / "qmldir").write_text("module Quickshell.Io\nProcess 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\n")
    (io / "Process.qml").write_text('''import QtQuick
Item {
  property var command: []
  property bool running: false
  property QtObject stdout
  property var launches: []
  signal exited(int exitCode, int exitStatus)
  onRunningChanged: if (running) launches = launches.concat([command.slice()])
  function finish(code, text) {
    if (stdout) { stdout.text = text || ""; stdout.streamFinished() }
    running = false
    exited(code, 0)
  }
}
''')
    (io / "StdioCollector.qml").write_text('''import QtQuick
QtObject { property bool waitForEnd; property string text; signal streamFinished() }
''')
    commons = root / "qs" / "Commons"
    commons.mkdir(parents=True)
    (commons / "qmldir").write_text("module qs.Commons\nsingleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\nsingleton Border 1.0 Border.qml\n")
    (commons / "Style.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
  property var font: ({baseSize: 12, family: "monospace", body: 12, caption: 12})
  property var spacing: ({controlHeight: 30, controlGap: 8, md: 8, sm: 4, xxs: 2, popupRowHeight: 24, hairline: 1, controlPaddingX: 8})
  property int normalBorderWidth: 1
  property int cornerRadius: 0
  function space(value) { return value }
  property int gapsOut: 0
  property var bar: ({sizeHorizontal: 26, sizeVertical: 26})
  signal fontBaseSizeChanged()
}
''')
    (commons / "Color.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
  property var popups: ({text: "white", background: "black"})
  property var menu: ({background: "black", border: "white", text: "white", selectedBackground: "grey", selectedText: "white"})
  property color urgent: "red"
  property color accent: "white"
}
''')
    (commons / "Border.qml").write_text('''pragma Singleton
import QtQuick
QtObject { function flat(color, width) { return {} } }
''')
    ui = root / "qs" / "Ui"
    ui.mkdir()
    (ui / "qmldir").write_text("module qs.Ui\nButton 1.0 Button.qml\nBorderSurface 1.0 BorderSurface.qml\nPanelSeparator 1.0 PanelSeparator.qml\n")
    (ui / "Button.qml").write_text('''import QtQuick
Rectangle {
  property string text
  property string tooltipText
  property color foreground
  property color accent
  property color background
  property bool bordered
  property bool focusable
  property bool selected
  implicitWidth: 160; implicitHeight: 30
  signal clicked()
}
''')
    (ui / "BorderSurface.qml").write_text("import QtQuick\nRectangle { property var borderSpec }\n")
    (ui / "PanelSeparator.qml").write_text("import QtQuick\nItem { property color foreground }\n")
    source = (repo / "lib/StationPanel.qml").read_text()
    facades = re.findall(r'  QtObject \{\n    id: (?:panelIntent|\w+TabPort)\n[\s\S]*?\n  \}', source)
    assert len(facades) == 6
    fixture = (repo / "tools/v2/fixtures/tst-panel-session.qml").read_text()
    fixture = fixture.replace("  // COMPOSITION_PORTS", "\n".join(facades))
    (root / "tst_panel.qml").write_text(fixture)
    result = subprocess.run(
        ["/usr/lib/qt6/bin/qmltestrunner", "-import", str(root), "-input", str(root)],
        env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME=""),
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    raise SystemExit(result.returncode)

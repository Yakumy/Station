"""Exercise the production panel's fixed card size and bounded tab viewport.

Uses host components with no Station service, compositor changes or installation.
Requires Wayland access; opens only an isolated preview window.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="station-panel-size-") as directory:
    root = Path(directory)
    for name in ("Commons", "Ui"):
        (root / name).symlink_to(Path("/usr/share/omarchy/shell") / name, target_is_directory=True)
    # The bare Color name resolves ambiguously in this isolated context. Keep
    # production geometry/behavior, qualifying only host theme references.
    shutil.copytree(repo / "lib", root / "Station")
    (root / "assets").symlink_to(repo / "assets", target_is_directory=True)
    for path in (root / "Station").rglob("*.qml"):
        source = path.read_text()
        if re.search(r"(?<![\w.])Color\.", source):
            if "import qs.Commons as Commons" not in source:
                source = "import qs.Commons as Commons\n" + source
            path.write_text(re.sub(r"(?<![\w.])Color\.", "Commons.Color.", source))
    (root / "shell.qml").write_text(r'''import QtQuick
import Quickshell
import qs.Commons
import "Station/panel" as PanelUi
ShellRoot {
  Component.onCompleted: Qt.callLater(function() { station.open() })
  FloatingWindow {
    implicitWidth: 200
    implicitHeight: 80
    visible: true
    PanelUi.StationPanel { id: station }
  }
  function find(node, name, visited) {
    if (!node || visited.indexOf(node) >= 0) return null
    visited.push(node)
    if (node.objectName === name) return node
    var lists = [node.data || [], node.children || [], node.contentItem ? [node.contentItem] : []]
    for (var j = 0; j < lists.length; j++) {
      for (var i = 0; i < lists[j].length; i++) {
        var result = find(lists[j][i], name, visited)
        if (result) return result
      }
    }
    return null
  }
  Timer {
    id: check
    interval: 120; running: true; repeat: true
    property int step: 0
    property var card: null
    property var scroll: null
    property var initial: null
    property var extra: null
    function require(ok, message) {
      if (!ok) { console.log("PANEL_SIZE_FAILED " + message); Qt.quit(); stop() }
      return ok
    }
    onTriggered: {
      if (step === 0) {
        card = find(station, "stationPanelWindow", [])
        scroll = find(station, "stationTabScroll", [])
        if (!require(card && scroll, "missing panel objects")) return
        initial = {width:card.contentWidth, height:card.contentHeight}
        if (!require(initial.width > 0 && initial.height > 0, "empty card")) return
      } else if (!require(card.contentWidth === initial.width && card.contentHeight === initial.height,
          "card resized on tab " + station.selectedTab)) return
      if (step < 6) {
        station.selectedTab = step
      } else if (step === 6) {
        // Simulate expanded notices/conflicts without attaching a live service.
        var column = find(station, "stationTabContent", [])
        extra = Qt.createQmlObject('import QtQuick; Item { width: 1; height: 2000 }', column)
      } else if (step === 7) {
        if (!require(scroll.contentHeight > scroll.height && scroll.clip,
            "overflow must stay inside scroll viewport: " + scroll.contentHeight + "/" + scroll.height)) return
        scroll.contentItem.contentY = 100
        station.selectedTab = 0
      } else if (step === 8) {
        if (!require(scroll.contentItem.contentY === 0, "tab switch must reset scroll")) return
        extra.destroy()
        card.contentHeight = Math.round(initial.height / 2)
      } else if (step === 9) {
        if (!require(scroll.height > 0 && scroll.height < card.contentHeight && scroll.contentHeight > scroll.height,
            "short viewport must retain overflow access")) return
        console.log("PANEL_SIZE_OK six tabs, overflow, scroll reset and short viewport")
        Qt.quit(); stop(); return
      }
      step++
      // The final step deliberately simulates the host's screen-height cap.
      if (step === 9) initial.height = card.contentHeight
    }
  }
}
''')
    result = subprocess.run(["quickshell", "--no-color", "-p", str(root)],
                            env=dict(os.environ, QT_QPA_PLATFORM="wayland"), text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
    print(result.stdout)
    if "PANEL_SIZE_OK" not in result.stdout or any(token in result.stdout for token in
            ("ERROR", "ReferenceError", "TypeError", "Binding loop", "Unable to assign", "PANEL_SIZE_FAILED")):
        raise SystemExit(1)

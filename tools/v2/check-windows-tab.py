"""Render WindowsTab and exercise cross-monitor exchange with real host tokens."""
from pathlib import Path
import os
import socket
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[2]
display = os.environ.get("WAYLAND_DISPLAY", "")
runtime = os.environ.get("XDG_RUNTIME_DIR", "")
address = Path(display) if display else None
if address and not address.is_absolute():
    address = Path(runtime) / address if runtime else None
try:
    if address is None:
        raise OSError("WAYLAND_DISPLAY or XDG_RUNTIME_DIR is unset")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(1)
        connection.connect(str(address))
except OSError as error:
    raise SystemExit(f"Bar-tab render check needs Wayland access ({error}).")

output = Path(sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="station-bar-tab-render-"))
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="station-bar-tab-probe-") as directory:
    root = Path(directory)
    for name in ("Commons", "Ui"):
        (root / name).symlink_to(Path("/usr/share/omarchy/shell") / name, target_is_directory=True)
    (root / "Station").symlink_to(repo / "lib", target_is_directory=True)
    qml = r'''import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "Station" as Station
ShellRoot {
  Item {
    id: fakeService
    property var displayDraft: [
      {name: "eDP-1", width: 1920, height: 1080, x: 0, y: 1080, scale: 1, transform: 0, enabled: true},
      {name: "HDMI-A-2", width: 1920, height: 1200, x: 0, y: -120, scale: 1, transform: 0, enabled: true},
      {name: "DP-3", width: 2560, height: 1440, x: 1920, y: 0, scale: 1, transform: 0, enabled: false}]
    property var config: ({windows:{innerGap:26,outerGap:20,split:35,rounding:10,speed:0.5}})
    property bool windowSettingsBusy: false
    function displayEnabled(name) { return name !== "DP-3" }
    function monitorBar(name) {
      if (name === "eDP-1") return {enabled: true, position: "bottom", width: 48, height: 72, background: "blur", style: "pill", contentSize: 18}
      if (name === "HDMI-A-2") return {enabled: true, position: "left", width: 100, height: 0, background: "solid", style: "default", contentSize: 0}
      return {enabled: false, position: "right", width: 100, height: 0, background: "transparent", style: "default", contentSize: 0}
    }
    function monitorBarMinimum(name) { return name === "eDP-1" ? 58 : 1 }
    function monitorBarMaximumHeight(name) { return name === "HDMI-A-2" ? 60 : 54 }
    function monitorBarMaximumContent(name) { return 24 }
    function setMonitorBarEnabled() { return "ok" }
    function setMonitorBarPosition() { return "ok" }
    function setMonitorBarWidth() { return "ok" }
    function setMonitorBarHeight() { return "ok" }
    function setMonitorBarBackground() { return "ok" }
    function setMonitorBarStyle() { return "ok" }
    function setMonitorBarContentSize() { return "ok" }
  }
  Item {
    id: panel
    property var service: fakeService
    property var selectedDisplay: fakeService.displayDraft[0]
    property var bar: null
    property real regionPadH: Style.space(24)
    property real space1: Style.space(4)
    property real space2: Style.space(8)
    property real space3: Style.space(12)
    property real space4: Style.space(16)
    property real disabledOpacity: 0.6
    property color textPrimary: Commons.Color.popups.text
    property color textDim: Qt.darker(Commons.Color.popups.text, 1.4)
    function selectDisplay(name) {
      for (var i = 0; i < fakeService.displayDraft.length; i++)
        if (fakeService.displayDraft[i].name === name) selectedDisplay = fakeService.displayDraft[i]
    }
  }
  FloatingWindow {
    implicitWidth: Style.space(996)
    implicitHeight: tab.implicitHeight
    color: Commons.Color.popups.background
    visible: true
    Rectangle {
      id: capture
      anchors.fill: parent
      color: Commons.Color.popups.background
      Station.WindowsTab { id: tab; width: parent.width; panelRoot: panel }
    }
  }
  function findObject(node, name) {
    if (!node) return null
    if (node.objectName === name) return node
    var children = node.children || []
    for (var i = 0; i < children.length; i++) {
      var found = findObject(children[i], name)
      if (found) return found
    }
    return null
  }
  Timer {
    property int phase: 0
    property var first: null
    property var second: null
    interval: 700; running: true; repeat: true
    onTriggered: {
      var layout = findObject(tab, "windowsLayout")
      var a = findObject(layout, "windowPreview-1")
      var b = findObject(layout, "windowPreview-3")
      if (!layout || !a || !b) { console.log("WINDOWS_CHECK_FAILED missing delegates"); Qt.quit(); return }
      if (phase === 0) {
        first = {x:a.x,y:a.y}; second = {x:b.x,y:b.y}
        tab.animateSwap = true
        tab.swapped = true
        phase++
        return
      }
      if (a.destination !== 1 || b.destination !== 0 || (a.x === first.x && a.y === first.y)
          || (b.x === second.x && b.y === second.y)) {
        console.log("WINDOWS_CHECK_FAILED exchange"); Qt.quit(); return
      }
      capture.grabToImage(function(result) {
        result.saveToFile("OUTPUT/windows-tab.png")
        console.log("WINDOWS_RENDER_AND_EXCHANGE_OK")
        Qt.quit()
      })
      stop()
    }
  }
}
'''.replace("OUTPUT", str(output))
    (root / "shell.qml").write_text(qml)
    result = subprocess.run(["quickshell", "--no-color", "-p", str(root)],
                            env=dict(os.environ, QT_QPA_PLATFORM="wayland"), text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
    print(result.stdout)
    print(output)
    if "WINDOWS_RENDER_AND_EXCHANGE_OK" not in result.stdout or any(token in result.stdout for token in
            ("ERROR", "ReferenceError", "TypeError", "Binding loop", "Unable to assign", "grabToImage:", "WINDOWS_CHECK_FAILED")):
        raise SystemExit(1)

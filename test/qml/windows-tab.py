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
    raise SystemExit(f"Windows-tab render check needs Wayland access ({error}).")

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
import "Station/windows" as WindowsUi
ShellRoot {
  Item {
    id: fakeService
    property var displayDraft: [
      {name: "eDP-1", width: 1920, height: 1080, x: 0, y: 1080, scale: 1, transform: 0, enabled: true},
      {name: "HDMI-A-2", width: 1920, height: 1200, x: 0, y: -120, scale: 1, transform: 0, enabled: true},
      {name: "DP-3", width: 2560, height: 1440, x: 1920, y: 0, scale: 1, transform: 0, enabled: false}]
    property var config: ({windows:{innerGap:26,outerGap:20,split:35,rounding:10,speed:0.5}})
    property bool windowSettingsBusy: false
    property string testBarBackground: "solid"
    function displayEnabled(name) { return name !== "DP-3" }
    function monitorBar(name) {
      if (name === "eDP-1") return {enabled: true, position: "bottom", width: 48, height: 72, background: "blur", style: "pill", contentSize: 18}
      if (name === "HDMI-A-2") return {enabled: true, position: "left", width: 100, height: 0, background: testBarBackground, style: "default", contentSize: 0}
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
      WindowsUi.WindowsTab { id: tab; width: parent.width; tokens: panel; service: panel.service; selectedDisplay: panel.selectedDisplay; bar: panel.bar }
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
    interval: 40; running: true; repeat: true
    property bool sawMiddle: false
    function fail(reason) { console.log("WINDOWS_CHECK_FAILED " + reason); Qt.quit(); stop() }
    onTriggered: {
      var layout = findObject(tab, "windowsLayout")
      var a = findObject(layout, "windowPreview-1")
      var b = findObject(layout, "windowPreview-3")
      var remaining = findObject(layout, "windowPreview-0")
      var outline = findObject(layout, "windowOutline-1")
      if (!layout || !a || !b || !outline) { fail("missing delegates"); return }
      if (phase === 0) {
        var solidArea = layout.workArea(1)
        fakeService.testBarBackground = "transparent"
        var transparentArea = layout.workArea(1)
        fakeService.testBarBackground = "blur"
        var blurArea = layout.workArea(1)
        fakeService.testBarBackground = "solid"
        if (Math.abs(solidArea.x - blurArea.x) > 0.001) {
          fail("blur default bar gap"); return
        }
        // Gaps are observed compositor values: a bar background never changes them.
        if (Math.abs(solidArea.x - transparentArea.x) > 0.001) {
          fail("bar background changed the gap"); return
        }
        var name = findObject(layout, "monitorName-eDP-1")
        if (!name || name.x !== 0 || name.y + name.height >= 0) { fail("external label"); return }
        if (a.x >= remaining.x || b.x >= findObject(layout, "windowPreview-2").x) {
          fail("window order"); return
        }
        first = {x:a.x,y:a.y,width:a.width,height:a.height,remaining:remaining.width}
        second = {x:b.x,y:b.y,width:b.width,height:b.height}
        layout.previewExchange(0.5)
        if (a.x !== first.x || a.y !== first.y || b.x !== second.x || b.y !== second.y) {
          fail("startup jump"); return
        }
        phase++
        return
      }
      if (phase === 1) {
        if (layout.progress === 1) {
          sawMiddle = true
          if (remaining.width <= first.remaining || findObject(layout, "windowPreview-2").height >= second.height) { fail("reflow"); return }
        }
        if (layout.animating) return
        if (!sawMiddle || a.x !== second.x || a.y !== second.y || b.x !== first.x || b.y !== first.y) {
          fail("ordered exchange"); return
        }
        var before = {x:a.x,y:a.y,width:a.width,height:a.height}
        layout.previewExchange(0.25)
        layout.previewExchange(2)
        if (a.x !== before.x || a.y !== before.y || a.width !== before.width || a.height !== before.height
            || layout.playbackSpeed !== 0.25) { fail("replay jump or live retiming"); return }
        phase++
        return
      }
      if (layout.animating || layout.queuedSpeed >= 0) return
      tab.preview("rounding", 20)
      if (outline.radius !== 20 || outline.scale !== layout.zoom || !outline.antialiasing
          || outline.border.pixelAligned) { fail("scaled radius"); return }
      layout.previewExchange(0)
      if (layout.animating || layout.progress !== 2) { fail("zero speed"); return }
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

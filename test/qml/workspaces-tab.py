"""Render WorkspacesTab in all three modes and drive its draft, − and +, drag and Apply with real host tokens.

Uses a fake service and an isolated preview window. No Station service, compositor
command or installed file is touched. Pass a directory to keep the renders.
"""
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
    raise SystemExit(f"Workspaces-tab render check needs Wayland access ({error}).")

output = Path(sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="station-workspaces-tab-render-"))
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="station-workspaces-tab-probe-") as directory:
    root = Path(directory)
    for name in ("Commons", "Ui"):
        (root / name).symlink_to(Path("/usr/share/omarchy/shell") / name, target_is_directory=True)
    (root / "Station").symlink_to(repo / "lib", target_is_directory=True)
    qml = r'''import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "Station/stations" as Stations
ShellRoot {
  Item {
    id: fakeService
    property var displayDraft: [
      {name: "eDP-1", width: 1920, height: 1080, x: 0, y: 1080, scale: 1, transform: 0, enabled: true},
      {name: "HDMI-A-2", width: 1920, height: 1200, x: 0, y: -120, scale: 1, transform: 0, enabled: true},
      {name: "DP-3", width: 2560, height: 1440, x: 1920, y: 0, scale: 1, transform: 0, enabled: false}]
    property var config: ({workspaceMode: "station", workspaceLayout: {repetitive: {}, nonrepetitive: {}},
      direction: "ltr", indicatorStyle: "prefixed", compactMode: "hover", showOpenApps: true})
    property var workspaceTarget: ({outputs: ["eDP-1", "HDMI-A-2"]})
    property string state: "idle"
    property var calls: []
    function setSetting(name, value) {
      calls.push([name, JSON.stringify(value)])
      if (name !== "workspaces") return "invalid"
      config = Object.assign(JSON.parse(JSON.stringify(config)), JSON.parse(JSON.stringify(value)))
      return "ok"
    }
  }
  Item {
    id: tokens
    property real regionPadH: Style.space(24)
    property real space1: Style.space(4)
    property real space2: Style.space(8)
    property real space3: Style.space(12)
    property real space4: Style.space(16)
    property real disabledOpacity: 0.6
    property color textPrimary: Commons.Color.popups.text
    property color textDim: Qt.darker(Commons.Color.popups.text, 1.4)
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
      Stations.WorkspacesTab { id: tab; width: parent.width; tokens: tokens; service: fakeService }
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
  function badges(name) {
    var flow = findObject(tab, "workspaceBadges-" + name)
    var values = []
    for (var i = 0; flow && i < flow.children.length; i++)
      if (String(flow.children[i].objectName).indexOf("workspaceBadge-") === 0) values.push(flow.children[i].modelData)
    return values.sort(function(a, b) { return a - b }).join(",")
  }
  function inside(child, parent) {
    var point = child.mapToItem(parent, 0, 0)
    return point.x >= 0 && point.y >= 0 && point.x + child.width <= parent.width + 0.5
      && point.y + child.height <= parent.height + 0.5
  }
  Timer { id: settle; property var done: null; interval: 700; onTriggered: done() }
  Timer {
    property int phase: 0
    interval: 60; running: true; repeat: true
    function fail(reason) { console.log("WORKSPACES_CHECK_FAILED " + reason); Qt.quit(); stop() }
    // Let control transitions settle so the render shows the final state.
    function save(name, done) {
      settle.done = function() {
        capture.grabToImage(function(result) { result.saveToFile("OUTPUT/" + name + ".png"); done() })
      }
      settle.restart()
    }
    onTriggered: {
      var layout = findObject(tab, "workspacesLayout")
      if (!layout) { fail("missing layout"); return }
      var actions = findObject(tab, "workspacesActions")
      if (phase === 0) {
        if (badges("eDP-1") !== "1,3,5" || badges("HDMI-A-2") !== "2,4,6" || badges("DP-3") !== "") {
          fail("station badges " + badges("eDP-1") + " / " + badges("HDMI-A-2")); return
        }
        var role = findObject(layout, "workspaceMonitorRole-HDMI-A-2")
        var name = findObject(layout, "workspaceMonitorName-HDMI-A-2")
        var card = findObject(layout, "workspaceMonitor-HDMI-A-2")
        if (!role || role.text !== "| 2" || findObject(layout, "workspaceMonitorRole-DP-3").text !== "| Off") { fail("roles"); return }
        if (inside(name, card) || name.parent.y + name.parent.height >= 0 || !inside(findObject(layout, "workspaceBadge-HDMI-A-2-2"), card)) { fail("outside name and inside badges"); return }
        if (findObject(tab, "workspaceCountIncrease") || findObject(layout, "workspaceStep-eDP-1-up")) { fail("station count controls"); return }
        var selector = findObject(tab, "workspaceModeSelector")
        var row = selector.parent
        if (!selector.enabled || findObject(tab, "workspaceModeNote").text !== "") { fail("selector on two monitors"); return }
        if (Math.abs(selector.y + selector.height / 2 - row.height / 2) > 1) { fail("selector centered"); return }
        if (actions.visible) { fail("actions before an edit"); return }
        phase = -1
        save("station", function() { phase = 1 })
        return
      }
      if (phase === 1) {
        findObject(tab, "workspaceModeSelector").changed("nonrepetitive")
        if (fakeService.calls.length || fakeService.config.workspaceMode !== "station") { fail("mode applied before Apply"); return }
        if (!actions.visible) { fail("actions after an edit"); return }
        if (badges("eDP-1") !== "1,2,3,4,5" || badges("HDMI-A-2") !== "6,7,8,9,10") { fail("non-repetitive default"); return }
        if (findObject(tab, "workspaceModeNote").text !== "Drag workspaces onto a monitor to assign them") { fail("drag note"); return }
        // − and + only on the last monitor.
        if (findObject(layout, "workspaceStep-eDP-1-up") || !findObject(layout, "workspaceStep-HDMI-A-2-up")) { fail("last monitor steps"); return }
        layout.countChangeRequested("HDMI-A-2", 1)
        if (badges("HDMI-A-2") !== "6,7,8,9,10,11") { fail("plus " + badges("HDMI-A-2")); return }
        layout.countChangeRequested("HDMI-A-2", -1)
        layout.countChangeRequested("HDMI-A-2", -1)
        if (badges("HDMI-A-2") !== "6,7,8,9") { fail("minus"); return }
        // Dropping onto a monitor finds it, and moving 1 and 3 hands them over.
        var target = findObject(layout, "workspaceMonitor-HDMI-A-2")
        if (layout.outputAt(target.x + target.width / 2, target.y + target.height / 2) !== "HDMI-A-2"
            || layout.outputAt(-50, -50) !== "") { fail("drop target"); return }
        layout.workspaceMoved(1, "HDMI-A-2")
        layout.workspaceMoved(3, "HDMI-A-2")
        if (badges("eDP-1") !== "2,4,5" || badges("HDMI-A-2") !== "1,3,6,7,8,9") { fail("drag " + badges("eDP-1")); return }
        // − removes the highest number even when another monitor holds it.
        layout.workspaceMoved(9, "eDP-1")
        layout.countChangeRequested("HDMI-A-2", -1)
        if (badges("eDP-1") !== "2,4,5" || badges("HDMI-A-2") !== "1,3,6,7,8") { fail("minus elsewhere"); return }
        findObject(tab, "workspacesCancel").clicked()
        if (actions.visible || tab.mode !== "station" || badges("eDP-1") !== "1,3,5") { fail("cancel"); return }
        findObject(tab, "workspaceModeSelector").changed("nonrepetitive")
        layout.workspaceMoved(1, "HDMI-A-2")
        phase = -1
        save("nonrepetitive", function() { phase = 2 })
        return
      }
      if (phase === 2) {
        findObject(tab, "workspacesApply").clicked()
        if (fakeService.calls.length !== 1 || fakeService.config.workspaceMode !== "nonrepetitive"
            || JSON.stringify(fakeService.config.workspaceLayout.nonrepetitive)
              !== JSON.stringify({"eDP-1": [2, 3, 4, 5], "HDMI-A-2": [1, 6, 7, 8, 9, 10]})) {
          fail("apply " + JSON.stringify(fakeService.calls)); return
        }
        if (actions.visible) { fail("actions after apply"); return }
        findObject(tab, "workspaceModeSelector").changed("repetitive")
        if (badges("eDP-1") !== "1,2,3,4,5" || badges("HDMI-A-2") !== "1,2,3,4,5") { fail("repetitive default"); return }
        for (var i = 0; i < 7; i++) layout.countChangeRequested("eDP-1", 1)
        for (var j = 0; j < 6; j++) layout.countChangeRequested("HDMI-A-2", -1)
        if (badges("eDP-1") !== "1,2,3,4,5,6,7,8,9,10" || badges("HDMI-A-2") !== "1") { fail("repetitive limits"); return }
        if (findObject(layout, "workspaceStep-eDP-1-up").opacity === 1 || findObject(layout, "workspaceStep-HDMI-A-2-down").opacity === 1) {
          fail("repetitive limit buttons"); return
        }
        tab.edit({ compactMode: "on" })
        if (findObject(tab, "showOpenAppsRow").opacity === 1) { fail("apps row with compact on"); return }
        layout.zoomAt(1.5, layout.width / 2, layout.height / 2)
        fakeService.state = "migrating"
        if (findObject(tab, "workspacesApply").enabled) { fail("busy apply"); return }
        fakeService.state = "idle"
        phase = -1
        save("repetitive", function() { phase = 3 })
        return
      }
      if (phase === 3) {
        fakeService.workspaceTarget = ({outputs: ["eDP-1"]})
        var selector = findObject(tab, "workspaceModeSelector")
        var note = findObject(tab, "workspaceModeNote")
        if (selector.enabled || note.text !== "Works only on multiple monitors") { fail("single monitor"); return }
        if (selector.opacity !== tokens.disabledOpacity) {
          fail("single monitor style"); return
        }
        var frame = findObject(tab, "workspaceModeSelector").parent
        if (!inside(note, frame) || note.mapToItem(frame, 0, 0).y < selector.mapToItem(frame, 0, selector.height).y) {
          fail("note under the buttons"); return
        }
        phase = -1
        save("single", function() {
          console.log("WORKSPACES_RENDER_OK")
          Qt.quit()
        })
        return
      }
    }
  }
}
'''.replace("OUTPUT", str(output))
    (root / "shell.qml").write_text(qml)
    result = subprocess.run(["quickshell", "--no-color", "-p", str(root)],
                            env=dict(os.environ, QT_QPA_PLATFORM="wayland"), text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    print(output)
    if "WORKSPACES_RENDER_OK" not in result.stdout or any(token in result.stdout for token in
            ("ERROR", "ReferenceError", "TypeError", "Binding loop", "Unable to assign", "grabToImage:",
             "WORKSPACES_CHECK_FAILED")):
        raise SystemExit(1)

"""Render StationBar's workspace number row against the live Hyprland session.

Read-only: the bar reads Quickshell's Hyprland monitors and workspaces, and clicks go to
a test handler, so no workspace changes. Needs a Wayland session. Pass a directory to
keep the render.
"""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[2]
if not os.environ.get("WAYLAND_DISPLAY") or not os.environ.get("HYPRLAND_INSTANCE_SIGNATURE"):
    raise SystemExit("Workspace number check needs a Hyprland session.")
monitors = json.loads(subprocess.run(["hyprctl", "monitors", "-j"], text=True, check=True,
                                     stdout=subprocess.PIPE).stdout)
outputs = sorted(m["name"] for m in monitors if not m.get("disabled"))
output = Path(sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="station-workspace-ids-"))
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="station-workspace-ids-probe-") as directory:
    root = Path(directory)
    for name in ("Commons", "Ui"):
        (root / name).symlink_to(Path("/usr/share/omarchy/shell") / name, target_is_directory=True)
    (root / "Station").symlink_to(repo / "lib", target_is_directory=True)
    qml = r'''import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "Station/bars" as Bars
import "Station/stations/Grid.js" as Grid
ShellRoot {
  QtObject {
    id: host
    property bool foregroundAnimationEnabled: false
    property bool vertical: false
    property int barSize: 32
    property real effectiveContentSize: 0
    property string position: "top"
    property string fontFamily: Style.font.family
    property color barForeground: Commons.Color.foreground
    property color urgent: Commons.Color.urgent
    function hideTooltip(item) {}
    function showTooltip(item, text) {}
  }
  FloatingWindow {
    implicitWidth: 900; implicitHeight: 40
    color: Commons.Color.background
    visible: true
    Rectangle {
      id: capture
      anchors.fill: parent
      color: Commons.Color.background
      Bars.StationBar {
        id: bar
        bar: host
        appsMode: "hide"
        stationCount: 3
        workspaceMap: ({ outputs: OUTPUTS })
        property var picked: []
        onStationSelected: function(number) { picked.push(number) }
      }
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
    interval: 300; running: true; repeat: true
    function fail(reason) { console.log("WORKSPACE_IDS_FAILED " + reason); Qt.quit(); stop() }
    onTriggered: {
      if (!bar.screenName) return
      if (phase === 0) {
        var width = bar.width
        if (findObject(bar, "workspaceIdRow").visible) { fail("row shown while off"); return }
        bar.showWorkspaceIds = true
        if (!(bar.width > width)) { fail("row adds no width"); return }
        phase = 1
        return
      }
      if (phase === 1) {
        var ids = bar.workspaceIds
        for (var s = 1; s <= 3; s++) {
          var id = Grid.workspace(s, bar.screenName, bar.workspaceMap)
          if (id !== null && ids.indexOf(id) === -1) { fail("missing configured " + id); return }
        }
        if (ids.indexOf(bar.activeWorkspaceId) === -1) { fail("missing active " + bar.activeWorkspaceId); return }
        for (var i = 0; i < ids.length; i++) {
          var mark = findObject(bar, "workspaceIdActive-" + ids[i])
          if (!mark || mark.visible !== (ids[i] === bar.activeWorkspaceId)) { fail("active mark " + ids[i]); return }
        }
        var other = ids.filter(function(value) { return value !== bar.activeWorkspaceId
          && Grid.station(value, bar.workspaceMap) !== null })[0]
        if (other !== undefined) {
          findObject(bar, "workspaceId-" + other).pressed(Qt.LeftButton)
          if (bar.picked[0] !== Grid.station(other, bar.workspaceMap)) { fail("click " + other); return }
        }
        // Repetitive uses Omarchy's blocks and indicator: only the Station mark stays.
        var saved = bar.workspaceMap
        bar.workspaceMap = ({ outputs: saved.outputs, mode: "repetitive", counts: saved.outputs.map(function() { return 3 }),
          blocks: saved.outputs.map(function(name, index) { return index }) })
        if (!bar.omarchyIndicator || findObject(bar, "stationDrawer").visible || bar.workspaceIds.length
            || bar.width !== bar.anchorItem.width) { fail("repetitive keeps Station labels"); return }
        bar.workspaceMap = saved
        console.log("WORKSPACE_IDS " + bar.screenName + " active " + bar.activeWorkspaceId + " row " + ids.join(","))
        phase = 2
        capture.grabToImage(function(result) {
          result.saveToFile("OUTPUT/workspace-ids.png")
          console.log("WORKSPACE_IDS_OK")
          Qt.quit()
        })
      }
    }
  }
}
'''.replace("OUTPUTS", json.dumps(outputs)).replace("OUTPUT/", str(output) + "/")
    (root / "shell.qml").write_text(qml)
    result = subprocess.run(["quickshell", "--no-color", "-p", str(root)],
                            env=dict(os.environ, QT_QPA_PLATFORM="wayland"), text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    print(output)
    if "WORKSPACE_IDS_OK" not in result.stdout or any(token in result.stdout for token in
            ("ERROR", "ReferenceError", "TypeError", "Binding loop", "Unable to assign",
             "WORKSPACE_IDS_FAILED")):
        raise SystemExit(1)

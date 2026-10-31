"""Offscreen pointer/geometry checks against production bar; read-only live feed."""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="station-open-apps-") as directory:
    root = Path(directory)
    for name in ("Commons", "Ui"):
        (root / name).symlink_to(Path("/usr/share/omarchy/shell") / name)
    (root / "Station").symlink_to(repo / "lib")
    (root / "shell.qml").write_text('''import QtQuick
import QtQuick.Window
import QtTest
import Quickshell
import "Station" as Station
ShellRoot {
  Station.OpenAppsController { id: feed; mapping: ({ outputs: ["A", "B"] }) }
  QtObject {
    id: host
    property bool foregroundAnimationEnabled: false
    property bool vertical: false
    property int barSize: 32
    property real effectiveContentSize: 0
    property string position: "top"
    property string fontFamily: "sans-serif"
    property color barForeground: "white"
    property color urgent: "red"
    function hideTooltip(item) {}
    function showTooltip(item, text) {}
  }
  Window {
    visible: true; width: 2000; height: 1000
    Station.StationBar {
      id: bar
      bar: host
      property int selected: 0
      stationNumber: 2
      onStationSelected: function(number) { selected = number }
      stationApps: ({ 1: [{ address: "a", appId: "dev.zed.Zed", initialAppId: "", title: "A", focused: true },
        { address: "b", appId: "missing-app-for-fallback", initialAppId: "", title: "B", focused: false }], 2: [], 3: [] })
    }
    Timer {
      interval: 200; running: true
      onTriggered: {
        try { checks.test_drawer() } finally { Qt.quit() }
      }
    }
    TestCase {
      id: checks
      name: "StationDrawer"
      when: false
      function test_drawer() {
        tryVerify(function() { return feed.clients.length > 0 }, 4000)
        var collapsed = bar.width
        var arrow = findChild(bar, "stationExpander")
        mouseMove(arrow, arrow.width / 2, arrow.height / 2)
        tryCompare(bar, "expanded", true)
        tryCompare(bar, "revealProgress", 1, 1000)
        verify(bar.width > collapsed)
        var first = findChild(bar, "stationLabel-1")
        var app = findChild(bar, "stationApp-a")
        var secondApp = findChild(bar, "stationApp-b")
        var next = findChild(bar, "stationGroup-2")
        compare(Math.round(app.mapToItem(bar, 0, 0).x - first.mapToItem(bar, first.width, 0).x), Math.round(bar.labelGap))
        compare(Math.round(secondApp.x - app.x - app.width), Math.round(bar.appGap))
        var group = findChild(bar, "stationGroup-1")
        compare(Math.round(next.x - group.x - group.width), Math.round(bar.stationGap))
        verify(app.width < bar.logoSize)
        var captured = false
        bar.grabToImage(function(result) {
          result.saveToFile("/tmp/station-drawer-preview.png")
          captured = true
        })
        tryVerify(function() { return captured }, 1000)
        mouseClick(app, app.width / 2, app.height / 2)
        compare(bar.selected, 1)
        mouseClick(findChild(bar, "stationLabel-3"), 2, 2)
        compare(bar.selected, 3)
        mouseMove(bar, bar.width + 100, bar.height + 100)
        tryCompare(bar, "expanded", false)
        tryCompare(bar, "revealProgress", 0, 1000)
        compare(bar.width, collapsed)
        host.vertical = true
        verify(bar.height > bar.width)
        bar.expanded = true
        tryCompare(bar, "revealProgress", 1, 1000)
        host.effectiveContentSize = 24
        bar.stationApps = ({ 1: bar.stationApps[1].map(function(row) {
          return Object.assign({}, row, { focused: !row.focused })
        }), 2: [], 3: [] })
        wait(100)
        var images = []
        function walk(item) {
          if ("stationRasterManaged" in item && item.stationRasterManaged) images.push(item)
          for (var child of item.children || []) walk(child)
        }
        walk(bar)
        compare(images.length, 2)
        for (var item of images) {
          var expected = Math.ceil(item.width * item.Screen.devicePixelRatio * bar.rasterZoom)
          compare(item.sourceSize.width, expected)
          compare(item.layer.textureSize.width, expected)
        }
        feed.active = false
        compare(Object.keys(feed.rows).length, 0)
        bar.showApps = false
        tryCompare(bar, "revealProgress", 0, 1000)
        verify(!arrow.visible)
        console.log("OPEN_APPS_SMOKE_PASSED")
      }
      function cleanupTestCase() { Qt.quit() }
    }
  }
}
''')
    result = subprocess.run(["quickshell", "--no-color", "-p", str(root)],
                            env=dict(os.environ, QT_QPA_PLATFORM="offscreen"),
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=15)
    print(result.stdout)
    assert "OPEN_APPS_SMOKE_PASSED" in result.stdout
    assert not any(error in result.stdout for error in ("FAIL!", "TypeError", "ReferenceError", "Error:", "Unable to assign"))

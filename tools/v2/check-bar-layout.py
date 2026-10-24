"""Exercise Station's bar controls with the installed WidgetButton offscreen.

Only theme tokens and the bar API are doubled; no desktop changes are made.
"""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='station-bar-test-') as directory:
    root = Path(directory)
    (root / 'assets').symlink_to(repo / 'assets', target_is_directory=True)
    (root / 'Station').symlink_to(repo / 'lib', target_is_directory=True)
    ui = root / 'qs' / 'Ui'
    commons = root / 'qs' / 'Commons'
    ui.mkdir(parents=True)
    commons.mkdir(parents=True)
    (ui / 'qmldir').write_text('module qs.Ui\nWidgetButton 1.0 WidgetButton.qml\n')
    (ui / 'WidgetButton.qml').write_text(Path('/usr/share/omarchy/shell/Ui/WidgetButton.qml').read_text())
    (commons / 'qmldir').write_text('module qs.Commons\nsingleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\n')
    (commons / 'Style.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
  property var font: ({family: "monospace", body: 12})
  property var bar: ({sizeHorizontal: 26})
  property int cornerRadius: 0
  function space(n) { return Math.round(n * font.body / 12) }
  function spaceReal(n) { return n * font.body / 12 }
}
''')
    (commons / 'Color.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
  property color foreground: "white"
  property color urgent: "red"
  property color accent: "white"
  property var popups: ({text: "white"})
}
''')
    (root / 'tst_bar.qml').write_text('''import QtQuick
import QtTest
import qs.Commons
import qs.Ui as Ui
import "Station" as Station
Item {
  width: 300; height: 300
  QtObject {
    id: bar
    property string position: "top"
    readonly property bool vertical: position === "left" || position === "right"
    property int extraHeight: 0
    readonly property int barSize: Style.space(26) + extraHeight
    property string fontFamily: "monospace"
    property color barForeground: "white"
    property color urgent: "red"
    property bool foregroundAnimationEnabled: false
    function registerClickTarget(item) {}
    function unregisterClickTarget(item) {}
    function hideTooltip(item) {}
    function showTooltip(item, text) {}
  }
  Ui.WidgetButton {
    id: menu
    bar: bar
    text: "\\ue900"
    fontFamily: "omarchy"
    horizontalMargin: 7.5
  }
  Station.StationBar {
    id: controls
    bar: bar
    x: bar.vertical ? 0 : menu.width
    y: bar.vertical ? menu.height : 0
    width: implicitWidth
    height: implicitHeight
  }
  SignalSpy { id: pressed; target: controls; signalName: "pressed" }
  TestCase {
    name: "StationBar"
    when: windowShown
    function test_layout_data() {
      var rows = []
      for (var size of [10, 12, 18])
        for (var position of ["top", "bottom", "left", "right"])
          for (var extraHeight of [0, 1, 20])
          for (var zoom of [1, 1.75, 2.5])
          for (var station of [1, 10])
            rows.push({tag: size + "-" + position + "-S" + station + "-height" + extraHeight + "-zoom" + zoom,
              size: size, position: position, station: station, extraHeight: extraHeight, zoom: zoom})
      return rows
    }
    function test_layout(data) {
      Style.font = {family: "monospace", body: data.size}
      bar.position = data.position
      bar.extraHeight = data.extraHeight
      menu.scale = data.zoom
      controls.scale = data.zoom
      controls.stationNumber = data.station
      wait(30)
      var logo = controls.anchorItem
      var indicator = controls.children.filter(function(item) { return item.text === "S" + data.station })[0]
      verify(indicator !== undefined)
      compare(indicator.text, "S" + data.station)
      verify(controls.logoSize > 0)
      var label = indicator.children.filter(function(item) { return item.text === indicator.text && item.visible })[0]
      var mark = logo.children.filter(function(item) { return item.tint !== undefined })[0]
      verify(mark !== undefined && label !== undefined)
      var metrics = Qt.createQmlObject('import QtQuick; FontMetrics {}', controls)
      metrics.font = label.font
      var ink = metrics.tightBoundingRect(label.text)
      verify(label.x + ink.x >= 0)
      verify(label.x + ink.x + ink.width <= indicator.width)
      verify(label.y + label.baselineOffset + ink.y >= 0)
      verify(label.y + label.baselineOffset + ink.y + ink.height <= indicator.height)
      if (bar.vertical) {
        compare(controls.width, bar.barSize)
        compare(logo.width, bar.barSize)
        compare(indicator.width, bar.barSize)
        compare(indicator.x, 0)
        compare(indicator.y, logo.height)
        compare(controls.height, logo.height + indicator.height)
        compare(logo.height, menu.height)
      } else {
        compare(controls.height, bar.barSize)
        compare(logo.y, indicator.y)
        compare(logo.height, indicator.height)
        var labelTop = label.y + label.baselineOffset + ink.y
        verify(Math.abs(mark.y + mark.height / 2 - labelTop - ink.height / 2) <= 0.5,
          "painted vertical centers must match")
        var menuLabel = menu.children.filter(function(item) { return item.text === menu.text })[0]
        var menuRight = menuLabel.x + controls.menuInk.x + controls.menuInk.width
        var firstGap = menu.width + mark.x - menuRight
        var secondGap = indicator.x + label.x + ink.x - mark.x - mark.width
        verify(Math.abs(firstGap - secondGap) <= 0.5, "painted gaps must match: " + firstGap + " / " + secondGap + "; menu=" + menu.width + "; slot=" + controls.menuSlotWidth)
        var menuTop = menuLabel.y + menuLabel.baselineOffset + controls.menuInk.y
        compare(mark.y, menuTop)
        compare(mark.y * data.zoom, menuTop * data.zoom)
        compare(mark.height, controls.menuInk.height)
      }
      metrics.destroy()
      pressed.clear()
      mouseClick(logo, logo.width / 2, logo.height / 2)
      mouseClick(indicator, indicator.width / 2, indicator.height / 2)
      compare(pressed.count, 2)
    }
  }
}
''')
    environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_CONTROLS_STYLE='Basic')
    result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-import', str(root), '-input', str(root)],
                            env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    raise SystemExit(result.returncode)

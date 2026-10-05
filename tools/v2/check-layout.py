"""Exercise the production layout component with Qt pointer events offscreen.

Only the Omarchy paint tokens/surface and preview compositor call are doubled.
The real QML drag handler, JS geometry, and Service position setter run unchanged.
No live compositor input, monitor changes, or desktop configuration writes.
"""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
service = (repo / 'Service.qml').read_text()
start = service.index('  function setDisplayPosition(')
end = service.index('\n  function ', start + 1)
setter = service[start:end]
with tempfile.TemporaryDirectory(prefix='station-layout-test-') as directory:
    root = Path(directory)
    probe = root / 'Probe'
    probe.mkdir()
    for name in ('DisplayLayout.qml', 'Model.js', 'MonitorsLua.js'):
        (probe / name).write_text((repo / 'lib' / name).read_text())
    ui = root / 'qs' / 'Ui'
    commons = root / 'qs' / 'Commons'
    ui.mkdir(parents=True)
    commons.mkdir(parents=True)
    (ui / 'qmldir').write_text('module qs.Ui\nBorderSurface 1.0 BorderSurface.qml\n')
    (ui / 'BorderSurface.qml').write_text('import QtQuick\nRectangle { property var borderSpec }\n')
    (commons / 'qmldir').write_text('module qs.Commons\nsingleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\nsingleton Border 1.0 Border.qml\n')
    (commons / 'Style.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
  property var spacing: ({md: 8})
  property int cornerRadius: 0
  property int normalBorderWidth: 1
  property var font: ({family: "monospace", caption: 12})
  function space(n) { return n * 5 / 6 }
}
''')
    (commons / 'Color.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
  property var popups: ({background: "black", border: "white"})
  property var menu: ({background: "black", text: "white", selectedBackground: "grey", selectedText: "white"})
  property string accent: "white"
}
''')
    (commons / 'Border.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
  function surfaceSpec() { return {} }
  function controlSpec() { return {} }
}
''')
    (root / 'tst_layout.qml').write_text('''import QtQuick
import QtTest
import "Probe" as Station
import "Probe/Model.js" as Model
import "Probe/MonitorsLua.js" as MonitorsLua
Item {
  width: 567; height: 240
  QtObject {
    id: service
    property string state: "idle"
    property var displayDraft: []
    property int previews: 0
    property int writes: 0
    onDisplayDraftChanged: writes++
''' + setter + '''
    function previewLayout() {
      if (Model.layoutOverlaps(displayDraft).length) throw new Error("Displays overlap")
      previews++
      state = "previewing"
    }
  }
  Flickable {
    id: panelScroll
    width: 567; height: 180
    contentWidth: width; contentHeight: 420
    clip: true
    Station.DisplayLayout { id: layout; width: panelScroll.width; service: service }
  }
  TestCase {
    name: "DisplayLayout"; when: windowShown
    function initTestCase() { failOnWarning(/.*/) }
    function init() {
      service.state = "idle"
      service.displayDraft = [
        {name:"eDP-1", x:0, y:1200, width:1920, height:1080, scale:1, transform:0, enabled:true, lane:1},
        {name:"HDMI-A-2", x:0, y:0, width:1920, height:1200, scale:1, transform:0, enabled:true, lane:2}
      ]
      service.previews = 0; service.writes = 0
      wait(10)
    }
    function card(name) {
      for (var i = 0; i < layout.children.length; i++)
        if (layout.children[i].modelData && layout.children[i].modelData.name === name) return layout.children[i]
      fail("Missing card " + name)
    }
    function move(name, x, y) {
      var target = card(name), display = target.modelData
      mouseDrag(layout, target.x + target.width / 2, target.y + target.height / 2,
        (x - display.x) * layout.zoom, (y - display.y) * layout.zoom, Qt.LeftButton, Qt.NoModifier, 5)
      compare(service.writes, 1, "Both axes must publish in one model update")
      compare(service.previews, 1, "Preview must survive rebuilding the delegate")
      var changed = service.displayDraft.filter(function(d) { return d.name === name })[0]
      compare(changed.x, x); compare(changed.y, y)
      compare(Model.layoutOverlaps(service.displayDraft).length, 0)
    }
    function test_horizontal_right() { move("HDMI-A-2", 1920, 1200) }
    function test_horizontal_left_negative() { move("HDMI-A-2", -1920, 1200) }
    function test_vertical_below() { move("HDMI-A-2", 0, 2280) }
    function test_vertical_drag_is_not_stolen_by_panel_scroll() {
      move("HDMI-A-2", 0, 2280)
      compare(panelScroll.contentY, 0)
    }
    function test_click_only_selects() {
      var target = card("HDMI-A-2")
      mouseClick(target, target.width / 2, target.height / 2)
      compare(service.previews, 0); compare(service.writes, 0)
    }
    function test_drag_after_revert() {
      move("HDMI-A-2", 1920, 1200)
      init() // the service republishes the old geometry on Revert
      move("HDMI-A-2", -1920, 1200)
    }
    function test_edge_snap_in_screen_pixels() { moveNearEdge() }
    function moveNearEdge() {
      var target = card("HDMI-A-2")
      var dx = 1920 * layout.zoom - 7, dy = 1200 * layout.zoom + 5
      mouseDrag(layout, target.x + target.width/2, target.y + target.height/2,
        dx, dy, Qt.LeftButton, Qt.NoModifier, 5)
      compare(service.displayDraft[1].x, 1920); compare(service.displayDraft[1].y, 1200)
      compare(service.previews, 1)
    }
    function test_scaled_rotated_selected_mode() {
      var displays = service.displayDraft.slice()
      displays[1] = Object.assign({}, displays[1], {mode:"2560x1440@60.00Hz", scale:2, transform:1})
      service.displayDraft = displays
      service.writes = 0; wait(10)
      compare(card("HDMI-A-2").width / layout.zoom, 720)
      compare(card("HDMI-A-2").height / layout.zoom, 1280)
      move("HDMI-A-2", 1920, 1200)
    }
    function test_three_large_displays_fit() {
      service.displayDraft = [0,1,2].map(function(i) {
        return {name:"DP-" + (i+1), x:i*3840, y:0, width:3840, height:2160, scale:1, transform:0, enabled:true, lane:i+1}
      })
      wait(10)
      for (var i=0;i<3;i++) {
        var target=card("DP-"+(i+1))
        verify(target.x >= layout.inset - 0.01)
        verify(target.x + target.width <= layout.width - layout.inset + 0.01)
        verify(target.y >= layout.inset - 0.01)
        verify(target.y + target.height <= layout.height - layout.inset + 0.01)
      }
    }
    function test_invalid_position_is_rejected() {
      compare(service.setDisplayPosition("missing", 0, 0), "invalid")
      compare(service.setDisplayPosition("eDP-1", NaN, 0), "invalid")
      service.state = "previewing"
      compare(service.setDisplayPosition("eDP-1", 1920, 0), "invalid")
      compare(service.writes, 0)
    }
  }
}
''')
    environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_CONTROLS_STYLE='Basic')
    result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-import', str(root), '-input', str(root)],
                            env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    raise SystemExit(result.returncode)

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
for name in ('setDisplayValue', 'setDisplayEnabled', 'displayEnabled'):
    start = service.index('  function ' + name + '(')
    end = service.index('\n  function ', start + 1)
    setter += service[start:end]
# The setter gates on the same editable flag the service declares, so the
# probe has to declare it too or the real function throws.
editable = next(line for line in service.splitlines() if 'property bool draftEditable' in line).strip()
with tempfile.TemporaryDirectory(prefix='station-layout-test-') as directory:
    root = Path(directory)
    probe = root / 'Probe'
    probe.mkdir()
    for name in ('DisplayLayout.qml', 'BarLayout.qml', 'InlineDropdown.qml', 'Model.js', 'MonitorsLua.js'):
        (probe / name).write_text((repo / 'lib' / name).read_text())
    ui = root / 'qs' / 'Ui'
    commons = root / 'qs' / 'Commons'
    ui.mkdir(parents=True)
    commons.mkdir(parents=True)
    (ui / 'qmldir').write_text('module qs.Ui\nBorderSurface 1.0 BorderSurface.qml\nToggleSwitch 1.0 ToggleSwitch.qml\n')
    (ui / 'BorderSurface.qml').write_text('import QtQuick\nRectangle { property var borderSpec }\n')
    (ui / 'ToggleSwitch.qml').write_text('''import QtQuick
Item {
  property real trackHeight
  property bool checked
  property color foreground
  property color accent
  signal toggled()
}
''')
    (commons / 'qmldir').write_text('module qs.Commons\nsingleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\nsingleton Border 1.0 Border.qml\n')
    (commons / 'Style.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
  property var spacing: ({xs: 3, sm: 4, md: 8, xxs: 2, xxl: 12, popupRowHeight: 24, hairline: 1, controlPaddingX: 8})
  property int cornerRadius: 0
  property int normalBorderWidth: 1
  property var font: ({family: "monospace", caption: 12, body: 12, title: 14, display: 24})
  function space(n) { return n * 5 / 6 }
}
''')
    (commons / 'Color.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
  property var popups: ({background: "black", border: "white", text: "white"})
  property var menu: ({background: "black", text: "white", border: "white", selectedBackground: "grey", selectedText: "white"})
  property string accent: "white"
}
''')
    (commons / 'Border.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
  function surfaceSpec() { return {} }
  function controlSpec() { return {} }
  function flat(color, width) { return { color: color, width: width } }
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
    property bool previewBusy: false
    property string draftMode: "extend"
    property string draftSingleTarget: ""
    property string layoutError: ""
    ''' + editable + '''
    property var displayDraft: []
    property int previews: 0
    property int writes: 0
    onDisplayDraftChanged: writes++
    function roleOf(name) {
      for (var i = 0; i < displayDraft.length; i++) if (displayDraft[i].name === name) return i
      return -1
    }
    function monitorBar(name) { return {enabled: true, position: "top"} }
    function setMonitorBarPosition(name, position) {}
    function setMonitorBarEnabled(name, enabled) {}
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
  QtObject {
    id: barPanelRoot
    property var service: service
    property real disabledOpacity: 0.5
    property real space2: 2
    property real space4: 4
  }
  Station.BarLayout {
    id: barLayout
    width: 567; height: 370
    panelRoot: barPanelRoot
    visible: false
  }
  TestCase {
    name: "DisplayLayout"; when: windowShown
    function initTestCase() { failOnWarning(/.*/) }
    function init() {
      service.state = "idle"
      panelScroll.cancelFlick()
      panelScroll.contentY = 0
      layout.selectedDisplayName = ""
      layout.zoomFactor = 1; layout.panX = 0; layout.panY = 0
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
    function barCard(name) {
      for (var i = 0; i < barLayout.children.length; i++)
        if (barLayout.children[i].modelData && barLayout.children[i].modelData.name === name) return barLayout.children[i]
      fail("Missing bar card " + name)
    }
    function move(name, x, y) {
      var target = card(name), display = target.modelData
      mouseDrag(layout, target.x + target.width / 2, target.y + target.height * 0.8,
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
    function test_card_off_survives_delegate_destruction() {
      var menu = findChild(card("HDMI-A-2"), "monitorRoleMenu")
      verify(menu !== null)
      menu.changed("off")
      compare(service.previews, 1, "Off must start preview even when the model destroys its menu")
      compare(service.writes, 1)
      compare(service.displayDraft[1].enabled, false)
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
      mouseDrag(layout, target.x + target.width/2, target.y + target.height * 0.8,
        dx, dy, Qt.LeftButton, Qt.NoModifier, 5)
      compare(service.displayDraft[1].x, 1920); compare(service.displayDraft[1].y, 1200)
      compare(service.previews, 1)
    }
    function test_scaled_rotated_selected_mode() {
      var displays = service.displayDraft.slice()
      displays[1] = Object.assign({}, displays[1], {mode:"2560x1440@60.00Hz", scale:2, transform:1})
      service.displayDraft = displays
      service.writes = 0; wait(10)
      fuzzyCompare((card("HDMI-A-2").width + layout.monitorGap) / layout.zoom, 720, 0.01)
      fuzzyCompare((card("HDMI-A-2").height + layout.monitorGap) / layout.zoom, 1280, 0.01)
      move("HDMI-A-2", 1920, 1200)
    }
    function test_three_large_displays_fit() {
      service.displayDraft = [0,1,2].map(function(i) {
        return {name:"DP-" + (i+1), x:i*3840, y:0, width:3840, height:2160, scale:1, transform:0, enabled:true, lane:i+1}
      })
      wait(10)
      for (var i=0;i<3;i++) {
        var target=card("DP-"+(i+1))
        verify(target.x >= layout.horizontalInset - 0.01)
        verify(target.x + target.width <= layout.width - layout.horizontalInset + 0.01)
        verify(target.y >= layout.verticalInset - 0.01)
        verify(target.y + target.height <= layout.height - layout.verticalInset + 0.01)
      }
    }
    function test_adjacent_displays_have_the_compact_visual_gap() {
      service.displayDraft = [
        {name:"eDP-1", x:0, y:0, width:1920, height:1080, scale:1, transform:0, enabled:true, lane:1},
        {name:"HDMI-A-2", x:1920, y:0, width:1920, height:1080, scale:1, transform:0, enabled:true, lane:2}
      ]
      wait(10)
      var first = card("eDP-1"), second = card("HDMI-A-2")
      fuzzyCompare(second.x - first.x - first.width, layout.monitorGap, 0.01)
    }
    function test_adjacent_bar_cards_have_the_compact_visual_gap() {
      service.displayDraft = [
        {name:"eDP-1", x:0, y:0, width:1920, height:1080, scale:1, transform:0, enabled:true, lane:1},
        {name:"HDMI-A-2", x:1920, y:0, width:1920, height:1080, scale:1, transform:0, enabled:true, lane:2}
      ]
      wait(10)
      var first = barCard("eDP-1"), second = barCard("HDMI-A-2")
      fuzzyCompare(second.x - first.x - first.width, barLayout.monitorGap, 0.01)
    }
    function test_rotation_handles_hover_diagonally_outside_all_four_corners() {
      service.displayDraft = [
        {name:"eDP-1", x:0, y:0, width:1920, height:1080, scale:1, transform:0, enabled:true, lane:1},
        {name:"HDMI-A-2", x:1920, y:0, width:1920, height:1080, scale:1, transform:0, enabled:true, lane:2}
      ]
      layout.selectedDisplayName = "eDP-1"
      wait(10)
      var selected = card("eDP-1"), neighbor = card("HDMI-A-2")
      var toolbar = findChild(layout, "rotationTools")
      var corners = ["rotateTopLeft", "rotateTopRight", "rotateBottomLeft", "rotateBottomRight"]
      var handles = corners.map(function(name) { return findChild(toolbar, name) })
      for (var handle of handles) verify(handle !== null)
      verify(toolbar.z > selected.z && toolbar.z > neighbor.z,
        "Rotation controls must paint above neighboring cards")
      mouseMove(layout, 10, 10)
      for (var handle of handles) verify(!findChild(handle, "rotationIcon").visible,
        "Icons must stay hidden away from corners")
      for (var i = 0; i < handles.length; i++) {
        if (i === 2) {
          panelScroll.contentY = Math.max(0,
            selected.y + selected.height + toolbar.outerExtent - panelScroll.height + 10)
          wait(10)
        }
        var handle = handles[i]
        var icon = findChild(handle, "rotationIcon")
        var iconTop = icon.mapToItem(layout, 0, 0)
        var right = i % 2 === 1, bottom = i >= 2
        if (right) verify(iconTop.x >= selected.x + selected.width,
          "Right rotation icon belongs diagonally outside the card")
        else verify(iconTop.x + icon.width <= selected.x,
          "Left rotation icon belongs diagonally outside the card")
        if (bottom) verify(iconTop.y >= selected.y + selected.height,
          "Bottom rotation icon belongs diagonally outside the card")
        else verify(iconTop.y + icon.height <= selected.y,
          "Top rotation icon belongs diagonally outside the card")
        verify(iconTop.y >= 0 && iconTop.y + icon.height <= layout.height,
          "Rotation icon must stay within the canvas at fit zoom")
        var corner = Qt.point(
          selected.x + (right ? selected.width - toolbar.reachX / 2 : toolbar.reachX / 2),
          selected.y + (bottom ? selected.height - toolbar.reachY / 2 : toolbar.reachY / 2))
        mouseMove(layout, corner.x, corner.y)
        verify(icon.visible, corners[i] + " should reveal on hover")
        var iconCenter = icon.mapToItem(layout, icon.width / 2, icon.height / 2)
        mouseMove(layout, iconCenter.x, iconCenter.y)
        verify(icon.visible, "Icon stays visible while moving diagonally out to click it")
        mouseMove(layout, 10, panelScroll.contentY + 10)
        verify(!icon.visible, "Icon hides again when the pointer leaves")
      }
      panelScroll.contentY = 0
      wait(10)
      var clockwise = handles[1]
      var clockwiseIcon = findChild(clockwise, "rotationIcon")
      var hit = clockwiseIcon.mapToItem(layout, clockwiseIcon.width / 2, clockwiseIcon.height / 2)
      mouseMove(layout, selected.x + selected.width - toolbar.reachX / 2,
        selected.y + toolbar.reachY / 2)
      mouseMove(layout, hit.x, hit.y)
      verify(clockwiseIcon.visible)
      mouseClick(layout, hit.x, hit.y)
      compare(service.previews, 1, "External handle remains clickable")
      compare(service.displayDraft[0].transform, 1)
      compare(toolbar.selectedCard, card("eDP-1"),
        "Rotation overlay must follow a replaced monitor delegate")
    }
    function test_rotation_handle_over_taller_neighbor_remains_clickable() {
      service.displayDraft = [
        {name:"HDMI-A-2", x:0, y:0, width:1920, height:2160, scale:1, transform:0, enabled:true, lane:1},
        {name:"eDP-1", x:1920, y:800, width:720, height:1280, scale:1, transform:0, enabled:true, lane:2}
      ]
      layout.selectedDisplayName = "eDP-1"
      wait(10)
      var selected = card("eDP-1"), neighbor = card("HDMI-A-2")
      var counterclockwise = findChild(layout, "rotateTopLeft")
      var icon = findChild(counterclockwise, "rotationIcon")
      var toolbar = findChild(layout, "rotationTools")
      var corner = Qt.point(selected.x + toolbar.reachX / 2,
        selected.y + toolbar.reachY / 2)
      mouseMove(layout, corner.x, corner.y)
      verify(icon.visible)
      verify(!findChild(findChild(layout, "rotateTopRight"), "rotationIcon").visible,
        "Narrow monitor corners must not reveal both icons at once")
      var hit = icon.mapToItem(layout, icon.width / 2, icon.height / 2)
      verify(hit.x < neighbor.x + neighbor.width,
        "Narrow card's external handle must cross the neighbor's edge")
      verify(hit.y > neighbor.y && hit.y < neighbor.y + neighbor.height,
        "Handle must overlap the taller neighbor vertically")
      verify(hit.y < selected.y, "Handle remains above the selected card")
      compare(layout.childAt(hit.x, hit.y), findChild(layout, "rotationTools"),
        "Rotation toolbar must be the top hit target")
      var local = toolbar.mapFromItem(layout, hit.x, hit.y)
      compare(toolbar.childAt(local.x, local.y), counterclockwise,
        "Rotation icon must be inside the toolbar hit target")
      mouseClick(layout, hit.x, hit.y)
      compare(service.displayDraft[1].transform, 3)
      compare(service.previews, 1, "Handle must win the hit test over the neighbor")
    }
    function test_zoom_keeps_pointer_position_stable() {
      var target = card("HDMI-A-2")
      var oldWidth = target.width
      var oldCenterX = target.x + target.width / 2
      var oldCenterY = target.y + target.height / 2
      layout.zoomAt(1.2, oldCenterX, oldCenterY)
      verify(target.width > oldWidth)
      compare(Math.round(target.x + target.width / 2), Math.round(oldCenterX))
      compare(Math.round(target.y + target.height / 2), Math.round(oldCenterY))
      compare(service.previews, 0)
    }
    function test_background_pan_does_not_modify_monitor_layout() {
      var oldX = layout.panX, oldY = layout.panY
      mouseDrag(layout, 12, 12, 30, 20, Qt.LeftButton, Qt.NoModifier, 5)
      verify(layout.panX > oldX)
      verify(layout.panY > oldY)
      compare(service.writes, 0)
      compare(service.previews, 0)
    }
    function test_invalid_position_is_rejected() {
      compare(service.setDisplayPosition("missing", 0, 0), "invalid")
      compare(service.setDisplayPosition("eDP-1", NaN, 0), "invalid")
      service.state = "applyingLayout"
      compare(service.setDisplayPosition("eDP-1", 1920, 0), "invalid")
      compare(service.writes, 0)
      service.state = "previewing"
      compare(service.setDisplayPosition("eDP-1", 1920, 0), "ok")
      compare(service.writes, 1)
    }
    function test_drag_while_a_preview_is_pending() {
      move("HDMI-A-2", 1920, 1200)
      compare(service.state, "previewing")
      var target = card("HDMI-A-2"), display = target.modelData
      // The 10%-inset default fit makes cards intentionally larger. Scroll
      // the compact harness viewport so the second drag begins on a visible
      // point while still exercising the production MouseArea.
      panelScroll.contentY = Math.max(0,
        target.y + target.height * 0.8 - panelScroll.height / 2)
      wait(10)
      mouseDrag(layout, target.x + target.width / 2, target.y + target.height * 0.8,
        (-1920 - display.x) * layout.zoom, (1200 - display.y) * layout.zoom,
        Qt.LeftButton, Qt.NoModifier, 5)
      compare(service.previews, 2, "A re-arrangement joins the pending preview")
      var changed = service.displayDraft.filter(function(d) { return d.name === "HDMI-A-2" })[0]
      compare(changed.x, -1920); compare(changed.y, 1200)
      compare(Model.layoutOverlaps(service.displayDraft).length, 0)
    }
  }
}
''')
    environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_CONTROLS_STYLE='Basic')
    result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-import', str(root), '-input', str(root)],
                            env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    raise SystemExit(result.returncode)

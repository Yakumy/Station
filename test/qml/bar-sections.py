"""Exercise production center layout and tray hosting with isolated widget doubles."""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
source = (repo / 'lib/bars/omarchy/MonitorBar.qml').read_text()
center = source[source.index('  component CenterModules:'):source.index('  component CenterGestureArea:')]
lists = source[source.index('  Component {\n    id: traySectionComponent'):source.index('  component ModuleSlot:')]
start = source.index('    Loader {\n      id: traySectionLoader')
tray_loader = source[start:source.index('\n    BorderSurface {', start)]
start = source.index('      Rectangle {\n        visible: root.barStyle === "pill" && centerModules.visibleLength')
pill = source[start:source.index('\n      Rectangle {', start + 10)]
pill = pill.replace('centerModules', 'middle').replace('barContent', 'root').replace('Rectangle {', 'Rectangle {\n        id: pill', 1)
qml = '''import QtQuick
import QtTest
import "MODEL" as BarModel
Item {
  id: root
  width: 800; height: 800
  property bool vertical: false
  property int barSize: 40
  property real contentScale: 1
  property bool traySectionDragActive: false
  property string barStyle: "pill"
  property real pillInset: 4
  property real pillPadding: 8
  property color barSurfaceColor: "white"
  property string centerAnchor: "clock"
  property var rows: ({center: [{id:"clock", size:40}],
    centerBegin: [{id:"before", size:60}], centerEnd: [{id:"after", size:20}], tray: []})
  function layoutEntries(region) { return rows[region] || [] }
  function entryIndex(entries, name) { return BarModel.entryIndex(entries, name) }
  function entriesBefore(entries, name) { return BarModel.entriesBefore(entries, name) }
  function entriesAfter(entries, name) { return BarModel.entriesAfter(entries, name) }
  function findCenterAnchorEntry() { return rows.center.find(function(e) { return e.id === centerAnchor }) || {} }
  function setCenterSectionHovered(value) {}
  component CenterGestureArea: Item {}
  component ModuleSlot: Item {
    id: slot
    required property var entry
    property string region: ""
    property real inheritedScale: 1
    readonly property string moduleName: entry.id || ""
    readonly property bool hostsTraySection: moduleName === "omarchy.tray" && region !== "tray"
    readonly property var activeItem: fakeWidget
    readonly property real baseFlowLength: entry.size || 0
    readonly property real maximumBaseFlowLength: baseFlowLength
    implicitWidth: root.vertical ? root.barSize / inheritedScale : baseFlowLength * root.contentScale / inheritedScale
    implicitHeight: root.vertical ? baseFlowLength * root.contentScale / inheritedScale : root.barSize / inheritedScale
    width: implicitWidth; height: implicitHeight
    Item {
      id: fakeWidget
      property Item sectionHost: drawerHost
      property string sectionEdge: "start"
      Item { id: drawerHost; implicitWidth: childrenRect.width; implicitHeight: childrenRect.height; width: implicitWidth; height: implicitHeight }
    }
TRAY_LOADER
  }
CENTER
LISTS
  Item {
    width: root.vertical ? 40 : 600; height: root.vertical ? 600 : 40
    CenterModules { id: middle; anchors.fill: parent }
PILL
  }
  ModuleSlot { id: tray; y: 650; entry: ({id:"omarchy.tray",size:40}); region:"right" }
  TestCase {
    name: "BarSections"; when: windowShown
    function findSlot(node, id) {
      if (node.moduleName === id) return node
      for (var i = 0; i < node.children.length; i++) {
        var found = findSlot(node.children[i], id)
        if (found) return found
      }
      return null
    }
    function test_centerGeometry() {
      for (var orientation = 0; orientation < 2; orientation++) {
        root.vertical = orientation === 1
        for (var zoom = 1; zoom <= 2; zoom++) {
          root.contentScale = zoom
          wait(30)
          var clock = findSlot(middle, "clock")
          var before = findSlot(middle, "before")
          var after = findSlot(middle, "after")
          var c = clock.mapToItem(middle, 0, 0)
          var b = before.mapToItem(middle, 0, 0)
          var a = after.mapToItem(middle, 0, 0)
          compare((root.vertical ? c.y : c.x) + 20 * zoom, 300)
          compare(root.vertical ? b.y + before.height : b.x + before.width, root.vertical ? c.y : c.x)
          compare(root.vertical ? a.y : a.x, (root.vertical ? c.y : c.x) + 40 * zoom)
          compare(middle.leadingExtent, 80 * zoom)
          compare(middle.trailingExtent, 40 * zoom)
          compare(middle.maximumBaseLeadingExtent, 80)
          for (var theme = 0; theme < 2; theme++) {
            root.barSurfaceColor = theme === 0 ? "white" : "black"
            compare(pill.color, root.barSurfaceColor)
            compare((root.vertical ? pill.y : pill.x), 300 - 80 * zoom - root.pillPadding)
            compare((root.vertical ? pill.height : pill.width), 120 * zoom + root.pillPadding * 2)
          }
        }
      }
      root.vertical = false; root.contentScale = 1
    }
    function test_noAnchorAndEmptyCenter() {
      root.centerAnchor = "absent"
      wait(30)
      compare(middle.leadingExtent, 80)
      compare(middle.trailingExtent, 40)
      root.rows = {center:[], centerBegin:[{id:"before",size:60}], centerEnd:[{id:"after",size:20}], tray:[]}
      wait(30)
      compare(middle.leadingExtent, 60)
      compare(middle.trailingExtent, 20)
    }
    function test_trayHosting() {
      root.contentScale = 2
      root.rows = {center:[], tray:[{id:"drawerWidget", size:30}]}
      wait(30)
      var child = findSlot(tray.activeItem.sectionHost, "drawerWidget")
      verify(child !== null, "tray widgets are mounted in the drawer host")
      compare(child.inheritedScale, 2)
      compare(child.width, 30, "the host already applies content zoom")
      compare(child.height, 20)
      root.vertical = true
      wait(30)
      compare(child.width, 20)
      compare(child.height, 30)
      root.rows = {center:[], tray:[]}
      root.traySectionDragActive = true
      for (var orientation = 0; orientation < 2; orientation++) {
        root.vertical = orientation === 1
        wait(30)
        verify(tray.activeItem.sectionHost.width > 0, "empty drawer has a drop width")
        verify(tray.activeItem.sectionHost.height > 0, "empty drawer has a drop height")
      }
    }
  }
}
'''.replace('MODEL', (repo / 'lib/bars/omarchy/BarModel.js').as_uri()).replace('CENTER', center).replace('LISTS', lists).replace('TRAY_LOADER', tray_loader).replace('PILL', pill)
with tempfile.TemporaryDirectory(prefix='station-bar-sections-') as directory:
    root = Path(directory)
    # The production drawer loader uses the host's icon-slot metric.
    commons = root / 'qs/Commons'
    commons.mkdir(parents=True)
    (commons / 'qmldir').write_text('module qs.Commons\nsingleton Style 1.0 Style.qml\n')
    (commons / 'Style.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var bar: ({iconSlot:40}) }\n')
    (root / 'tst_sections.qml').write_text(qml.replace('import QtTest', 'import QtTest\nimport qs.Commons'))
    result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-import', directory, '-input', directory],
                            env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME=''),
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    raise SystemExit(result.returncode)

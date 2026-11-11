"""Real Qt pointer events on the production widget pointer owner, with effect doubles."""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
source = (repo / 'lib/bars/omarchy/MonitorBar.qml').read_text()
start = source.index('    MouseArea {\n      id: modulePointer')
pointer = source[start:source.index('\n    onActiveItemChanged:', start)]
qml = '''import QtQuick
import QtTest
Item {
  id: root
  width: 600; height: 400
  property var shell: ({mutateShellConfig: function() {}})
  property var barMoveWindow: null
  property int moves: 0
  property int finishes: 0
  property int cancels: 0
  property int clicks: 0
  property int reorders: 0
  property var barDragWindow: null
  property var barDragScreen: null
  property real barDragOffsetX: 0
  property real barDragOffsetY: 0
  property real barDragSceneX: 0
  property real barDragSceneY: 0
  property real barDragScreenX: 0
  property real barDragScreenY: 0
  property var barDragSource: null
  property var barDragTarget: null
  property string barDragRegion: ""
  property bool barDragAfter: false
  property var barDragTargetGeometry: null
  QtObject { id: moduleHover; property bool hovered: false }
  function moduleClickTargetAt() { return true }
  function clearBarDrag() { barDragTarget = null }
  function hideTooltip() {}
  function targetWindow() { return {screen: {width:600,height:400}} }
  function beginBarMove(w) { barMoveWindow = w; moves++ }
  function windowScreenPoint(p, w) { return p }
  function updateBarMove(p) {}
  function finishBarMove() { finishes++ }
  function clearBarMove() { cancels++ }
  function captureBarDragGhost() {}
  function barDragScreenPoint(p) { return p }
  function moduleDropAtScene() { return {slot:slot,region:"left",after:false} }
  function dropMarkerRect() { return {} }
  function dropBarModule() { reorders++ }
  function dropBarModuleAtTarget() { reorders++ }
  function pressModuleClickTarget() { clicks++; return true }
  Item {
    id: slot
    width: 120; height: 40; x: 200; y: 100
    property bool hostsTraySection: false
    property var activeItem: slot
POINTER
  }
  TestCase {
    name: "BarMovePointer"; when: windowShown
    function init() { root.moves=0; root.finishes=0; root.cancels=0; root.clicks=0; root.reorders=0 }
    function test_click() {
      mouseClick(slot, 30, 20)
      compare(root.clicks, 1); compare(root.moves, 0)
    }
    function test_shortDragReorders() {
      mousePress(slot, 30, 20)
      mouseMove(slot, 80, 20, 20)
      mouseRelease(slot, 80, 20)
      compare(root.reorders, 1); compare(root.moves, 0); compare(root.clicks, 0)
    }
    function test_holdMoveOutsideSlot() {
      for (var point of [[-180,20],[380,20],[30,-90],[30,280]]) {
        mousePress(slot, 30, 20)
        wait(260)
        compare(root.moves, root.finishes + 1)
        mouseMove(slot, point[0], point[1], 20)
        mouseRelease(slot, point[0], point[1])
        compare(root.finishes, root.moves)
      }
      compare(root.moves, 4); compare(root.clicks, 0); compare(root.reorders, 0)
    }
    function test_cancelHeldMove() {
      mousePress(slot, 30, 20); wait(260)
      slot.enabled = false; wait(10)
      compare(root.cancels, 1); compare(root.finishes, 0)
      mouseRelease(slot, 30, 20); slot.enabled = true
    }
  }
}
'''.replace('POINTER', pointer).replace('Style.space(4)', '4')
with tempfile.TemporaryDirectory(prefix='station-bar-move-') as directory:
    path = Path(directory) / 'tst_move.qml'
    path.write_text(qml)
    result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-input', str(path)],
        env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME=''),
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    raise SystemExit(result.returncode)

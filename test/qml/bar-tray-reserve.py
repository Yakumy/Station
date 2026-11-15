"""Run ModuleSlot's production tray-length bindings against both Omarchy tray shapes.

Omarchy 4.0's tray reserves its whole hidden drawer in its implicit size. The 4.5 tray
(issue #11) sizes to the pinned icons, the chevron and the revealed part only.
"""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
source = (repo / 'lib/bars/omarchy/MonitorBar.qml').read_text()
slot = source[source.index('  component ModuleSlot:'):]
start = slot.index('    readonly property real baseContentWidth:')
bindings = slot[start:slot.index('    readonly property real baseFlowLength:', start)]
qml = '''import QtQuick
import QtTest
import "MODEL" as BarModel
Item {
  id: root
  property bool vertical: false
  // pinned 20, chevron 12, drawer 64
  component OldTray: Item {
    property int drawerExtent: 64
    property real revealExtent: 0
    implicitWidth: vertical ? 40 : 20 + 12 + drawerExtent
    implicitHeight: vertical ? 20 + 12 + drawerExtent : 40
  }
  component NewTray: Item {
    property bool fixedAtStart: true
    property int drawerExtent: 64
    property real revealExtent: 0
    implicitWidth: vertical ? 40 : 20 + 12 + revealExtent
    implicitHeight: vertical ? 20 + 12 + revealExtent : 40
  }
  component Slot: Item {
    property string moduleName: "omarchy.tray"
    property Item activeItem: null
BINDINGS
  }
  OldTray { id: oldTray }
  NewTray { id: newTray }
  Item { id: audio; implicitWidth: 40; implicitHeight: 40 }
  Slot { id: oldSlot; activeItem: oldTray }
  Slot { id: newSlot; activeItem: newTray }
  Slot { id: audioSlot; activeItem: audio; moduleName: "omarchy.audio" }
  TestCase {
    name: "BarTrayReserve"
    function length(slot) { return root.vertical ? slot.visibleBaseContentHeight : slot.visibleBaseContentWidth }
    function test_bothTrayShapes() {
      for (var orientation = 0; orientation < 2; orientation++) {
        root.vertical = orientation === 1
        for (var reveal = 0; reveal <= 64; reveal += 32) {
          oldTray.revealExtent = reveal
          newTray.revealExtent = reveal
          verify(oldSlot.trayReservesDrawer, "4.0 tray reserves its drawer")
          verify(!newSlot.trayReservesDrawer, "4.5 tray does not")
          compare(length(oldSlot), 32 + reveal, "4.0 tray follows chevron and reveal")
          compare(oldSlot.trayFlowInset, 64 - reveal)
          compare(length(newSlot), 32 + reveal, "4.5 tray keeps its whole length")
          compare(newSlot.trayFlowInset, 0, "4.5 tray content is not shifted")
        }
        verify(!audioSlot.trayReservesDrawer)
        compare(length(audioSlot), 40)
      }
    }
  }
}
'''.replace('MODEL', (repo / 'lib/bars/omarchy/BarModel.js').as_uri()).replace('BINDINGS', bindings)
with tempfile.TemporaryDirectory(prefix='station-bar-tray-') as directory:
    (Path(directory) / 'tst_tray.qml').write_text(qml)
    result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-input', directory],
                            env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME=''),
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    raise SystemExit(result.returncode)

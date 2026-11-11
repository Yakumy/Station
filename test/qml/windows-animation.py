"""Exercise the production preview clock without compositor frame throttling."""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
source = (repo / 'lib/windows/WindowsLayout.qml').read_text()
clock = source[source.index('  property int rotation:'):source.index('  required property var service')]
qml = '''import QtQuick
import QtTest
Item {
  id: canvas
  property var displays: [{name:"A"}, {name:"B"}, {name:"C"}]
  property int count: 3
  property var service: ({displayEnabled: function(name) { return name === "A" || (canvas.count > 1 && name === "B") || canvas.count === 3 }})
CLOCK
  TestCase {
    name: "WindowsAnimation"; when: windowShown
    function test_cycles() {
      for (var count of [3, 2, 1]) {
        canvas.count = count
        canvas.previewExchange(2)
        verify(canvas.animating)
        tryCompare(canvas, "animating", false, 3000)
        compare(canvas.progress, Math.max(2, count))
        canvas.previewExchange(0)
        compare(canvas.progress, Math.max(2, count))
      }
    }
    function test_queueAndSnapshots() {
      canvas.count = 3
      canvas.previewExchange(2)
      wait(100)
      var before = canvas.progress
      canvas.displays = canvas.displays.slice()
      compare(canvas.progress, before)
      canvas.previewExchange(1.5)
      canvas.previewExchange(2)
      compare(canvas.queuedSpeed, 2)
      tryCompare(canvas, "animating", false, 4000)
      compare(canvas.queuedSpeed, -1)
      compare(canvas.progress, 3)
    }
  }
}
'''.replace('CLOCK', clock)
with tempfile.TemporaryDirectory(prefix='station-window-clock-') as folder:
    path = Path(folder) / 'tst_clock.qml'
    path.write_text(qml)
    result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-input', str(path)],
        env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME=''),
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
    print(result.stdout)
    raise SystemExit(result.returncode)

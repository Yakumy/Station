"""Exercise the production bar rendering policy on real Qt text and images."""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
source = (repo / 'lib/MonitorBar.qml').read_text()
start = source.index('    function walkContentImages(')
end = source.index('    function scheduleContentImageZoom(', start)
policy = source[start:end]
with tempfile.TemporaryDirectory(prefix='station-bar-render-') as directory:
    root = Path(directory)
    (root / 'tst_render.qml').write_text('''import QtQuick
import QtTest
Item {
  width: 600; height: 100
  Item {
    id: slot
    property var activeItem: contents
    property real contentZoom: 1
    property var imageContentRoot: null
    property var imageSourceBaselines: new Map()
    property var textRenderBaselines: new Map()
''' + policy + '''
  }
  Item {
    id: contents
    Text { id: label; text: "Sunday 00:11"; renderType: Text.NativeRendering }
    Item {
      Text { id: glyph; text: "★"; renderType: Text.NativeRendering }
      Text { id: scalable; text: "S3"; renderType: Text.CurveRendering }
      Image { id: icon; sourceSize: Qt.size(16, 16) }
    }
  }
  Component { id: lateText; Text { text: "late"; renderType: Text.NativeRendering } }
  TestCase {
    name: "BarRendering"; when: windowShown
    function initTestCase() { failOnWarning(/.*/) }
    function test_zoom_and_restore() {
      slot.contentZoom = 1.75
      slot.applyContentImageZoom()
      compare(label.renderType, Text.QtRendering)
      compare(glyph.renderType, Text.QtRendering)
      compare(scalable.renderType, Text.CurveRendering)
      compare(icon.sourceSize.width, 28)
      slot.applyContentImageZoom()
      compare(icon.sourceSize.width, 28)
      var late = lateText.createObject(contents)
      slot.applyContentImageZoom()
      compare(late.renderType, Text.QtRendering)
      late.destroy()
      wait(1)
      slot.contentZoom = 2
      slot.applyContentImageZoom()
      compare(icon.sourceSize.width, 32)
      slot.contentZoom = 1
      slot.applyContentImageZoom()
      compare(label.renderType, Text.NativeRendering)
      compare(glyph.renderType, Text.NativeRendering)
      compare(scalable.renderType, Text.CurveRendering)
      compare(icon.sourceSize.width, 16)
    }
  }
}
''')
    result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-input', str(root)],
                            env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_CONTROLS_STYLE='Basic'),
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    raise SystemExit(result.returncode)

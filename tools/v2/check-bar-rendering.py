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
size_start = source.index('  readonly property int defaultContentSize:')
size_end = source.index('  readonly property real screenLength:', size_start)
sizing = source[size_start:size_end].replace('Style.font.body', '12').replace('Style.spacing.sm', '4')
publish_start = source.index('      onMinimumLengthChanged:')
publish_end = source.index('\n\n      Rectangle {', publish_start)
publish = source[publish_start:publish_end]
with tempfile.TemporaryDirectory(prefix='station-bar-render-') as directory:
    root = Path(directory)
    (root / 'tst_render.qml').write_text('''import QtQuick
import QtTest
Item {
  id: root
  width: 600; height: 100
  property int requestedContentSize: 12
  property int barSize: 40
  property real measuredMinimumLength: 0
''' + sizing + '''
  // Keep the measurement inside a separate component, as in BarPanel. The
  // outer root must receive updates instead of referencing its private id.
  Loader {
    sourceComponent: Component {
      Item {
        id: barContent
        property int maximumContentSize: root.barSize - 8
        property real minimumLength: 100
''' + publish + '''
      }
    }
  }
  Item {
    id: slot
    property var activeItem: contents
    property real contentZoom: 1
    property var imageContentRoot: null
    property var imageSourceBaselines: new Map()
    property var textRenderBaselines: new Map()
    property var layerTextureBaselines: new Map()
''' + policy + '''
  }
  Item {
    id: contents
    Text { id: label; text: "Sunday 00:11"; renderType: Text.NativeRendering }
    Item {
      Text { id: glyph; text: "★"; renderType: Text.NativeRendering }
      Text { id: scalable; text: "S3"; renderType: Text.CurveRendering }
      Image { id: icon; width: 16; height: 16; sourceSize: Qt.size(16, 16); layer.enabled: true }
      Item {
        id: trayLayer; width: 48; height: 16; layer.enabled: true
        Item { id: nestedLayer; width: 16; height: 16; layer.enabled: true; layer.textureSize: Qt.size(24, 24) }
      }
    }
  }
  Component { id: lateText; Text { text: "late"; renderType: Text.NativeRendering } }
  TestCase {
    name: "BarRendering"; when: windowShown
    function initTestCase() { failOnWarning(/.*/) }
    function test_content_size_crosses_component_boundary() {
      tryCompare(root, "maximumContentSize", 32)
      root.requestedContentSize = 24
      compare(root.effectiveContentSize, 24)
      compare(root.contentScale, 2)
      root.barSize = 28
      tryCompare(root, "maximumContentSize", 20)
      compare(root.effectiveContentSize, 20)
      root.barSize = 48
      tryCompare(root, "maximumContentSize", 40)
      compare(root.effectiveContentSize, 24)
    }
    function test_zoom_and_restore() {
      slot.contentZoom = 1.75
      slot.applyContentImageZoom()
      compare(label.renderType, Text.QtRendering)
      compare(glyph.renderType, Text.QtRendering)
      compare(scalable.renderType, Text.CurveRendering)
      compare(icon.sourceSize.width, 28)
      compare(icon.layer.textureSize.width, Math.ceil(28 * icon.Screen.devicePixelRatio))
      compare(trayLayer.layer.textureSize.width, Math.ceil(84 * trayLayer.Screen.devicePixelRatio))
      compare(nestedLayer.layer.textureSize.width, 42)
      slot.applyContentImageZoom()
      compare(icon.sourceSize.width, 28)
      compare(icon.layer.textureSize.width, Math.ceil(28 * icon.Screen.devicePixelRatio))
      compare(trayLayer.layer.textureSize.width, Math.ceil(84 * trayLayer.Screen.devicePixelRatio))
      compare(nestedLayer.layer.textureSize.width, 42)
      var late = lateText.createObject(contents)
      slot.applyContentImageZoom()
      compare(late.renderType, Text.QtRendering)
      late.destroy()
      wait(1)
      slot.contentZoom = 2
      slot.applyContentImageZoom()
      compare(icon.sourceSize.width, 32)
      compare(nestedLayer.layer.textureSize.width, 48)
      trayLayer.width = 64
      compare(trayLayer.layer.textureSize.width, Math.ceil(128 * trayLayer.Screen.devicePixelRatio))
      slot.contentZoom = 1
      slot.applyContentImageZoom()
      compare(label.renderType, Text.NativeRendering)
      compare(glyph.renderType, Text.NativeRendering)
      compare(scalable.renderType, Text.CurveRendering)
      compare(icon.sourceSize.width, 16)
      compare(icon.layer.textureSize, Qt.size(-1, -1))
      compare(trayLayer.layer.textureSize, Qt.size(-1, -1))
      compare(nestedLayer.layer.textureSize, Qt.size(24, 24))
    }
  }
}
''')
    result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-input', str(root)],
                            env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_CONTROLS_STYLE='Basic'),
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    raise SystemExit(result.returncode)

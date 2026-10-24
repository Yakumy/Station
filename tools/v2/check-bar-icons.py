"""GPU rendering regression: production vector mark versus a native-size reference.

Requires Wayland access; saves /tmp/station-icon-rendering.png with original,
corrected and reference marks, left to right. Does not change desktop settings.
"""
from pathlib import Path
import tempfile, subprocess, os
repo=Path(__file__).resolve().parents[2]
s=(repo/'lib/MonitorBar.qml').read_text(); policy=s[s.index('    function walkContentImages('):s.index('    function scheduleContentImageZoom(')]
with tempfile.TemporaryDirectory(prefix='station-icon-visual-') as d:
 p=Path(d)
 (p/'StationMark.qml').write_text((repo/'lib/StationMark.qml').read_text())
 commons = p/'qs'/'Commons'
 commons.mkdir(parents=True)
 (commons/'qmldir').write_text('module qs.Commons\nsingleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\n')
 (commons/'Style.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { function space(n) { return n } }')
 (commons/'Color.qml').write_text('pragma Singleton\nimport QtQuick\nQtObject { property var popups: ({text: "#aabbdd"}) }')
 qml = ('''import QtQuick
import QtQuick.Effects
import QtTest
Item {
 id: root; width: 300; height: 90
 Rectangle { anchors.fill: parent; color: "#282838" }
 component Mark: Item {
   width: 16; height: 16
   Image { id: img; anchors.fill: parent; source: "__MASK_URL__"; sourceSize: Qt.size(width, height); visible: false; layer.enabled: true }
   MultiEffect { anchors.fill: parent; source: img; colorization: 1; colorizationColor: "#aabbdd" }
 }
 Mark { x: 20; y: 20; scale: 3; transformOrigin: Item.TopLeft }
 Item {
   id: corrected; x: 110; y: 20; width: 16; height: 16; scale: 3; transformOrigin: Item.TopLeft
   StationMark { tint: "#aabbdd"; width: 16; height: 16 }
 }
 StationMark { tint: "#aabbdd"; x: 200; y: 20; width: 48; height: 48 }
 Item {
   id: slot
   property var activeItem: corrected
   property real contentZoom: 3
   property var imageContentRoot: null
   property var imageSourceBaselines: new Map()
   property var textRenderBaselines: new Map()
   property var layerTextureBaselines: new Map()
''' + policy + '''
 }
 TestCase {
   name: "IconVisual"; when: windowShown
   function test_render() {
     slot.applyContentImageZoom()
     wait(500)
     var image = grabImage(root)
     image.save("/tmp/station-icon-rendering.png")
     var beforeError = 0, afterError = 0
     for (var x=0; x<48; x++) for (var y=0; y<48; y++) {
       beforeError += Math.abs(image.red(20+x,20+y)-image.red(200+x,20+y))
       afterError += Math.abs(image.red(110+x,20+y)-image.red(200+x,20+y))
     }
     verify(beforeError > 0, "The fixture must reproduce the original blur")
     verify(afterError < beforeError / 4, "Expected at least 4x less pixel error: before=" + beforeError + ", after=" + afterError)
   }
 }
}
''')
 (p/'tst_icons.qml').write_text(qml.replace('__MASK_URL__', (repo/'assets/station-main-logo-mask.svg').as_uri()))
 r=subprocess.run(['/usr/lib/qt6/bin/qmltestrunner','-import',d,'-input',d],env=dict(os.environ,QT_QPA_PLATFORM='wayland',QT_QPA_PLATFORMTHEME='',QT_QUICK_CONTROLS_STYLE='Basic'),timeout=30)
 raise SystemExit(r.returncode)

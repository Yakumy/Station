"""Pixel-check the production app effects with black, white and colored artwork."""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
source = (repo / 'lib/StationBar.qml').read_text()
start = source.index('      MultiEffect {\n        id: inactiveAppEffect')
end = source.index('      Text {', start)
effects = source[start:end].replace('appButton.modelData.focused', 'testCase.focused')
with tempfile.TemporaryDirectory(prefix='station-app-colors-') as directory:
    root = Path(directory)
    (root / 'art.svg').write_text('''<svg xmlns="http://www.w3.org/2000/svg" width="80" height="20">
<path fill="black" d="M0 0h20v20H0z"/><path fill="white" d="M20 0h20v20H20z"/>
<path fill="red" d="M40 0h20v20H40z"/></svg>''')
    (root / 'tst_colors.qml').write_text('''import QtQuick
import QtQuick.Effects
import QtTest
Rectangle {
  width: 100; height: 40; color: "black"
  Image {
    id: appImage
    width: 80; height: 20
    source: "art.svg"
    sourceSize: Qt.size(80, 20)
    visible: testCase.focused
    layer.enabled: true
  }
''' + effects + '''
  TestCase {
    id: testCase
    name: "AppIconColors"
    when: windowShown
    property bool focused: true
    function test_original_focus_and_smaller_dimmed_grayscale() {
      tryCompare(appImage, "status", Image.Ready)
      waitForRendering(parent)
      var shot = grabImage(parent)
      compare(shot.red(10, 10), 0)
      compare(shot.red(30, 10), 255)
      compare(shot.green(30, 10), 255)
      compare(shot.red(50, 10), 255)
      compare(shot.green(50, 10), 0)
      compare(shot.blue(50, 10), 0)
      compare(shot.red(58, 10), 255)
      compare(shot.red(70, 10), 0, "transparent artwork stays transparent")
      focused = false
      waitForRendering(parent)
      shot = grabImage(parent)
      fuzzyCompare(inactiveAppEffect.scale, 0.8, 0.001)
      compare(shot.red(58, 10), 0, "artwork shrinks around its center")
      compare(shot.red(30, 0), 0, "vertical extent also shrinks")
      fuzzyCompare(shot.red(30, 10), 128, 2)
      for (var x of [10, 30, 50]) {
        fuzzyCompare(shot.red(x, 10), shot.green(x, 10), 2)
        fuzzyCompare(shot.green(x, 10), shot.blue(x, 10), 2)
      }
    }
  }
}
''')
    result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-input', str(root)],
        env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='',
                 QT_QUICK_BACKEND='rhi', QSG_RHI_BACKEND='opengl'),
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
    print(result.stdout)
    raise SystemExit(result.returncode)

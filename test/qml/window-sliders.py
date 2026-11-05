"""Exercise WindowsTab with the installed host slider and isolated pointer events.
No live compositor input or configuration writes.
"""
from pathlib import Path
import shutil
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='station-window-sliders-') as directory:
    root = Path(directory)
    probe = root / 'Probe'
    probe.mkdir()
    shutil.copytree(repo / "lib", probe, dirs_exist_ok=True)
    ui = root / 'qs' / 'Ui'
    commons = root / 'qs' / 'Commons'
    ui.mkdir(parents=True)
    commons.mkdir(parents=True)
    (ui / 'qmldir').write_text('module qs.Ui\nPanelSlider 1.0 PanelSlider.qml\nPanelSectionHeader 1.0 PanelSectionHeader.qml\nPanelSeparator 1.0 PanelSeparator.qml\nBorderSurface 1.0 BorderSurface.qml\n')
    (ui / 'BorderSurface.qml').write_text('import QtQuick\nRectangle { property var borderSpec }\n')
    (commons / 'qmldir').write_text('module qs.Commons\nsingleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\nsingleton Border 1.0 Border.qml\n')
    (commons / 'Style.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
  property var spacing: ({controlHeight: 36, xs: 3, sm: 4, md: 8, xl: 10, xxs: 2, xxl: 12, popupRowHeight: 24, hairline: 1, controlPaddingX: 8})
  property var bar: ({sizeHorizontal: 26, sizeVertical: 26})
  property int cornerRadius: 0
  property int normalBorderWidth: 1
  property var font: ({family: "monospace", caption: 12, body: 12, title: 14, display: 24})
  function selectedFillFor(a, b) { return a }
  function space(n) { return n * 5 / 6 }
}
''')
    (commons / 'Color.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
  property QtObject popups: QtObject { property color background: "black"; property color border: "white"; property color text: "white" }
  property QtObject menu: QtObject { property color background: "black"; property color text: "white"; property color border: "white"; property color selectedBackground: "grey"; property color selectedText: "white" }
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
    (ui / 'PanelSlider.qml').write_text(Path('/usr/share/omarchy/shell/Ui/PanelSlider.qml').read_text())
    (ui / 'PanelSectionHeader.qml').write_text('import QtQuick\nText { property color foreground }\n')
    (ui / 'PanelSeparator.qml').write_text('import QtQuick\nItem { property color foreground }\n')
    (probe / 'WindowsLayout.qml').write_text('import QtQuick\nItem { property var tokens; property var service; property var values; function previewExchange(speed) {} }\n')
    (root / 'tst_windows.qml').write_text('''import QtQuick
import QtTest
import "Probe/windows" as WindowsUi
Item {
  width: 900; height: 500
  QtObject {
    id: fakeService
    property var config: ({windows:{innerGap:20,outerGap:20,split:50,rounding:10,speed:1}})
    property bool windowSettingsBusy: false
    property real requested: 0
    function monitorBar(name) { return {} }
    function setWindowSetting(key, value) { requested = value; windowSettingsBusy = true; return "ok" }
  }
  QtObject {
    id: panel
    property var service: fakeService
    property var selectedDisplay: null
    property var bar: null
    property color textPrimary: "white"
    property color textDim: "grey"
    property int regionPadH: 12
    property int space1: 4
    property int space2: 8
    property int space3: 12
  }
  WindowsUi.WindowsTab { id: tab; width: 900; tokens: panel; service: panel.service; selectedDisplay: panel.selectedDisplay; bar: panel.bar }
  TestCase {
    name: "WindowSlider"; when: windowShown
    function sliders(item, found) {
      if (item.liveValue !== undefined && item.minimum !== undefined) found.push(item)
      for (var i = 0; i < item.children.length; i++) sliders(item.children[i], found)
      return found
    }
    function snapshot(split) {
      fakeService.config = {windows:{innerGap:20,outerGap:20,split:split,rounding:10,speed:1}}
    }
    function test_holdSelectionThroughObservationAndSave() {
      var slider = sliders(tab, [])[2]
      verify(slider !== undefined)
      wait(50)
      mousePress(slider, slider.width * 0.8, slider.height / 2)
      compare(slider.liveValue, 65)
      snapshot(50) // A detached bridge poll during the drag.
      wait(20)
      compare(tab.values.split, 65)
      compare(slider.liveValue, 65)
      mouseRelease(slider, slider.width * 0.8, slider.height / 2)
      compare(fakeService.requested, 65)
      snapshot(50) // Old observed setting while the transaction runs.
      wait(30)
      compare(tab.values.split, 65)
      compare(slider.liveValue, 65)
      snapshot(65) // Applied read-back arrives before busy is cleared.
      fakeService.windowSettingsBusy = false
      wait(20)
      compare(slider.liveValue, 65)
      // A later personal override/read-back must still be displayed.
      snapshot(42)
      wait(20)
      compare(slider.liveValue, 42)
    }
    function test_overrideAndFailedSaveSettleToAppliedValue() {
      var slider = sliders(tab, [])[2]
      for (var i = 0; i < 2; i++) {
        snapshot(50)
        mouseClick(slider, slider.width * 0.8, slider.height / 2)
        wait(10)
        compare(slider.liveValue, 65)
        if (i === 0) snapshot(45) // Personal override.
        fakeService.windowSettingsBusy = false // Failure retains previous observation.
        wait(20)
        compare(slider.liveValue, i === 0 ? 45 : 50)
      }
    }
  }
}
''')
    environment = dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_CONTROLS_STYLE='Basic')
    result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-import', str(root), '-input', str(root)],
                            env=environment, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    raise SystemExit(result.returncode)

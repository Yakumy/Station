"""Exercise the production key picker offscreen; only host paint is doubled.

No clipboard provider, compositor binding or live desktop is modified.
"""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='station-binding-picker-') as directory:
    root = Path(directory)
    probe = root / 'Probe'
    probe.mkdir()
    for name in ('BindingKeyPicker.qml', 'InlineDropdown.qml'):
        (probe / name).write_text((repo / 'lib' / name).read_text())
    ui = root / 'qs' / 'Ui'
    commons = root / 'qs' / 'Commons'
    ui.mkdir(parents=True)
    commons.mkdir(parents=True)
    (ui / 'qmldir').write_text('module qs.Ui\nButton 1.0 Button.qml\n')
    (ui / 'Button.qml').write_text('''import QtQuick
Rectangle {
  id: root
  property string text
  property string tooltipText
  property color foreground
  property bool bordered
  property bool focusable
  implicitWidth: 160; implicitHeight: 30
  activeFocusOnTab: focusable
  signal clicked()
  Keys.onReturnPressed: clicked()
  Keys.onSpacePressed: clicked()
  MouseArea { anchors.fill: parent; onClicked: { root.forceActiveFocus(); root.clicked() } }
}
''')
    (commons / 'qmldir').write_text('module qs.Commons\nsingleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\n')
    (commons / 'Style.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
  property var spacing: ({controlGap: 8, md: 8, sm: 4, xxs: 2, popupRowHeight: 24, hairline: 1, controlPaddingX: 8})
  property int normalBorderWidth: 1
  property int cornerRadius: 0
  property var font: ({family: "monospace", body: 12})
  function space(n) { return n * 5 / 6 }
}
''')
    (commons / 'Color.qml').write_text('''pragma Singleton
import QtQuick
QtObject {
  property var popups: ({text: "white"})
  property var menu: ({background: "black", border: "white", selectedBackground: "grey", selectedText: "white", text: "white"})
}
''')
    (root / 'tst_picker.qml').write_text('''import QtQuick
import QtTest
import "Probe" as Station
Item {
  width: 700; height: 400
  Item { id: other; x: 500; width: 100; height: 40 }
  Station.BindingKeyPicker { id: picker; value: "LEFT" }
  SignalSpy { id: picked; target: picker; signalName: "picked" }
  TestCase {
    name: "BindingKeyPicker"
    when: windowShown
    function init() {
      picker.visible = true; picker.available = true
      picker.stopCapture(); other.forceActiveFocus(); picked.clear()
    }
    function test_capture_data() {
      return [{tag: "letter", key: Qt.Key_K, name: "K"},
        {tag: "digit", key: Qt.Key_4, name: "4"},
        {tag: "arrow", key: Qt.Key_Left, name: "LEFT"},
        {tag: "function", key: Qt.Key_F12, name: "F12"},
        {tag: "return", key: Qt.Key_Return, name: "RETURN"},
        {tag: "space", key: Qt.Key_Space, name: "SPACE"},
        {tag: "punctuation", key: Qt.Key_Semicolon, name: "SEMICOLON"}]
    }
    function test_capture(data) {
      mouseClick(findChild(picker, "captureKey"))
      verify(picker.capturing)
      keyClick(data.key)
      compare(picked.count, 1); compare(picked.signalArguments[0][0], data.name)
      verify(!picker.capturing)
      keyClick(Qt.Key_A)
      compare(picked.count, 1)
    }
    function test_cancel_and_modifiers() {
      picker.startCapture(); keyClick(Qt.Key_Control)
      compare(picked.count, 0); verify(picker.capturing)
      keyClick(Qt.Key_V, Qt.ControlModifier)
      compare(picked.count, 0); verify(picker.capturing)
      keyClick(Qt.Key_Escape)
      compare(picked.count, 0); verify(!picker.capturing)
    }
    function test_unsupported() {
      picker.startCapture()
      compare(picker.keyName(Qt.Key_unknown), "")
      keyClick(Qt.Key_VolumeUp)
      compare(picked.count, 0); verify(picker.capturing)
    }
    function test_tab_leaves_capture() {
      picker.startCapture(); keyClick(Qt.Key_Tab)
      compare(picked.count, 0); verify(!picker.capturing)
    }
    function test_lifetime() {
      picker.startCapture(); picker.visible = false
      verify(!picker.capturing)
      picker.visible = true; picker.startCapture(); picker.available = false
      verify(!picker.capturing)
      picker.available = true; picker.startCapture(); other.forceActiveFocus()
      verify(!picker.capturing); compare(picked.count, 0)
    }
    function test_special_menu() {
      mouseClick(findChild(picker, "specialKey"))
      keyClick(Qt.Key_Down); keyClick(Qt.Key_Return)
      compare(picked.count, 1); compare(picked.signalArguments[0][0], "ESCAPE")
    }
  }
}
''')
    result = subprocess.run(['/usr/lib/qt6/bin/qmltestrunner', '-import', str(root), '-input', str(root)],
        env=dict(os.environ, QT_QPA_PLATFORM='offscreen', QT_QPA_PLATFORMTHEME='', QT_QUICK_CONTROLS_STYLE='Basic'),
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    raise SystemExit(result.returncode)

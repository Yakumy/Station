"""Offscreen pointer checks for the production Wallpaper canvas; no desktop writes."""
from pathlib import Path
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="station-wallpaper-layout-") as directory:
    root = Path(directory)
    probe = root / "Probe"
    probe.mkdir()
    for name in ("WallpaperLayout.qml", "WallpaperImage.qml", "Wallpaper.js"):
        (probe / name).write_text((repo / "lib" / name).read_text())
    for module in ("Ui", "Commons"):
        (root / "qs" / module).mkdir(parents=True)
    ui = root / "qs" / "Ui"
    commons = root / "qs" / "Commons"
    (ui / "qmldir").write_text('module qs.Ui\nBorderSurface 1.0 BorderSurface.qml\n')
    (ui / "BorderSurface.qml").write_text('import QtQuick\nRectangle { property var borderSpec }\n')
    (commons / "qmldir").write_text('module qs.Commons\nsingleton Style 1.0 Style.qml\nsingleton Color 1.0 Color.qml\nsingleton Border 1.0 Border.qml\nsingleton Util 1.0 Util.qml\n')
    (commons / "Style.qml").write_text('''pragma Singleton
import QtQuick
QtObject {
  property int cornerRadius: 0
  property int normalBorderWidth: 1
  property var font: ({family: "monospace", caption: 12, body: 14})
  function space(n) { return n }
}
''')
    (commons / "Color.qml").write_text('''pragma Singleton
import QtQuick
QtObject { property var popups: ({background: "black", text: "white"}); property string accent: "cyan" }
''')
    (commons / "Border.qml").write_text('''pragma Singleton
import QtQuick
QtObject { function controlSpec() { return {} }; function flat() { return {} } }
'''.replace(' }; function', ' }\n function'))
    (commons / "Util.qml").write_text('''pragma Singleton
import QtQuick
QtObject { function fileUrl(path) { return path ? "file://" + path : "" } }
''')
    (root / "image.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" width="2000" height="1000"><path fill="red" d="M0 0h1000v1000H0z"/><path fill="blue" d="M1000 0h1000v1000H1000z"/></svg>')
    (root / "image-copy.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" width="2000" height="1000"><path fill="red" d="M0 0h1000v1000H0z"/><path fill="blue" d="M1000 0h1000v1000H1000z"/></svg>')
    qml = '''import QtQuick
import QtTest
import "Probe" as Station
import "Probe/Wallpaper.js" as Wallpaper
Item {
  width: 600; height: 400
  QtObject {
    id: controller
    property bool busy: false
    property var layout: Wallpaper.topology([
      {name: "A", width: 1000, height: 1000, x: 0, y: 0},
      {name: "B", width: 1000, height: 1000, x: 1000, y: 0}], ["A", "B"])
    property var draft: ({mode: "span", source: IMAGE_PATH, perDisplay: {}, framing: Wallpaper.framing({})})
    function frame(value) { draft = Object.assign({}, draft, {framing: Wallpaper.framing(value)}) }
  }
  Station.WallpaperLayout { id: canvas; anchors.fill: parent; controller: controller }
  Station.WallpaperImage {
    id: desktopCrop
    width: 100; height: 100
    scene: controller.draft
    layout: controller.layout
    display: controller.layout.displays[0]
    visible: false
  }
  TestCase {
    name: "WallpaperLayout"
    when: windowShown
    function init() {
      controller.busy = false
      controller.draft = Object.assign({}, controller.draft, {mode: "span", framing: Wallpaper.framing({zoom: 2})})
      tryVerify(function() { return canvas.sourceSize.width === 2000 })
    }
    function test_drag_moves_group_without_changing_topology() {
      var before = JSON.stringify(controller.layout)
      var unit = canvas.fit
      mouseDrag(canvas, 300, 200, 70, 30, Qt.LeftButton, Qt.NoModifier, 10)
      verify(controller.draft.framing.x > 0.5)
      verify(controller.draft.framing.y > 0.5)
      compare(canvas.fit, unit)
      compare(JSON.stringify(controller.layout), before)
    }
    function test_edges_clamp_and_zoom_keeps_image_fixed() {
      controller.frame({zoom: 2, x: 100, y: -100})
      compare(controller.draft.framing.x, 1)
      compare(controller.draft.framing.y, 0)
      var imageFit = canvas.imageFit
      var oldFit = canvas.fit
      canvas.zoom(2)
      compare(canvas.imageFit, imageFit)
      compare(canvas.fit, oldFit / 2)
    }
    function test_keyboard_moves_group() {
      canvas.forceActiveFocus()
      keyClick(Qt.Key_Right)
      verify(controller.draft.framing.x > 0.5)
    }
    function test_other_modes_do_not_drag_or_zoom_group() {
      controller.draft = Object.assign({}, controller.draft, {mode: "individual"})
      var before = JSON.stringify(controller.draft)
      mouseDrag(canvas, 300, 200, 50, 20, Qt.LeftButton, Qt.NoModifier, 10)
      canvas.zoom(2)
      compare(JSON.stringify(controller.draft), before)
    }
    function test_desktop_renderer_samples_the_correct_monitor_rectangle() {
      controller.frame({})
      desktopCrop.visible = true
      desktopCrop.display = controller.layout.displays[0]
      tryCompare(desktopCrop, "status", Image.Ready)
      waitForRendering(desktopCrop)
      compare(grabImage(desktopCrop).pixel(50, 50), Qt.color("red"))
      desktopCrop.display = controller.layout.displays[1]
      waitForRendering(desktopCrop)
      compare(grabImage(desktopCrop).pixel(50, 50), Qt.color("blue"))
      desktopCrop.visible = false
    }
    function test_same_size_source_handoff_keeps_the_arranged_group_in_place() {
      controller.frame({zoom: 2, x: 0.78, y: 0.35})
      var first = findChild(canvas, "wallpaperMonitor-A")
      verify(first !== null)
      var oldX = first.x, oldY = first.y, oldWidth = first.width
      controller.draft = Object.assign({}, controller.draft, {source: COPY_PATH})
      compare(first.x, oldX)
      compare(first.y, oldY)
      tryVerify(function() { return canvas.sourceSize.width === 2000 })
      compare(first.x, oldX)
      compare(first.y, oldY)
      compare(first.width, oldWidth)
    }
  }
}
'''
    import json
    (root / "tst_wallpaper.qml").write_text(qml.replace("IMAGE_PATH", json.dumps(str(root / "image.svg")))
                                                   .replace("COPY_PATH", json.dumps(str(root / "image-copy.svg"))))
    result = subprocess.run(["/usr/lib/qt6/bin/qmltestrunner", "-import", str(root), "-input", str(root)],
                            env=dict(os.environ, QT_QPA_PLATFORM="offscreen", QT_QPA_PLATFORMTHEME="", QT_QUICK_CONTROLS_STYLE="Basic"),
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    raise SystemExit(result.returncode)

"""Offscreen pointer checks for the production Wallpaper canvas; no desktop writes."""
from pathlib import Path
import shutil
import os
import subprocess
import tempfile

repo = Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix="station-wallpaper-layout-") as directory:
    root = Path(directory)
    probe = root / "Probe"
    probe.mkdir()
    shutil.copytree(repo / "lib", probe, dirs_exist_ok=True)
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
  property var spacing: ({sm: 4})
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
import "Probe/wallpaper" as WallpaperUi
import "Probe/wallpaper/Wallpaper.js" as Wallpaper
Item {
  width: 600; height: 400
  QtObject {
    id: controller
    property bool busy: false
    property var layout: Wallpaper.topology([
      {name: "A", width: 1000, height: 1000, x: 0, y: 0},
      {name: "B", width: 1000, height: 1000, x: 1000, y: 0}], ["A", "B"])
    property var draft: ({mode: "span", source: IMAGE_PATH, perDisplay: {}, framing: Wallpaper.framing({}), safe: true})
    property int frameCommits: 0
    property bool polled: false
    property var polledDraft: null
    function frame(value) { draft = Object.assign({}, draft, {framing: Wallpaper.framing(value)}) }
    function frameDisplay(identity, value) {
      frameCommits++
      var next = Wallpaper.withFrame(draft, identity, value)
      if (polled) polledDraft = next
      else draft = next
    }
  }
  WallpaperUi.WallpaperLayout { id: canvas; anchors.fill: parent; controller: controller }
  WallpaperUi.WallpaperImage {
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
      controller.polled = false
      controller.frameCommits = 0
      canvas.releaseFrame()
      controller.draft = Object.assign({}, controller.draft, {mode: "span", frames: {}, framing: Wallpaper.framing({zoom: 2})})
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
    function test_default_zoom_fits_monitor_union_with_ten_percent_inset() {
      controller.frame({zoom: 1, x: 0.5, y: 0.5})
      var first = findChild(canvas, "wallpaperMonitor-A")
      var second = findChild(canvas, "wallpaperMonitor-B")
      verify(first !== null && second !== null)
      fuzzyCompare(first.x, canvas.horizontalInset, 0.01)
      fuzzyCompare(second.x + second.width, canvas.width - canvas.horizontalInset, 0.01)
      verify(first.y >= canvas.verticalInset - 0.01)
      verify(first.y + first.height <= canvas.height - canvas.verticalInset + 0.01)
      fuzzyCompare(second.x - first.x - first.width, 0, 0.01)
    }
    function test_non_span_modes_omit_names_without_distorting_crops() {
      controller.draft = Object.assign({}, controller.draft, {mode: "individual"})
      var first = findChild(canvas, "wallpaperMonitor-A")
      var second = findChild(canvas, "wallpaperMonitor-B")
      verify(first !== null && second !== null)
      verify(second.x - first.x - first.width >= canvas.monitorGap - 0.01)
      fuzzyCompare(first.width / first.height, first.modelData.width / first.modelData.height, 0.01)
      var name = findChild(first, "monitorName-A")
      verify(name === null)
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
      var before = JSON.stringify(controller.draft.framing)
      mouseDrag(canvas, 300, 200, 50, 20, Qt.LeftButton, Qt.NoModifier, 10)
      canvas.zoom(2)
      compare(JSON.stringify(controller.draft.framing), before)
    }
    function modeTile(mode, name) {
      controller.draft = Object.assign({}, controller.draft, {mode: mode, frames: {}})
      var tile = findChild(canvas, "wallpaperMonitor-" + name)
      verify(tile !== null)
      tryVerify(function() { return tile.children[0].imageSize.width === 2000 })
      return tile
    }
    function test_tiles_keep_the_exact_monitor_shape() {
      var tile = modeTile("individual", "A")
      fuzzyCompare(tile.width, tile.height, 0.01)
    }
    function test_drag_frames_only_that_monitor_in_both_modes() {
      for (var mode of ["same", "individual"]) {
        var tile = modeTile(mode, "A")
        var picked = ""
        var pick = function(name) { picked = name }
        canvas.selected.connect(pick)
        mouseDrag(tile, tile.width / 2, tile.height / 2, 40, 0, Qt.LeftButton, Qt.NoModifier, 10)
        canvas.selected.disconnect(pick)
        compare(picked, "A")
        var frames = controller.draft.frames[mode]
        verify(frames.A.x < 0.5, mode + ": the image follows the pointer")
        compare(frames.B, undefined)
        compare(controller.draft.framing.zoom, 2)
      }
    }
    function test_wheel_zooms_only_the_monitor_under_the_pointer() {
      var tile = modeTile("same", "B")
      mouseWheel(tile, tile.width / 2, tile.height / 2, 0, 120)
      fuzzyCompare(canvas.frameOf({identity: "B"}).zoom, 1.1, 0.0001)
      compare(canvas.frameOf({identity: "A"}).zoom, 1)
      tryVerify(function() { return controller.frameCommits === 1 })
      fuzzyCompare(controller.draft.frames.same.B.zoom, 1.1, 0.0001)
    }
    function test_a_gesture_is_drawn_locally_before_a_polled_bridge_answers() {
      var tile = modeTile("same", "A")
      controller.polled = true
      var image = tile.children[0]
      var center = image.mapToItem(canvas, image.width / 2, image.height / 2)
      mousePress(canvas, center.x, center.y)
      for (var i = 1; i <= 5; i++) mouseMove(canvas, center.x + i * 8, center.y)
      verify(canvas.frameOf({identity: "A"}).x < 0.5, "the local frame moves at once")
      compare(controller.frameCommits, 0, "nothing crosses the bridge per pointer move")
      mouseRelease(canvas, center.x + 40, center.y)
      compare(controller.frameCommits, 1)
      compare(Wallpaper.hasFrame(controller.draft, {identity: "A"}), false)
      var shown = canvas.frameOf({identity: "A"}).x
      verify(shown < 0.5, "the frame holds until the answer arrives")
      controller.draft = controller.polledDraft
      compare(canvas.liveFrame, null)
      compare(canvas.frameOf({identity: "A"}).x, shown)
    }
    function test_ignored_frame_returns_to_the_truth() {
      var tile = modeTile("same", "A")
      controller.polled = true
      controller.polledDraft = null
      canvas.setFrame({identity: "A"}, {zoom: 2})
      canvas.commitFrame()
      compare(canvas.frameOf({identity: "A"}).zoom, 2)
      tryVerify(function() { return canvas.liveFrame === null }, 2000)
      compare(canvas.frameOf({identity: "A"}).zoom, 1)
    }
    function test_keyboard_frames_the_selected_monitor_and_reset_clears_it() {
      modeTile("individual", "A")
      canvas.selectedName = "B"
      canvas.forceActiveFocus()
      keyClick(Qt.Key_Plus)
      keyClick(Qt.Key_Plus)
      keyClick(Qt.Key_Right)
      canvas.commitFrame()
      var frame = controller.draft.frames.individual.B
      verify(frame.zoom > 1.2)
      verify(frame.x < 0.5)
      compare(controller.draft.frames.individual.A, undefined)
      canvas.resetSelected()
      compare(controller.draft.frames.individual.B, undefined)
      canvas.selectedName = ""
    }
    function test_busy_blocks_framing() {
      var tile = modeTile("same", "A")
      controller.busy = true
      mouseDrag(tile, tile.width / 2, tile.height / 2, 40, 0, Qt.LeftButton, Qt.NoModifier, 10)
      mouseWheel(tile, tile.width / 2, tile.height / 2, 0, 120)
      compare(canvas.liveFrame, null)
      controller.busy = false
    }
    function test_desktop_renderer_shows_each_monitors_frame_and_preview_matches() {
      var display = controller.layout.displays[0]
      desktopCrop.visible = true
      desktopCrop.display = display
      var show = function(frame) {
        controller.draft = Object.assign(Wallpaper.withFrame(Object.assign({}, controller.draft, {mode: "same", frames: {}}), "A", frame))
        tryCompare(desktopCrop, "status", Image.Ready)
        waitForRendering(desktopCrop)
        return grabImage(desktopCrop)
      }
      var left = show({x: 0})
      compare(left.pixel(10, 50), Qt.color("red"))
      compare(left.pixel(90, 50), Qt.color("red"))
      var right = show({x: 1})
      compare(right.pixel(10, 50), Qt.color("blue"))
      compare(right.pixel(90, 50), Qt.color("blue"))
      var filled = show({})
      compare(filled.pixel(10, 50), Qt.color("red"))
      compare(filled.pixel(90, 50), Qt.color("blue"))
      // Zoom 2 at the far left shows source x 0..500 of the red half.
      var zoomed = show({zoom: 2, x: 0, y: 0})
      compare(zoomed.pixel(90, 90), Qt.color("red"))
      desktopCrop.visible = false
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

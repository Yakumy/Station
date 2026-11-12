"""Render Wallpaper controls and exercise dropdown bindings with a fake owner.

Uses real host tokens in an isolated window. No menu, file picker, installed file,
wallpaper or monitor setting is changed. Pass a directory to retain screenshots.
"""
from pathlib import Path
import os
import re
import shutil
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[2]
output = Path(sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="station-wallpaper-tab-render-"))
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="station-wallpaper-tab-probe-") as directory:
    root = Path(directory)
    for name in ("Commons", "Ui"):
        (root / name).symlink_to(Path("/usr/share/omarchy/shell") / name, target_is_directory=True)
    # Like panel-size, qualify Color in the isolated file context, where its
    # bare name resolves ambiguously. Production components and behavior stay.
    shutil.copytree(repo / "lib", root / "Station")
    for path in (root / "Station").rglob("*.qml"):
        source = path.read_text()
        if re.search(r"(?<![\w.])Color\.", source):
            if "import qs.Commons as Commons" not in source:
                source = "import qs.Commons as Commons\n" + source
            path.write_text(re.sub(r"(?<![\w.])Color\.", "Commons.Color.", source))
    (root / "fixture.svg").write_text('<svg xmlns="http://www.w3.org/2000/svg" width="1920" height="1080"><rect width="1920" height="1080" fill="gray"/></svg>')
    qml = r'''import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "Station/wallpaper" as WallpaperUi
import "Station/wallpaper/Wallpaper.js" as Wallpaper
ShellRoot {
  QtObject {
    id: owner
    property var draft: ({mode: "same", followTheme: true, source: "IMAGE", perDisplay: {}, framing: Wallpaper.framing({}), frames: {}, safe: true})
    property var layout: Wallpaper.topology([
      {name: "eDP-1", width: 1920, height: 1080, x: 0, y: 1080},
      {name: "HDMI-A-2", width: 1920, height: 1080, x: 0, y: 0}], ["A", "B"])
    property bool busy: false
    property bool importBusy: false
    property bool pickerBusy: false
    property bool dirty: false
    property string notice: ""
    property bool noticeError: false
    property string themePath: "IMAGE"
    property string themeName: "tokyo-night"
    property string menu: ""
    property string chosen: ""
    function change(key, value) { var next = Object.assign({}, draft); next[key] = value; draft = next; dirty = true }
    function choose(identity) { chosen = identity; return true }
    function openMenu(kind) { menu = kind; return true }
    function reset() {}
    function apply() {}
    function frame(value) { change("framing", value) }
    function frameDisplay(identity, value) { draft = Wallpaper.withFrame(draft, identity, value) }
  }
  QtObject {
    id: tokens
    property real regionPadH: Style.space(24)
    property real space1: Style.space(4)
    property real space2: Style.space(8)
    property real space3: Style.space(12)
    property real space4: Style.space(16)
    property color textPrimary: Commons.Color.popups.text
    property color textDim: Qt.darker(Commons.Color.popups.text, 1.4)
  }
  FloatingWindow {
    implicitWidth: Style.space(996)
    implicitHeight: tab.implicitHeight
    visible: true
    color: Commons.Color.popups.background
    Rectangle {
      id: capture
      anchors.fill: parent
      color: Commons.Color.popups.background
      WallpaperUi.WallpaperTab { id: tab; width: parent.width; tokens: tokens; controller: owner; dismiss: function() {} }
    }
  }
  function find(node, name) {
    if (node.objectName === name) return node
    var children = node.children || []
    for (var i = 0; i < children.length; i++) {
      var result = find(children[i], name)
      if (result) return result
    }
    return null
  }
  Timer {
    id: check
    property int phase: 0
    interval: 500; running: true; repeat: true
    function fail(reason) { console.log("WALLPAPER_TAB_FAILED " + reason); stop(); Qt.quit() }
    function save(name, done) {
      stop()
      capture.grabToImage(function(result) {
        result.saveToFile("OUTPUT/" + name + ".png")
        done(); check.start()
      })
    }
    onTriggered: {
      var mode = find(tab, "wallpaperModeDropdown")
      var follow = find(tab, "wallpaperFollowDropdown")
      if (!mode || !follow) { fail("missing dropdowns"); return }
      if (phase === 0) {
        if (find(tab, "wallpaperSelectedMonitor").text !== "") { fail("same selection heading"); return }
        if (find(tab, "wallpaperImageHint").text !== "fixture.svg") { fail("filename hint"); return }
        if (mode.value !== "same" || follow.value !== "yes") { fail("initial values"); return }
        var frame = mode.parent.parent.parent
        var originalWidth = frame.parent.width - Style.space(28) * 2 - Style.space(24) * 2
        if (Math.abs(mode.width - originalWidth * 1.2 * 0.96) > 0.1) { fail("4 percent reduced controls"); return }
        if (frame.x < 0 || mode.x < 0 || mode.x + mode.width > mode.parent.width) { fail("control overflow"); return }
        var buttons = ["wallpaperChooseImage", "wallpaperThemeBackground", "wallpaperThemePicker"].map(function(name) { return find(tab, name) })
        if (buttons.some(function(button) { return Math.abs(button.width - mode.width) > 0.1 || button.height !== buttons[0].height })) { fail("unequal row controls"); return }
        var titles = []
        function collectTitles(node) {
          if (node.objectName === "controlRowTitle") titles.push(node)
          var children = node.children || []
          for (var i = 0; i < children.length; i++) collectTitles(children[i])
        }
        collectTitles(tab)
        if (JSON.stringify(titles.map(function(title) { return title.text })) !== JSON.stringify(["Mode", "Follow Omarchy theme", "Image", "Theme background", "Theme"])) { fail("row titles"); return }
        if (titles.some(function(title) { return title.x !== titles[0].x || title.y !== titles[0].y || title.color !== titles[0].color || title.font.pixelSize !== titles[0].font.pixelSize })) { fail("title styling"); return }
        if (mode.width < mode.parent.width * 0.8) { fail("dropdown width"); return }
        save("same", function() { mode.changed("individual"); check.phase = 1 })
      } else if (phase === 1) {
        if (tab.scene.mode !== "individual") { fail("mode change"); return }
        tab.selectedName = "HDMI-A-2"
        find(tab, "wallpaperChooseImage").clicked()
        if (owner.chosen !== "B") { fail("selected monitor target"); return }
        // Simulate owner acceptance arriving through the bridge; the dropdown
        // must update even after the host has imperatively set its value.
        follow.value = "yes"
        owner.change("followTheme", false)
        phase++
      } else if (phase === 2) {
        if (find(tab, "wallpaperSelectedMonitor").text !== "Selected: HDMI-A-2") { fail("monitor heading"); return }
        if (follow.value !== "no") { fail("accepted image did not update Follow"); return }
        save("individual", function() {
          find(tab, "wallpaperThemeBackground").clicked()
          if (owner.menu !== "background") { check.fail("background menu"); return }
          find(tab, "wallpaperThemePicker").clicked()
          if (owner.menu !== "theme") { check.fail("theme menu"); return }
          mode.value = "individual"
          owner.change("mode", "span")
          check.phase = 3
        })
      } else if (phase === 3) {
        if (find(tab, "wallpaperSelectedMonitor").text !== "") { fail("span selection heading"); return }
        if (mode.value !== "span") { fail("external mode binding"); return }
        save("span", function() { check.phase = 4 })
      } else {
        console.log("WALLPAPER_TAB_OK")
        stop(); Qt.quit()
      }
    }
  }
}
'''.replace("IMAGE", str(root / "fixture.svg")).replace("OUTPUT", str(output))
    (root / "shell.qml").write_text(qml)
    result = subprocess.run(["quickshell", "--no-color", "-p", str(root)],
                            env=dict(os.environ, QT_QPA_PLATFORM="wayland"), text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30)
    print(result.stdout)
    print(output)
    if "WALLPAPER_TAB_OK" not in result.stdout or any(token in result.stdout for token in
            ("ERROR", "ReferenceError", "TypeError", "Binding loop", "Unable to assign", "grabToImage:", "WALLPAPER_TAB_FAILED")):
        raise SystemExit(1)

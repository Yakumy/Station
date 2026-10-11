"""Render the production Wallpaper tab and exercise its controller in isolation.

Uses a temporary Quickshell process with real installed UI tokens. The fake
Station service never enables desktop surfaces, writes preferences, or invokes
Hyprland. Screenshots are retained in the requested /tmp output directory.
"""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[2]
output = Path(sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="station-wallpaper-renders-"))
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="station-wallpaper-probe-") as directory:
    root = Path(directory)
    for name in ("Commons", "Ui"):
        (root / name).symlink_to(Path("/usr/share/omarchy/shell") / name, target_is_directory=True)
    (root / "Station").symlink_to(repo / "lib", target_is_directory=True)
    # Deterministic asymmetric image makes crop alignment visible.
    image = root / "wallpaper.svg"
    image.write_text('<svg xmlns="http://www.w3.org/2000/svg" width="3200" height="1800">'
                     '<path fill="#32495d" d="M0 0h3200v1800H0z"/>'
                     '<circle cx="2200" cy="700" r="420" fill="#e7bc76"/>'
                     '<path fill="#698775" d="M0 1800L900 500l600 1300 600-700 1100 700z"/></svg>')
    qml = r'''import QtQuick
import Quickshell
import qs.Commons
import "Station" as Station
ShellRoot {
  id: probe
  property int step: 0
  Item {
    id: service
    property bool configLoaded: false
    property var config: ({wallpaper: {}})
    property var monitors: [
      {name: "eDP-1", width: 1920, height: 1080, x: -1920, y: 1080, scale: 1},
      {name: "HDMI-A-2", width: 1920, height: 1200, x: -1920, y: -120, scale: 1}]
    property alias wallpaper: controller
    property string stateDir: "/tmp/unused-station-wallpaper-probe"
    property bool panelWanted: false
    property int rememberedTab: 3
    function saveConfig() { throw new Error("Probe must not save config") }
    function enqueue() { throw new Error("Probe must not execute commands") }
    Station.WallpaperController { id: controller; station: service }
  }
  Item {
    id: panel
    property var service: service
    property real regionPadH: Style.space(24)
    property real space2: Style.space(8)
    property real space3: Style.space(12)
    property color textDim: Qt.darker(Color.popups.text, 1.4)
  }
  FloatingWindow {
    id: window
    title: "Station wallpaper validation"
    implicitWidth: Style.space(996)
    implicitHeight: tab.implicitHeight
    color: Color.popups.background
    visible: true
    Rectangle {
      id: capture
      width: parent.width; height: tab.implicitHeight; color: Color.popups.background
      Station.WallpaperTab { id: tab; width: parent.width; panelRoot: panel }
    }
  }
  Timer {
    interval: 500; running: true; repeat: true
    onTriggered: {
      if (probe.step === 0) {
        controller.themePath = IMAGE_PATH
        controller.reset()
        controller.change("mode", "span")
        controller.frame({zoom: 1.4, x: 0.7, y: 0.5})
      } else if (probe.step === 1) {
        capture.grabToImage(function(result) { result.saveToFile(OUTPUT_PATH + "/span-dark.png") })
      } else if (probe.step === 2) {
        Color.loadColors('background = "#eff1f5"\nforeground = "#4c4f69"\naccent = "#1e66f5"')
        Color.loadShell('[popups]\nbackground = "#eff1f5"\ntext = "#4c4f69"\n[menu]\nbackground = "#eff1f5"\ntext = "#4c4f69"')
      } else if (probe.step === 3) {
        capture.grabToImage(function(result) { result.saveToFile(OUTPUT_PATH + "/span-light.png") })
      } else if (probe.step === 4) {
        controller.change("mode", "individual")
      } else if (probe.step === 5) {
        capture.grabToImage(function(result) { result.saveToFile(OUTPUT_PATH + "/individual-light.png") })
      } else if (probe.step === 6) {
        console.log("WALLPAPER_RENDER_OK")
        Qt.quit()
      }
      probe.step++
    }
  }
}
'''
    qml = qml.replace('IMAGE_PATH', json.dumps(str(image))).replace('OUTPUT_PATH', json.dumps(str(output)))
    # Avoid an id/property self-reference on panel.service.
    qml = qml.replace('id: service', 'id: fakeService').replace('station: service', 'station: fakeService').replace('property var service: service', 'property var service: fakeService')
    (root / "shell.qml").write_text(qml)
    result = subprocess.run(["quickshell", "--no-color", "-p", str(root)],
                            env=dict(os.environ, QT_QPA_PLATFORM="wayland"),
                            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=20)
    print(result.stdout)
    print(output)
    if "WALLPAPER_RENDER_OK" not in result.stdout or any(s in result.stdout for s in
            ("ERROR", "ReferenceError", "TypeError", "Binding loop", "Unable to assign", "grabToImage:")):
        raise SystemExit(1)

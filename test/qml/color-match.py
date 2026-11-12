"""Render the Color Match tab with real host tokens, and drive its owner with a fake queue.

The owner runs with a real FileView on a temporary toggle file. No command runs:
the queue records argv and answers with a chosen exit code.
"""
from pathlib import Path
import os
import socket
import subprocess
import sys
import tempfile

repo = Path(__file__).resolve().parents[2]
display = os.environ.get("WAYLAND_DISPLAY", "")
runtime = os.environ.get("XDG_RUNTIME_DIR", "")
address = Path(display) if display else None
if address and not address.is_absolute():
    address = Path(runtime) / address if runtime else None
try:
    if address is None:
        raise OSError("WAYLAND_DISPLAY or XDG_RUNTIME_DIR is unset")
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(1)
        connection.connect(str(address))
except OSError as error:
    raise SystemExit(f"Color Match check needs Wayland access ({error}).")

output = Path(sys.argv[1] if len(sys.argv) > 1 else tempfile.mkdtemp(prefix="station-color-render-"))
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(prefix="station-color-probe-") as directory:
    root = Path(directory)
    for name in ("Commons", "Ui"):
        (root / name).symlink_to(Path("/usr/share/omarchy/shell") / name, target_is_directory=True)
    (root / "Station").symlink_to(repo / "lib", target_is_directory=True)
    qml = r'''import QtQuick
import Quickshell
import qs.Commons
import qs.Commons as Commons
import "Station/color" as ColorUi
import "Station/color/ColorMatch.js" as ColorMatch
ShellRoot {
  Item {
    id: fakeService
    property var displayDraft: [
      {name: "eDP-1", width: 1920, height: 1080, x: 1920, y: 120, scale: 1, transform: 0, enabled: true},
      {name: "HDMI-A-2", width: 1920, height: 1200, x: 0, y: 0, scale: 1, transform: 0, enabled: true}]
    property var colorMatch: ({ busy: false, error: "", hdr: ["eDP-1"],
      values: { "eDP-1": ColorMatch.clean(null), "HDMI-A-2": ColorMatch.clean({ temperature: 5600, tint: 12 }) } })
    property var calls: []
    function displayEnabled(name) { return true }
    function setColorValue(name, key, value) { calls = calls.concat([["set", name, key, value]]); return "ok" }
    function resetColor(name) { calls = calls.concat([["reset", name]]); return "ok" }
  }
  Item {
    id: panel
    property var selectedDisplay: fakeService.displayDraft[1]
    property real regionPadH: Style.space(24)
    property real space1: Style.space(4)
    property real space2: Style.space(8)
    property real space3: Style.space(12)
    property real space4: Style.space(16)
    property real disabledOpacity: 0.6
    property real controlHeight: Style.spacing.controlHeight
    property color textPrimary: Commons.Color.popups.text
    property color textDim: Qt.darker(Commons.Color.popups.text, 1.4)
    function selectDisplay(name) {
      for (var i = 0; i < fakeService.displayDraft.length; i++)
        if (fakeService.displayDraft[i].name === name) selectedDisplay = fakeService.displayDraft[i]
    }
  }
  FloatingWindow {
    implicitWidth: Style.space(996)
    implicitHeight: tab.implicitHeight
    color: Commons.Color.popups.background
    visible: true
    Rectangle {
      id: capture
      anchors.fill: parent
      color: Commons.Color.popups.background
      ColorUi.ColorMatchTab { id: tab; width: parent.width; tokens: panel; service: fakeService
        selectedDisplay: panel.selectedDisplay; bar: null; selectDisplay: function(name) { panel.selectDisplay(name) } }
    }
  }

  // The owner, on a temporary file, with a recording queue.
  property var queued: []
  property int answer: 0
  property var published: null
  property int saves: 0
  ColorUi.ColorMatchController {
    id: owner
    togglePath: "TOGGLE"
    profileDir: "/tmp/station-color-profiles"
    monitors: [{ name: "HDMI-A-2", description: "Test Panel", serial: "1", colorManagementPreset: "srgb" },
      { name: "DP-1", description: "HDR Panel", serial: "2", colorManagementPreset: "hdr" }]
    settings: ({})
    enqueue: function(argv, done) { queued = queued.concat([argv]); done(answer, answer ? "lua error" : "") }
    publishSettings: function(value) { published = value; owner.settings = value }
    saveSettings: function() { saves++ }
  }

  function findObject(node, name) {
    if (!node) return null
    if (node.objectName === name) return node
    var children = node.children || []
    for (var i = 0; i < children.length; i++) {
      var found = findObject(children[i], name)
      if (found) return found
    }
    return null
  }
  Timer {
    id: checkTimer
    property int phase: 0
    interval: 60; running: true; repeat: true
    function fail(reason) { console.log("COLOR_CHECK_FAILED " + reason); Qt.quit(); stop() }
    onTriggered: {
      if (phase === 0) {
        if (findObject(tab, "colorValue-temperature").text !== "5600 K") { fail("saved temperature"); return }
        if (findObject(tab, "colorValue-tint").text !== "+12") { fail("signed tint"); return }
        if (findObject(tab, "colorValue-gamma").text !== "1.00") { fail("gamma format"); return }
        if (findObject(tab, "colorState-HDMI-A-2").text !== "Adjusted") { fail("adjusted card"); return }
        if (findObject(tab, "colorState-eDP-1").text !== "HDR") { fail("hdr card"); return }
        var slider = findObject(tab, "colorSlider-temperature")
        if (!slider.enabled || !findObject(tab, "colorReset").enabled) { fail("controls enabled"); return }
        slider.moved(7349)
        if (findObject(tab, "colorValue-temperature").text !== "7300 K") { fail("live value rounds to 100 K"); return }
        slider.released(7349)
        var last = fakeService.calls[fakeService.calls.length - 1]
        if (JSON.stringify(last) !== JSON.stringify(["set", "HDMI-A-2", "temperature", 7300])) { fail("release " + JSON.stringify(last)); return }
        var count = fakeService.calls.length
        slider.released(5600)
        if (fakeService.calls.length !== count) { fail("unchanged release applied"); return }
        // Brightness runs past 100% on the track, stops there and says why.
        var bright = findObject(tab, "colorSlider-brightness"), hint = findObject(tab, "colorHint-brightness")
        bright.moved(130)
        if (findObject(tab, "colorValue-brightness").text !== "100%") { fail("capped value " + findObject(tab, "colorValue-brightness").text); return }
        if (hint.text !== "100% is the maximum brightness") { fail("cap message " + hint.text); return }
        bright.released(130)
        if (fakeService.calls.length !== count) { fail("capped release applied"); return }
        if (bright.liveValue !== 100) { fail("capped knob returns " + bright.liveValue); return }
        if (hint.text !== "100% is the maximum brightness") { fail("cap message stays after release"); return }
        bright.moved(90)
        if (hint.text !== "Dims this monitor to match a darker one") { fail("cap message clears"); return }
        bright.released(100)
        findObject(tab, "colorReset").clicked()
        if (fakeService.calls[fakeService.calls.length - 1][0] !== "reset") { fail("reset"); return }
        phase++
        return
      }
      // Let the knobs settle before the capture, then check the HDR monitor.
      if (phase < 12) { phase++; return }
      if (phase === 12) {
        var knobs = ["temperature", "tint", "brightness", "gamma", "saturation"].map(function(key) {
          var control = findObject(tab, "colorSlider-" + key)
          return Math.round(control.progress * 100)
        })
        if (JSON.stringify(knobs) !== JSON.stringify([32, 56, 50, 50, 50])) { fail("knob progress " + JSON.stringify(knobs)); return }
        capture.grabToImage(function(result) {
          result.saveToFile("OUTPUT/color-match-tab.png")
          panel.selectDisplay("eDP-1")
          checkTimer.phase = 13
        })
        phase = 99
        return
      }
      if (phase === 99) return
      if (phase === 13) {
        if (findObject(tab, "colorSlider-tint").enabled || findObject(tab, "colorReset").enabled) { fail("hdr disables controls"); return }
        if (findObject(tab, "colorNotice").text.indexOf("HDR") < 0) { fail("hdr notice"); return }
        owner.started = true
        phase = 14
        return
      }
      if (phase === 14) {
        if (!owner.fileLoaded) return
        if (queued.length !== 0) { fail("empty settings wrote a file"); return }
        if (owner.setValue("DP-1", "tint", 10) !== "hdr") { fail("hdr refused"); return }
        if (owner.setValue("HDMI-A-2", "nope", 10) !== "invalid") { fail("unknown key"); return }
        if (owner.setValue("HDMI-A-2", "temperature", 5000) !== "ok") { fail("set"); return }
        var argv = queued[0]
        if (argv[5] !== "/tmp/station-color-profiles" || argv[8] !== "eval"
            || argv[9].indexOf('hl.monitor({ output = "HDMI-A-2", icc = "/tmp/station-color-profiles/HDMI-A-2-') !== 0
            || argv.length !== 12 || !/^HDMI-A-2-[0-9a-f]{8}\.icc$/.test(argv[10])) { fail("argv " + JSON.stringify(argv.slice(4, 11))); return }
        if (published["Test Panel"].temperature !== 5000 || saves !== 1) { fail("published and saved"); return }
        // A failed apply restores the previous settings and saves nothing.
        answer = 3
        if (owner.setValue("HDMI-A-2", "tint", 40) !== "ok") { fail("second set"); return }
        if (owner.settings["Test Panel"].tint !== 0 || saves !== 1 || owner.error.indexOf("lua error") < 0) { fail("rollback"); return }
        console.log("COLOR_MATCH_OK")
        Qt.quit(); stop()
      }
    }
  }
}
'''.replace("OUTPUT", str(output)).replace("TOGGLE", str(root / "toggles" / "station-color.lua"))
    (root / "shell.qml").write_text(qml)
    try:
        result = subprocess.run(["quickshell", "--no-color", "-p", str(root)],
                                env=dict(os.environ, QT_QPA_PLATFORM="wayland"), text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=40)
    except subprocess.TimeoutExpired as error:
        print(error.stdout.decode() if isinstance(error.stdout, bytes) else error.stdout)
        raise
    print(result.stdout)
    print(output)
    if "COLOR_MATCH_OK" not in result.stdout or any(token in result.stdout for token in
            ("ERROR", "ReferenceError", "TypeError", "Binding loop", "Unable to assign", "COLOR_CHECK_FAILED")):
        raise SystemExit(1)

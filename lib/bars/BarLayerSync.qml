import QtQuick
import Quickshell.Io
import "../platform/Hypr.js" as Hypr

// Registers Station's named bar layer rule. Blur itself is compositor-owned:
// Station reads the global options only to confirm they are observable, never
// forces them, and drops any lease an older version recorded.
Item {
  id: root
  property bool active: false
  property var displays: []
  property var monitorBar: null
  property var clearLegacyLease: null
  property var evalLua: null
  property bool barBlurSyncQueued: false

  function parseJson(raw, fallback) {
    try { return JSON.parse(String(raw || "")) } catch (error) { return fallback }
  }

  function barBlurWanted() {
    return displays.some(function(display) {
      var bar = monitorBar(display.name)
      return bar.enabled && bar.background === "blur"
    })
  }

  function syncBarBlur() {
    if (!active) return
    if (barBlurProbe.running) { barBlurSyncQueued = true; return }
    barBlurProbe.running = true
  }

  function finishBarBlurProbe(code, raw) {
    if (code !== 0) {
      if (barBlurSyncQueued) {
        barBlurSyncQueued = false
        Qt.callLater(syncBarBlur)
      }
      return
    }
    var lines = String(raw || "").trim().split("\n")
    var enabledOption = parseJson(lines[0], {})
    var sizeOption = parseJson(lines[1], {})
    var passesOption = parseJson(lines[2], {})
    if (typeof enabledOption.bool !== "boolean" || !Number.isInteger(sizeOption.int)
        || !Number.isInteger(passesOption.int)) {
      if (barBlurSyncQueued) {
        barBlurSyncQueued = false
        Qt.callLater(syncBarBlur)
      }
      return
    }
    clearLegacyLease()
    evalLua(Hypr.barBlur(barBlurWanted(), {}))
    if (barBlurSyncQueued) {
      barBlurSyncQueued = false
      Qt.callLater(syncBarBlur)
    }
  }

  Process {
    id: barBlurProbe
    command: ["bash", "-lc", "hyprctl getoption decoration:blur:enabled -j; hyprctl getoption decoration:blur:size -j; hyprctl getoption decoration:blur:passes -j"]
    property string captured: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: barBlurProbe.captured = text }
    onRunningChanged: if (running) captured = ""
    onExited: function(code) { root.finishBarBlurProbe(code, captured) }
  }
}

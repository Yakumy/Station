import QtQuick
import Quickshell.Io
import qs.Commons

// Widget-owned: requests and pending drafts end with the panel instance.
Item {
  id: root
  property string selectedDisplayName: ""
  property int brightness: 0
  property bool brightnessAvailable: false
  readonly property bool brightnessLoading: brightnessRead.running
  property var pendingBrightnessRequest: null
  readonly property var textSizeStops: [9, 10, 11, 12, 13, 14, 16, 20]
  property int textSizePreviewIndex: -1
  property int queuedTextSize: -1
  onSelectedDisplayNameChanged: { brightnessAvailable = false; refreshBrightness() }

  function refreshBrightness(name) {
    var target = name || selectedDisplayName
    if (!target || brightnessRead.running) return
    brightnessRead.monitorName = target
    brightnessRead.command = ["omarchy-brightness-display", "--monitor", target]
    brightnessRead.running = true
  }

  function queueBrightness(value) {
    if (!brightnessAvailable || !selectedDisplayName) return
    brightnessDebounce.pending = Math.round(value)
    brightnessDebounce.monitorName = selectedDisplayName
    brightnessDebounce.restart()
  }

  function nearestTextIndex(px) {
    var best = 0, distance = Infinity
    for (var i = 0; i < textSizeStops.length; i++) {
      var next = Math.abs(textSizeStops[i] - px)
      if (next < distance) { best = i; distance = next }
    }
    return best
  }

  function currentTextIndex() {
    return textSizePreviewIndex >= 0 ? textSizePreviewIndex : nearestTextIndex(Style.font.baseSize)
  }

  function displayedTextSize() {
    return textSizePreviewIndex >= 0 ? textSizeStops[textSizePreviewIndex] : Style.font.baseSize
  }

  function setTextSizeIndex(index) {
    if (index < 0 || index >= textSizeStops.length) return
    if (index === currentTextIndex()) return
    textSizePreviewIndex = index
    if (textSizeWrite.running) { queuedTextSize = textSizeStops[index]; return }
    textSizeWrite.command = ["omarchy-display-text-size", String(textSizeStops[index])]
    textSizeWrite.running = true
  }

  function setBrightness(value, monitorName) {
    if (!monitorName) return
    var level = Math.max(1, Math.min(100, Math.round(value)))
    if (monitorName === selectedDisplayName) brightness = level
    if (brightnessWrite.running) {
      pendingBrightnessRequest = { value: level, monitorName: monitorName }
      return
    }
    brightnessWrite.command = ["omarchy", "brightness", "display", "--no-osd", "--monitor",
      monitorName, level + "%"]
    brightnessWrite.running = true
  }

  Process {
    id: brightnessRead
    property string monitorName: ""
    property string captured: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: brightnessRead.captured = text }
    onRunningChanged: if (running) captured = ""
    onExited: function(exitCode) {
      if (monitorName !== root.selectedDisplayName) {
        root.refreshBrightness()
        return
      }
      var first = captured.split("\n")[0].trim()
      root.brightnessAvailable = exitCode === 0 && first !== "" && first !== "unavailable" && isFinite(Number(first))
      root.brightness = root.brightnessAvailable ? Number(first) : 0
    }
  }

  Timer {
    id: brightnessDebounce
    property int pending: 0
    property string monitorName: ""
    interval: 180
    onTriggered: root.setBrightness(pending, monitorName)
  }

  Process {
    id: brightnessWrite
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      var pending = root.pendingBrightnessRequest
      root.pendingBrightnessRequest = null
      if (pending) root.setBrightness(pending.value, pending.monitorName)
    }
  }

  Process {
    id: textSizeWrite
    stdout: StdioCollector { waitForEnd: true }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.textSizePreviewIndex = -1
      if (root.queuedTextSize >= 0) {
        var next = root.queuedTextSize
        root.queuedTextSize = -1
        command = ["omarchy-display-text-size", String(next)]
        running = true
      }
    }
  }

  Connections {
    target: Style
    function onFontBaseSizeChanged() {
      if (root.textSizePreviewIndex >= 0
          && root.nearestTextIndex(Style.font.baseSize) === root.textSizePreviewIndex)
        root.textSizePreviewIndex = -1
    }
  }
}

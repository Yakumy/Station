import QtQuick
import Quickshell.Hyprland
import Quickshell.Io
import "OpenApps.js" as OpenApps

// A read-only feed owned by the persistent service. Never writes the snapshots
// used by migrations, never dispatches workspace/window commands.
Item {
  id: root
  property bool active: true
  property var mapping: null
  property var pending: null
  property int minimum: 1
  property int current: 1
  property var focused: null
  readonly property var rows: active
    ? OpenApps.rows(mapping, clients, focused, pending, minimum, current) : ({})
  property bool dirty: false
  property bool busy: false
  property var monitors: []
  property var clients: []
  property var stagedClients: []
  onActiveChanged: {
    if (active) invalidate()
  }
  Component.onCompleted: invalidate()
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (/window|workspace|focusedmon|monitoradded|monitorremoved|configreloaded|pin|togglegroup/.test(String(event.name)))
        root.invalidate()
    }
  }

  function invalidate() {
    if (!active) return
    dirty = true
    if (!busy && !debounce.running) debounce.start()
  }
  function finish(ok, focused) {
    busy = false
    if (active && ok && !dirty) {
      root.clients = stagedClients
      root.focused = focused
    } else if (!ok) root.clients = []
    if (active && dirty) debounce.restart()
  }
  function parse(text, fallback) {
    try { return JSON.parse(text) } catch (_) { return fallback }
  }
  Timer {
    id: debounce
    interval: 60
    onTriggered: {
      if (!root.active) return
      root.dirty = false
      root.busy = true
      monitorRead.running = true
    }
  }
  Process {
    id: monitorRead
    command: ["hyprctl", "monitors", "all", "-j"]
    property string output: ""
    stdout: StdioCollector { onStreamFinished: monitorRead.output = text }
    onExited: function(code) {
      root.monitors = root.parse(output, null)
      if (code === 0 && Array.isArray(root.monitors)) clientRead.running = true
      else root.finish(false, null)
    }
  }
  Process {
    id: clientRead
    command: ["hyprctl", "clients", "-j"]
    property string output: ""
    stdout: StdioCollector { onStreamFinished: clientRead.output = text }
    onExited: function(code) {
      root.stagedClients = root.parse(output, null)
      if (code === 0 && Array.isArray(root.stagedClients)) focusRead.running = true
      else root.finish(false, null)
    }
  }
  Process {
    id: focusRead
    command: ["hyprctl", "activewindow", "-j"]
    property string output: ""
    stdout: StdioCollector { onStreamFinished: focusRead.output = text }
    onExited: function(code) {
      var focused = root.parse(output, null)
      root.finish(code === 0 && focused !== null, focused)
    }
  }
}

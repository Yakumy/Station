import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Serial compositor I/O. Commands run one at a time; queued work carrying a
// configuration generation is retired after a reload, while a running command
// always completes. Snapshots run FIFO and keep each caller's client-read intent.
// Owns the observed monitor and client lists; failure policy stays with the arbiter.
Item {
  id: root
  property int configGeneration: 0
  property var snapshotFailed: null

  property var monitors: []
  property var clients: []
  property var actionQueue: []
  property var currentAction: null
  property var refreshDone: null
  property bool refreshClientsToo: true
  property bool snapshotBusy: false
  property var snapshotQueue: []

  function parseJson(raw, fallback) {
    try { return JSON.parse(String(raw || "")) } catch (error) { return fallback }
  }

  function enqueue(command, done, expectedGeneration) {
    actionQueue = actionQueue.concat([{ command: command, done: done || null, generation: expectedGeneration }])
    runNext()
  }

  function runNext() {
    if (action.running || currentAction || actionQueue.length === 0) return
    currentAction = actionQueue[0]
    actionQueue = actionQueue.slice(1)
    if (currentAction.generation !== undefined && currentAction.generation !== configGeneration) {
      var stale = currentAction
      currentAction = null
      if (stale.done) stale.done(1, "Configuration changed before applying the command.")
      runNext()
      return
    }
    action.command = currentAction.command
    action.running = true
  }

  function evalLua(lua, done) {
    if (!String(lua || "").trim()) { if (done) done(0, ""); return }
    enqueue(["hyprctl", "eval", lua], done, configGeneration)
  }

  function refresh(includeClients, done) {
    if (snapshotBusy) {
      snapshotQueue = snapshotQueue.concat([{ clients: includeClients, done: done }])
      return
    }
    snapshotBusy = true
    refreshClientsToo = includeClients
    refreshDone = done || null
    monitorSnapshot.running = true
  }

  function completeSnapshot(code) {
    var done = refreshDone
    refreshDone = null
    snapshotBusy = false
    if (code !== 0) {
      if (snapshotFailed) snapshotFailed()
    } else if (done) done()
    if (snapshotQueue.length) {
      var next = snapshotQueue[0]
      snapshotQueue = snapshotQueue.slice(1)
      refresh(next.clients, next.done)
    }
  }

  Process {
    id: monitorSnapshot
    command: ["hyprctl", "monitors", "all", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.monitors = root.parseJson(text, [])
    }
    onExited: function(code) {
      if (code === 0 && root.refreshClientsToo) clientSnapshot.running = true
      else root.completeSnapshot(code)
    }
  }

  Process {
    id: clientSnapshot
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.clients = Model.normalizeClients(root.parseJson(text, []), root.monitors)
    }
    onExited: function(code) { root.completeSnapshot(code) }
  }

  Process {
    id: action
    property string captured: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: action.captured = text }
    stderr: StdioCollector { waitForEnd: true }
    onRunningChanged: if (running) captured = ""
    onExited: function(code) {
      var job = root.currentAction
      root.currentAction = null
      if (job && job.done) job.done(code, action.captured)
      root.runNext()
    }
  }
}

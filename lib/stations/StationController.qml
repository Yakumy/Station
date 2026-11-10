import QtQuick
import "../displays/Model.js" as Model
import "../platform/Hypr.js" as Hypr
import "Grid.js" as Grid

// Owns switching stations and moving windows between them. Actions run under the
// Service's operation generation; a topology change retires them. The active
// window comes from `hyprctl activewindow -j`, never a cached focus entry.
Item {
  id: root
  property string operationState: "idle"
  property int gen: 0
  property var monitors: []
  property var clients: []
  property var lanes: ({})
  property var config: ({})
  property var workspaceData: ({ pending: null })
  property var workspaceMap: ({ outputs: [] })
  property bool removalGraceRunning: false
  property double lastTopologyMs: 0
  property var targetMapping: null
  property var begin: null
  property var finish: null
  property var refresh: null
  property var enqueue: null
  property var evalLua: null
  property var recordExpectedEvents: null
  property var rememberStation: null

  property int currentStation: 1
  property int queuedStation: 0
  property string queuedOutput: ""
  property var lastWindowAction: ({})

  function parseJson(raw, fallback) {
    try { return JSON.parse(String(raw || "")) } catch (error) { return fallback }
  }

  function clearQueued() { queuedStation = 0; queuedOutput = "" }

  function followFocusChanged() { followFocus.restart() }

  function focusedMonitor() {
    for (var i = 0; i < monitors.length; i++) if (monitors[i].focused) return monitors[i]
    return null
  }

  function workspaceFor(station, output) {
    return Grid.workspace(Number(station), output, workspaceMap)
  }

  function readyForWindows() {
    return operationState === "idle" && !workspaceData.pending && Grid.valid(workspaceMap) && !removalGraceRunning
      && Grid.equal(workspaceMap, targetMapping())
  }

  // `outputName` names the output a Repetitive switch acts on, as a bar click
  // does. Otherwise the focused output.
  function showStation(stationValue, outputName) {
    var stationNumber = Number(stationValue)
    if (!Number.isInteger(stationNumber) || stationNumber < 1 || stationNumber > Grid.ceiling(workspaceMap)) return "invalid"
    // Keep the latest numbered-key intent while the compositor batch runs.
    // Dropping a quick return to S1 leaves the user looking at an empty S2/S3.
    if (operationState === "switching") {
      queuedStation = stationNumber
      queuedOutput = outputName ? String(outputName) : ""
      return "queued"
    }
    if (!readyForWindows()) return "busy"
    var available = workspaceMap.outputs
    var generation = begin("switching")
    var focused = focusedMonitor()
    var finalOutput = outputName && available.indexOf(String(outputName)) !== -1 ? String(outputName)
      : (focused ? focused.name : available[0])
    var statements = Hypr.workspaceRules(Grid.assignments(workspaceMap))
    statements = statements.concat(stationFocusStatements(stationNumber, finalOutput))
    recordExpectedEvents({ kinds: ["workspace", "focusedmon"], outputs: available.slice(), until: Date.now() + 2000 })
    evalLua(Hypr.batch(statements), function(code, message) {
      if (generation !== gen) return
      if (code === 0 && (!message || message.trim() === "ok")) {
        currentStation = stationNumber
        rememberStation(stationNumber)
      }
      var next = queuedStation
      var nextOutput = queuedOutput
      queuedStation = 0
      queuedOutput = ""
      finish(generation)
      if (next && readyForWindows()) showStation(next, nextOutput)
    })
    return "started"
  }

  function switchStation(value) {
    return showStation(value)
  }

  // A bar label or app icon: in Repetitive, that bar's output shows the number.
  function showWorkspace(value, output) {
    return showStation(value, Grid.mode(workspaceMap) === "repetitive" ? output : "")
  }

  function finishWindowAction(generation, result) {
    if (generation !== gen) return
    lastWindowAction = Object.assign({}, lastWindowAction, { result: result })
    finish(generation)
  }

  function windowActionCurrent(generation) {
    return generation === gen && operationState === "moving" && !workspaceData.pending
      && Grid.equal(workspaceMap, targetMapping()) && !removalGraceRunning
  }

  function readActiveWindow(generation, done, allowScratchpad) {
    refresh(true, function() {
      if (!windowActionCurrent(generation)) { finishWindowAction(generation, "cancelled"); return }
      enqueue(["hyprctl", "activewindow", "-j"], function(code, output) {
        if (!windowActionCurrent(generation)) { finishWindowAction(generation, "cancelled"); return }
        var raw = parseJson(output, null)
        if (code !== 0 || !raw || !raw.address) { finishWindowAction(generation, "no-window"); return }
        var client = Model.normalizeClients([raw], monitors)[0]
        // Explicit numbered sends can retrieve Omarchy's scratchpad windows.
        // Grid eligibility remains strict for migrations and directional moves.
        var scratchpad = allowScratchpad && !client.pinned
          && Number(client.workspace && client.workspace.id) < 0
          && client.workspace.name === "special:scratchpad"
        if (workspaceMap.outputs.indexOf(client.monitor) === -1
          || (!Grid.eligible(client, workspaceMap) && !scratchpad)) {
          finishWindowAction(generation, "unmanaged"); return
        }
        lastWindowAction = Object.assign({}, lastWindowAction, { address: client.address,
          beforeWorkspace: Number(client.workspace.id), beforeMonitor: client.monitor })
        done(client)
      })
    })
  }

  // Station mode focuses the station on every output. Repetitive shows the number
  // on one output, and Non-repetitive shows the workspace on its owner.
  function stationFocusStatements(station, finalOutput) {
    var mode = Grid.mode(workspaceMap)
    if (mode === "repetitive") {
      var output = workspaceMap.outputs.indexOf(finalOutput) !== -1 ? finalOutput : workspaceMap.outputs[0]
      var id = workspaceFor(station, output)
      return [Hypr.placeWorkspace(id, output), Hypr.focusWorkspace(id)]
    }
    if (mode === "nonrepetitive")
      return [Hypr.placeWorkspace(station, Grid.home(station, finalOutput, workspaceMap)), Hypr.focusWorkspace(station)]
    var outputs = workspaceMap.outputs.filter(function(name) { return name !== finalOutput })
    if (workspaceMap.outputs.indexOf(finalOutput) !== -1) outputs.push(finalOutput)
    return outputs.map(function(output) { return Hypr.focusWorkspace(workspaceFor(station, output)) })
  }

  // After a migration: Station mode shows the station again. Non-repetitive and
  // Repetitive put every output back on a workspace of its own block.
  function settleStatements(station, finalOutput) {
    var mode = Grid.mode(workspaceMap)
    if (mode === "station") return stationFocusStatements(station, finalOutput)
    var statements = []
    if (mode === "nonrepetitive") {
      var total = workspaceMap.counts.reduce(function(a, b) { return a + b }, 0)
      workspaceMap.outputs.forEach(function(output, index) {
        var own = Grid.numbers(workspaceMap, index)
        var last = index === workspaceMap.outputs.length - 1
        statements.push(Hypr.homeWorkspaceAmong(output, own, last ? total : null))
      })
    }
    if (Grid.blocked(workspaceMap)) workspaceMap.outputs.forEach(function(output, index) {
      var block = workspaceMap.blocks[index] * Grid.MAX_STATIONS
      statements.push(Hypr.homeWorkspace(output, block + 1, block + Grid.MAX_STATIONS))
    })
    if (workspaceMap.outputs.indexOf(finalOutput) !== -1) statements.push(Hypr.focusMonitor(finalOutput))
    return statements
  }

  function settleAfterMigration(identity) {
    if (Grid.mode(workspaceMap) === "station") return
    var focused = focusedMonitor()
    var statements = settleStatements(currentStation, focused ? focused.name : "")
    var client = identity ? clients.find(function(c) { return Grid.sameClient(identity, c) }) : null
    if (client && client.address) statements.push(Hypr.focusWindow(client.address))
    if (!statements.length) return
    recordExpectedEvents({ kinds: ["workspace", "focusedmon"], outputs: workspaceMap.outputs.slice(), until: Date.now() + 2000 })
    evalLua(Hypr.batch(statements))
  }

  function syncWindowStation(client, generation, result) {
    var station = Grid.station(Number(client.workspace.id), workspaceMap)
    if (station === null || workspaceMap.outputs.indexOf(client.monitor) === -1) {
      finishWindowAction(generation, "unmanaged"); return
    }
    // Only Station mode switches the other outputs along with the window.
    var statements = Grid.mode(workspaceMap) === "station" ? stationFocusStatements(station, client.monitor) : []
    statements.push(Hypr.focusWindow(client.address))
    recordExpectedEvents({ kinds: ["workspace", "focusedmon"], outputs: workspaceMap.outputs.slice(), until: Date.now() + 2000 })
    evalLua(Hypr.batch(statements), function(code) {
      if (!windowActionCurrent(generation)) { finishWindowAction(generation, "cancelled"); return }
      if (code !== 0) { finishWindowAction(generation, "error"); return }
      currentStation = station
      rememberStation(station)
      finishWindowAction(generation, result)
    })
  }

  function moveActionWindow(client, station, output, follow, generation) {
    var target = workspaceFor(station, output)
    if (target === null) { finishWindowAction(generation, "unmanaged"); return }
    var statements = Hypr.workspaceRules(Grid.assignments(workspaceMap))
    if (Grid.mode(workspaceMap) !== "station") statements.push(Hypr.placeWorkspace(target, output))
    statements.push(Hypr.moveWindow(client.address, target, follow))
    recordExpectedEvents({ kinds: ["workspace", "focusedmon"], outputs: [client.monitor, output], until: Date.now() + 2000 })
    evalLua(Hypr.batch(statements), function(code, message) {
      if (!windowActionCurrent(generation)) { finishWindowAction(generation, "cancelled"); return }
      if (code !== 0 || (message && message.trim() !== "ok")) { finishWindowAction(generation, "error"); return }
      refresh(true, function() {
        if (!windowActionCurrent(generation)) { finishWindowAction(generation, "cancelled"); return }
        var after = clients.find(function(c) { return Grid.sameClient(Grid.identity(client), c) })
        if (!after) { finishWindowAction(generation, "closed"); return }
        if (Number(after.workspace.id) !== target || after.monitor !== output) {
          finishWindowAction(generation, "destination-mismatch"); return
        }
        lastWindowAction = Object.assign({}, lastWindowAction, { afterWorkspace: target, afterMonitor: after.monitor })
        if (follow) syncWindowStation(after, generation, "moved")
        else finishWindowAction(generation, "moved-silently")
      })
    })
  }

  function sendWindow(stationValue, follow) {
    var station = Number(stationValue)
    if (!Number.isInteger(station) || station < 1 || station > Grid.ceiling(workspaceMap)) return "invalid"
    if (!readyForWindows()) return "busy"
    var generation = begin("moving")
    lastWindowAction = { action: follow ? "send" : "silent", station: station, result: "reading", receivedAt: Date.now() }
    readActiveWindow(generation, function(client) {
      moveActionWindow(client, station, Grid.home(station, client.monitor, workspaceMap), follow, generation)
    }, true)
    return "started"
  }

  function sendToStation(value) { return sendWindow(value, true) }
  function sendSilent(value) { return sendWindow(value, false) }

  function goDirection(direction) {
    direction = String(direction || "").toLowerCase()
    if (["left", "right", "up", "down"].indexOf(direction) === -1) return "invalid"
    var delta = Model.step(direction, config.direction)
    if (delta === null) return "edge"
    if (!readyForWindows()) return "busy"
    refresh(true, function() {
      if (!readyForWindows()) return
      var focused = focusedMonitor()
      var station = focused ? Grid.station(Number(focused.activeWorkspace.id), workspaceMap) : currentStation
      var output = focused && workspaceMap.outputs.indexOf(focused.name) !== -1 ? focused.name : workspaceMap.outputs[0]
      var existing = Grid.existing(clients, monitors, Grid.STATION_COUNT, workspaceMap, output)
      var target = Model.nextExisting(station || currentStation, delta, existing)
      if (target !== null) showStation(target, output)
    })
    return "started"
  }

  function shiftWindow(direction) {
    direction = String(direction || "").toLowerCase()
    if (["left", "right", "up", "down"].indexOf(direction) === -1) return "invalid"
    if (!readyForWindows()) return "busy"
    var generation = begin("moving")
    lastWindowAction = { action: "direction", direction: direction, result: "reading", receivedAt: Date.now() }
    readActiveWindow(generation, function(client) {
      var statements = Hypr.workspaceRules(Grid.assignments(workspaceMap))
      statements.push(Hypr.nativeMove(client.address, direction))
      var neighbor = Model.neighborMonitor(client.monitor, direction, monitors, workspaceMap.outputs)
      recordExpectedEvents({ kinds: ["workspace", "focusedmon"], outputs: neighbor ? [client.monitor, neighbor] : [client.monitor], until: Date.now() + 2000 })
      evalLua(Hypr.batch(statements), function(code, message) {
        if (!windowActionCurrent(generation)) { finishWindowAction(generation, "cancelled"); return }
        if (code !== 0 || (message && message.trim() !== "ok")) { finishWindowAction(generation, "error"); return }
        nativeMoveSettle.before = client
        nativeMoveSettle.direction = direction
        nativeMoveSettle.generation = generation
        nativeMoveSettle.restart()
      })
    })
    return "started"
  }

  function afterNativeMove(before, direction, generation) {
    if (!windowActionCurrent(generation)) { finishWindowAction(generation, "cancelled"); return }
    refresh(true, function() {
      if (!windowActionCurrent(generation)) { finishWindowAction(generation, "cancelled"); return }
      var client = clients.find(function(c) { return Grid.sameClient(Grid.identity(before), c) })
      if (!client) { finishWindowAction(generation, "closed"); return }
      if (Model.windowChanged(before, client)) {
        lastWindowAction = Object.assign({}, lastWindowAction, { afterWorkspace: Number(client.workspace.id), afterMonitor: client.monitor })
        if (before.monitor !== client.monitor && Grid.mode(workspaceMap) === "station") {
          // A reconnected output can retain an unrelated active workspace.
          // Hyprland's directional move adopts that workspace, but crossing a
          // display boundary must preserve the window's source station.
          var sourceStation = Grid.station(Number(before.workspace.id), workspaceMap)
          var expectedWorkspace = workspaceFor(sourceStation, client.monitor)
          if (sourceStation !== null && expectedWorkspace !== null
              && Number(client.workspace.id) !== expectedWorkspace) {
            moveActionWindow(client, sourceStation, client.monitor, true, generation)
            return
          }
          syncWindowStation(client, generation, "native")
        } else if (Number(before.workspace.id) !== Number(client.workspace.id))
          syncWindowStation(client, generation, "native")
        else finishWindowAction(generation, "native")
        return
      }
      var targetMonitor = Model.neighborMonitor(client.monitor, direction, monitors, workspaceMap.outputs)
      var station = Grid.station(Number(client.workspace.id), workspaceMap)
      if (Grid.mode(workspaceMap) !== "station") { moveAcross(client, station, targetMonitor, direction, generation); return }
      if (!targetMonitor) {
        var delta = Model.step(direction, config.direction)
        if (delta === null || station + delta < 1 || station + delta > Grid.ceiling(workspaceMap)) {
          finishWindowAction(generation, "edge"); return
        }
        station += delta
        targetMonitor = Model.boundaryMonitor(client.monitor, direction, monitors, workspaceMap.outputs)
      }
      moveActionWindow(client, station, targetMonitor, true, generation)
    })
  }

  // Repetitive and Non-repetitive have no station to keep: a neighbor's shown
  // workspace takes the window, and an outer edge steps the window's number.
  function moveAcross(client, number, targetMonitor, direction, generation) {
    if (targetMonitor) {
      var monitor = monitors.find(function(m) { return m.name === targetMonitor })
      var shown = monitor ? Grid.station(Number(monitor.activeWorkspace && monitor.activeWorkspace.id), workspaceMap) : null
      if (shown === null || workspaceFor(shown, targetMonitor) === null)
        shown = Grid.mode(workspaceMap) === "repetitive" ? 1 : Grid.start(workspaceMap.outputs.indexOf(targetMonitor), workspaceMap)
      moveActionWindow(client, shown, targetMonitor, true, generation)
      return
    }
    var delta = Model.step(direction, config.direction)
    if (delta === null || number === null || number + delta < 1 || number + delta > Grid.ceiling(workspaceMap)) {
      finishWindowAction(generation, "edge"); return
    }
    var next = number + delta
    moveActionWindow(client, next, Grid.home(next, client.monitor, workspaceMap), true, generation)
  }

  Timer {
    id: nativeMoveSettle
    property var before: null
    property string direction: ""
    property int generation: 0
    interval: 20
    onTriggered: root.afterNativeMove(before, direction, generation)
  }

  Timer {
    id: followFocus
    interval: 100
    onTriggered: root.refresh(true, function() {
      if (!root.readyForWindows() || Date.now() - root.lastTopologyMs <= 500) return
      // Only stations keep every output together.
      if (Grid.mode(root.workspaceMap) !== "station") return
      var monitor = root.focusedMonitor()
      if (!monitor || !root.lanes[monitor.name]) return
      var workspace = Number(monitor.activeWorkspace && monitor.activeWorkspace.id)
      if (!Grid.contains(workspace, root.workspaceMap)) return
      var station = Grid.station(workspace, root.workspaceMap)
      if (station !== root.currentStation) root.showStation(station)
    })
  }
}

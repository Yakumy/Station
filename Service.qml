import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "lib/Model.js" as Model
import "lib/Hypr.js" as Hypr
import "lib/Binds.js" as Binds
import "lib/Store.js" as Store
import "lib/Recovery.js" as Recovery
import "lib/MonitorsLua.js" as MonitorsLua
import "lib/Transactions.js" as Transactions
import "lib/Events.js" as Events
import "lib/Grid.js" as Grid

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var config: Store.configDefaults()
  property var persisted: Store.stateDefaults()
  property var monitors: []
  property var clients: []
  property var lanes: ({})
  property var workspaceData: ({ mapping: null, pending: null })
  property bool mappingLoaded: false
  property string migrationPhase: ""
  property bool topologyDirty: false
  property int migrationAttempts: 0
  property var lastWindowAction: ({})
  property var migrationFocus: null
  property var migrationCommit: null
  readonly property var workspaceMap: workspaceData.mapping
  property var unmanaged: []
  property int currentStation: persisted.lastStation || 1
  property int gen: 0
  property bool configLoaded: false
  property bool stateLoaded: false
  property bool dirsReady: false
  property bool previewLoaded: false
  property bool previewFound: false
  property bool started: false
  property int configGeneration: 0
  property int appliedGeneration: -1
  property var bindStatuses: []
  property string menuBindingsText: ""
  property bool menuBindingsOk: false
  property string hyprBindingsText: ""
  property string personalBindingsText: ""
  property int stockDisableAttempts: 0
  // The bar rebuilds our widget when its layout entries change (a plugin
  // enable/disable, a widget move) and whenever an output reconfigures, and
  // the panel window dies with the widget. The widget writes its open state
  // here on the way out; destruction cannot, so a rebuilt widget reads true
  // and asks for the panel back. Deliberately in-memory: a shell restart
  // starts with the panel closed.
  property bool panelWanted: false
  // The bar has a separate widget on each output. Preserve the output that
  // owned the panel when a layout edit or bar entry change rebuilds it.
  property string panelScreenName: ""
  property double panelTransferUntil: 0
  // Disabling the output that owns an open KeyboardPanel must be a two-step
  // hand-off. Its layer surface owns a Hyprland focus grab; destroying that
  // surface as part of monitor removal can crash Hyprland before migration.
  // The owning widget closes first and acknowledges after the surface has
  // unmapped, then the service focuses the surviving output and applies the
  // monitor rule. Only after that succeeds may the target widget reopen.
  property int panelEvacuationSerial: 0
  property int panelEvacuationWaiting: 0
  property string panelEvacuationFrom: ""
  property string panelEvacuationTo: ""
  property string panelEvacuationPurpose: ""
  // Set by the panel on every tab switch. The widget is rebuilt when the bar
  // reloads its entries, and a rebuilt instance would otherwise start back
  // on Displays; the service is the object that survives that rebuild.
  property int rememberedTab: 0
  // Keep the inspector's selected connector through a per-output bar rebuild.
  // A temporary output disappearance must not erase the selection.
  property string rememberedDisplayName: ""
  // A preview is an editing session, not a lock: the draft stays editable
  // until Keep or Revert, so the user can rearrange again without having to
  // settle the previous attempt first.
  readonly property bool draftEditable: (state === "idle" || state === "previewing") && !previewBusy
  property bool previewBusy: false
  property string previewAbortReason: ""
  property var previewBaseline: null
  property var keepOptions: null
  property bool keepFilesPending: false
  property bool candidateReady: false
  property bool plainCandidateReady: false
  property var displayDraft: []
  property string draftMode: "extend"
  property string draftSingleTarget: ""
  property var previewBefore: []
  property var previewApplied: null
  property var pendingDisplayConfig: null
  property string previewApplyLua: ""
  property bool previewApplyStaged: false
  property var previewApplyExpectedOutputs: []
  property string previewApplyFocusTarget: ""
  property string previewApplyActivateLua: ""
  property bool previewApplyMigrateFirst: false
  property string previewApplyPanelOrigin: ""
  property string previewApplyPanelTarget: ""
  property string pendingRevertReason: ""
  property string pendingRevertPanelTarget: ""
  property string pendingRevertPanelOrigin: ""
  property string pendingRevertFocusTarget: ""
  property string pendingRevertActivateLua: ""
  property string layoutError: ""
  property int previewSeconds: 0
  property string monitorsSource: ""
  property var expect: ({ kinds: [], outputs: [], until: 0 })
  property double lastTopologyMs: 0
  property var actionQueue: []
  property var currentAction: null
  property var refreshDone: null
  property bool refreshClientsToo: true
  property bool snapshotBusy: false
  property var snapshotQueue: []

  readonly property string configDir: Quickshell.env("HOME") + "/.config/omarchy/station"
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/station"
  readonly property string configPath: configDir + "/config.json"
  readonly property string statePath: stateDir + "/state.json"
  readonly property string monitorsPath: Quickshell.env("HOME") + "/.config/hypr/monitors.lua"
  readonly property string candidatePath: stateDir + "/monitors.lua.candidate"
  readonly property string plainCandidatePath: stateDir + "/monitors-block.plain.lua.candidate"
  readonly property string plainPath: stateDir + "/monitors-block.plain.lua"

  function begin(nextState) {
    gen += 1
    state = nextState
    return gen
  }

  function finish(generation) {
    if (generation === gen) state = "idle"
  }

  function parseJson(raw, fallback) {
    try { return JSON.parse(String(raw || "")) } catch (error) { return fallback }
  }

  function validConnector(value) {
    try { MonitorsLua.connector(value); return true } catch (error) { return false }
  }

  function saveConfig() {
    if (configLoaded && dirsReady) configFile.setText(JSON.stringify(config, null, 2) + "\n")
  }

  function saveState() {
    if (stateLoaded && dirsReady) stateFile.setText(JSON.stringify(persisted, null, 2) + "\n")
  }

  function enqueue(command, done) {
    actionQueue = actionQueue.concat([{ command: command, done: done || null }])
    runNext()
  }

  function runNext() {
    if (action.running || currentAction || actionQueue.length === 0) return
    currentAction = actionQueue[0]
    actionQueue = actionQueue.slice(1)
    action.command = currentAction.command
    action.running = true
  }

  function evalLua(lua, done) {
    if (!String(lua || "").trim()) { if (done) done(0, ""); return }
    enqueue(["hyprctl", "eval", lua], done)
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
      if (state === "migrating") migrationFailed("could not read compositor state")
      else if (state === "previewing") {
        previewBusy = false
        revertPreview("Could not read the display state; reverting the preview.")
      } else if (state === "applyingLayout") {
        layoutError = "Could not read the restored display state."
        state = "idle"
      }
    } else if (done) done()
    if (snapshotQueue.length) {
      var next = snapshotQueue[0]
      snapshotQueue = snapshotQueue.slice(1)
      refresh(next.clients, next.done)
    }
  }

  function updateAssignments() {
    var connected = monitors.filter(function(m) { return root.validConnector(m.name) })
    var ids = Model.identities(connected)
    if (config.enabled.length) connected.forEach(function(m, i) {
      if (!config.lanes[ids[i]] && config.enabled.indexOf(m.name) === -1)
        config.enabled = config.enabled.concat([m.name])
    })
    var assigned = Model.assignLanes(connected, config.lanes, lanes)
    lanes = assigned.lanes
    unmanaged = assigned.unmanaged
    config.lanes = assigned.preferences
    saveConfig()
    if (state !== "previewing" && state !== "applyingLayout") syncDisplayDraft()
  }

  function syncDisplayDraft() {
    var enabled = Model.enabledNames(monitors, config.enabled)
    displayDraft = monitors.filter(function(m) { return root.validConnector(m.name) && lanes[m.name] }).map(function(m) {
      return { name: m.name, description: m.description || m.model || "", width: Number(m.width),
        height: Number(m.height), refreshRate: Number(m.refreshRate), availableModes: m.availableModes || [],
        mode: Model.currentMode(m), x: Number(m.x) || 0, y: Number(m.y) || 0,
        scale: Number(m.scale) || 1, transform: Number(m.transform) || 0,
        enabled: enabled.indexOf(m.name) !== -1, lane: lanes[m.name] }
    })
    draftMode = config.mode
    draftSingleTarget = config.singleTarget
  }

  function focusedMonitor() {
    for (var i = 0; i < monitors.length; i++) if (monitors[i].focused) return monitors[i]
    return null
  }

  function focusedClient() {
    for (var i = 0; i < clients.length; i++) if (clients[i].focusHistoryID === 0) return clients[i]
    return null
  }

  function targetMapping() {
    var options = state === "previewing" && previewApplied ? previewApplied.options : config
    return Grid.mapping(monitors, lanes, options)
  }

  function workspaceFor(station, output) {
    return Grid.workspace(Number(station), output, workspaceMap)
  }

  function readyForWindows() {
    return state === "idle" && !workspaceData.pending && Grid.valid(workspaceMap) && !removalGrace.running
      && Grid.equal(workspaceMap, targetMapping())
  }

  function applyRules(station) {
    if (Grid.valid(workspaceMap)) evalLua(Hypr.batch(Hypr.compactRules(workspaceMap.outputs)))
  }

  function showStation(stationValue) {
    var stationNumber = Number(stationValue)
    if (!Number.isInteger(stationNumber) || stationNumber < 1 || stationNumber > Model.MAX_STATION) return "invalid"
    if (!readyForWindows()) return "busy"
    var available = workspaceMap.outputs
    var generation = begin("switching")
    var focused = focusedMonitor()
    var rules = Hypr.compactRules(available)
    var statements = rules.slice()
    statements = statements.concat(stationFocusStatements(stationNumber, focused ? focused.name : available[0]))
    expect = { kinds: ["workspace", "focusedmon"], outputs: available.slice(), until: Date.now() + 2000 }
    evalLua(Hypr.batch(statements), function(code) {
      if (generation !== gen) return
      if (code === 0) {
        currentStation = stationNumber
        persisted.lastStation = stationNumber
        saveState()
      }
      finish(generation)
    })
    return "started"
  }

  function switchStation(value) {
    return showStation(value)
  }

  function finishWindowAction(generation, result) {
    if (generation !== gen) return
    lastWindowAction = Object.assign({}, lastWindowAction, { result: result })
    finish(generation)
  }

  function windowActionCurrent(generation) {
    return generation === gen && state === "moving" && !workspaceData.pending
      && Grid.equal(workspaceMap, targetMapping()) && !removalGrace.running
  }

  function readActiveWindow(generation, done) {
    refresh(true, function() {
      if (!windowActionCurrent(generation)) { finishWindowAction(generation, "cancelled"); return }
      enqueue(["hyprctl", "activewindow", "-j"], function(code, output) {
        if (!windowActionCurrent(generation)) { finishWindowAction(generation, "cancelled"); return }
        var raw = parseJson(output, null)
        if (code !== 0 || !raw || !raw.address) { finishWindowAction(generation, "no-window"); return }
        var client = Model.normalizeClients([raw], monitors)[0]
        if (workspaceMap.outputs.indexOf(client.monitor) === -1 || !Grid.eligible(client, workspaceMap)) {
          finishWindowAction(generation, "unmanaged"); return
        }
        lastWindowAction = Object.assign({}, lastWindowAction, { address: client.address,
          beforeWorkspace: Number(client.workspace.id), beforeMonitor: client.monitor })
        done(client)
      })
    })
  }

  function stationFocusStatements(station, finalOutput) {
    var outputs = workspaceMap.outputs.filter(function(name) { return name !== finalOutput })
    if (workspaceMap.outputs.indexOf(finalOutput) !== -1) outputs.push(finalOutput)
    return outputs.map(function(output) { return Hypr.focusWorkspace(workspaceFor(station, output)) })
  }

  function syncWindowStation(client, generation, result) {
    var station = Grid.station(Number(client.workspace.id), workspaceMap)
    if (station === null || workspaceMap.outputs.indexOf(client.monitor) === -1) {
      finishWindowAction(generation, "unmanaged"); return
    }
    var statements = stationFocusStatements(station, client.monitor)
    statements.push(Hypr.focusWindow(client.address))
    expect = { kinds: ["workspace", "focusedmon"], outputs: workspaceMap.outputs.slice(), until: Date.now() + 2000 }
    evalLua(Hypr.batch(statements), function(code) {
      if (!windowActionCurrent(generation)) { finishWindowAction(generation, "cancelled"); return }
      if (code !== 0) { finishWindowAction(generation, "error"); return }
      currentStation = station
      persisted.lastStation = station
      saveState()
      finishWindowAction(generation, result)
    })
  }

  function moveActionWindow(client, station, output, follow, generation) {
    var target = workspaceFor(station, output)
    var statements = Hypr.compactRules(workspaceMap.outputs)
    statements.push(Hypr.moveWindow(client.address, target, follow))
    expect = { kinds: ["workspace", "focusedmon"], outputs: [client.monitor, output], until: Date.now() + 2000 }
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
    if (!Number.isInteger(station) || station < 1 || station > Model.MAX_STATION) return "invalid"
    if (!readyForWindows()) return "busy"
    var generation = begin("moving")
    lastWindowAction = { action: follow ? "send" : "silent", station: station, result: "reading", receivedAt: Date.now() }
    readActiveWindow(generation, function(client) { moveActionWindow(client, station, client.monitor, follow, generation) })
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
      var existing = Grid.existing(clients, monitors, config.minStations, workspaceMap)
      var target = Model.nextExisting(station || currentStation, delta, existing)
      if (target !== null) showStation(target)
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
      var statements = Hypr.compactRules(workspaceMap.outputs)
      statements.push(Hypr.nativeMove(client.address, direction))
      var neighbor = Model.neighborMonitor(client.monitor, direction, monitors, workspaceMap.outputs)
      expect = { kinds: ["workspace", "focusedmon"], outputs: neighbor ? [client.monitor, neighbor] : [client.monitor], until: Date.now() + 2000 }
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
        if (before.monitor !== client.monitor) {
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
      if (!targetMonitor) {
        var delta = Model.step(direction, config.direction)
        if (delta === null || station + delta < 1 || station + delta > Model.MAX_STATION) {
          finishWindowAction(generation, "edge"); return
        }
        station += delta
        targetMonitor = Model.boundaryMonitor(client.monitor, direction, monitors, workspaceMap.outputs)
      }
      moveActionWindow(client, station, targetMonitor, true, generation)
    })
  }

  function reconcile() {
    if (state === "applyingLayout") return
    if (removalGrace.running) return
    if (migrationPhase || state === "migrating") { topologyDirty = true; return }
    var preview = state === "previewing"
    if (!preview) begin("migrating")
    refresh(true, function() {
      updateAssignments()
      var target = targetMapping()
      if (!Grid.valid(target)) {
        if (preview) migrationFailed("No usable display after the layout change.")
        else state = "idle"
        return
      }
      try {
        var old = workspaceMap || (persisted.legacyWorkspaceGrid ? Grid.legacy(lanes) : target)
        var pending = workspaceData.pending
        var plan = pending ? Grid.resume(pending, target, clients) : Grid.plan(old, target, clients, currentStation)
        if (!preview && previewBaseline) plan = Grid.restorePreview(previewBaseline, plan, clients)
        var focused = focusedClient()
        migrationFocus = focused ? Grid.identity(focused) : null
        // FileView does not emit saved when setText receives identical text.
        // A revision makes every journal attempt an acknowledged disk write,
        // including recovery of an otherwise unchanged plan after restart.
        workspaceData = { mapping: old, pending: plan, preview: previewBaseline,
          revision: Number(workspaceData.revision || 0) + 1 }
        topologyDirty = false
        migrationPhase = "journal"
        workspaceFile.setText(JSON.stringify(workspaceData, null, 2) + "\n")
      } catch (error) { migrationFailed(String(error)) }
    })
  }

  function migrationFailed(message) {
    migrationPhase = ""
    var preview = state === "previewing"
    if (!preview) state = "idle"
    layoutError = "Workspace migration: " + message
    // Keep the journal for a later retry; never decode partially moved IDs again.
    if (++migrationAttempts <= 3) migrationRetry.restart()
    else if (preview) { previewBusy = false; revertPreview(layoutError) }
  }

  function migrationSaved() {
    if (migrationPhase === "journal") {
      migrationPhase = "moving"
      executeMigration()
    } else if (migrationPhase === "commit") {
      workspaceData = migrationCommit
      migrationCommit = null
      migrationPhase = ""
      migrationAttempts = 0
      if (layoutError.indexOf("Workspace migration:") === 0) layoutError = ""
      persisted.legacyWorkspaceGrid = false
      persisted.lastStation = currentStation
      saveState()
      if (state === "previewing") {
        if (topologyDirty || !Grid.equal(workspaceMap, targetMapping())) { reconcile(); return }
        evalLua(Hypr.batch(stationFocusStatements(currentStation, panelScreenName)), function() {
          root.finishPreviewApply()
        })
        return
      }
      previewBaseline = null
      state = "idle"
      if (topologyDirty || !Grid.equal(workspaceMap, targetMapping())) { reconcile(); return }
      showStation(currentStation)
      if (migrationFocus) {
        var focused = clients.find(function(c) { return Grid.sameClient(migrationFocus, c) })
        if (focused && Grid.station(Number(focused.workspace.id), workspaceMap) === currentStation)
          evalLua("hl.dispatch(hl.dsp.focus({ window = " + Hypr.luaString("address:" + Hypr.address(focused.address)) + " }))")
      }
    }
  }

  function executeMigration() {
    var plan = workspaceData.pending
    var statements = Hypr.compactRules(plan.to.outputs)
    var destinations = {}
    var affected = {}
    plan.windows.forEach(function(row) {
      var client = clients.find(function(c) { return Grid.sameClient(row, c) })
      if (!client || client.pinned) return
      if (Number(client.workspace.id) !== row.to || client.monitor !== row.output) {
        if (client.monitor) affected[client.monitor] = true
        affected[row.output] = true
      }
      if (Number(client.workspace.id) !== row.to) statements.push(Hypr.moveWindow(row.address, row.to, false))
      destinations[row.to] = row.output
    })
    // Workspace rules only place new workspaces. Existing workspaces must also
    // be placed explicitly after all address-based moves have finished.
    Object.keys(destinations).forEach(function(id) {
      statements.push(Hypr.moveWorkspace(Number(id), destinations[id]))
    })
    expect = { kinds: ["workspace", "focusedmon"], outputs: Object.keys(affected), until: Date.now() + 2000 }
    evalLua(Hypr.batch(statements), function(code, output) {
      if (code !== 0 || (output && output.trim() !== "ok")) { migrationFailed("compositor rejected the move batch"); return }
      refresh(true, function() {
        if (topologyDirty || !Grid.equal(plan.to, targetMapping())) {
          migrationPhase = ""
          if (state !== "previewing") state = "idle"
          reconcile(); return
        }
        var failed = plan.windows.some(function(row) {
          var client = clients.find(function(c) { return Grid.sameClient(row, c) })
          return client && !client.pinned && (Number(client.workspace.id) !== row.to || client.monitor !== row.output)
        })
        if (failed) { migrationFailed("destination verification failed"); return }
        currentStation = plan.station
        migrationCommit = { mapping: plan.to, pending: null,
          preview: state === "previewing" ? previewBaseline : null, revision: workspaceData.revision + 1 }
        migrationPhase = "commit"
        workspaceFile.setText(JSON.stringify(migrationCommit, null, 2) + "\n")
      })
    })
  }

  function applyBinds() {
    if (!started || appliedGeneration === configGeneration || keybindings.running || hyprBindSnapshot.running) return
    keybindings.running = true
  }

  function finishBindCheck() {
    var definitions = Binds.effectiveDefinitions(config.keybindings)
    var fallback = Binds.parseHypr(hyprBindingsText).concat(Binds.parseLua(personalBindingsText))
    var accepted = []
    var statuses = []
    for (var i = 0; i < definitions.length; i++) {
      var definition = definitions[i]
      var status = Binds.classify(definition.combo, { ok: menuBindingsOk, text: menuBindingsText }, fallback)
      var approved = config.approvedReplacements.indexOf(Binds.normalize(definition.combo)) !== -1
      if (status.status === "conflict" && approved) status = { status: "replacement", owners: status.owners }
      statuses.push({ combo: definition.combo, label: definition.label,
        id: definition.id, status: status.status, owners: status.owners })
      if (status.status !== "conflict") {
        var copy = Object.assign({}, definition)
        if (approved) copy.replacement = true
        accepted.push(copy)
      }
    }
    bindStatuses = statuses
    var lua = Binds.applyLua(accepted, persisted.appliedBinds)
    evalLua(lua, function(code) {
      if (code === 0) {
        persisted.appliedBinds = accepted.map(function(item) { return item.combo })
        appliedGeneration = configGeneration
        saveState()
      }
    })
  }

  function approveBinding(combo) {
    var normalized = Binds.normalize(combo)
    if (!Binds.validCombo(normalized)) return "invalid"
    if (config.approvedReplacements.indexOf(normalized) === -1)
      config.approvedReplacements = config.approvedReplacements.concat([normalized])
    config = Object.assign({}, config)
    saveConfig()
    appliedGeneration = -1
    applyBinds()
    return "ok"
  }

  function setBinding(id, combo) {
    var known = Binds.definitions().some(function(definition) { return definition.id === id })
    var normalized = Binds.normalize(combo)
    if (!known || !Binds.validCombo(normalized)) return "invalid"
    var custom = Object.assign({}, config.keybindings)
    custom[id] = normalized.replace(/\+/g, " + ")
    config.keybindings = custom
    config.approvedReplacements = config.approvedReplacements.filter(function(value) { return value !== normalized })
    config = Object.assign({}, config)
    saveConfig()
    appliedGeneration = -1
    applyBinds()
    return "ok"
  }

  function applyRuntime() {
    // A config reload/hotplug during Keep must not reapply the old saved mode.
    if (state === "previewing" || state === "applyingLayout") return
    updateAssignments()
    try {
      var monitorRules = MonitorsLua.runtimeModeRules(Object.keys(lanes).map(function(name) {
        return { name: name, lane: lanes[name] }
      }), config)
      var outputs = MonitorsLua.changedOutputs(Object.keys(lanes).map(function(name) {
        return { name: name, lane: lanes[name] }
      }), config, monitors, false)
      expect = { kinds: ["monitor", "workspace"], outputs: outputs, until: Date.now() + 2000 }
      evalLua(Hypr.batch(monitorRules), function() { root.reconcile() })
    } catch (error) { console.warn("Station monitor mode:", error) }
    applyBinds()
  }

  function setDisplayValue(name, key, value) {
    if (!draftEditable) return "busy"
    try { MonitorsLua.connector(name) } catch (error) { return "invalid" }
    if (!displayDraft.some(function(d) { return d.name === name })) return "invalid"
    if (["mode", "x", "y", "scale", "transform", "enabled"].indexOf(key) === -1) return "invalid"
    var next = displayDraft.map(function(display) {
      if (display.name !== name) return display
      var copy = Object.assign({}, display)
      copy[key] = value
      return copy
    })
    displayDraft = next
    return "ok"
  }

  function setDisplayEnabled(name, enabled) {
    if (!draftEditable) return "busy"
    if (!enabled && displayDraft.filter(function(d) { return d.enabled && d.name !== name }).length === 0) {
      layoutError = "At least one display must remain enabled."
      return "invalid"
    }
    if (setDisplayValue(name, "enabled", enabled) !== "ok") return "invalid"
    if (enabled && draftMode === "single" && draftSingleTarget !== name) {
      draftMode = "extend"
      draftSingleTarget = ""
    }
    // Turning off the Single target must select a surviving target.
    if (draftMode === "single" && (!enabled && draftSingleTarget === name))
      draftSingleTarget = displayDraft.find(function(d) { return d.enabled }).name
    return previewLayout()
  }

  function displayEnabled(name) {
    var states = MonitorsLua.runtimeModeStates(displayDraft, { mode: draftMode, singleTarget: draftSingleTarget,
      enabled: displayDraft.filter(function(d) { return d.enabled }).map(function(d) { return d.name }) })
    return states.some(function(d) { return d.name === name && !d.disabled })
  }

  function setDisplayPosition(name, x, y) {
    if (!draftEditable || !isFinite(x) || !isFinite(y)) return "invalid"
    try { MonitorsLua.connector(name) } catch (error) { return "invalid" }
    if (!displayDraft.some(function(display) { return display.name === name })) return "invalid"
    displayDraft = displayDraft.map(function(display) {
      return display.name === name ? Object.assign({}, display, { x: Math.round(x), y: Math.round(y) }) : display
    })
    return "ok"
  }

  function setModeValue(mode, target) {
    if (!draftEditable) return "busy"
    if (["extend", "mirror", "single"].indexOf(mode) === -1) return "invalid"
    if (mode === "single") {
      try { MonitorsLua.connector(target) } catch (error) { return "invalid" }
      if (!displayDraft.some(function(display) { return display.name === target })) return "invalid"
      setDisplayValue(target, "enabled", true)
    }
    draftMode = mode
    draftSingleTarget = mode === "single" ? target : ""
    return previewLayout()
  }

  function setDirectionValue(value) {
    if (["ltr", "rtl", "ttb", "btt"].indexOf(value) === -1) return "invalid"
    config.direction = value
    config = Object.assign({}, config)
    saveConfig()
    return "ok"
  }

  function swapRole(name, roleIndex) {
    if (!readyForWindows()) return "busy"
    var roles = displayDraft.filter(function(display) { return display.enabled && lanes[display.name] })
      .map(function(display) { return lanes[display.name] }).sort(function(a, b) { return a - b })
    var wanted = roles[Number(roleIndex)]
    if (!wanted || !lanes[name]) return "invalid"
    var other = Object.keys(lanes).find(function(connector) { return lanes[connector] === wanted })
    if (!other || other === name) return "ok"
    var old = Object.assign({}, lanes)
    var next = Object.assign({}, lanes)
    next[other] = old[name]
    next[name] = wanted
    lanes = next
    config.lanes = Object.assign({}, config.lanes)
    var ids = Model.identities(monitors)
    for (var i = 0; i < monitors.length; i++) if (next[monitors[i].name]) config.lanes[ids[i]] = next[monitors[i].name]
    saveConfig()
    syncDisplayDraft()
    reconcile()
    return "started"
  }

  function roleOf(name) {
    var roles = displayDraft.filter(function(display) { return root.displayEnabled(display.name) && lanes[display.name] })
      .map(function(display) { return lanes[display.name] }).sort(function(a, b) { return a - b })
    return roles.indexOf(lanes[name])
  }

  function previewLayout() {
    if (!draftEditable) return "busy"
    if (workspaceData.pending || migrationPhase) return "busy"
    try {
      if (draftMode === "extend" && Model.layoutOverlaps(displayDraft.filter(function(d) { return d.enabled })).length)
        throw new Error("Displays overlap")
      var generated = MonitorsLua.generate(displayDraft, {
        mode: draftMode, enabled: displayDraft.filter(function(d) { return d.enabled }).map(function(d) { return d.name }),
        singleTarget: draftSingleTarget
      })
      // A re-edit joins the session already in progress: keep the baseline
      // the first preview captured, so Revert still means "back to the layout
      // as it was before this session", and Revert never lands mid-session.
      if (state !== "previewing") { previewBefore = monitors.slice(); previewApplied = null }
      pendingDisplayConfig = generated
      layoutError = ""
      if (panelWanted) panelTransferUntil = Date.now() + 3000
      removalGrace.stop()
      reloadDebounce.stop()
      begin("previewing")
      previewBusy = true
      previewCountdown.stop()
      previewArm.running = true
      return "started"
    } catch (error) {
      layoutError = String(error.message || error)
      return "invalid"
    }
  }

  function applyPreview() {
    if (state !== "previewing" || !pendingDisplayConfig) return
    refresh(true, function() { root.applyPreviewSnapshot() })
  }

  function panelTransferTarget(options) {
    var states = MonitorsLua.runtimeModeStates(displayDraft, options)
    var usable = states.filter(function(d) { return !d.disabled && !d.mirror })
    if (!usable.length) return ""
    return usable.some(function(d) { return d.name === panelScreenName }) ? panelScreenName : usable[0].name
  }

  function previewFocusTarget(options) {
    var states = MonitorsLua.runtimeModeStates(displayDraft, options)
    var usable = states.filter(function(d) { return !d.disabled && !d.mirror })
    if (!usable.length) return ""
    var focused = monitors.find(function(monitor) { return monitor.focused })
    if (!focused) return ""
    var next = states.find(function(state) { return state.name === focused.name })
    return next && (next.disabled || next.mirror) ? usable[0].name : ""
  }

  function activationRule(name) {
    if (!name) return ""
    var monitor = monitors.find(function(item) { return item.name === name })
    var mirror = monitor ? String(monitor.mirrorOf || "") : ""
    if (monitor && monitor.disabled !== true && (!mirror || mirror === "none")) return ""
    var display = displayDraft.find(function(item) { return item.name === name })
    // A state-only rule can lose to the persisted full rule when a disabled
    // output is re-added. Reassert its exact geometry so it stays available
    // long enough to receive focus and the migrating windows.
    return display ? MonitorsLua.monitorRule(display, { disabled: false, mirror: "" }) : ""
  }

  function clearPanelEvacuation() {
    panelEvacuationTimeout.stop()
    panelEvacuationWaiting = 0
    panelEvacuationFrom = ""
    panelEvacuationTo = ""
    panelEvacuationPurpose = ""
  }

  function clearPreviewApplyStage() {
    clearPanelEvacuation()
    previewApplyLua = ""
    previewApplyStaged = false
    previewApplyExpectedOutputs = []
    previewApplyFocusTarget = ""
    previewApplyActivateLua = ""
    previewApplyMigrateFirst = false
    previewApplyPanelOrigin = ""
    previewApplyPanelTarget = ""
  }

  function failPreviewApply(message) {
    var origin = previewApplyPanelOrigin
    clearPreviewApplyStage()
    if (panelWanted && origin) {
      panelScreenName = origin
      panelTransferUntil = Date.now() + 3000
    }
    previewBusy = false
    revertPreview(message)
  }

  function stagePreviewApply(lua, expectedOutputs, options) {
    previewApplyLua = lua
    previewApplyStaged = true
    previewApplyExpectedOutputs = expectedOutputs
    previewApplyFocusTarget = previewFocusTarget(options)
    previewApplyActivateLua = activationRule(previewApplyFocusTarget)
    previewApplyMigrateFirst = previewApplyActivateLua !== ""
    previewApplyPanelOrigin = panelScreenName
    previewApplyPanelTarget = panelWanted ? panelTransferTarget(options) : ""
    if (panelWanted && previewApplyPanelOrigin && previewApplyPanelTarget
        && previewApplyPanelOrigin !== previewApplyPanelTarget) {
      requestPanelEvacuation(previewApplyPanelOrigin, previewApplyPanelTarget, "preview")
      return
    }
    continuePreviewApply()
  }

  function requestPanelEvacuation(from, to, purpose) {
    panelEvacuationFrom = from
    panelEvacuationTo = to
    panelEvacuationPurpose = purpose
    panelTransferUntil = Date.now() + 3000
    panelEvacuationWaiting = panelEvacuationSerial + 1
    panelEvacuationTimeout.restart()
    // Assign last: panel instances react to this notification only after
    // all request fields contain the complete hand-off.
    panelEvacuationSerial = panelEvacuationWaiting
  }

  function acknowledgePanelEvacuation(serial, screenName) {
    if (Number(serial) !== panelEvacuationWaiting || String(screenName || "") !== panelEvacuationFrom) return
    var purpose = panelEvacuationPurpose
    panelEvacuationTimeout.stop()
    panelEvacuationWaiting = 0
    if (purpose === "revert") continueRevertPreview()
    else continuePreviewApply()
  }

  function panelEvacuationTimedOut() {
    if (panelEvacuationPurpose !== "revert") {
      failPreviewApply("Could not safely move Station before disabling its display.")
      return
    }
    var origin = panelEvacuationFrom
    clearPanelEvacuation()
    pendingRevertReason = ""
    pendingRevertPanelTarget = ""
    pendingRevertPanelOrigin = ""
    pendingRevertFocusTarget = ""
    pendingRevertActivateLua = ""
    previewBusy = false
    layoutError = "Could not safely close Station before restoring the saved display layout."
    if (panelWanted && origin) {
      panelScreenName = origin
      panelTransferUntil = Date.now() + 3000
    }
  }

  function continuePreviewApply() {
    if (state !== "previewing" || !previewApplyStaged) return
    var lua = previewApplyLua
    var expectedOutputs = previewApplyExpectedOutputs.slice()
    var focusTarget = previewApplyFocusTarget
    var activateLua = previewApplyActivateLua
    function applyMonitors() {
      if (root.state !== "previewing") return
      root.expect = { kinds: ["monitor", "workspace"], outputs: expectedOutputs, until: Date.now() + 2000 }
      root.evalLua(lua, function(code, output) {
        if (root.state !== "previewing") return
        if (code !== 0 || (output && output.trim() !== "ok")) {
          root.failPreviewApply("Could not apply the display preview.")
          return
        }
        var target = root.previewApplyPanelTarget
        root.clearPreviewApplyStage()
        if (root.panelWanted && target) {
          root.panelScreenName = target
          root.panelTransferUntil = Date.now() + 3000
        }
        root.reconcile()
      })
    }
    function focusSurvivor() {
      function afterFocus() {
        // When the destination started disabled, move clients while both
        // outputs still exist. Removing their current output first exposes
        // GTK clients to a stale Wayland-output callback and can crash them.
        if (root.previewApplyMigrateFirst) root.reconcile()
        else applyMonitors()
      }
      if (!focusTarget) { afterFocus(); return }
      root.evalLua(Hypr.focusMonitor(focusTarget), function(code, output) {
        if (root.state !== "previewing") return
        if (code !== 0 || (output && output.trim() !== "ok")) {
          root.failPreviewApply("Could not focus the surviving display; preview was not applied.")
          return
        }
        afterFocus()
      })
    }
    // A Single-to-Single switch can target an output that is currently off.
    // Bring it up on its own, then focus it, and only then remove the old one.
    root.expect = { kinds: ["monitor", "workspace"], outputs: expectedOutputs, until: Date.now() + 2000 }
    if (!activateLua) { focusSurvivor(); return }
    evalLua(activateLua, function(code, output) {
      if (root.state !== "previewing") return
      if (code !== 0 || (output && output.trim() !== "ok")) {
        root.failPreviewApply("Could not enable the surviving display; preview was not applied.")
        return
      }
      focusSurvivor()
    })
  }

  function finishPreviewApply() {
    if (state !== "previewing") return
    if (previewApplyStaged && previewApplyMigrateFirst) {
      var lua = previewApplyLua
      var expectedOutputs = previewApplyExpectedOutputs.slice()
      var target = previewApplyPanelTarget
      // Mark this phase consumed before dispatch. Monitor events are expected
      // while the old output is removed and must not start it a second time.
      previewApplyMigrateFirst = false
      expect = { kinds: ["monitor", "workspace"], outputs: expectedOutputs, until: Date.now() + 2000 }
      evalLua(lua, function(code, output) {
        if (root.state !== "previewing") return
        if (code !== 0 || (output && output.trim() !== "ok")) {
          root.failPreviewApply("Could not finish the display preview.")
          return
        }
        root.clearPreviewApplyStage()
        if (root.panelWanted && target) {
          root.panelScreenName = target
          root.panelTransferUntil = Date.now() + 3000
        }
        root.refresh(true, function() {
          // The fresh snapshot has absorbed the expected removal.
          root.topologyDirty = false
          root.finishPreviewApply()
        })
      })
      return
    }
    if (topologyDirty || !Grid.equal(workspaceMap, targetMapping())) { reconcile(); return }
    if (previewAbortReason) {
      var reason = previewAbortReason
      previewAbortReason = ""
      previewBusy = false
      revertPreview(reason)
      return
    }
    // Give the user the full confirmation interval after migration, even if
    // the compositor was slow. The original watchdog still protects the apply.
    enqueue(["touch", stateDir + "/preview.token"], function(code) {
      if (root.state !== "previewing") return
      root.previewBusy = false
      if (code !== 0) { root.revertPreview("Could not renew preview recovery."); return }
      Quickshell.execDetached(["sh", "-c", Transactions.watchdog, "sh", "20", stateDir + "/preview.token"])
      root.previewSeconds = 12
      previewCountdown.restart()
      if (root.panelWanted) root.panelTransferUntil = Date.now() + 3000
    })
  }

  function applyPreviewSnapshot() {
    if (state !== "previewing" || !pendingDisplayConfig) return
    if (!previewBaseline && Grid.valid(workspaceMap)) {
      previewBaseline = Grid.plan(workspaceMap, workspaceMap, clients, currentStation)
      previewBaseline.panelScreenName = panelScreenName
    }
    Quickshell.execDetached(["sh", "-c", Transactions.watchdog, "sh", "20", stateDir + "/preview.token"])
    var lua = pendingDisplayConfig.block.split("\n").filter(function(line) {
      return line !== MonitorsLua.START && line !== MonitorsLua.END
    }).join("\n")
    var previous = previewApplied ? previewApplied.displays : previewBefore.map(function(monitor) {
      return Object.assign({}, monitor, { mode: Model.currentMode(monitor),
        enabled: Model.enabledNames(previewBefore, config.enabled).indexOf(monitor.name) !== -1 })
    })
    var previousOptions = previewApplied ? previewApplied.options : {
      mode: config.mode, singleTarget: config.singleTarget, enabled: config.enabled
    }
    var nextOptions = { mode: draftMode, singleTarget: draftSingleTarget,
      enabled: displayDraft.filter(function(d) { return d.enabled }).map(function(d) { return d.name }) }
    var positionRules = MonitorsLua.positionOnlyRules(previous, pendingDisplayConfig.displays,
      previewApplied ? previewApplied.mode : config.mode, draftMode)
    if (positionRules !== null) lua = positionRules.join("; ")
    else {
      var modeRules = MonitorsLua.modeOnlyRules(previous, pendingDisplayConfig.displays,
        previousOptions, nextOptions)
      if (modeRules !== null) lua = modeRules.join("; ")
    }
    var expectedOutputs = positionRules !== null ? positionRules.map(function(rule) {
      return pendingDisplayConfig.displays.find(function(display) {
        return rule.indexOf("output = " + MonitorsLua.luaString(display.name) + ",") !== -1
      }).name
    }) : modeRules !== null ? MonitorsLua.changedModeNames(pendingDisplayConfig.displays,
      previousOptions, nextOptions) : MonitorsLua.changedOutputs(
        pendingDisplayConfig.displays, nextOptions, previewBefore, true)
    previewApplied = { displays: pendingDisplayConfig.displays, mode: draftMode, options: nextOptions }
    stagePreviewApply(lua, expectedOutputs, nextOptions)
  }

  function revertPreview(reason) {
    if (state !== "previewing") return "idle"
    if (previewBusy) return "busy"
    previewBusy = true
    pendingRevertReason = reason || ""
    pendingRevertPanelTarget = panelWanted ? panelTransferTarget(config) : ""
    var origin = panelScreenName
    pendingRevertPanelOrigin = origin
    pendingRevertFocusTarget = previewFocusTarget(config)
    pendingRevertActivateLua = activationRule(pendingRevertFocusTarget)
    clearPreviewApplyStage()
    if (panelWanted && origin && pendingRevertPanelTarget && origin !== pendingRevertPanelTarget) {
      requestPanelEvacuation(origin, pendingRevertPanelTarget, "revert")
      return "started"
    }
    continueRevertPreview()
    return "started"
  }

  function continueRevertPreview() {
    if (state !== "previewing") return
    var reason = pendingRevertReason
    var target = pendingRevertPanelTarget
    var origin = pendingRevertPanelOrigin
    var focusTarget = pendingRevertFocusTarget
    var activateLua = pendingRevertActivateLua
    pendingRevertReason = ""
    pendingRevertPanelTarget = ""
    pendingRevertPanelOrigin = ""
    pendingRevertFocusTarget = ""
    pendingRevertActivateLua = ""
    clearPreviewApplyStage()
    previewCountdown.stop()
    function failPreparation(message) {
      if (root.state !== "previewing") return
      root.previewBusy = false
      root.layoutError = message
      if (root.panelWanted && origin) {
        root.panelScreenName = origin
        root.panelTransferUntil = Date.now() + 3000
      }
      root.previewSeconds = 12
      previewCountdown.restart()
    }
    function reloadSavedLayout() {
      if (root.state !== "previewing") return
      if (root.panelWanted) {
        if (target) root.panelScreenName = target
        root.panelTransferUntil = Date.now() + 3000
      }
      root.gen += 1
      root.state = "applyingLayout"
      root.pendingDisplayConfig = null
      if (root.previewBaseline && root.previewBaseline.panelScreenName)
        root.panelScreenName = root.previewBaseline.panelScreenName
      root.enqueue(["rm", "-f", root.stateDir + "/preview.token"], function() {
        root.enqueue(["hyprctl", "reload"], function(code) {
          if (code !== 0) root.layoutError = "Could not reload the saved monitor layout."
          root.restoreAppliedLayout()
        })
      })
      if (reason) root.layoutError = reason
    }
    function focusSurvivor() {
      if (!focusTarget) { reloadSavedLayout(); return }
      root.evalLua(Hypr.focusMonitor(focusTarget), function(code, output) {
        if (code !== 0 || (output && output.trim() !== "ok")) {
          failPreparation("Could not focus the saved display; layout was not restored.")
          return
        }
        reloadSavedLayout()
      })
    }
    if (!activateLua) { focusSurvivor(); return }
    expect = { kinds: ["monitor", "workspace"], outputs: [focusTarget], until: Date.now() + 2000 }
    evalLua(activateLua, function(code, output) {
      if (code !== 0 || (output && output.trim() !== "ok")) {
        failPreparation("Could not enable the saved display; layout was not restored.")
        return
      }
      focusSurvivor()
    })
  }

  function keepPreview() {
    if (state !== "previewing" || !pendingDisplayConfig) return "idle"
    if (previewBusy || workspaceData.pending) return "busy"
    try {
      if (panelWanted) panelTransferUntil = Date.now() + 3000
      var source = monitorsSource || ""
      var merged = MonitorsLua.replaceManagedBlock(source, pendingDisplayConfig.block)
      // The managed block is appended last and overrides older rules. Merely
      // mentioning an output earlier in the file is not a configuration error.
      keepOptions = JSON.parse(JSON.stringify(previewApplied.options))
      previewCountdown.stop()
      startKeepFiles(merged, pendingDisplayConfig.plain)
      return "started"
    } catch (error) {
      layoutError = String(error.message || error)
      return "invalid"
    }
  }

  function startKeepFiles(source, plain) {
    state = "applyingLayout"
    keepFilesPending = true
    // Unchanged FileView text produces no saved signal. Everything else must
    // be acknowledged before the transaction can read its candidate files.
    candidateReady = candidateFile.text() === source
    plainCandidateReady = plainCandidateFile.text() === plain
    if (!candidateReady) candidateFile.setText(source)
    if (!plainCandidateReady) plainCandidateFile.setText(plain)
    maybeStartKeep()
  }

  function maybeStartKeep() {
    if (!keepFilesPending || !candidateReady || !plainCandidateReady) return
    keepFilesPending = false
    keepTransaction.running = true
  }

  function keepFileFailed() {
    if (!keepFilesPending) return
    keepFilesPending = false
    finishKeep(2, "")
  }

  function restoreAppliedLayout() {
    // Our configreloaded event is suppressed while applyingLayout. Explicitly
    // rebuild the draft from the fresh compositor snapshot and restore binds.
    appliedGeneration = -1
    previewApplied = null
    clearPreviewApplyStage()
    previewBusy = false
    previewAbortReason = ""
    pendingRevertReason = ""
    pendingRevertPanelTarget = ""
    pendingRevertPanelOrigin = ""
    pendingRevertFocusTarget = ""
    pendingRevertActivateLua = ""
    keepOptions = null
    refresh(true, function() {
      root.state = "idle"
      root.syncDisplayDraft()
      root.applyRuntime()
    })
  }

  function finishKeep(code, errorText) {
    if (code !== 0) {
      layoutError = code === 3 ? "Hyprland rejected the layout; the backup was restored. " + errorText.trim()
        : "Could not save the monitor layout."
      pendingDisplayConfig = null
      if (code === 3) restoreAppliedLayout()
      else enqueue(["hyprctl", "reload"], function() { root.restoreAppliedLayout() })
      return
    }
    config.enabled = keepOptions.enabled.slice()
    config.mode = keepOptions.mode
    config.singleTarget = keepOptions.singleTarget || ""
    config = Object.assign({}, config)
    pendingDisplayConfig = null
    previewApplied = null
    previewBaseline = null
    keepOptions = null
    layoutError = ""
    monitorsFile.reload()
    saveConfig()
    refresh(true, function() {
      root.state = "idle"
      // Keep accepts a preview that is already live. The config-file watcher
      // has also applied the persisted rules, so replaying monitor state here
      // creates a third topology operation for no benefit. Only rebuild the
      // bookkeeping, commit the accepted preview journal, and restore runtime
      // binds erased by a config reload.
      root.updateAssignments()
      root.applyBinds()
      root.reconcile()
    })
  }

  function maybeStart() {
    if (started || !dirsReady || !configLoaded || !stateLoaded || !previewLoaded || !mappingLoaded) return
    started = true
    currentStation = persisted.lastStation
    if (previewFound) {
      Quickshell.execDetached(["rm", "-f", stateDir + "/preview.token"])
      Quickshell.execDetached(["hyprctl", "reload"])
    }
    refresh(true, function() {
      updateAssignments()
      applyRuntime()
      acquireStockLease()
      if (!persisted.activeNoticeShown) {
        Quickshell.execDetached(["notify-send", "Station", "Station is active. SUPER+1…0 now switch stations."])
        persisted.activeNoticeShown = true
        saveState()
      }
    })
  }

  function barPlacement(widgetId) {
    var layout = shell && shell.barConfig && shell.barConfig.bar ? shell.barConfig.bar.layout : null
    if (!layout) return null
    var sections = ["left", "center", "right"]
    for (var s = 0; s < sections.length; s++) {
      var rows = layout[sections[s]] || []
      for (var i = 0; i < rows.length; i++) if (rows[i] && rows[i].id === widgetId)
        return { section: sections[s], index: i }
    }
    return null
  }

  function acquireStockLease() {
    if (!config.hideNative || pluginList.running) return
    pluginList.running = true
  }

  function restoreStockLease() {
    var lease = persisted.stockLease
    if (!lease) return
    if (lease.disabledByStation && lease.wasEnabled) {
      enqueue(["omarchy", "plugin", "enable", "omarchy.workspaces"], function(code) {
        if (code !== 0) return
        // Re-enabling alone drops it in the centre, and the recorded spot is
        // where it sat before Station leased it: between the Omarchy menu mark
        // and our own widget. Park it behind Station instead so the row reads
        // menu, Station, workspaces; the recorded section/index only covers a
        // bar that has since dropped the Station widget.
        root.enqueue(["omarchy", "bar", "move", "omarchy.workspaces", "--after",
          "yakumy.station"], function(afterCode) {
          if (afterCode === 0) {
            root.persisted.stockLease = null
            root.saveState()
            return
          }
          root.enqueue(["omarchy", "bar", "move", "omarchy.workspaces", "--section", lease.section,
            "--index", String(lease.index)], function() {
            root.persisted.stockLease = null
            root.saveState()
          })
        })
      })
    } else {
      persisted.stockLease = null
      saveState()
    }
  }

  function setSetting(name, value) {
    if (name === "hideNative") {
      if (panelWanted) panelTransferUntil = Date.now() + 3000
      config.hideNative = !!value
      config = Object.assign({}, config)
      saveConfig()
      if (config.hideNative) acquireStockLease(); else restoreStockLease()
      return "ok"
    }
    if (name === "followFocus") config.followFocus = !!value
    else if (name === "graceMs") {
      var grace = Number(value)
      config.graceMs = isFinite(grace) ? Math.max(0, Math.min(30000, grace)) : 5000
    }
    else if (name === "minStations") config.minStations = Math.max(1, Math.min(10, Number(value) || 3))
    else return "invalid"
    config = Object.assign({}, config)
    saveConfig()
    return "ok"
  }

  function removeStationBlock() {
    if (state !== "idle") return "busy"
    try {
      var source = MonitorsLua.removeManagedBlock(monitorsSource)
      if (source === monitorsSource) return "absent"
      var generated = MonitorsLua.generate(displayDraft, { mode: "extend",
        enabled: displayDraft.map(function(display) { return display.name }), singleTarget: "" })
      keepOptions = { mode: "extend", enabled: displayDraft.map(function(display) { return display.name }), singleTarget: "" }
      startKeepFiles(source, generated.plain)
      return "started"
    } catch (error) { layoutError = String(error.message || error); return "invalid" }
  }

  function handleStockPlugins(raw) {
    var list = parseJson(raw, [])
    var entry = list.find(function(item) { return item.id === "omarchy.workspaces" })
    var enabled = !!(entry && entry.enabled)
    if (persisted.stockLease) {
      if (persisted.stockLease.disabledByStation && enabled && stockDisableAttempts < 3 && !stockDisable.running) {
        stockDisableAttempts += 1
        stockDisable.running = true
      }
      return
    }
    var place = barPlacement("omarchy.workspaces") || { section: "left", index: 1 }
    persisted.stockLease = { wasEnabled: enabled, section: place.section, index: place.index,
      disabledByStation: enabled }
    saveState()
    if (enabled && !stockDisable.running) {
      stockDisableAttempts += 1
      stockDisable.running = true
    }
  }

  function togglePanel() {
    return shell ? String(shell.toggle("yakumy.station", "{}")) : "no-shell"
  }

  function openPanel() {
    return shell ? String(shell.summon("yakumy.station", "{}")) : "no-shell"
  }

  function eventExpected(event) {
    var output = ""
    if (String(event.name || "").indexOf("workspace") === 0) {
      var workspace = Number(String(event.data || "").split(",")[0])
      if (Grid.contains(workspace, workspaceMap)) output = workspaceMap.outputs[Grid.slot(workspace, workspaceMap)] || ""
    }
    return Events.expected(event, expect, Date.now(), output)
  }

  function handleEvent(event) {
    var name = String(event && event.name || "").toLowerCase()
    if (!name) return
    // These events are part of our display transaction. Its completion takes
    // a fresh snapshot; applying saved config here races Keep and resets drafts.
    if ((state === "previewing" || state === "applyingLayout")
        && (name.indexOf("monitoradded") === 0 || name.indexOf("monitorremoved") === 0)) {
      topologyDirty = true
      if (state === "previewing" && !previewBusy && !eventExpected(event))
        revertPreview("Display connection changed; preview reverted.")
      return
    }
    if (name === "configreloaded") {
      configGeneration += 1
      if (state === "applyingLayout") return
      if (state === "previewing") {
        if (previewBusy) previewAbortReason = "Display configuration reloaded; preview reverted."
        else revertPreview("Display configuration reloaded; preview reverted.")
        return
      }
      reloadDebounce.restart()
      return
    }
    if (name.indexOf("monitoradded") === 0) {
      if (eventExpected(event)) return
      lastTopologyMs = Date.now()
      removalGrace.stop()
      if (state === "migrating") topologyDirty = true
      refresh(true, function() { updateAssignments(); applyRuntime() })
      return
    }
    if (name.indexOf("monitorremoved") === 0) {
      if (eventExpected(event)) return
      lastTopologyMs = Date.now()
      if (state === "migrating") topologyDirty = true
      if (state === "switching") {
        gen += 1
        state = "idle"
      }
      if (state === "previewing") Quickshell.execDetached(["hyprctl", "reload"])
      removalGrace.interval = config.graceMs
      removalGrace.restart()
      return
    }
    if ((name.indexOf("workspace") !== -1 || name.indexOf("focusedmon") !== -1)
        && !eventExpected(event) && config.followFocus && state === "idle"
        && Date.now() - lastTopologyMs > 500) followFocus.restart()
  }

  Component.onCompleted: ensureDirs.running = true

  Component.onDestruction: {
    var lease = persisted.stockLease || { section: "left", index: 0, wasEnabled: false, disabledByStation: false }
    if (["left", "center", "right"].indexOf(lease.section) === -1
        || !Number.isInteger(lease.index) || lease.index < 0) return
    var restore = lease.disabledByStation && lease.wasEnabled ? "1" : "0"
    Quickshell.execDetached(["sh", "-c", Recovery.cleanup, "sh", stateDir,
      monitorsPath, lease.section, String(lease.index), restore])
  }

  FileView {
    id: configFile
    path: root.configPath
    atomicWrites: true
    printErrors: false
    onLoaded: { if (!root.configLoaded) { root.config = Store.loadConfig(root.parseJson(text(), {})); root.configLoaded = true; root.maybeStart() } }
    onLoadFailed: { if (!root.configLoaded) { root.config = Store.configDefaults(); root.configLoaded = true; root.maybeStart() } }
  }

  FileView {
    id: monitorsFile
    path: root.monitorsPath
    watchChanges: true
    printErrors: false
    onLoaded: root.monitorsSource = text()
    onLoadFailed: root.monitorsSource = ""
    onFileChanged: reload()
  }

  FileView {
    id: candidateFile; path: root.candidatePath; atomicWrites: true; printErrors: false
    onSaved: { root.candidateReady = true; root.maybeStartKeep() }
    onSaveFailed: root.keepFileFailed()
  }
  FileView {
    id: plainCandidateFile; path: root.plainCandidatePath; atomicWrites: true; printErrors: false
    onSaved: { root.plainCandidateReady = true; root.maybeStartKeep() }
    onSaveFailed: root.keepFileFailed()
  }

  FileView {
    id: personalBindings
    path: Quickshell.env("HOME") + "/.config/hypr/bindings.lua"
    watchChanges: true
    printErrors: false
    onLoaded: root.personalBindingsText = text()
    onLoadFailed: root.personalBindingsText = ""
    onFileChanged: { reload(); root.appliedGeneration = -1; root.applyBinds() }
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    onLoaded: { if (!root.stateLoaded) { root.persisted = Store.loadState(root.parseJson(text(), {})); root.stateLoaded = true; root.maybeStart() } }
    onLoadFailed: { if (!root.stateLoaded) { root.persisted = Store.stateDefaults(); root.stateLoaded = true; root.maybeStart() } }
  }

  FileView {
    id: workspaceFile
    path: root.stateDir + "/workspace-map.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (root.mappingLoaded) return
      var data = root.parseJson(text(), null)
      if (!data || (!Grid.valid(data.mapping) && !(data.pending && data.pending.from && data.pending.from.legacy))) {
        root.layoutError = "Could not read the saved workspace mapping."
        return
      }
      root.workspaceData = data
      root.previewBaseline = data.preview || null
      root.mappingLoaded = true
      root.maybeStart()
    }
    onLoadFailed: {
      if (!root.mappingLoaded) { root.mappingLoaded = true; root.maybeStart() }
    }
    onSaved: root.migrationSaved()
    onSaveFailed: root.migrationFailed("could not save the migration journal")
  }

  FileView {
    id: previewToken
    path: root.stateDir + "/preview.token"
    printErrors: false
    onLoaded: { root.previewFound = true; root.previewLoaded = true; root.maybeStart() }
    onLoadFailed: { root.previewFound = false; root.previewLoaded = true; root.maybeStart() }
  }

  Process {
    id: ensureDirs
    command: ["mkdir", "-p", root.configDir, root.stateDir]
    onExited: {
      root.dirsReady = true
      configFile.reload()
      stateFile.reload()
      workspaceFile.reload()
      previewToken.reload()
      root.maybeStart()
    }
  }

  Process {
    id: previewArm
    command: ["touch", root.stateDir + "/preview.token"]
    onExited: function(code) {
      if (code === 0) root.applyPreview()
      else { root.layoutError = "Could not arm preview recovery."; root.previewBusy = false; root.state = "idle" }
    }
  }

  Process {
    id: keepTransaction
    command: ["sh", "-c", Transactions.keep, "sh", root.candidatePath, root.monitorsPath,
      root.plainCandidatePath, root.plainPath, root.stateDir + "/preview.token"]
    property string errors: ""
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: keepTransaction.errors = text }
    onRunningChanged: if (running) errors = ""
    onExited: function(code) { root.finishKeep(code, errors) }
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

  Process {
    id: keybindings
    command: ["omarchy", "menu", "keybindings", "--print"]
    property string captured: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: keybindings.captured = text }
    onRunningChanged: if (running) captured = ""
    onExited: function(code) {
      root.menuBindingsText = captured
      root.menuBindingsOk = code === 0 && captured.trim() !== ""
      hyprBindSnapshot.running = true
    }
  }

  Process {
    id: hyprBindSnapshot
    command: ["hyprctl", "binds", "-j"]
    property string captured: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: hyprBindSnapshot.captured = text }
    onRunningChanged: if (running) captured = ""
    onExited: { root.hyprBindingsText = captured; root.finishBindCheck() }
  }

  Process {
    id: pluginList
    command: ["omarchy-shell", "shell", "listPlugins"]
    property string captured: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: pluginList.captured = text }
    onRunningChanged: if (running) captured = ""
    onExited: function(code) { if (code === 0) root.handleStockPlugins(captured) }
  }

  Process {
    id: stockDisable
    command: ["omarchy", "plugin", "disable", "omarchy.workspaces"]
    stdout: StdioCollector { waitForEnd: true }
    onExited: leaseVerify.restart()
  }

  Timer {
    id: nativeMoveSettle
    property var before: null
    property string direction: ""
    property int generation: 0
    interval: 20
    onTriggered: root.afterNativeMove(before, direction, generation)
  }

  Timer { id: reloadDebounce; interval: 300; onTriggered: { root.appliedGeneration = -1; root.refresh(true, function() { root.applyRuntime() }) } }
  Timer { id: removalGrace; interval: 5000; onTriggered: root.refresh(true, function() { root.applyRuntime() }) }
  Timer { id: migrationRetry; interval: 500; onTriggered: root.reconcile() }
  Timer { id: leaseVerify; interval: 600; onTriggered: if (!pluginList.running) pluginList.running = true }
  Timer {
    id: panelEvacuationTimeout
    interval: 1200
    onTriggered: if (root.panelEvacuationWaiting) root.panelEvacuationTimedOut()
  }
  Timer {
    id: previewCountdown
    interval: 1000
    repeat: true
    onTriggered: {
      root.previewSeconds -= 1
      if (root.previewSeconds <= 0) root.revertPreview("Preview timed out.")
    }
  }
  Timer {
    id: followFocus
    interval: 100
    onTriggered: root.refresh(true, function() {
      if (!root.readyForWindows() || Date.now() - root.lastTopologyMs <= 500) return
      var monitor = root.focusedMonitor()
      if (!monitor || !root.lanes[monitor.name]) return
      var workspace = Number(monitor.activeWorkspace && monitor.activeWorkspace.id)
      if (!Grid.contains(workspace, root.workspaceMap)) return
      var station = Grid.station(workspace, root.workspaceMap)
      if (station !== root.currentStation) root.showStation(station)
    })
  }

  Connections { target: Hyprland; function onRawEvent(event) { root.handleEvent(event) } }

  IpcHandler {
    target: "yakumy.station"
    function switchStation(value: string): string { return root.switchStation(value) }
    function sendToStation(value: string): string { return root.sendToStation(value) }
    function sendSilent(value: string): string { return root.sendSilent(value) }
    function goDirection(value: string): string { return root.goDirection(value) }
    function shiftWindow(value: string): string { return root.shiftWindow(value) }
    function togglePanel(): string { return root.togglePanel() }
    function previewLayout(): string { return root.previewLayout() }
    function keepPreview(): string { return root.keepPreview() }
    function revertPreview(): string { return root.revertPreview("") }
    function setMode(value: string): string {
      return value.indexOf("single:") === 0 ? root.setModeValue("single", value.substring(7))
        : root.setModeValue(value, "")
    }
    function setDirection(value: string): string {
      return root.setDirectionValue(value)
    }
    function approveBinding(value: string): string { return root.approveBinding(value) }
    function status(): string { return JSON.stringify({ state: root.state, generation: root.gen,
      station: root.currentStation, lanes: root.lanes, unmanaged: root.unmanaged,
      workspaceMap: root.workspaceMap, migrationPending: root.workspaceData.pending !== null,
      migrationPhase: root.migrationPhase, layoutError: root.layoutError,
      lastWindowAction: root.lastWindowAction,
      monitors: root.monitors, bindStatuses: root.bindStatuses, panelWanted: root.panelWanted,
      panelScreenName: root.panelScreenName, previewBusy: root.previewBusy, previewSeconds: root.previewSeconds,
      panelEvacuationWaiting: root.panelEvacuationWaiting,
      draftMode: root.draftMode, savedMode: root.config.mode, singleTarget: root.draftSingleTarget,
      stockLease: root.persisted.stockLease, stockDisableAttempts: root.stockDisableAttempts,
      stockDisableRunning: stockDisable.running }) }
  }
}

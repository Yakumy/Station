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
  property var displayDraft: []
  property string draftMode: "extend"
  property string draftSingleTarget: ""
  property var previewBefore: []
  property var pendingDisplayConfig: null
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
    if (state !== "previewing") syncDisplayDraft()
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
    return Grid.mapping(monitors, lanes, config)
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
    for (var i = 0; i < available.length; i++) statements.push(Hypr.focusWorkspace(workspaceFor(stationNumber, available[i])))
    if (focused && available.indexOf(focused.name) !== -1) statements.push(Hypr.focusMonitor(focused.name))
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

  function sendWindow(stationValue, follow) {
    if (!readyForWindows()) return "busy"
    var stationNumber = Number(stationValue)
    var client = focusedClient()
    if (!Number.isInteger(stationNumber) || stationNumber < 1 || stationNumber > Model.MAX_STATION) return "invalid"
    if (!client || client.pinned || workspaceMap.outputs.indexOf(client.monitor) === -1 || !Grid.eligible(client, workspaceMap)) return "unmanaged"
    var statement = Hypr.moveWindow(client.address, workspaceFor(stationNumber, client.monitor), follow)
    evalLua(statement, function() { refresh(true, null) })
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
    var existing = Grid.existing(clients, monitors, config.minStations, workspaceMap)
    var target = Model.nextExisting(currentStation, delta, existing)
    return target === null ? "edge" : showStation(target)
  }

  function shiftWindow(direction) {
    if (!readyForWindows()) return "busy"
    direction = String(direction || "").toLowerCase()
    if (["left", "right", "up", "down"].indexOf(direction) === -1) return "invalid"
    refresh(true, function() { root.shiftFocusedWindow(direction) })
    return "started"
  }

  function shiftFocusedWindow(direction) {
    if (!readyForWindows()) return "busy"
    var client = focusedClient()
    if (!client || client.pinned || workspaceMap.outputs.indexOf(client.monitor) === -1 || !Grid.eligible(client, workspaceMap)) return "unmanaged"
    var managed = workspaceMap.outputs
    var targetMonitor = Model.neighborMonitor(client.monitor, direction, monitors, managed)
    var targetStation = Grid.station(Number(client.workspace.id), workspaceMap)
    if (!targetMonitor) {
      var delta = Model.step(direction, config.direction)
      if (delta === null || targetStation + delta < 1 || targetStation + delta > Model.MAX_STATION) return "edge"
      targetStation += delta
      var opposite = { left: "right", right: "left", up: "down", down: "up" }[direction]
      targetMonitor = Model.edgeMonitor(opposite, monitors, managed)
    }
    if (!targetMonitor || !lanes[targetMonitor]) return "edge"
    var statements = Hypr.compactRules(workspaceMap.outputs)
    statements.push(Hypr.moveWindow(client.address, workspaceFor(targetStation, targetMonitor), true))
    evalLua(Hypr.batch(statements),
      function() { refresh(true, null) })
    return "started"
  }

  function reconcile() {
    if (state === "previewing" || state === "applyingLayout") return
    if (removalGrace.running) return
    if (migrationPhase || state === "migrating") { topologyDirty = true; return }
    begin("migrating")
    refresh(true, function() {
      updateAssignments()
      var target = targetMapping()
      if (!Grid.valid(target)) { state = "idle"; return }
      try {
        var old = workspaceMap || (persisted.legacyWorkspaceGrid ? Grid.legacy(lanes) : target)
        var pending = workspaceData.pending
        var plan = pending ? Grid.resume(pending, target, clients) : Grid.plan(old, target, clients, currentStation)
        var focused = focusedClient()
        migrationFocus = focused ? Grid.identity(focused) : null
        // FileView does not emit saved when setText receives identical text.
        // A revision makes every journal attempt an acknowledged disk write,
        // including recovery of an otherwise unchanged plan after restart.
        workspaceData = { mapping: old, pending: plan, revision: Number(workspaceData.revision || 0) + 1 }
        topologyDirty = false
        migrationPhase = "journal"
        workspaceFile.setText(JSON.stringify(workspaceData, null, 2) + "\n")
      } catch (error) { migrationFailed(String(error)) }
    })
  }

  function migrationFailed(message) {
    migrationPhase = ""
    state = "idle"
    layoutError = "Workspace migration: " + message
    // Keep the journal for a later retry; never decode partially moved IDs again.
    if (++migrationAttempts <= 3) migrationRetry.restart()
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
    plan.windows.forEach(function(row) {
      var client = clients.find(function(c) { return Grid.sameClient(row, c) })
      if (!client || client.pinned) return
      if (Number(client.workspace.id) !== row.to) statements.push(Hypr.moveWindow(row.address, row.to, false))
      destinations[row.to] = row.output
    })
    // Workspace rules only place new workspaces. Existing workspaces must also
    // be placed explicitly after all address-based moves have finished.
    Object.keys(destinations).forEach(function(id) {
      statements.push(Hypr.moveWorkspace(Number(id), destinations[id]))
    })
    expect = { kinds: ["workspace", "focusedmon"], outputs: plan.to.outputs.slice(), until: Date.now() + 2000 }
    evalLua(Hypr.batch(statements), function(code, output) {
      if (code !== 0 || (output && output.trim() !== "ok")) { migrationFailed("compositor rejected the move batch"); return }
      refresh(true, function() {
        if (topologyDirty || !Grid.equal(plan.to, targetMapping())) {
          migrationPhase = ""; state = "idle"; reconcile(); return
        }
        var failed = plan.windows.some(function(row) {
          var client = clients.find(function(c) { return Grid.sameClient(row, c) })
          return client && !client.pinned && (Number(client.workspace.id) !== row.to || client.monitor !== row.output)
        })
        if (failed) { migrationFailed("destination verification failed"); return }
        currentStation = plan.station
        migrationCommit = { mapping: plan.to, pending: null, revision: workspaceData.revision + 1 }
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
    try { MonitorsLua.connector(name) } catch (error) { return "invalid" }
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

  function setModeValue(mode, target) {
    if (["extend", "mirror", "single"].indexOf(mode) === -1) return "invalid"
    if (mode === "single") {
      try { MonitorsLua.connector(target) } catch (error) { return "invalid" }
      if (!displayDraft.some(function(display) { return display.name === target })) return "invalid"
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
    var roles = displayDraft.filter(function(display) { return display.enabled && lanes[display.name] })
      .map(function(display) { return lanes[display.name] }).sort(function(a, b) { return a - b })
    return roles.indexOf(lanes[name])
  }

  function previewLayout() {
    if (state !== "idle") return "busy"
    try {
      if (Model.layoutOverlaps(displayDraft).length) throw new Error("Displays overlap")
      var generated = MonitorsLua.generate(displayDraft, {
        mode: draftMode, enabled: displayDraft.filter(function(d) { return d.enabled }).map(function(d) { return d.name }),
        singleTarget: draftSingleTarget
      })
      previewBefore = monitors.slice()
      pendingDisplayConfig = generated
      layoutError = ""
      begin("previewing")
      previewArm.running = true
      return "started"
    } catch (error) {
      layoutError = String(error.message || error)
      return "invalid"
    }
  }

  function applyPreview() {
    if (state !== "previewing" || !pendingDisplayConfig) return
    Quickshell.execDetached(["sh", "-c", Transactions.watchdog, "sh", "20", stateDir + "/preview.token"])
    previewSeconds = 12
    previewCountdown.restart()
    var lua = pendingDisplayConfig.block.split("\n").filter(function(line) {
      return line !== MonitorsLua.START && line !== MonitorsLua.END
    }).join("\n")
    expect = { kinds: ["monitor", "workspace"], outputs: MonitorsLua.changedOutputs(
      pendingDisplayConfig.displays, { mode: draftMode, singleTarget: draftSingleTarget,
        enabled: displayDraft.filter(function(d) { return d.enabled }).map(function(d) { return d.name }) },
      previewBefore, true), until: Date.now() + 2000 }
    evalLua(lua)
  }

  function revertPreview(reason) {
    if (state !== "previewing") return "idle"
    gen += 1
    state = "applyingLayout"
    previewCountdown.stop()
    pendingDisplayConfig = null
    enqueue(["rm", "-f", stateDir + "/preview.token"], function() {
      root.enqueue(["hyprctl", "reload"], function() { root.state = "idle"; root.refresh(true, null) })
    })
    if (reason) layoutError = reason
    return "started"
  }

  function keepPreview() {
    if (state !== "previewing" || !pendingDisplayConfig) return "idle"
    try {
      var source = monitorsSource || ""
      var merged = MonitorsLua.replaceManagedBlock(source, pendingDisplayConfig.block)
      var conflicts = MonitorsLua.externalRuleConflicts(source,
        pendingDisplayConfig.displays.map(function(display) { return display.name }))
      if (conflicts.length) layoutError = "Other monitor rules also mention: " + conflicts.join(", ")
      candidateFile.setText(merged)
      plainCandidateFile.setText(pendingDisplayConfig.plain)
      previewCountdown.stop()
      state = "applyingLayout"
      keepDelay.restart()
      return "started"
    } catch (error) {
      layoutError = String(error.message || error)
      return "invalid"
    }
  }

  function finishKeep(code, errorText) {
    if (code !== 0) {
      layoutError = code === 3 ? "Hyprland rejected the layout; the backup was restored. " + errorText.trim()
        : "Could not save the monitor layout."
      state = "idle"
      refresh(true, null)
      return
    }
    config.enabled = displayDraft.filter(function(display) { return display.enabled }).map(function(display) { return display.name })
    config.mode = draftMode
    config.singleTarget = draftSingleTarget
    config = Object.assign({}, config)
    pendingDisplayConfig = null
    monitorsFile.reload()
    saveConfig()
    state = "idle"
    applyRuntime()
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
        root.enqueue(["omarchy", "bar", "move", "omarchy.workspaces", "--section", lease.section,
          "--index", String(lease.index)], function() {
          root.persisted.stockLease = null
          root.saveState()
        })
      })
    } else {
      persisted.stockLease = null
      saveState()
    }
  }

  function setSetting(name, value) {
    if (name === "hideNative") {
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
      candidateFile.setText(source)
      plainCandidateFile.setText(generated.plain)
      state = "applyingLayout"
      keepDelay.restart()
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
    if (name === "configreloaded") {
      configGeneration += 1
      if (state === "applyingLayout") return
      reloadDebounce.restart()
      return
    }
    if (name.indexOf("monitoradded") === 0) {
      if (eventExpected(event)) return
      lastTopologyMs = Date.now()
      removalGrace.stop()
      if (state === "migrating") topologyDirty = true
      refresh(true, function() { updateAssignments(); applyRuntime(); openPanel() })
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

  FileView { id: candidateFile; path: root.candidatePath; atomicWrites: true; printErrors: false }
  FileView { id: plainCandidateFile; path: root.plainCandidatePath; atomicWrites: true; printErrors: false }

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
      else { root.layoutError = "Could not arm preview recovery."; root.state = "idle" }
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

  Timer { id: reloadDebounce; interval: 300; onTriggered: { root.appliedGeneration = -1; root.refresh(true, function() { root.applyRuntime() }) } }
  Timer { id: removalGrace; interval: 5000; onTriggered: root.refresh(true, function() { root.applyRuntime() }) }
  Timer { id: migrationRetry; interval: 500; onTriggered: root.reconcile() }
  Timer { id: leaseVerify; interval: 600; onTriggered: if (!pluginList.running) pluginList.running = true }
  Timer { id: keepDelay; interval: 150; onTriggered: keepTransaction.running = true }
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
      return root.setModeValue(value, "")
    }
    function setDirection(value: string): string {
      return root.setDirectionValue(value)
    }
    function approveBinding(value: string): string { return root.approveBinding(value) }
    function status(): string { return JSON.stringify({ state: root.state, generation: root.gen,
      station: root.currentStation, lanes: root.lanes, unmanaged: root.unmanaged,
      workspaceMap: root.workspaceMap, migrationPending: root.workspaceData.pending !== null,
      migrationPhase: root.migrationPhase, layoutError: root.layoutError,
      monitors: root.monitors, bindStatuses: root.bindStatuses,
      stockLease: root.persisted.stockLease, stockDisableAttempts: root.stockDisableAttempts,
      stockDisableRunning: stockDisable.running }) }
  }
}

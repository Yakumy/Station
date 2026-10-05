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

Item {
  id: root

  property var shell: null
  property var manifest: null
  property var config: Store.configDefaults()
  property var persisted: Store.stateDefaults()
  property var monitors: []
  property var clients: []
  property var lanes: ({})
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
    if (monitorSnapshot.running || clientSnapshot.running) {
      refreshRetry.pendingClients = refreshRetry.pendingClients || includeClients
      refreshRetry.pendingDone = done || refreshRetry.pendingDone
      refreshRetry.restart()
      return
    }
    refreshClientsToo = includeClients
    refreshDone = done || null
    monitorSnapshot.running = true
  }

  function updateAssignments() {
    var connected = monitors.filter(function(m) { return root.validConnector(m.name) })
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

  function present() {
    return Model.presentForMode(monitors.filter(function(m) { return m.disabled !== true }),
      lanes, config.mode, config.enabled, config.singleTarget)
  }

  function focusedMonitor() {
    for (var i = 0; i < monitors.length; i++) if (monitors[i].focused) return monitors[i]
    return null
  }

  function focusedClient() {
    for (var i = 0; i < clients.length; i++) if (clients[i].focusHistoryID === 0) return clients[i]
    return null
  }

  function applyRules(station) {
    var statements = Hypr.workspaceRules(station, lanes, present(), Model.host)
    evalLua(Hypr.batch(statements))
  }

  function showStation(stationValue) {
    var stationNumber = Number(stationValue)
    if (!Number.isInteger(stationNumber) || stationNumber < 1 || stationNumber > Model.MAX_STATION) return "invalid"
    var available = present()
    if (!available.length) return "no-monitor"
    var generation = begin("switching")
    var focused = focusedMonitor()
    var rules = Hypr.workspaceRules(stationNumber, lanes, available, Model.host)
    var statements = rules.slice()
    for (var i = 0; i < available.length; i++) statements.push(Hypr.focusWorkspace(Model.ws(stationNumber, available[i])))
    if (focused && lanes[focused.name]) statements.push(Hypr.focusMonitor(focused.name))
    expect = { kinds: ["workspace", "focusedmon"], outputs: Object.keys(lanes).filter(function(name) {
      return available.indexOf(lanes[name]) !== -1
    }), until: Date.now() + 2000 }
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
    var stationNumber = Number(stationValue)
    var client = focusedClient()
    if (!Number.isInteger(stationNumber) || stationNumber < 1 || stationNumber > Model.MAX_STATION) return "invalid"
    if (!client || client.pinned || !lanes[client.monitor] || !Model.inGrid(Number(client.workspace.id))) return "unmanaged"
    var statement = Hypr.moveWindow(client.address, Model.ws(stationNumber, lanes[client.monitor]), follow)
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
    var existing = Model.existingStations(clients, monitors, config.minStations, Object.keys(lanes))
    var target = Model.nextExisting(currentStation, delta, existing)
    return target === null ? "edge" : showStation(target)
  }

  function shiftWindow(direction) {
    direction = String(direction || "").toLowerCase()
    if (["left", "right", "up", "down"].indexOf(direction) === -1) return "invalid"
    refresh(true, function() { root.shiftFocusedWindow(direction) })
    return "started"
  }

  function shiftFocusedWindow(direction) {
    var client = focusedClient()
    if (!client || client.pinned || !lanes[client.monitor] || !Model.inGrid(Number(client.workspace.id))) return "unmanaged"
    var managed = Object.keys(lanes)
    var targetMonitor = Model.neighborMonitor(client.monitor, direction, monitors, managed)
    var targetStation = Model.stationOf(Number(client.workspace.id))
    if (!targetMonitor) {
      var delta = Model.step(direction, config.direction)
      if (delta === null || targetStation + delta < 1 || targetStation + delta > Model.MAX_STATION) return "edge"
      targetStation += delta
      var opposite = { left: "right", right: "left", up: "down", down: "up" }[direction]
      targetMonitor = Model.edgeMonitor(opposite, monitors, managed)
    }
    if (!targetMonitor || !lanes[targetMonitor]) return "edge"
    var statements = Hypr.workspaceRules(targetStation, lanes, present(), Model.host)
    statements.push(Hypr.moveWindow(client.address, Model.ws(targetStation, lanes[targetMonitor]), true))
    evalLua(Hypr.batch(statements),
      function() { refresh(true, null) })
    return "started"
  }

  function reconcile(scheduleSecond) {
    if (scheduleSecond === undefined) scheduleSecond = true
    var generation = begin("reconciling")
    refresh(true, function() {
      if (generation !== gen) return
      updateAssignments()
      var moves = Model.planReconcile(clients, present(), lanes)
      var statements = moves.map(function(move) { return Hypr.moveWindow(move.address, move.to, false) })
      evalLua(Hypr.batch(statements), function() {
        if (generation !== gen) return
        finish(generation)
        showStation(currentStation)
        if (scheduleSecond) secondReconcile.restart()
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
      evalLua(Hypr.batch(monitorRules))
    } catch (error) { console.warn("Station monitor mode:", error) }
    applyRules(currentStation)
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
    var moves = Model.planRoleChange(clients, old, next)
    lanes = next
    var statements = moves.map(function(move) { return Hypr.moveWindow(move.address, move.to, false) })
    config.lanes = Object.assign({}, config.lanes)
    var ids = Model.identities(monitors)
    for (var i = 0; i < monitors.length; i++) if (next[monitors[i].name]) config.lanes[ids[i]] = next[monitors[i].name]
    saveConfig()
    syncDisplayDraft()
    evalLua(Hypr.batch(Hypr.workspaceRules(currentStation, lanes, present(), Model.host).concat(statements)),
      function() { root.reconcile() })
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
    refresh(true, null)
  }

  function maybeStart() {
    if (started || !dirsReady || !configLoaded || !stateLoaded || !previewLoaded) return
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
      reconcile()
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
      if (Model.inGrid(workspace)) {
        var lane = Model.host(Model.slotOf(workspace), present())
        output = Object.keys(lanes).find(function(name) { return lanes[name] === lane }) || ""
      }
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
      refresh(true, function() { updateAssignments(); applyRuntime(); openPanel() })
      return
    }
    if (name.indexOf("monitorremoved") === 0) {
      if (eventExpected(event)) return
      lastTopologyMs = Date.now()
      if (state === "switching" || state === "reconciling") {
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
    onExited: {
      if (root.refreshClientsToo) clientSnapshot.running = true
      else {
        var done = root.refreshDone; root.refreshDone = null
        if (done) done()
      }
    }
  }

  Process {
    id: clientSnapshot
    command: ["hyprctl", "clients", "-j"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.clients = Model.normalizeClients(root.parseJson(text, []), root.monitors)
    }
    onExited: {
      var done = root.refreshDone; root.refreshDone = null
      if (done) done()
    }
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
    id: refreshRetry
    property bool pendingClients: false
    property var pendingDone: null
    interval: 100
    onTriggered: {
      var clientsToo = pendingClients; var done = pendingDone
      pendingClients = false; pendingDone = null
      root.refresh(clientsToo, done)
    }
  }

  Timer { id: reloadDebounce; interval: 300; onTriggered: { root.appliedGeneration = -1; root.refresh(true, function() { root.applyRuntime(); root.reconcile() }) } }
  Timer { id: removalGrace; interval: 5000; onTriggered: root.reconcile() }
  Timer { id: secondReconcile; interval: 1000; onTriggered: root.reconcile(false) }
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
      if (root.state !== "idle" || Date.now() - root.lastTopologyMs <= 500) return
      var monitor = root.focusedMonitor()
      if (!monitor || !root.lanes[monitor.name]) return
      var workspace = Number(monitor.activeWorkspace && monitor.activeWorkspace.id)
      if (!Model.inGrid(workspace)) return
      var station = Model.stationOf(workspace)
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
      monitors: root.monitors, bindStatuses: root.bindStatuses,
      stockLease: root.persisted.stockLease, stockDisableAttempts: root.stockDisableAttempts,
      stockDisableRunning: stockDisable.running }) }
  }
}

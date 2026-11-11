import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "lib/displays/Model.js" as Model
import "lib/panel/Tabs.js" as Tabs
import "lib/platform/Recovery.js" as Recovery
import "lib/platform/Transactions.js" as Transactions
import "lib/platform/Events.js" as Events
import "lib/platform/Store.js" as Store
import "lib/stations/Grid.js" as Grid
import "lib/panel/ServiceContract.js" as ServiceContract
import "lib/bars" as Bars
import "lib/color" as ColorUi
import "lib/displays" as Displays
import "lib/keybindings" as Keys
import "lib/panel" as PanelUi
import "lib/platform" as Platform
import "lib/stations" as Stations
import "lib/wallpaper" as WallpaperUi
import "lib/windows" as WindowsUi
import "lib/BarBridge.js" as BarBridge

// Composition root and operation arbiter. Feature protocols live in the owners
// below; each receives data and finite ports, never this object. This file keeps
// the operation state, compositor event routing, startup order and IPC, plus the
// public members IPC, the panel and the bar bridge consume.
Item {
  id: root

  property var shell: null
  onShellChanged: Qt.callLater(barSettings.reconcileActiveBarLayout)
  // Observe Omarchy's global edge independently of our per-monitor overrides.
  readonly property string focusedBarScreenName: Hyprland.focusedMonitor
    ? String(Hyprland.focusedMonitor.name || "") : ""
  property var manifest: null
  property var barBridge: null
  readonly property string pluginDir: manifest && typeof manifest.__sourceDir === "string"
    ? manifest.__sourceDir.replace(/\/$/, "") : ""
  onPluginDirChanged: Qt.callLater(wallpaperController.prepareLegacyWallpaper)

  // Operation arbiter. `state` is the operation; `gen` retires stale callbacks.
  property int gen: 0
  property bool started: false
  property int configGeneration: 0
  property string layoutError: ""
  property var expect: ({ kinds: [], outputs: [], until: 0 })
  property double lastTopologyMs: 0
  property string observedMonitorSignature: ""
  property var lanes: ({})
  property var unmanaged: []

  // Observations and state read by owners, IPC and the panel.
  property alias config: store.config
  property alias persisted: store.persisted
  readonly property alias configLoaded: store.configLoaded
  readonly property alias stateDir: store.stateDir
  readonly property string monitorsPath: Quickshell.env("HOME") + "/.config/hypr/monitors.lua"
  readonly property string internalDisablePath: Quickshell.env("HOME") + "/.local/state/omarchy/toggles/hypr/internal-monitor-disable.lua"
  readonly property string parkedTogglePath: stateDir + "/internal-monitor-disable.parked"
  readonly property string workspaceAuthorityPath: Quickshell.env("HOME") + "/.local/state/omarchy/toggles/hypr/station-workspaces.lua"
  readonly property string colorTogglePath: Quickshell.env("HOME") + "/.local/state/omarchy/toggles/hypr/station-color.lua"
  // Omarchy's record of each monitor's workspace block. Read only.
  readonly property string omarchyBlocksPath: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
    + "/omarchy/monitor-workspaces"
  property var omarchyBlocks: ({ byConnector: {}, taken: [] })
  // Repetitive is Omarchy's own numbering, so its reconcile runs.
  readonly property bool omarchyWorkspaces: Grid.blocked(workspaceMap)
  readonly property alias monitors: compositor.monitors
  readonly property alias clients: compositor.clients
  readonly property alias currentStation: stations.currentStation
  readonly property var workspaceData: workspace.snapshot
  readonly property var workspaceMap: workspaceData.mapping
  readonly property alias bindStatuses: keybindings.bindStatuses
  readonly property alias displayWidgetEnabled: leases.displayWidgetEnabled
  readonly property alias workspaceWidgetEnabled: leases.workspaceWidgetEnabled
  readonly property alias windowSettingsBusy: windowSettings.windowSettingsBusy
  readonly property var colorMatch: colorMatchController.snapshot
  readonly property alias wallpaper: wallpaperController
  readonly property var openApps: openAppsController.rows
  readonly property var workspaceApps: openAppsController.outputRows
  // The map the preferences ask for. The Workspaces tab draws it before a
  // migration commits it.
  readonly property var workspaceTarget: targetMapping()

  readonly property alias panelWanted: panel.panelWanted
  readonly property alias panelScreenName: panel.panelScreenName
  readonly property alias panelTransferUntil: panel.panelTransferUntil
  readonly property alias panelEvacuationSerial: panel.panelEvacuationSerial
  readonly property alias panelEvacuationWaiting: panel.panelEvacuationWaiting
  readonly property alias panelEvacuationFrom: panel.panelEvacuationFrom
  readonly property alias panelEvacuationReleases: panel.panelEvacuationReleases
  readonly property alias rememberedTab: panel.rememberedTab
  readonly property alias rememberedDisplayName: panel.rememberedDisplayName

  // A preview is an editing session, not a lock: the draft stays editable
  // until Keep or Revert, so the user can rearrange again without having to
  // settle the previous attempt first.
  readonly property bool draftEditable: displayController.draftEditable
  readonly property bool previewBusy: displayController.previewBusy
  readonly property int previewSeconds: displayController.previewSeconds
  readonly property var displayDraft: displayController.detached(displayController.displayDraft)
  readonly property string draftMode: displayController.draftMode
  readonly property string draftSingleTarget: displayController.draftSingleTarget
  readonly property var previewBaseline: displayController.detached(displayController.previewBaseline)
  readonly property var previewApplied: displayController.detached(displayController.previewApplied)
  readonly property var monitorBarMinimums: barSettings.monitorBarMinimums
  readonly property var monitorBarMaximumContents: barSettings.monitorBarMaximumContents

  Platform.SettingsStore {
    id: store
    loaded: function() { root.maybeStart() }
    directoriesReady: function() {
      workspace.reload()
      displayController.reloadPreviewToken()
      root.maybeStart()
    }
    configSaved: function() { wallpaperController.preferenceSaved() }
    configSaveFailed: function() { wallpaperController.preferenceFailed() }
  }
  Platform.CompositorLane {
    id: compositor
    configGeneration: root.configGeneration
    snapshotFailed: function() { root.handleSnapshotFailure() }
  }
  PanelUi.PanelIntent {
    id: panel
    closed: function() { barSettings.panelClosed() }
    continueApply: function() { displayController.continuePreviewApply() }
    continueRevert: function() { displayController.continueRevertPreview() }
    timedOut: function(purpose, from) { displayController.panelEvacuationTimedOut(purpose, from) }
  }
  Stations.StationController {
    id: stations
    operationState: root.state
    gen: root.gen
    monitors: root.monitors
    clients: root.clients
    lanes: root.lanes
    config: root.config
    workspaceData: root.workspaceData
    workspaceMap: root.workspaceMap
    removalGraceRunning: removalGrace.running
    lastTopologyMs: root.lastTopologyMs
    currentStation: root.persisted.lastStation || 1
    targetMapping: function() { return root.targetMapping() }
    begin: function(state) { return root.begin(state) }
    finish: function(generation) { root.finish(generation) }
    refresh: function(includeClients, done) { compositor.refresh(includeClients, done) }
    enqueue: function(command, done) { compositor.enqueue(command, done) }
    evalLua: function(lua, done) { compositor.evalLua(lua, done) }
    recordExpectedEvents: function(value) { root.expect = value }
    rememberStation: function(station) {
      root.persisted.lastStation = station
      store.saveState()
    }
  }
  Keys.KeybindingsController {
    id: keybindings
    started: root.started
    configGeneration: root.configGeneration
    config: root.config
    persisted: root.persisted
    updateConfig: function(change) {
      root.config = Object.assign({}, root.config, change)
      store.saveConfig()
    }
    saveState: function() { store.saveState() }
    evalLua: function(lua, done) { compositor.evalLua(lua, done) }
  }
  Bars.StockWidgetLeases {
    id: leases
    shell: root.shell
    started: root.started
    config: root.config
    persisted: root.persisted
    saveState: function() { store.saveState() }
    enqueue: function(command, done) { compositor.enqueue(command, done) }
  }
  Displays.ScreenRecovery {
    id: screenRecovery
    operationState: root.state
    monitors: root.monitors
    lanes: root.lanes
    setOperationState: function(value) { root.state = value }
    recordExpectedEvents: function(value) { root.expect = value }
    evalLua: function(lua, done) { compositor.evalLua(lua, done) }
    refresh: function(includeClients, done) { compositor.refresh(includeClients, done) }
    reconcile: function() { workspace.reconcile() }
    reportError: function(message) { root.layoutError = message }
  }
  Stations.WorkspaceAuthority {
    id: workspaceAuthority
    path: root.workspaceAuthorityPath
    released: root.omarchyWorkspaces
    evalLua: function(lua, done) { compositor.evalLua(lua, done) }
  }
  Bars.BarLayerSync {
    id: barLayers
    active: root.started && root.configLoaded
    displays: root.displayDraft
    monitorBar: function(name) { return barSettings.monitorBar(name) }
    windowValues: root.config.windows || ({})
    barPreferences: root.config.bars || ({})
    configGeneration: root.configGeneration
    clearLegacyLease: function() {
      if (root.persisted.barBlurLease) { root.persisted.barBlurLease = null; store.saveState() }
    }
    evalLua: function(lua, done) { compositor.evalLua(lua, done) }
  }
  Bars.BarSettingsController {
    id: barSettings
    preferences: root.config.bars || ({})
    hostConfig: root.shell && root.shell.barConfig ? root.shell.barConfig : null
    displays: root.displayDraft
    configLoaded: root.configLoaded
    panelWanted: root.panelWanted
    focusedBarScreenName: root.focusedBarScreenName
    persistPreferences: function(bars) {
      root.config = Object.assign({}, root.config, { bars: bars })
      store.saveConfig()
    }
    publishHost: root.shell && typeof root.shell.mutateShellConfig === "function"
      ? function(change) { return root.shell.mutateShellConfig(change) } : null
    retainPanel: function(tab) {
      if (tab) panel.setRememberedTab(Tabs.index(tab))
      panel.setPanelTransferUntil(Date.now() + 3000)
    }
    requestLayerSync: function() { barLayers.syncBarBlur(); barLayers.syncBarGaps() }
  }
  WindowsUi.WindowSettingsController {
    id: windowSettings
    appliedSettings: root.config.windows
    operationState: root.state
    configGeneration: root.configGeneration
    enqueue: function(command, done, generation) { compositor.enqueue(command, done, generation) }
    publishObserved: function(observed) {
      root.config = Object.assign({}, root.config, { windows: observed })
    }
    reportError: function(message) { root.layoutError = message }
    refreshStyle: function() {
      if (typeof Style.scheduleRefresh === "function") Style.scheduleRefresh()
    }
  }
  ColorUi.ColorMatchController {
    id: colorMatchController
    monitors: root.monitors
    settings: root.config.colorMatch || ({})
    started: root.started
    operationState: root.state
    togglePath: root.colorTogglePath
    profileDir: root.stateDir + "/color"
    enqueue: function(command, done) { compositor.enqueue(command, done) }
    publishSettings: function(value) {
      root.config = Object.assign({}, root.config, { colorMatch: value })
    }
    saveSettings: function() { store.saveConfig() }
  }
  Stations.WorkspaceController {
    id: workspace
    stateDir: root.stateDir
    operationState: root.state
    operationGeneration: root.gen
    removalGraceRunning: removalGrace.running
    clients: root.clients
    lanes: root.lanes
    currentStation: root.currentStation
    legacyWorkspaceGrid: root.persisted.legacyWorkspaceGrid || false
    previewBaseline: root.previewBaseline
    panelScreenName: root.panelScreenName
    layoutError: root.layoutError
    targetMapping: function() { return root.targetMapping() }
    refresh: function(includeClients, done) { compositor.refresh(includeClients, done) }
    updateAssignments: function() { root.updateAssignments() }
    focusedClient: function() { return root.focusedClient() }
    beginMigration: function() { return root.begin("migrating") }
    setOperationState: function(value) { root.state = value }
    evalLua: function(lua, done) { compositor.evalLua(lua, done) }
    recordExpectedEvents: function(value) { root.expect = value }
    reportError: function(message) { root.layoutError = message }
    setCurrentStation: function(station) { stations.currentStation = station }
    commitMigrationState: function(station) {
      root.persisted.legacyWorkspaceGrid = false
      root.persisted.lastStation = station
      store.saveState()
    }
    restorePreviewBaseline: function(value) { displayController.restorePreviewBaseline(value) }
    finishPreviewApply: function() { displayController.finishPreviewApply() }
    failPreview: function(message) { displayController.failPreview(message) }
    focusStatements: function(station, output) { return stations.settleStatements(station, output) }
    showStation: function(station) { stations.showStation(station) }
    settle: function(identity) { stations.settleAfterMigration(identity) }
    ready: function() { root.maybeStart() }
  }
  Displays.DisplayController {
    id: displayController
    stateDir: root.stateDir
    monitorsPath: root.monitorsPath
    internalDisablePath: root.internalDisablePath
    parkedTogglePath: root.parkedTogglePath
    candidatePath: root.stateDir + "/monitors.lua.candidate"
    plainCandidatePath: root.stateDir + "/monitors-block.plain.lua.candidate"
    plainPath: root.stateDir + "/monitors-block.plain.lua"
    operationState: root.state
    operationGeneration: root.gen
    configGeneration: root.configGeneration
    started: root.started
    preferences: ({ enabled: root.config.enabled, mode: root.config.mode,
      singleTarget: root.config.singleTarget, mirrorSource: root.config.mirrorSource })
    monitors: root.monitors
    clients: root.clients
    lanes: root.lanes
    currentStation: root.currentStation
    workspaceMap: root.workspaceMap
    migrationPending: !!root.workspaceData.pending
    migrationPhase: workspace.migrationPhase
    topologyDirty: workspace.topologyDirty
    panelWanted: root.panelWanted
    panelScreenName: root.panelScreenName
    layoutError: root.layoutError
    beginPreview: function() { return root.begin("previewing") }
    setOperationState: function(value) { root.state = value }
    beginRevert: function() { root.gen += 1 }
    invalidatePreviewOperation: function() { root.gen += 1; root.configGeneration += 1 }
    refresh: function(includeClients, done) { compositor.refresh(includeClients, done) }
    evalLua: function(lua, done) { compositor.evalLua(lua, done) }
    enqueue: function(command, done) { compositor.enqueue(command, done) }
    recordExpectedEvents: function(value) { root.expect = value }
    monitorSignature: function() { return root.monitorSignature() }
    reconcileWorkspace: function() { workspace.reconcile() }
    targetMapping: function() { return root.targetMapping() }
    clearWorkspaceTopologyDirty: function() { workspace.clearTopologyDirty() }
    requestPanelEvacuation: function(from, to, purpose, releases) { panel.requestPanelEvacuation(from, to, purpose, releases) }
    clearPanelEvacuation: function() { panel.clearPanelEvacuation() }
    // Optional scalars preserve screen-only and deadline-only writes as well as
    // their existing order. Do not capture a visual panel or widget proxy here.
    retainPanel: function(screen, until) {
      if (screen !== undefined) panel.panelScreenName = screen
      if (until !== undefined) panel.panelTransferUntil = until
    }
    stopTopologyTimers: function() { removalGrace.stop(); reloadDebounce.stop() }
    publishDisplayOptions: function(options) {
      root.config.enabled = options.enabled.slice()
      root.config.mode = options.mode
      root.config.singleTarget = options.singleTarget || ""
      root.config.mirrorSource = options.mirrorSource || ""
      root.config = Object.assign({}, root.config)
    }
    saveDisplayPreferences: function() { store.saveConfig() }
    invalidateAppliedBinds: function() { keybindings.invalidate() }
    updateAssignments: function() { root.updateAssignments() }
    applyBinds: function() { keybindings.applyBinds() }
    applyRuntime: function() { root.applyRuntime() }
    armScreenHealthCheck: function() { screenRecovery.armScreenHealthCheck() }
    launchWatchdog: function() {
      Quickshell.execDetached(["sh", "-c", Transactions.watchdog, "sh", "20", root.stateDir + "/preview.token",
        root.parkedTogglePath, root.internalDisablePath])
    }
    reportError: function(message) { root.layoutError = message }
    ready: function() { root.maybeStart() }
    finishAuthorityMigration: function(done, reloadRequired) { root.finishAuthorityMigration(done, reloadRequired) }
  }
  WallpaperUi.WallpaperController {
    id: wallpaperController
    monitors: root.monitors
    savedPreferences: root.config.wallpaper
    configLoaded: root.configLoaded
    stateDir: root.stateDir
    pluginDir: root.pluginDir
    enqueue: function(command, done) { compositor.enqueue(command, done) }
    publishPreferences: function(value) {
      root.config = Object.assign({}, root.config, { wallpaper: value })
    }
    savePreferences: function() { store.saveConfig() }
    releasePanel: function() { panel.panelWanted = false }
    returnPanel: function() {
      panel.rememberedTab = Tabs.index("wallpaper")
      panel.panelWanted = true
    }
  }
  Stations.OpenAppsController {
    id: openAppsController
    active: root.config.compactMode !== "on"
    mapping: root.workspaceMap
    pending: root.workspaceData.pending
    minimum: Grid.STATION_COUNT
    current: root.currentStation
  }

  function begin(nextState) {
    stations.clearQueued()
    gen += 1
    state = nextState
    return gen
  }

  function finish(generation) {
    if (generation === gen) state = "idle"
  }

  function handleSnapshotFailure() {
    if (state === "migrating") workspace.migrationFailed("could not read compositor state")
    else if (state === "previewing") {
      displayController.failPreview("Could not read the display state; reverting the preview.")
    } else if (state === "applyingLayout") {
      layoutError = "Could not read the restored display state."
      state = "idle"
    }
  }

  function updateAssignments() {
    var connected = monitors.filter(function(m) { return displayController.validConnector(m.name) })
    var assigned = Model.assignLanes(connected, config.lanes, lanes)
    lanes = assigned.lanes
    unmanaged = assigned.unmanaged
    var observed = state !== "previewing" && state !== "applyingLayout" ? Model.observedOptions(connected) : null
    config = Object.assign({}, config, observed || {}, { lanes: assigned.preferences })
    store.saveConfig()
    if (state !== "previewing" && state !== "applyingLayout") {
      observedMonitorSignature = monitorSignature()
      displayController.syncDisplayDraft()
    }
  }

  function focusedClient() {
    for (var i = 0; i < clients.length; i++) if (clients[i].focusHistoryID === 0) return clients[i]
    return null
  }

  function targetMapping() {
    var options = state === "previewing" && previewApplied ? previewApplied.options : config
    return Grid.mapping(monitors, lanes, options, { mode: config.workspaceMode, layout: config.workspaceLayout,
      blocks: omarchyBlocks })
  }

  function monitorSignature() {
    return JSON.stringify(monitors.map(function(m) { return [m.name, m.disabled, m.mirrorOf, m.x, m.y, m.scale, m.width, m.height, m.refreshRate, m.transform] }))
  }

  function observeDesktop() {
    if (!started || compositor.snapshotBusy || windowSettingsBusy || removalGrace.running) return
    if (state === "previewing" && !previewBusy) {
      compositor.refresh(false, function() {
        if (root.state === "previewing" && !root.previewBusy && displayController.previewObservedSignature
            && root.monitorSignature() !== displayController.previewObservedSignature)
          displayController.abandonPreview("External display change accepted; preview cancelled.")
      })
      return
    }
    if (state !== "idle") return
    var before = observedMonitorSignature
    compositor.refresh(false, function() {
      if (root.state !== "idle") return
      var after = root.monitorSignature()
      if (before === after) return
      root.updateAssignments()
      if (!Grid.equal(root.workspaceMap, root.targetMapping())) workspace.reconcile()
    })
    if (panelWanted) windowSettings.refreshWindowSettings()
  }

  function finishAuthorityMigration(done, reloadRequired) {
    function complete(code) {
      if (code === 0) { root.persisted.systemAuthorityVersion = 3; store.saveState() }
      else root.layoutError = "Could not reload the user's configuration for the Station 3 upgrade."
      done()
    }
    if (reloadRequired && persisted.systemAuthorityVersion !== 3)
      compositor.enqueue(["hyprctl", "reload"], complete)
    else complete(0)
  }

  function applyRuntime() {
    // A config reload/hotplug during Keep must not reapply the old saved mode.
    if (state === "previewing" || state === "applyingLayout") return
    updateAssignments()
    workspace.reconcile()
    windowSettings.refreshWindowSettings()
    keybindings.applyBinds()
    barLayers.syncBarBlur()
    barLayers.syncBarGaps()
    colorMatchController.reconcile()
  }

  function setDirectionValue(value) {
    if (["ltr", "rtl", "ttb", "btt"].indexOf(value) === -1) return "invalid"
    config.direction = value
    config = Object.assign({}, config)
    store.saveConfig()
    return "ok"
  }

  function swapRole(name, roleIndex) {
    if (!stations.readyForWindows()) return "busy"
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
    store.saveConfig()
    displayController.syncDisplayDraft()
    // A source change is an explicit topology edit and uses the same guarded preview.
    if (draftMode === "mirror") return displayController.previewMirrorSource(name)
    workspace.reconcile()
    return "started"
  }

  function roleOf(name) {
    var roles = displayDraft.filter(function(display) { return root.displayEnabled(display.name) && lanes[display.name] })
      .map(function(display) { return lanes[display.name] }).sort(function(a, b) { return a - b })
    return roles.indexOf(lanes[name])
  }

  // The Workspaces tab applies its whole draft at once: mode, per-monitor layout,
  // indicator style, compact mode and open apps. A change to the map runs the
  // journaled migration, so only `idle` accepts one.
  function setWorkspaceSetting(name, value) {
    var next = Object.assign({}, config)
    if (name === "workspaceMode") {
      if (Grid.MODES.indexOf(value) === -1) return "invalid"
      next.workspaceMode = value
    } else {
      if (!value || typeof value !== "object") return "invalid"
      if (value.workspaceMode !== undefined) {
        if (Grid.MODES.indexOf(value.workspaceMode) === -1) return "invalid"
        next.workspaceMode = value.workspaceMode
      }
      if (value.workspaceLayout !== undefined) next.workspaceLayout = Store.workspaceLayout(value.workspaceLayout)
      if (value.indicatorStyle !== undefined) {
        if (["prefixed", "number", "roman"].indexOf(value.indicatorStyle) === -1) return "invalid"
        next.indicatorStyle = value.indicatorStyle
      }
      if (value.compactMode !== undefined) {
        if (["off", "hover", "on"].indexOf(value.compactMode) === -1) return "invalid"
        next.compactMode = value.compactMode
      }
      if (value.showOpenApps !== undefined) next.showOpenApps = !!value.showOpenApps
    }
    var mapChanges = next.workspaceMode !== config.workspaceMode
      || JSON.stringify(next.workspaceLayout) !== JSON.stringify(config.workspaceLayout)
    if (mapChanges && (state !== "idle" || workspaceData.pending || removalGrace.running)) return "busy"
    config = next
    store.saveConfig()
    if (!Grid.equal(workspaceMap, targetMapping())) workspace.reconcile()
    return "ok"
  }

  function setSetting(name, value) {
    if (name === "workspaceMode" || name === "workspaces") return setWorkspaceSetting(name, value)
    if (name === "hideNative") {
      if (panelWanted) panel.panelTransferUntil = Date.now() + 3000
      config.hideNative = !!value
      config = Object.assign({}, config)
      store.saveConfig()
      leases.workspaceVisibilityChanged(config.hideNative)
      return "ok"
    }
    if (name === "hideDisplay") {
      if (panelWanted) panel.panelTransferUntil = Date.now() + 3000
      config.hideDisplay = !!value
      config = Object.assign({}, config)
      store.saveConfig()
      leases.displayVisibilityChanged(config.hideDisplay)
      return "ok"
    }
    if (name === "panelPosition") {
      if (value !== "left" && value !== "center") return "invalid"
      config.panelPosition = value
    }
    else if (name === "indicatorStyle") {
      if (["prefixed", "number", "roman"].indexOf(value) === -1) return "invalid"
      config.indicatorStyle = value
    }
    else if (name === "followFocus") config.followFocus = !!value
    else if (name === "graceMs") {
      var grace = Number(value)
      config.graceMs = isFinite(grace) ? Math.max(0, Math.min(30000, grace)) : 5000
    }
    else return "invalid"
    config = Object.assign({}, config)
    store.saveConfig()
    return "ok"
  }

  function maybeStart() {
    if (started || !store.dirsReady || !store.configLoaded || !store.stateLoaded
        || !displayController.previewLoaded || !workspace.mappingLoaded || !displayController.monitorsLoaded) return
    if (store.fresh && !workspaceRulesRead) {
      if (!workspaceRules.running) workspaceRules.running = true
      return
    }
    started = true
    workspaceAuthority.claim()
    stations.currentStation = persisted.lastStation
    if (displayController.previewFound) {
      Quickshell.execDetached(["rm", "-f", stateDir + "/preview.token"])
      Quickshell.execDetached(["sh", "-c", Transactions.unparkToggle + "hyprctl reload\n", "sh",
        parkedTogglePath, internalDisablePath])
    }
    displayController.migrateMonitorPrecedence(function() { compositor.refresh(true, function() {
      applyRuntime()
      if (!config.hideNative && persisted.stockLease) leases.restoreStockLease()
      if (!config.hideDisplay && persisted.displayLease) leases.restoreDisplayLease()
      leases.acquireStockLeases()
      if (!persisted.activeNoticeShown) {
        Quickshell.execDetached(["notify-send", "Station", "Station is active. SUPER+1…0 now switch stations."])
        persisted.activeNoticeShown = true
        store.saveState()
      }
    }) })
  }

  // A first start keeps the workspace assignment the user already had: Hyprland's
  // rules are still all theirs, because Station has applied none yet.
  property bool workspaceRulesRead: false
  function adoptWorkspaceRules(text) {
    if (workspaceRulesRead) return
    var rules = []
    try { rules = JSON.parse(String(text || "[]")) } catch (error) { rules = [] }
    var outputs = monitors.filter(function(m) {
      return !m.disabled && (m.mirrorOf === undefined || m.mirrorOf === null || m.mirrorOf === ""
        || m.mirrorOf === "none" || String(m.mirrorOf) === "-1")
    }).map(function(m) { return String(m.name) })
    var adopted = Grid.adopt(rules, outputs)
    if (adopted) {
      config = Object.assign({}, config, { workspaceMode: adopted.mode,
        workspaceLayout: Store.workspaceLayout(adopted.layout) })
      store.saveConfig()
    }
    workspaceRulesRead = true
    maybeStart()
  }
  Process {
    id: workspaceRules
    command: ["hyprctl", "workspacerules", "-j"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.adoptWorkspaceRules(text) }
    onExited: function(exitCode) { if (exitCode !== 0) root.adoptWorkspaceRules("") }
  }

  function togglePanel() {
    return shell ? String(shell.toggle("yakumy.station", "{}")) : "no-shell"
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
      workspace.markTopologyDirty()
      if (state === "previewing" && !eventExpected(event))
        displayController.abandonPreview("Display connection changed; preview cancelled.")
      return
    }
    if (name === "configreloaded") {
      configGeneration += 1
      persisted.appliedBinds = []
      config.approvedReplacements = []
      if (state === "applyingLayout") return
      if (state === "previewing") {
        displayController.abandonPreview("Display configuration reloaded; preview cancelled.")
        return
      }
      reloadDebounce.restart()
      return
    }
    if (name.indexOf("monitoradded") === 0) {
      if (eventExpected(event)) return
      lastTopologyMs = Date.now()
      removalGrace.stop()
      if (state === "migrating") workspace.markTopologyDirty()
      compositor.refresh(true, function() { applyRuntime() })
      return
    }
    if (name.indexOf("monitorremoved") === 0) {
      if (eventExpected(event)) return
      lastTopologyMs = Date.now()
      if (state === "migrating") workspace.markTopologyDirty()
      if (state === "switching") {
        gen += 1
        state = "idle"
      }
      removalGrace.interval = config.graceMs
      removalGrace.restart()
      return
    }
    if ((name.indexOf("workspace") !== -1 || name.indexOf("focusedmon") !== -1)
        && !eventExpected(event) && config.followFocus && state === "idle"
        && Date.now() - lastTopologyMs > 500) stations.followFocusChanged()
  }

  // Public surface for the panel and the bridge. Everything else belongs to an owner.
  function monitorBar(name) { return barSettings.monitorBar(name) }
  function monitorBarMaximumHeight(name) { return barSettings.monitorBarMaximumHeight(name) }
  function monitorBarMinimum(name) { return barSettings.monitorBarMinimum(name) }
  function reportMonitorBarMinimum(name, value) { return barSettings.reportMonitorBarMinimum(name, value) }
  function monitorBarMaximumContent(name) { return barSettings.monitorBarMaximumContent(name) }
  function reportMonitorBarMaximumContent(name, value) { return barSettings.reportMonitorBarMaximumContent(name, value) }
  function setMonitorBarPosition(name, position) { return barSettings.setMonitorBarPosition(name, position) }
  function setMonitorBarEnabled(name, enabled) { return barSettings.setMonitorBarEnabled(name, enabled) }
  function setMonitorBarWidth(name, width) { return barSettings.setMonitorBarWidth(name, width) }
  function setMonitorBarHeight(name, height) { return barSettings.setMonitorBarHeight(name, height) }
  function setMonitorBarBackground(name, background) { return barSettings.setMonitorBarBackground(name, background) }
  function setMonitorBarStyle(name, style) { return barSettings.setMonitorBarStyle(name, style) }
  function setMonitorBarContentSize(name, contentSize) { return barSettings.setMonitorBarContentSize(name, contentSize) }
  function setDisplayValue(name, key, value) { return displayController.setDisplayValue(name, key, value) }
  function setDisplayTransform(name, value) { return displayController.setDisplayTransform(name, value) }
  function applyDisplaySetting(name, key, value) { return displayController.applyDisplaySetting(name, key, value) }
  function setDisplayEnabled(name, enabled) { return displayController.setDisplayEnabled(name, enabled) }
  function displayEnabled(name) { return displayController.displayEnabled(name) }
  function setDisplayPosition(name, x, y) { return displayController.setDisplayPosition(name, x, y) }
  function setModeValue(mode, target) { return displayController.setModeValue(mode, target) }
  function previewLayout() { return displayController.previewLayout() }
  function keepPreview() { return displayController.keepPreview() }
  function revertPreview(reason) { return displayController.revertPreview(reason) }
  function switchStation(value) { return stations.showStation(value) }
  function showWorkspace(value, output) { return stations.showWorkspace(value, output) }
  function setBinding(id, combo) { return keybindings.setBinding(id, combo) }
  function approveBinding(combo) { return keybindings.approveBinding(combo) }
  function setWindowSetting(key, value) { return windowSettings.setWindowSetting(key, value) }
  function setColorValue(name, key, value) { return colorMatchController.setValue(name, key, value) }
  function resetColor(name) { return colorMatchController.reset(name) }
  function acquireStockLeases() { return leases.acquireStockLeases() }
  function setPanelWanted(value) { return panel.setPanelWanted(value) }
  function setPanelScreenName(value) { return panel.setPanelScreenName(value) }
  function setPanelTransferUntil(value) { return panel.setPanelTransferUntil(value) }
  function setRememberedTab(value) { return panel.setRememberedTab(value) }
  function setRememberedDisplayName(value) { return panel.setRememberedDisplayName(value) }
  function acknowledgePanelEvacuation(serial, screenName) { return panel.acknowledgePanelEvacuation(serial, screenName) }

  Component.onCompleted: {
    Qt.callLater(barSettings.reconcileActiveBarLayout)
    store.prepare()
    barBridge = BarBridge.publish(function() { return ServiceContract.snapshot(root) }, ServiceContract.actions(root))
  }

  Component.onDestruction: {
    BarBridge.clear(barBridge)
    Quickshell.execDetached(Recovery.cleanupCommand(stateDir, monitorsPath, persisted.stockLease, persisted.displayLease, workspaceAuthorityPath, colorTogglePath))
  }

  // Connector -> block, and every block Omarchy has handed out, as its bar reads it.
  function readOmarchyBlocks(text) {
    var next = { byConnector: {}, taken: [] }
    String(text || "").split("\n").forEach(function(line) {
      var fields = line.split("\t")
      var block = parseInt(fields[0], 10)
      if (fields.length < 3 || !/^[0-9]+$/.test(fields[0]) || block >= Grid.MAX_STATIONS) return
      next.taken.push(block)
      if (fields[1] !== "") next.byConnector[fields[1]] = block
    })
    if (JSON.stringify(next) !== JSON.stringify(omarchyBlocks)) omarchyBlocks = next
  }
  FileView {
    path: root.omarchyBlocksPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.readOmarchyBlocks(text())
    onLoadFailed: root.readOmarchyBlocks("")
  }
  onOmarchyBlocksChanged: if (started && state === "idle" && !Grid.equal(workspaceMap, targetMapping())) workspace.reconcile()

  Timer { interval: 1500; running: root.started; repeat: true; onTriggered: root.observeDesktop() }
  Timer { id: reloadDebounce; interval: 300; onTriggered: { keybindings.invalidate(); compositor.refresh(true, function() { root.applyRuntime() }) } }
  Timer { id: removalGrace; interval: 5000; onTriggered: compositor.refresh(true, function() { root.applyRuntime() }) }

  Connections { target: Hyprland; function onRawEvent(event) { root.handleEvent(event) } }

  IpcHandler {
    target: "yakumy.station"
    function switchStation(value: string): string { return stations.showStation(value) }
    function sendToStation(value: string): string { return stations.sendToStation(value) }
    function sendSilent(value: string): string { return stations.sendSilent(value) }
    function goDirection(value: string): string { return stations.goDirection(value) }
    function shiftWindow(value: string): string { return stations.shiftWindow(value) }
    function togglePanel(): string { return root.togglePanel() }
    function previewLayout(): string { return root.previewLayout() }
    function setDisplayEnabled(name: string, enabled: bool): string { return root.setDisplayEnabled(name, enabled) }
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
      version: root.manifest ? root.manifest.version : "", windows: root.config.windows,
      systemAuthorityVersion: root.persisted.systemAuthorityVersion || 0,
      station: root.currentStation, lanes: root.lanes, unmanaged: root.unmanaged,
      globalBarPosition: barSettings.globalBarPosition, lastGlobalBarPosition: barSettings.lastGlobalBarPosition,
      bars: root.config.bars, colorMatch: root.colorMatch,
      themeFollow: { name: wallpaper.themeName, path: wallpaper.themePath, revision: wallpaper.themeRevision,
        watching: wallpaper.themeWatching },
      workspaceMap: root.workspaceMap, migrationPending: root.workspaceData.pending !== null,
      migrationPhase: workspace.migrationPhase, layoutError: root.layoutError,
      lastWindowAction: stations.lastWindowAction,
      monitors: root.monitors, bindStatuses: root.bindStatuses, panelWanted: root.panelWanted,
      panelScreenName: root.panelScreenName, previewBusy: root.previewBusy, previewSeconds: root.previewSeconds,
      panelPosition: root.config.panelPosition,
      panelEvacuationWaiting: root.panelEvacuationWaiting,
      draftMode: root.draftMode, savedMode: root.config.mode, singleTarget: root.draftSingleTarget,
      stockLease: root.persisted.stockLease, stockDisableAttempts: leases.stockDisableAttempts,
      stockDisableRunning: leases.stockDisableRunning, displayLease: root.persisted.displayLease,
      displayDisableAttempts: leases.displayDisableAttempts, displayDisableRunning: leases.displayDisableRunning,
      displayWidgetEnabled: root.displayWidgetEnabled }) }
  }
}

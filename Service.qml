import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs.Commons
import "lib/Model.js" as Model
import "lib/Hypr.js" as Hypr
import "lib/Binds.js" as Binds
import "lib/Store.js" as Store
import "lib/Tabs.js" as Tabs
import "lib/Recovery.js" as Recovery
import "lib/MonitorsLua.js" as MonitorsLua
import "lib/Transactions.js" as Transactions
import "lib/Events.js" as Events
import "lib/Grid.js" as Grid
import "lib/ScreenHealth.js" as ScreenHealth
import "lib" as Station
import "lib/BarBridge.js" as BarBridge

Item {
  id: root

  property var shell: null
  onShellChanged: Qt.callLater(reconcileActiveBarLayout)
  // Observe Omarchy's global edge independently of our per-monitor overrides.
  readonly property string focusedBarScreenName: Hyprland.focusedMonitor
    ? String(Hyprland.focusedMonitor.name || "") : ""
  readonly property string lastGlobalBarPosition: barSettings.lastGlobalBarPosition
  readonly property string globalBarPosition: barSettings.globalBarPosition
  property var manifest: null
  property var barBridge: null
  readonly property string pluginDir: manifest && typeof manifest.__sourceDir === "string"
    ? manifest.__sourceDir.replace(/\/$/, "") : ""
  onPluginDirChanged: Qt.callLater(wallpaperController.prepareLegacyWallpaper)
  property var config: Store.configDefaults()
  readonly property var monitorBarMinimums: barSettings.monitorBarMinimums
  readonly property var monitorBarMaximumContents: barSettings.monitorBarMaximumContents
  property bool barBlurSyncQueued: false
  Station.BarSettingsController {
    id: barSettings
    preferences: root.config.bars || ({})
    hostConfig: root.shell && root.shell.barConfig ? root.shell.barConfig : null
    displays: root.displayDraft
    configLoaded: root.configLoaded
    panelWanted: root.panelWanted
    focusedBarScreenName: root.focusedBarScreenName
    persistPreferences: function(bars) {
      root.config = Object.assign({}, root.config, { bars: bars })
      root.saveConfig()
    }
    publishHost: root.shell && typeof root.shell.mutateShellConfig === "function"
      ? function(change) { return root.shell.mutateShellConfig(change) } : null
    retainPanel: function(tab) {
      if (tab) root.setRememberedTab(Tabs.index(tab))
      root.setPanelTransferUntil(Date.now() + 3000)
    }
    requestLayerSync: function() { root.syncBarBlur() }
  }
  Station.WindowSettingsController {
    id: windowSettings
    appliedSettings: root.config.windows
    operationState: root.state
    configGeneration: root.configGeneration
    enqueue: function(command, done, generation) { root.enqueue(command, done, generation) }
    publishObserved: function(observed) {
      root.config = Object.assign({}, root.config, { windows: observed })
    }
    reportError: function(message) { root.layoutError = message }
    refreshStyle: function() {
      if (typeof Style.scheduleRefresh === "function") Style.scheduleRefresh()
    }
  }
  Station.WorkspaceController {
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
    refresh: function(includeClients, done) { root.refresh(includeClients, done) }
    updateAssignments: function() { root.updateAssignments() }
    focusedClient: function() { return root.focusedClient() }
    beginMigration: function() { return root.begin("migrating") }
    setOperationState: function(value) { root.state = value }
    evalLua: function(lua, done) { root.evalLua(lua, done) }
    recordExpectedEvents: function(value) { root.expect = value }
    reportError: function(message) { root.layoutError = message }
    setCurrentStation: function(station) { root.currentStation = station }
    commitMigrationState: function(station) {
      root.persisted.legacyWorkspaceGrid = false
      root.persisted.lastStation = station
      root.saveState()
    }
    restorePreviewBaseline: function(value) { displayController.restorePreviewBaseline(value) }
    finishPreviewApply: function() { root.finishPreviewApply() }
    failPreview: function(message) { displayController.failPreview(message) }
    focusStatements: function(station, output) { return root.stationFocusStatements(station, output) }
    showStation: function(station) { root.showStation(station) }
    ready: function() { root.maybeStart() }
  }
  Station.DisplayController {
    id: displayController
    stateDir: root.stateDir
    monitorsPath: root.monitorsPath
    internalDisablePath: root.internalDisablePath
    candidatePath: root.candidatePath
    plainCandidatePath: root.plainCandidatePath
    plainPath: root.plainPath
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
    migrationPhase: root.migrationPhase
    topologyDirty: root.topologyDirty
    panelWanted: root.panelWanted
    panelScreenName: root.panelScreenName
    layoutError: root.layoutError
    beginPreview: function() { return root.begin("previewing") }
    setOperationState: function(value) { root.state = value }
    beginRevert: function() { root.gen += 1 }
    invalidatePreviewOperation: function() { root.gen += 1; root.configGeneration += 1 }
    refresh: function(includeClients, done) { root.refresh(includeClients, done) }
    evalLua: function(lua, done) { root.evalLua(lua, done) }
    enqueue: function(command, done) { root.enqueue(command, done) }
    recordExpectedEvents: function(value) { root.expect = value }
    monitorSignature: function() { return root.monitorSignature() }
    reconcileWorkspace: function() { root.reconcile() }
    targetMapping: function() { return root.targetMapping() }
    clearWorkspaceTopologyDirty: function() { workspace.clearTopologyDirty() }
    requestPanelEvacuation: function(from, to, purpose) { root.requestPanelEvacuation(from, to, purpose) }
    clearPanelEvacuation: function() { root.clearPanelEvacuation() }
    // Optional scalars preserve screen-only and deadline-only writes as well as
    // their existing order. Do not capture a visual panel or widget proxy here.
    retainPanel: function(screen, until) {
      if (screen !== undefined) root.panelScreenName = screen
      if (until !== undefined) root.panelTransferUntil = until
    }
    stopTopologyTimers: function() { removalGrace.stop(); reloadDebounce.stop() }
    publishDisplayOptions: function(options) {
      root.config.enabled = options.enabled.slice()
      root.config.mode = options.mode
      root.config.singleTarget = options.singleTarget || ""
      root.config.mirrorSource = options.mirrorSource || ""
      root.config = Object.assign({}, root.config)
    }
    saveDisplayPreferences: function() { root.saveConfig() }
    invalidateAppliedBinds: function() { root.appliedGeneration = -1 }
    updateAssignments: function() { root.updateAssignments() }
    applyBinds: function() { root.applyBinds() }
    applyRuntime: function() { root.applyRuntime() }
    armScreenHealthCheck: function() { root.armScreenHealthCheck() }
    launchWatchdog: function() {
      Quickshell.execDetached(["sh", "-c", Transactions.watchdog, "sh", "20", root.stateDir + "/preview.token"])
    }
    reportError: function(message) { root.layoutError = message }
    ready: function() { root.maybeStart() }
    finishAuthorityMigration: function(done, reloadRequired) { root.finishAuthorityMigration(done, reloadRequired) }
  }
  readonly property alias wallpaper: wallpaperController
  Station.WallpaperController { id: wallpaperController; station: root }
  property var persisted: Store.stateDefaults()
  property var monitors: []
  property var clients: []
  property var lanes: ({})
  readonly property var workspaceData: workspace.snapshot
  readonly property bool mappingLoaded: workspace.mappingLoaded
  readonly property string migrationPhase: workspace.migrationPhase
  readonly property bool topologyDirty: workspace.topologyDirty
  readonly property int migrationAttempts: workspace.migrationAttempts
  property var lastWindowAction: ({})
  readonly property var migrationFocus: workspace.detached(workspace.migrationFocus)
  readonly property var migrationCommit: workspace.detached(workspace.migrationCommit)
  readonly property var workspaceMap: workspaceData.mapping
  property var unmanaged: []
  property int currentStation: persisted.lastStation || 1
  property int gen: 0
  property int queuedStation: 0
  property bool configLoaded: false
  property bool stateLoaded: false
  property bool dirsReady: false
  readonly property bool previewLoaded: displayController.previewLoaded
  readonly property bool previewFound: displayController.previewFound
  property bool started: false
  property int configGeneration: 0
  property int appliedGeneration: -1
  property var bindStatuses: []
  property int bindProbeGeneration: -1
  property string menuBindingsText: ""
  property bool menuBindingsOk: false
  property string hyprBindingsText: ""
  property string personalBindingsText: ""
  property int stockDisableAttempts: 0
  property int displayDisableAttempts: 0
  property var displayWidgetEnabled: null
  property var workspaceWidgetEnabled: null
  property bool displayShowPending: false
  property bool workspaceShowPending: false
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
  readonly property bool draftEditable: displayController.draftEditable
  readonly property bool previewBusy: displayController.previewBusy
  readonly property string previewAbortReason: displayController.previewAbortReason
  readonly property var previewBaseline: displayController.detached(displayController.previewBaseline)
  readonly property var keepOptions: displayController.detached(displayController.keepOptions)
  readonly property string layoutWriteKind: displayController.layoutWriteKind
  readonly property bool keepFilesPending: displayController.keepFilesPending
  readonly property string keepSourceBaseline: displayController.keepSourceBaseline
  readonly property string keepDisableToggle: displayController.keepDisableToggle
  readonly property string internalDisableSource: displayController.internalDisableSource
  readonly property string internalDisablePath: Quickshell.env("HOME") + "/.local/state/omarchy/toggles/hypr/internal-monitor-disable.lua"
  readonly property bool candidateReady: displayController.candidateReady
  readonly property bool plainCandidateReady: displayController.plainCandidateReady
  readonly property var displayDraft: displayController.detached(displayController.displayDraft)
  readonly property string draftMode: displayController.draftMode
  readonly property string draftSingleTarget: displayController.draftSingleTarget
  readonly property string draftMirrorSource: displayController.draftMirrorSource
  readonly property var previewBefore: displayController.detached(displayController.previewBefore)
  readonly property var previewApplied: displayController.detached(displayController.previewApplied)
  readonly property string previewObservedSignature: displayController.previewObservedSignature
  readonly property var pendingDisplayConfig: displayController.detached(displayController.pendingDisplayConfig)
  readonly property string previewApplyLua: displayController.previewApplyLua
  readonly property bool previewApplyStaged: displayController.previewApplyStaged
  readonly property var previewApplyExpectedOutputs: displayController.detached(displayController.previewApplyExpectedOutputs)
  readonly property string previewApplyFocusTarget: displayController.previewApplyFocusTarget
  readonly property string previewApplyActivateLua: displayController.previewApplyActivateLua
  readonly property bool previewApplyMigrateFirst: displayController.previewApplyMigrateFirst
  readonly property string previewApplyPanelOrigin: displayController.previewApplyPanelOrigin
  readonly property string previewApplyPanelTarget: displayController.previewApplyPanelTarget
  readonly property string pendingRevertReason: displayController.pendingRevertReason
  readonly property string pendingRevertPanelTarget: displayController.pendingRevertPanelTarget
  readonly property string pendingRevertPanelOrigin: displayController.pendingRevertPanelOrigin
  readonly property string pendingRevertFocusTarget: displayController.pendingRevertFocusTarget
  readonly property string pendingRevertActivateLua: displayController.pendingRevertActivateLua
  property string layoutError: ""
  readonly property int previewSeconds: displayController.previewSeconds
  readonly property string monitorsSource: displayController.monitorsSource
  readonly property bool monitorsLoaded: displayController.monitorsLoaded
  property var expect: ({ kinds: [], outputs: [], until: 0 })
  property double lastTopologyMs: 0
  property var actionQueue: []
  property var currentAction: null
  property var refreshDone: null
  property bool refreshClientsToo: true
  property string observedMonitorSignature: ""
  property bool snapshotBusy: false
  property var snapshotQueue: []
  property bool screenRecoveryActive: false
  property int screenRecoveryAttempts: 0
  property string screenRecoveryTarget: ""
  property string screenRecoveryRule: ""

  readonly property string configDir: Quickshell.env("HOME") + "/.config/omarchy/station"
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/station"
  readonly property string configPath: configDir + "/config.json"
  readonly property string statePath: stateDir + "/state.json"
  readonly property string monitorsPath: Quickshell.env("HOME") + "/.config/hypr/monitors.lua"
  readonly property string candidatePath: stateDir + "/monitors.lua.candidate"
  readonly property string plainCandidatePath: stateDir + "/monitors-block.plain.lua.candidate"
  readonly property string plainPath: stateDir + "/monitors-block.plain.lua"

  // Only detached UI data crosses the replacement-bar boundary. In particular,
  // wallpaperController.station must never be reachable from a snapshot.
  readonly property var openApps: openAppsController.rows
  Station.OpenAppsController {
    id: openAppsController
    active: root.config.stationAppsMode !== "hide"
    mapping: root.workspaceMap
    pending: root.workspaceData.pending
    minimum: root.config.minStations
    current: root.currentStation
  }

  function barSnapshot() {
    return JSON.parse(JSON.stringify({
      windowSettingsBusy: windowSettingsBusy,
      currentStation: currentStation,
      openApps: openApps,
      displayDraft: displayDraft,
      bindStatuses: bindStatuses,
      config: config,
      monitorBarMinimums: monitorBarMinimums,
      monitorBarMaximumContents: monitorBarMaximumContents,
      draftMode: draftMode,
      draftSingleTarget: draftSingleTarget,
      draftEditable: draftEditable,
      state: state,
      layoutError: layoutError,
      previewBusy: previewBusy,
      previewSeconds: previewSeconds,
      panelEvacuationWaiting: panelEvacuationWaiting,
      panelEvacuationSerial: panelEvacuationSerial,
      panelEvacuationFrom: panelEvacuationFrom,
      panelScreenName: panelScreenName,
      panelTransferUntil: panelTransferUntil,
      panelWanted: panelWanted,
      rememberedTab: rememberedTab,
      rememberedDisplayName: rememberedDisplayName,
      displayWidgetEnabled: displayWidgetEnabled,
      workspaceWidgetEnabled: workspaceWidgetEnabled,
      pluginVersion: manifest && manifest.version ? String(manifest.version) : "",
      wallpaper: {
        draft: wallpaper.draft,
        layout: wallpaper.layout,
        busy: wallpaper.busy,
        importBusy: wallpaper.importBusy,
        notice: wallpaper.notice,
        noticeError: wallpaper.noticeError,
        pickerBusy: wallpaper.pickerBusy,
        themePath: wallpaper.themePath,
        dirty: wallpaper.dirty
      }
    }))
  }

  function setPanelWanted(value) {
    if (typeof value !== "boolean") return
    panelWanted = value
    if (!value) barSettings.panelClosed()
  }
  function setPanelScreenName(value) {
    if (typeof value === "string" && (value === "" || validConnector(value))) panelScreenName = value
  }
  function setPanelTransferUntil(value) {
    if (typeof value === "number" && isFinite(value) && value >= 0) panelTransferUntil = value
  }
  function setRememberedTab(value) {
    if (Tabs.validIndex(value)) rememberedTab = value
  }
  function setRememberedDisplayName(value) {
    if (typeof value === "string" && (value === "" || validConnector(value))) rememberedDisplayName = value
  }

  function begin(nextState) {
    queuedStation = 0
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

  function adoptHostBars() { return barSettings.adoptHostBars() }
  function monitorBar(name) { return barSettings.monitorBar(name) }
  function monitorBarMaximumHeight(name) { return barSettings.monitorBarMaximumHeight(name) }
  function monitorBarRenderedHeight(name) { return barSettings.monitorBarRenderedHeight(name) }
  function monitorBarMinimum(name) { return barSettings.monitorBarMinimum(name) }
  function reportMonitorBarMinimum(name, value) { return barSettings.reportMonitorBarMinimum(name, value) }
  function monitorBarMaximumContent(name) { return barSettings.monitorBarMaximumContent(name) }
  function reportMonitorBarMaximumContent(name, value) { return barSettings.reportMonitorBarMaximumContent(name, value) }
  function reconcileActiveBarLayout() { return barSettings.reconcileActiveBarLayout() }
  function publishMonitorBar(name, next) { return barSettings.publishMonitorBar(name, next) }
  function publishMonitorBars(changes, menuPosition) { return barSettings.publishMonitorBars(changes, menuPosition) }
  function activeStationBar() { return barSettings.activeStationBar() }
  function deferMonitorBarPublish(name, next) { return barSettings.deferMonitorBarPublish(name, next) }
  function flushPendingMonitorBars() { return barSettings.flushPendingMonitorBars() }
  function syncFocusedBarMenu() { return barSettings.syncFocusedBarMenu() }
  function syncGlobalBarPosition() { return barSettings.syncGlobalBarPosition() }
  function applyBarMenuPosition(name, position, previous) { return barSettings.applyBarMenuPosition(name, position, previous) }
  function setMonitorBarPosition(name, position) { return barSettings.setMonitorBarPosition(name, position) }
  function setMonitorBarEnabled(name, enabled) { return barSettings.setMonitorBarEnabled(name, enabled) }
  function setMonitorBarWidth(name, width) { return barSettings.setMonitorBarWidth(name, width) }
  function setMonitorBarHeight(name, height) { return barSettings.setMonitorBarHeight(name, height) }
  function setMonitorBarBackground(name, background) { return barSettings.setMonitorBarBackground(name, background) }
  function setMonitorBarStyle(name, style) { return barSettings.setMonitorBarStyle(name, style) }
  function setMonitorBarContentSize(name, contentSize) { return barSettings.setMonitorBarContentSize(name, contentSize) }

  function barBlurWanted() {
    return displayDraft.some(function(display) {
      var bar = monitorBar(display.name)
      return bar.enabled && bar.background === "blur"
    })
  }

  function syncBarBlur() {
    if (!started || !configLoaded) return
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
    if (persisted.barBlurLease) { persisted.barBlurLease = null; saveState() }
    evalLua(Hypr.barBlur(barBlurWanted(), {}))
    if (barBlurSyncQueued) {
      barBlurSyncQueued = false
      Qt.callLater(syncBarBlur)
    }
  }

  function saveConfig() {
    if (configLoaded && dirsReady) configFile.setText(JSON.stringify(config, null, 2) + "\n")
  }

  function saveState() {
    if (stateLoaded && dirsReady) stateFile.setText(JSON.stringify(persisted, null, 2) + "\n")
  }

  function armScreenHealthCheck() {
    if (screenRecoveryActive) return
    screenRecoveryAttempts = 0
    screenHealthCheck.restart()
  }

  function verifyScreenHealth() {
    if (screenRecoveryActive || screenRecoveryAttempts > 0) return
    if (state !== "idle") { screenHealthCheck.restart(); return }
    var target = ScreenHealth.recoveryTarget(monitors, Quickshell.screens)
    if (!target) return
    try {
      var monitor = monitors.find(function(item) { return item.name === target })
      var display = MonitorsLua.validateDisplay({ name: target, mode: Model.currentMode(monitor),
        availableModes: monitor.availableModes, x: Math.round(Number(monitor.x) || 0),
        y: Math.round(Number(monitor.y) || 0), scale: Number(monitor.scale),
        transform: Number(monitor.transform), enabled: true, lane: lanes[target] || 1 })
      screenRecoveryRule = MonitorsLua.monitorRule(display, { disabled: false, mirror: "" })
      screenRecoveryTarget = target
      screenRecoveryActive = true
      screenRecoveryAttempts += 1
      state = "recoveringScreen"
      expect = { kinds: ["monitor", "workspace"], outputs: [target], until: Date.now() + 3000 }
      console.warn("Station: cycling stale Wayland output " + target)
      evalLua(MonitorsLua.monitorRule(display, { geometry: false, disabled: true, mirror: "" }),
        function(code, output) {
          if (code !== 0 || (output && output.trim() !== "ok")) {
            root.screenRecoveryActive = false
            root.screenRecoveryTarget = ""
            root.screenRecoveryRule = ""
            root.state = "idle"
            root.layoutError = "Could not recover the display surface for " + target + "."
            return
          }
          screenRecoveryEnable.restart()
        })
    } catch (error) {
      screenRecoveryActive = false
      screenRecoveryTarget = ""
      screenRecoveryRule = ""
      state = "idle"
      layoutError = "Could not safely recover the display surface."
      console.warn("Station screen recovery:", error)
    }
  }

  function finishScreenRecovery() {
    var rule = screenRecoveryRule
    var target = screenRecoveryTarget
    expect = { kinds: ["monitor", "workspace"], outputs: [target], until: Date.now() + 3000 }
    evalLua(rule, function(code, output) {
      root.screenRecoveryActive = false
      root.screenRecoveryTarget = ""
      root.screenRecoveryRule = ""
      root.state = "idle"
      if (code !== 0 || (output && output.trim() !== "ok")) {
        root.layoutError = "Could not restore the display after surface recovery. Reload Hyprland."
        return
      }
      root.refresh(true, function() { if (root.state === "idle") root.reconcile() })
    })
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
      if (state === "migrating") migrationFailed("could not read compositor state")
      else if (state === "previewing") {
        displayController.failPreview("Could not read the display state; reverting the preview.")
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
    var assigned = Model.assignLanes(connected, config.lanes, lanes)
    lanes = assigned.lanes
    unmanaged = assigned.unmanaged
    var observed = state !== "previewing" && state !== "applyingLayout" ? Model.observedOptions(connected) : null
    config = Object.assign({}, config, observed || {}, { lanes: assigned.preferences })
    saveConfig()
    if (state !== "previewing" && state !== "applyingLayout") {
      observedMonitorSignature = monitorSignature()
      syncDisplayDraft()
    }
  }

  function syncDisplayDraft() {
    return displayController.syncDisplayDraft()
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
    // Keep the latest numbered-key intent while the compositor batch runs.
    // Dropping a quick return to S1 leaves the user looking at an empty S2/S3.
    if (state === "switching") { queuedStation = stationNumber; return "queued" }
    if (!readyForWindows()) return "busy"
    var available = workspaceMap.outputs
    var generation = begin("switching")
    var focused = focusedMonitor()
    var rules = Hypr.compactRules(available)
    var statements = rules.slice()
    statements = statements.concat(stationFocusStatements(stationNumber, focused ? focused.name : available[0]))
    expect = { kinds: ["workspace", "focusedmon"], outputs: available.slice(), until: Date.now() + 2000 }
    evalLua(Hypr.batch(statements), function(code, message) {
      if (generation !== gen) return
      if (code === 0 && (!message || message.trim() === "ok")) {
        currentStation = stationNumber
        persisted.lastStation = stationNumber
        saveState()
      }
      var next = queuedStation
      queuedStation = 0
      finish(generation)
      if (next && readyForWindows()) showStation(next)
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
    readActiveWindow(generation, function(client) { moveActionWindow(client, station, client.monitor, follow, generation) }, true)
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
    return workspace.reconcile()
  }

  function migrationFailed(message) {
    return workspace.migrationFailed(message)
  }

  function migrationSaved() {
    return workspace.migrationSaved()
  }

  function executeMigration() {
    return workspace.executeMigration()
  }

  function applyBinds() {
    if (!started || appliedGeneration === configGeneration || keybindings.running || hyprBindSnapshot.running) return
    bindProbeGeneration = configGeneration
    keybindings.running = true
  }

  function finishBindCheck() {
    if (bindProbeGeneration !== configGeneration) { Qt.callLater(applyBinds); return }
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
    var lua = Binds.applyLua(accepted, persisted.appliedBinds.filter(function(combo) {
      return !statuses.some(function(row) { return Binds.normalize(row.combo) === Binds.normalize(combo) && row.status === "conflict" })
    }))
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

  readonly property bool windowSettingsBusy: windowSettings.windowSettingsBusy
  function setWindowSetting(key, value) { return windowSettings.setWindowSetting(key, value) }
  function refreshWindowSettings(done, completingEdit) { return windowSettings.refreshWindowSettings(done, completingEdit) }

  function monitorSignature() {
    return JSON.stringify(monitors.map(function(m) { return [m.name, m.disabled, m.mirrorOf, m.x, m.y, m.scale, m.width, m.height, m.refreshRate, m.transform] }))
  }

  function observeDesktop() {
    if (!started || snapshotBusy || windowSettingsBusy || removalGrace.running) return
    if (state === "previewing" && !previewBusy) {
      refresh(false, function() {
        if (root.state === "previewing" && !root.previewBusy && root.previewObservedSignature
            && root.monitorSignature() !== root.previewObservedSignature)
          root.abandonPreview("External display change accepted; preview cancelled.")
      })
      return
    }
    if (state !== "idle") return
    var before = observedMonitorSignature
    refresh(false, function() {
      if (root.state !== "idle") return
      var after = root.monitorSignature()
      if (before === after) return
      root.updateAssignments()
      if (!Grid.equal(root.workspaceMap, root.targetMapping())) root.reconcile()
    })
    if (panelWanted) refreshWindowSettings()
  }

  function finishAuthorityMigration(done, reloadRequired) {
    function complete(code) {
      if (code === 0) { root.persisted.systemAuthorityVersion = 3; root.saveState() }
      else root.layoutError = "Could not reload the user's configuration for the Station 3 upgrade."
      done()
    }
    if (reloadRequired && persisted.systemAuthorityVersion !== 3)
      enqueue(["hyprctl", "reload"], complete)
    else complete(0)
  }

  function migrateMonitorPrecedence(done) {
    return displayController.migrateMonitorPrecedence(done)
  }

  function applyRuntime() {
    // A config reload/hotplug during Keep must not reapply the old saved mode.
    if (state === "previewing" || state === "applyingLayout") return
    updateAssignments()
    reconcile()
    refreshWindowSettings()
    applyBinds()
    syncBarBlur()
  }

  function setDisplayValue(name, key, value) {
    return displayController.setDisplayValue(name, key, value)
  }

  function setResizedDisplayValue(name, key, value) {
    return displayController.setResizedDisplayValue(name, key, value)
  }

  function setDisplayTransform(name, value) {
    return displayController.setDisplayTransform(name, value)
  }

  function applyDisplaySetting(name, key, value) {
    return displayController.applyDisplaySetting(name, key, value)
  }

  function setDisplayEnabled(name, enabled) {
    return displayController.setDisplayEnabled(name, enabled)
  }

  function displayEnabled(name) {
    return displayController.displayEnabled(name)
  }

  function setDisplayPosition(name, x, y) {
    return displayController.setDisplayPosition(name, x, y)
  }

  function setModeValue(mode, target) {
    return displayController.setModeValue(mode, target)
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
    // A source change is an explicit topology edit and uses the same guarded preview.
    if (draftMode === "mirror") return displayController.previewMirrorSource(name)
    reconcile()
    return "started"
  }

  function roleOf(name) {
    var roles = displayDraft.filter(function(display) { return root.displayEnabled(display.name) && lanes[display.name] })
      .map(function(display) { return lanes[display.name] }).sort(function(a, b) { return a - b })
    return roles.indexOf(lanes[name])
  }

  function previewLayout() {
    return displayController.previewLayout()
  }

  function applyPreview() {
    return displayController.applyPreview()
  }

  function panelTransferTarget(options) {
    return displayController.panelTransferTarget(options)
  }

  function previewFocusTarget(options) {
    return displayController.previewFocusTarget(options)
  }

  function activationRule(name) {
    return displayController.activationRule(name)
  }

  function clearPanelEvacuation() {
    panelEvacuationTimeout.stop()
    panelEvacuationWaiting = 0
    panelEvacuationFrom = ""
    panelEvacuationTo = ""
    panelEvacuationPurpose = ""
  }

  function clearPreviewApplyStage() {
    return displayController.clearPreviewApplyStage()
  }

  function failPreviewApply(message) {
    return displayController.failPreviewApply(message)
  }

  function stagePreviewApply(lua, expectedOutputs, options) {
    return displayController.stagePreviewApply(lua, expectedOutputs, options)
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
    return displayController.panelEvacuationTimedOut(panelEvacuationPurpose, panelEvacuationFrom)
  }

  function continuePreviewApply() {
    return displayController.continuePreviewApply()
  }

  function finishPreviewApply() {
    return displayController.finishPreviewApply()
  }

  function applyPreviewSnapshot() {
    return displayController.applyPreviewSnapshot()
  }

  function abandonPreview(reason) {
    return displayController.abandonPreview(reason)
  }

  function revertPreview(reason) {
    return displayController.revertPreview(reason)
  }

  function continueRevertPreview() {
    return displayController.continueRevertPreview()
  }

  function keepPreview() {
    return displayController.keepPreview()
  }

  function startKeepFiles(source, plain, kind) {
    return displayController.startKeepFiles(source, plain, kind)
  }

  function maybeStartKeep() {
    return displayController.maybeStartKeep()
  }

  function keepFileFailed() {
    return displayController.keepFileFailed()
  }

  function restoreAppliedLayout() {
    return displayController.restoreAppliedLayout()
  }

  function finishKeep(code, errorText) {
    return displayController.finishKeep(code, errorText)
  }

  function maybeStart() {
    if (started || !dirsReady || !configLoaded || !stateLoaded || !previewLoaded || !mappingLoaded || !monitorsLoaded) return
    started = true
    currentStation = persisted.lastStation
    if (previewFound) {
      Quickshell.execDetached(["rm", "-f", stateDir + "/preview.token"])
      Quickshell.execDetached(["hyprctl", "reload"])
    }
    migrateMonitorPrecedence(function() { refresh(true, function() {
      applyRuntime()
      if (!config.hideNative && persisted.stockLease) restoreStockLease()
      if (!config.hideDisplay && persisted.displayLease) restoreDisplayLease()
      acquireStockLeases()
      if (!persisted.activeNoticeShown) {
        Quickshell.execDetached(["notify-send", "Station", "Station is active. SUPER+1…0 now switch stations."])
        persisted.activeNoticeShown = true
        saveState()
      }
    }) })
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

  function acquireStockLeases() {
    if (!started || pluginList.running) return
    pluginList.running = true
  }

  function restoreStockLease(forceShow) {
    if (forceShow) workspaceShowPending = true
    if (stockDisable.running) return
    var lease = persisted.stockLease
    if (!lease && !forceShow) return
    if (forceShow || (lease && lease.disabledByStation && lease.wasEnabled)) {
      var place = lease || { section: "left", index: 1 }
      enqueue(["omarchy", "plugin", "enable", "omarchy.workspaces"], function(code) {
        if (code !== 0) { root.workspaceShowPending = false; leaseVerify.restart(); return }
        if (root.config.hideNative) {
          root.workspaceShowPending = false
          root.acquireStockLeases()
          return
        }
        // Re-enabling alone drops it in the centre, and the recorded spot is
        // where it sat before Station leased it: between the Omarchy menu mark
        // and our own widget. Park it behind Station instead so the row reads
        // menu, Station, workspaces; the recorded section/index only covers a
        // bar that has since dropped the Station widget.
        root.enqueue(["omarchy", "bar", "move", "omarchy.workspaces", "--after",
          "yakumy.station"], function(afterCode) {
          if (afterCode === 0) {
            root.persisted.stockLease = null
            root.workspaceShowPending = false
            root.saveState()
            return
          }
          root.enqueue(["omarchy", "bar", "move", "omarchy.workspaces", "--section", place.section,
            "--index", String(place.index)], function() {
            root.persisted.stockLease = null
            root.workspaceShowPending = false
            root.saveState()
          })
        })
      })
    } else {
      persisted.stockLease = null
      saveState()
    }
  }

  function restoreDisplayLease(forceShow) {
    if (forceShow) displayShowPending = true
    if (displayDisable.running) return
    var lease = persisted.displayLease
    if (!lease && !forceShow) return
    if (forceShow || (lease && lease.disabledByStation && lease.wasEnabled)) {
      var place = lease || { section: "right", index: 5 }
      enqueue(["omarchy", "plugin", "enable", "omarchy.monitor"], function(code) {
        if (code !== 0) { root.displayShowPending = false; leaseVerify.restart(); return }
        if (root.config.hideDisplay) {
          root.displayShowPending = false
          root.acquireStockLeases()
          return
        }
        root.enqueue(["omarchy", "bar", "move", "omarchy.monitor", "--section", place.section,
          "--index", String(place.index)], function(moveCode) {
          if (moveCode === 0 && lease) {
            root.persisted.displayLease = null
            root.saveState()
          }
          root.displayShowPending = false
          leaseVerify.restart()
        })
      })
    } else {
      persisted.displayLease = null
      saveState()
    }
  }

  function setSetting(name, value) {
    if (name === "hideNative") {
      if (panelWanted) panelTransferUntil = Date.now() + 3000
      config.hideNative = !!value
      config = Object.assign({}, config)
      saveConfig()
      if (config.hideNative) {
        workspaceShowPending = false
        stockDisableAttempts = 0
        acquireStockLeases()
      } else {
        restoreStockLease(true)
      }
      return "ok"
    }
    if (name === "hideDisplay") {
      if (panelWanted) panelTransferUntil = Date.now() + 3000
      config.hideDisplay = !!value
      config = Object.assign({}, config)
      saveConfig()
      if (config.hideDisplay) {
        displayShowPending = false
        displayDisableAttempts = 0
        acquireStockLeases()
      } else {
        // A deliberate Show also enables a widget that was hidden before
        // Station acquired it. Startup/removal still respect lease ownership.
        restoreDisplayLease(true)
      }
      return "ok"
    }
    if (name === "panelPosition") {
      if (value !== "left" && value !== "center") return "invalid"
      config.panelPosition = value
    }
    else if (name === "stationAppsMode") {
      if (["hover", "always", "hide"].indexOf(value) === -1) return "invalid"
      config.stationAppsMode = value
    }
    else if (name === "followFocus") config.followFocus = !!value
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
    return displayController.removeStationBlock()
  }

  function handleStockPlugins(raw) {
    var list = parseJson(raw, [])
    var changed = false
    var displayEntry = list.find(function(item) { return item.id === "omarchy.monitor" })
    var workspaceEntry = list.find(function(item) { return item.id === "omarchy.workspaces" })
    if (displayEntry) displayWidgetEnabled = !!displayEntry.enabled
    if (workspaceEntry) workspaceWidgetEnabled = !!workspaceEntry.enabled
    if (config.hideNative) {
      var workspaceEnabled = !!(workspaceEntry && workspaceEntry.enabled)
      if (persisted.stockLease) {
        if (persisted.stockLease.disabledByStation && workspaceEnabled
            && stockDisableAttempts < 3 && !stockDisable.running && !displayDisable.running) {
          stockDisableAttempts += 1
          stockDisable.running = true
        }
      } else {
        var workspacePlace = barPlacement("omarchy.workspaces") || { section: "left", index: 1 }
        persisted.stockLease = { wasEnabled: workspaceEnabled, section: workspacePlace.section,
          index: workspacePlace.index, disabledByStation: workspaceEnabled }
        changed = true
        if (workspaceEnabled && !stockDisable.running && !displayDisable.running) {
          stockDisableAttempts += 1
          stockDisable.running = true
        }
      }
    }
    if (config.hideDisplay) {
      var displayEnabled = !!(displayEntry && displayEntry.enabled)
      if (persisted.displayLease) {
        if (!persisted.displayLease.disabledByStation && displayEnabled) {
          var renewedPlace = barPlacement("omarchy.monitor") || persisted.displayLease
          persisted.displayLease = { wasEnabled: true, section: renewedPlace.section,
            index: renewedPlace.index, disabledByStation: true }
          changed = true
        }
        if (persisted.displayLease.disabledByStation && displayEnabled
            && displayDisableAttempts < 3 && !displayDisable.running && !stockDisable.running) {
          displayDisableAttempts += 1
          displayDisable.running = true
        }
      } else {
        var displayPlace = barPlacement("omarchy.monitor") || { section: "right", index: 5 }
        persisted.displayLease = { wasEnabled: displayEnabled, section: displayPlace.section,
          index: displayPlace.index, disabledByStation: displayEnabled }
        changed = true
        if (displayEnabled && !displayDisable.running && !stockDisable.running) {
          displayDisableAttempts += 1
          displayDisable.running = true
        }
      }
    }
    if (changed) saveState()
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
      workspace.markTopologyDirty()
      if (state === "previewing" && !eventExpected(event))
        abandonPreview("Display connection changed; preview cancelled.")
      return
    }
    if (name === "configreloaded") {
      configGeneration += 1
      persisted.appliedBinds = []
      config.approvedReplacements = []
      if (state === "applyingLayout") return
      if (state === "previewing") {
        abandonPreview("Display configuration reloaded; preview cancelled.")
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
      refresh(true, function() { applyRuntime() })
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
        && Date.now() - lastTopologyMs > 500) followFocus.restart()
  }

  Component.onCompleted: {
    Qt.callLater(reconcileActiveBarLayout)
    ensureDirs.running = true
    barBridge = BarBridge.publish(function() { return root.barSnapshot() }, {
      switchStation: function(value) { return root.switchStation(value) },
      setSetting: function(name, value) { return root.setSetting(name, value) },
      setModeValue: function(mode, target) { return root.setModeValue(mode, target) },
      setDirectionValue: function(value) { return root.setDirectionValue(value) },
      setBinding: function(id, combo) { return root.setBinding(id, combo) },
      approveBinding: function(combo) { return root.approveBinding(combo) },
      setDisplayValue: function(name, key, value) { return root.setDisplayValue(name, key, value) },
      setDisplayTransform: function(name, value) { return root.setDisplayTransform(name, value) },
      setDisplayPosition: function(name, x, y) { return root.setDisplayPosition(name, x, y) },
      setDisplayEnabled: function(name, enabled) { return root.setDisplayEnabled(name, enabled) },
      setMonitorBarEnabled: function(name, enabled) { return root.setMonitorBarEnabled(name, enabled) },
      setMonitorBarPosition: function(name, position) { return root.setMonitorBarPosition(name, position) },
      setMonitorBarWidth: function(name, width) { return root.setMonitorBarWidth(name, width) },
      setMonitorBarHeight: function(name, height) { return root.setMonitorBarHeight(name, height) },
      setMonitorBarBackground: function(name, background) { return root.setMonitorBarBackground(name, background) },
      setMonitorBarStyle: function(name, style) { return root.setMonitorBarStyle(name, style) },
      setMonitorBarContentSize: function(name, contentSize) { return root.setMonitorBarContentSize(name, contentSize) },
      reportMonitorBarMinimum: function(name, value) { return root.reportMonitorBarMinimum(name, value) },
      reportMonitorBarMaximumContent: function(name, value) { return root.reportMonitorBarMaximumContent(name, value) },
      monitorBar: function(name) { return root.monitorBar(name) },
      monitorBarMaximumHeight: function(name) { return root.monitorBarMaximumHeight(name) },
      monitorBarMinimum: function(name) { return root.monitorBarMinimum(name) },
      monitorBarMaximumContent: function(name) { return root.monitorBarMaximumContent(name) },
      applyDisplaySetting: function(name, key, value) { return root.applyDisplaySetting(name, key, value) },
      swapRole: function(name, roleIndex) { return root.swapRole(name, roleIndex) },
      displayEnabled: function(name) { return root.displayEnabled(name) },
      roleOf: function(name) { return root.roleOf(name) },
      previewLayout: function() { return root.previewLayout() },
      keepPreview: function() { return root.keepPreview() },
      revertPreview: function(reason) { return root.revertPreview(reason || "") },
      acquireStockLeases: function() { return root.acquireStockLeases() },
      acknowledgePanelEvacuation: function(serial, screenName) {
        return root.acknowledgePanelEvacuation(serial, screenName)
      },
      setPanelWanted: function(value) { return root.setPanelWanted(value) },
      setPanelScreenName: function(value) { return root.setPanelScreenName(value) },
      setPanelTransferUntil: function(value) { return root.setPanelTransferUntil(value) },
      setWindowSetting: function(key, value) { return root.setWindowSetting(key, value) },
      setRememberedTab: function(value) { return root.setRememberedTab(value) },
      setRememberedDisplayName: function(value) { return root.setRememberedDisplayName(value) },
      wallpaperChoose: function(identity) { return root.wallpaper.choose(identity) },
      wallpaperChange: function(key, value) { return root.wallpaper.change(key, value) },
      wallpaperFrame: function(value) { return root.wallpaper.frame(value) },
      wallpaperReset: function() { return root.wallpaper.reset() },
      wallpaperUseTheme: function() { return root.wallpaper.useTheme() },
      wallpaperApply: function() { return root.wallpaper.apply() }
    })
  }

  Component.onDestruction: {
    BarBridge.clear(barBridge)
    var lease = persisted.stockLease || { section: "left", index: 0, wasEnabled: false, disabledByStation: false }
    if (["left", "center", "right"].indexOf(lease.section) === -1
        || !Number.isInteger(lease.index) || lease.index < 0)
      lease = { section: "left", index: 0, wasEnabled: false, disabledByStation: false }
    var displayLease = persisted.displayLease
      || { section: "right", index: 0, wasEnabled: false, disabledByStation: false }
    if (["left", "center", "right"].indexOf(displayLease.section) === -1
        || !Number.isInteger(displayLease.index) || displayLease.index < 0)
      displayLease = { section: "right", index: 0, wasEnabled: false, disabledByStation: false }
    var restore = lease.disabledByStation && lease.wasEnabled ? "1" : "0"
    var restoreDisplay = displayLease.disabledByStation && displayLease.wasEnabled ? "1" : "0"
    Quickshell.execDetached(["sh", "-c", Recovery.cleanup, "sh", stateDir,
      monitorsPath, lease.section, String(lease.index), restore,
      displayLease.section, String(displayLease.index), restoreDisplay])
  }

  FileView {
    id: configFile
    path: root.configPath
    atomicWrites: true
    printErrors: false
    onLoaded: { if (!root.configLoaded) { root.config = Store.loadConfig(root.parseJson(text(), {})); root.configLoaded = true; root.maybeStart() } }
    onLoadFailed: { if (!root.configLoaded) { root.config = Store.configDefaults(); root.configLoaded = true; root.maybeStart() } }
    onSaved: wallpaperController.preferenceSaved()
    onSaveFailed: wallpaperController.preferenceFailed()
  }

  FileView {
    id: personalBindings
    path: Quickshell.env("HOME") + "/.config/hypr/bindings.lua"
    watchChanges: true
    printErrors: false
    onLoaded: { root.personalBindingsText = text(); root.appliedGeneration = -1; root.applyBinds() }
    onLoadFailed: root.personalBindingsText = ""
    onFileChanged: reload()
  }

  FileView {
    id: stateFile
    path: root.statePath
    atomicWrites: true
    printErrors: false
    onLoaded: { if (!root.stateLoaded) { root.persisted = Store.loadState(root.parseJson(text(), {})); root.stateLoaded = true; root.maybeStart() } }
    onLoadFailed: { if (!root.stateLoaded) { root.persisted = Store.stateDefaults(); root.stateLoaded = true; root.maybeStart() } }
  }

  Process {
    id: ensureDirs
    command: ["mkdir", "-p", root.configDir, root.stateDir]
    onExited: {
      root.dirsReady = true
      configFile.reload()
      stateFile.reload()
      workspace.reload()
      displayController.reloadPreviewToken()
      root.maybeStart()
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
    id: barBlurProbe
    command: ["bash", "-lc", "hyprctl getoption decoration:blur:enabled -j; hyprctl getoption decoration:blur:size -j; hyprctl getoption decoration:blur:passes -j"]
    property string captured: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: barBlurProbe.captured = text }
    onRunningChanged: if (running) captured = ""
    onExited: function(code) { root.finishBarBlurProbe(code, captured) }
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
    onExited: {
      if (root.workspaceShowPending && !root.config.hideNative) root.restoreStockLease(true)
      leaseVerify.restart()
    }
  }

  Process {
    id: displayDisable
    command: ["omarchy", "plugin", "disable", "omarchy.monitor"]
    stdout: StdioCollector { waitForEnd: true }
    onExited: {
      if (root.displayShowPending && !root.config.hideDisplay) root.restoreDisplayLease(true)
      leaseVerify.restart()
    }
  }

  Timer {
    id: nativeMoveSettle
    property var before: null
    property string direction: ""
    property int generation: 0
    interval: 20
    onTriggered: root.afterNativeMove(before, direction, generation)
  }

  Timer { interval: 1500; running: root.started; repeat: true; onTriggered: root.observeDesktop() }
  Timer { id: reloadDebounce; interval: 300; onTriggered: { root.appliedGeneration = -1; root.refresh(true, function() { root.applyRuntime() }) } }
  Timer { id: removalGrace; interval: 5000; onTriggered: root.refresh(true, function() { root.applyRuntime() }) }
  Timer { id: leaseVerify; interval: 600; onTriggered: if (!pluginList.running) pluginList.running = true }
  Timer { id: screenHealthCheck; interval: 2500; onTriggered: root.verifyScreenHealth() }
  Timer { id: screenRecoveryEnable; interval: 250; onTriggered: root.finishScreenRecovery() }
  Timer {
    id: panelEvacuationTimeout
    // A replacement-bar widget polls every 1000 ms once its panel starts
    // closing, then waits 180 ms for the layer surface to unmap. Keep enough
    // scheduling margin for that guarded acknowledgement; no monitor rule is
    // dispatched until it arrives, and expiry still aborts safely.
    interval: 2500
    onTriggered: if (root.panelEvacuationWaiting) root.panelEvacuationTimedOut()
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
      globalBarPosition: root.globalBarPosition, lastGlobalBarPosition: root.lastGlobalBarPosition,
      bars: root.config.bars,
      workspaceMap: root.workspaceMap, migrationPending: root.workspaceData.pending !== null,
      migrationPhase: root.migrationPhase, layoutError: root.layoutError,
      lastWindowAction: root.lastWindowAction,
      monitors: root.monitors, bindStatuses: root.bindStatuses, panelWanted: root.panelWanted,
      panelScreenName: root.panelScreenName, previewBusy: root.previewBusy, previewSeconds: root.previewSeconds,
      panelPosition: root.config.panelPosition,
      panelEvacuationWaiting: root.panelEvacuationWaiting,
      draftMode: root.draftMode, savedMode: root.config.mode, singleTarget: root.draftSingleTarget,
      stockLease: root.persisted.stockLease, stockDisableAttempts: root.stockDisableAttempts,
      stockDisableRunning: stockDisable.running, displayLease: root.persisted.displayLease,
      displayDisableAttempts: root.displayDisableAttempts, displayDisableRunning: displayDisable.running,
      displayWidgetEnabled: root.displayWidgetEnabled }) }
  }
}

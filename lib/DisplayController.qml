import QtQuick
import Quickshell.Io
import "Model.js" as Model
import "Grid.js" as Grid
import "Hypr.js" as Hypr
import "MonitorsLua.js" as MonitorsLua
import "Transactions.js" as Transactions

// Persistent display edit/preview owner. Service retains operation arbitration,
// generation domains, command/snapshot queues and the serial panel barrier.
Item {
  id: root
  property string stateDir: ""
  property string monitorsPath: ""
  property string internalDisablePath: ""
  property string candidatePath: ""
  property string plainCandidatePath: ""
  property string plainPath: ""
  property string operationState: "idle"
  property int operationGeneration: 0
  property int configGeneration: 0
  property bool started: false
  property var preferences: ({enabled: [], mode: "extend", singleTarget: "", mirrorSource: ""})
  property var monitors: []
  property var clients: []
  property var lanes: ({})
  property int currentStation: 1
  property var workspaceMap: null
  property bool migrationPending: false
  property string migrationPhase: ""
  property bool topologyDirty: false
  property bool panelWanted: false
  property string panelScreenName: ""
  property string layoutError: ""
  property var beginPreview: null
  property var setOperationState: null
  property var beginRevert: null
  property var invalidatePreviewOperation: null
  property var refresh: null
  property var evalLua: null
  property var enqueue: null
  property var recordExpectedEvents: null
  property var monitorSignature: null
  property var reconcileWorkspace: null
  property var targetMapping: null
  property var clearWorkspaceTopologyDirty: null
  property var requestPanelEvacuation: null
  property var clearPanelEvacuation: null
  property var retainPanel: null
  property var stopTopologyTimers: null
  property var publishDisplayOptions: null
  property var saveDisplayPreferences: null
  property var invalidateAppliedBinds: null
  property var updateAssignments: null
  property var applyBinds: null
  property var applyRuntime: null
  property var armScreenHealthCheck: null
  property var launchWatchdog: null
  property var reportError: null
  property var ready: null
  property var finishAuthorityMigration: null

  property var displayDraft: []
  property string draftMode: "extend"
  property string draftSingleTarget: ""
  property string draftMirrorSource: ""
  readonly property bool draftEditable: (operationState === "idle" || operationState === "previewing") && !previewBusy
  property bool previewBusy: false
  property string previewAbortReason: ""
  property var previewBaseline: null
  property var previewBefore: []
  property var previewApplied: null
  property string previewObservedSignature: ""
  property int previewSeconds: 0
  property var pendingDisplayConfig: null
  property var keepOptions: null
  property string layoutWriteKind: ""
  property bool keepFilesPending: false
  property string keepSourceBaseline: ""
  property string keepDisableToggle: ""
  property bool candidateReady: false
  property bool plainCandidateReady: false
  property string internalDisableSource: ""
  property string monitorsSource: ""
  property bool monitorsLoaded: false
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
  property bool previewLoaded: false
  property bool previewFound: false

  function detached(value) { return JSON.parse(JSON.stringify(value)) }
  function validConnector(value) {
    try { MonitorsLua.connector(value); return true } catch (error) { return false }
  }
  function reloadPreviewToken() { previewToken.reload() }
  function restorePreviewBaseline(value) { previewBaseline = detached(value) }
  function failPreview(message) { previewBusy = false; return revertPreview(message) }
  function previewMirrorSource(name) { draftMirrorSource = name; return previewLayout() }

  function syncDisplayDraft() {
    var enabled = monitors.filter(function(m) { return !m.disabled }).map(function(m) { return m.name })
    var saved = MonitorsLua.managedGeometry(monitorsSource)
    displayDraft = monitors.filter(function(m) { return root.validConnector(m.name) && lanes[m.name] }).map(function(m) {
      var geometry = m.disabled || Model.isMirror(m) ? saved[m.name] : null
      if (!geometry || (m.availableModes || []).indexOf(geometry.mode) < 0) geometry = null
      return { name: m.name, description: m.description || m.model || "", width: Number(m.width),
        height: Number(m.height), refreshRate: Number(m.refreshRate), availableModes: m.availableModes || [],
        mode: geometry ? geometry.mode : Model.currentMode(m),
        x: geometry ? geometry.x : Number(m.x) || 0, y: geometry ? geometry.y : Number(m.y) || 0,
        scale: geometry ? geometry.scale : Number(m.scale) || 1,
        transform: geometry ? geometry.transform : Number(m.transform) || 0,
        enabled: enabled.indexOf(m.name) !== -1, lane: lanes[m.name] }
    })
    draftMode = preferences.mode
    draftSingleTarget = preferences.singleTarget
    draftMirrorSource = preferences.mirrorSource || ""
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

  function setResizedDisplayValue(name, key, value) {
    if (!draftEditable || ["mode", "scale", "transform"].indexOf(key) === -1) return "invalid"
    try { MonitorsLua.connector(name) } catch (error) { return "invalid" }
    var before = displayDraft.find(function(display) { return display.name === name })
    if (!before) return "invalid"
    var changed = Object.assign({}, before)
    changed[key] = value
    var peers = draftMode === "extend" && before.enabled
      ? displayDraft.filter(function(display) { return display.enabled }) : [before]
    var position = Model.resizedPosition(before, changed, peers)
    changed.x = Math.round(position.x)
    changed.y = Math.round(position.y)
    displayDraft = displayDraft.map(function(display) {
      return display.name === name ? changed : display
    })
    return "ok"
  }

  function setDisplayTransform(name, value) {
    if (!Number.isInteger(value) || value < 0 || value > 7) return "invalid"
    return setResizedDisplayValue(name, "transform", value)
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

  function setDisplayEnabled(name, enabled) {
    if (!draftEditable) return "busy"
    if (!enabled && displayDraft.filter(function(d) { return d.enabled && d.name !== name }).length === 0) {
      reportError("At least one display must remain enabled.")
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
    var states = MonitorsLua.runtimeModeStates(displayDraft, { mode: draftMode, singleTarget: draftSingleTarget, mirrorSource: draftMirrorSource,
      enabled: displayDraft.filter(function(d) { return d.enabled }).map(function(d) { return d.name }) })
    return states.some(function(d) { return d.name === name && !d.disabled })
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
    draftMirrorSource = mode === preferences.mode ? (preferences.mirrorSource || "") : ""
    return previewLayout()
  }

  function applyDisplaySetting(name, key, value) {
    // Side controls are deliberate, discrete choices and do not need the
    // safety countdown used for topology edits. Persist first and let
    // Hyprland's watched config apply the new value once; previewing it first
    // would reconfigure the output, then the old file could win on a reload,
    // and Keep would reconfigure it a third time.
    if (operationState !== "idle" || migrationPending || migrationPhase) return "busy"
    if (["scale", "mode"].indexOf(key) === -1) return "invalid"
    var display = displayDraft.find(function(item) { return item.name === name })
    if (display && display[key] === value) return "ok"
    var before = displayDraft
    if (setResizedDisplayValue(name, key, value) !== "ok") return "invalid"
    try {
      var options = { mode: draftMode, singleTarget: draftSingleTarget, mirrorSource: draftMirrorSource,
        enabled: displayDraft.filter(function(d) { return d.enabled }).map(function(d) { return d.name }) }
      var generated = MonitorsLua.generate(displayDraft, options)
      var source = MonitorsLua.replaceManagedBlock(monitorsSource || "", generated.block)
      pendingDisplayConfig = generated
      keepOptions = JSON.parse(JSON.stringify(options))
      reportError("")
      if (panelWanted) retainPanel(undefined, Date.now() + 3000)
      stopTopologyTimers()
      startKeepFiles(source, generated.plain, "control")
      return "started"
    } catch (error) {
      displayDraft = before
      pendingDisplayConfig = null
      keepOptions = null
      reportError(String(error.message || error))
      return "invalid"
    }
  }

  function previewLayout() {
    if (!draftEditable) return "busy"
    if (migrationPending || migrationPhase) return "busy"
    try {
      if (draftMode === "extend" && Model.layoutOverlaps(displayDraft.filter(function(d) { return d.enabled })).length)
        throw new Error("Displays overlap")
      var generated = MonitorsLua.generate(displayDraft, {
        mode: draftMode, enabled: displayDraft.filter(function(d) { return d.enabled }).map(function(d) { return d.name }),
        singleTarget: draftSingleTarget, mirrorSource: draftMirrorSource
      })
      // A re-edit joins the session already in progress: keep the baseline
      // the first preview captured, so Revert still means "back to the layout
      // as it was before this session", and Revert never lands mid-session.
      if (operationState !== "previewing") { previewBefore = monitors.slice(); previewApplied = null }
      pendingDisplayConfig = generated
      reportError("")
      if (panelWanted) retainPanel(undefined, Date.now() + 3000)
      stopTopologyTimers()
      beginPreview()
      previewBusy = true
      previewCountdown.stop()
      previewArm.running = true
      return "started"
    } catch (error) {
      reportError(String(error.message || error))
      return "invalid"
    }
  }

  function applyPreview() {
    if (operationState !== "previewing" || !pendingDisplayConfig) return
    refresh(true, function() { root.applyPreviewSnapshot() })
  }

  function applyPreviewSnapshot() {
    if (operationState !== "previewing" || !pendingDisplayConfig) return
    if (!previewBaseline && Grid.valid(workspaceMap)) {
      previewBaseline = Grid.plan(workspaceMap, workspaceMap, clients, currentStation)
      previewBaseline.panelScreenName = panelScreenName
    }
    launchWatchdog()
    var lua = pendingDisplayConfig.block.split("\n").filter(function(line) {
      return line !== MonitorsLua.START && line !== MonitorsLua.END
    }).join("\n")
    var previous = previewApplied ? previewApplied.displays : previewBefore.map(function(monitor) {
      return Object.assign({}, monitor, { mode: Model.currentMode(monitor),
        enabled: Model.enabledNames(previewBefore, preferences.enabled).indexOf(monitor.name) !== -1 })
    })
    var previousOptions = previewApplied ? previewApplied.options : {
      mode: preferences.mode, singleTarget: preferences.singleTarget, mirrorSource: preferences.mirrorSource, enabled: preferences.enabled
    }
    var nextOptions = { mode: draftMode, singleTarget: draftSingleTarget, mirrorSource: draftMirrorSource,
      enabled: displayDraft.filter(function(d) { return d.enabled }).map(function(d) { return d.name }) }
    var positionRules = MonitorsLua.positionOnlyRules(previous, pendingDisplayConfig.displays,
      previewApplied ? previewApplied.mode : preferences.mode, draftMode)
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

  function stagePreviewApply(lua, expectedOutputs, options) {
    previewApplyLua = lua
    previewApplyStaged = true
    previewApplyExpectedOutputs = expectedOutputs
    previewApplyFocusTarget = previewFocusTarget(options)
    previewApplyActivateLua = activationRule(previewApplyFocusTarget)
    previewApplyMigrateFirst = previewApplyActivateLua !== ""
    previewApplyPanelOrigin = panelScreenName
    previewApplyPanelTarget = panelWanted ? panelTransferTarget(options) : ""
    // KeyboardPanel owns dismiss surfaces on every output, including peers.
    // Close it even when its own monitor survives the topology change.
    if (panelWanted && previewApplyPanelOrigin && previewApplyPanelTarget
        && expectedOutputs.length > 0) {
      requestPanelEvacuation(previewApplyPanelOrigin, previewApplyPanelTarget, "preview")
      return
    }
    continuePreviewApply()
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
      retainPanel(origin)
      retainPanel(undefined, Date.now() + 3000)
    }
    previewBusy = false
    revertPreview(message)
  }

  function continuePreviewApply() {
    if (operationState !== "previewing" || !previewApplyStaged) return
    var lua = previewApplyLua
    var expectedOutputs = previewApplyExpectedOutputs.slice()
    var focusTarget = previewApplyFocusTarget
    var activateLua = previewApplyActivateLua
    function applyMonitors() {
      if (root.operationState !== "previewing") return
      recordExpectedEvents({ kinds: ["monitor", "workspace"], outputs: expectedOutputs, until: Date.now() + 2000 })
      root.evalLua(lua, function(code, output) {
        if (root.operationState !== "previewing") return
        if (code !== 0 || (output && output.trim() !== "ok")) {
          root.failPreviewApply("Could not apply the display preview.")
          return
        }
        var target = root.previewApplyPanelTarget
        root.clearPreviewApplyStage()
        if (root.panelWanted && target) {
          retainPanel(target)
          retainPanel(undefined, Date.now() + 3000)
        }
        reconcileWorkspace()
      })
    }
    function focusSurvivor() {
      function afterFocus() {
        // When the destination started disabled, move clients while both
        // outputs still exist. Removing their current output first exposes
        // GTK clients to a stale Wayland-output callback and can crash them.
        if (root.previewApplyMigrateFirst) reconcileWorkspace()
        else applyMonitors()
      }
      if (!focusTarget) { afterFocus(); return }
      root.evalLua(Hypr.focusMonitor(focusTarget), function(code, output) {
        if (root.operationState !== "previewing") return
        if (code !== 0 || (output && output.trim() !== "ok")) {
          root.failPreviewApply("Could not focus the surviving display; preview was not applied.")
          return
        }
        afterFocus()
      })
    }
    // A Single-to-Single switch can target an output that is currently off.
    // Bring it up on its own, then focus it, and only then remove the old one.
    recordExpectedEvents({ kinds: ["monitor", "workspace"], outputs: expectedOutputs, until: Date.now() + 2000 })
    if (!activateLua) { focusSurvivor(); return }
    evalLua(activateLua, function(code, output) {
      if (root.operationState !== "previewing") return
      if (code !== 0 || (output && output.trim() !== "ok")) {
        root.failPreviewApply("Could not enable the surviving display; preview was not applied.")
        return
      }
      focusSurvivor()
    })
  }

  function finishPreviewApply() {
    if (operationState !== "previewing") return
    if (previewApplyStaged && previewApplyMigrateFirst) {
      var lua = previewApplyLua
      var expectedOutputs = previewApplyExpectedOutputs.slice()
      var target = previewApplyPanelTarget
      // Mark this phase consumed before dispatch. Monitor events are expected
      // while the old output is removed and must not start it a second time.
      previewApplyMigrateFirst = false
      recordExpectedEvents({ kinds: ["monitor", "workspace"], outputs: expectedOutputs, until: Date.now() + 2000 })
      evalLua(lua, function(code, output) {
        if (root.operationState !== "previewing") return
        if (code !== 0 || (output && output.trim() !== "ok")) {
          root.failPreviewApply("Could not finish the display preview.")
          return
        }
        root.clearPreviewApplyStage()
        if (root.panelWanted && target) {
          retainPanel(target)
          retainPanel(undefined, Date.now() + 3000)
        }
        root.refresh(true, function() {
          // The fresh snapshot has absorbed the expected removal.
          clearWorkspaceTopologyDirty()
          root.finishPreviewApply()
        })
      })
      return
    }
    if (topologyDirty || !Grid.equal(workspaceMap, targetMapping())) { reconcileWorkspace(); return }
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
      if (root.operationState !== "previewing") return
      root.previewBusy = false
      if (code !== 0) { root.revertPreview("Could not renew preview recovery."); return }
      launchWatchdog()
      root.previewSeconds = 12
      root.previewObservedSignature = root.monitorSignature()
      previewCountdown.restart()
      if (root.panelWanted) retainPanel(undefined, Date.now() + 3000)
    })
  }

  function abandonPreview(reason) {
    previewCountdown.stop()
    invalidatePreviewOperation()
    clearPanelEvacuation()
    clearPreviewApplyStage()
    pendingDisplayConfig = null
    previewApplied = null
    previewAbortReason = ""
    previewBusy = false
    setOperationState(migrationPhase ? "migrating" : "idle")
    reportError(reason || "External display change accepted; preview cancelled.")
    enqueue(["rm", "-f", stateDir + "/preview.token"], function() {
      root.refresh(true, function() { root.applyRuntime() })
    })
  }

  function revertPreview(reason) {
    if (operationState !== "previewing") return "idle"
    if (previewBusy) return "busy"
    previewBusy = true
    pendingRevertReason = reason || ""
    pendingRevertPanelTarget = panelWanted ? panelTransferTarget(preferences) : ""
    var origin = panelScreenName
    pendingRevertPanelOrigin = origin
    pendingRevertFocusTarget = previewFocusTarget(preferences)
    pendingRevertActivateLua = activationRule(pendingRevertFocusTarget)
    clearPreviewApplyStage()
    if (panelWanted && origin && pendingRevertPanelTarget) {
      requestPanelEvacuation(origin, pendingRevertPanelTarget, "revert")
      return "started"
    }
    continueRevertPreview()
    return "started"
  }

  function continueRevertPreview() {
    if (operationState !== "previewing") return
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
      if (root.operationState !== "previewing") return
      root.previewBusy = false
      reportError(message)
      if (root.panelWanted && origin) {
        retainPanel(origin)
        retainPanel(undefined, Date.now() + 3000)
      }
      root.previewSeconds = 12
      root.previewObservedSignature = root.monitorSignature()
      previewCountdown.restart()
    }
    function reloadSavedLayout() {
      if (root.operationState !== "previewing") return
      if (root.panelWanted) {
        if (target) retainPanel(target)
        retainPanel(undefined, Date.now() + 3000)
      }
      beginRevert()
      setOperationState("applyingLayout")
      root.pendingDisplayConfig = null
      if (root.previewBaseline && root.previewBaseline.panelScreenName)
        retainPanel(root.previewBaseline.panelScreenName)
      root.enqueue(["rm", "-f", root.stateDir + "/preview.token"], function() {
        root.enqueue(["hyprctl", "reload"], function(code) {
          if (code !== 0) reportError("Could not reload the saved monitor layout.")
          root.restoreAppliedLayout()
        })
      })
      if (reason) reportError(reason)
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
    recordExpectedEvents({ kinds: ["monitor", "workspace"], outputs: [focusTarget], until: Date.now() + 2000 })
    evalLua(activateLua, function(code, output) {
      if (code !== 0 || (output && output.trim() !== "ok")) {
        failPreparation("Could not enable the saved display; layout was not restored.")
        return
      }
      focusSurvivor()
    })
  }

  function panelEvacuationTimedOut(purpose, origin) {
    if (purpose !== "revert") {
      failPreviewApply("Could not safely move Station before disabling its display.")
      return
    }
    clearPanelEvacuation()
    pendingRevertReason = ""
    pendingRevertPanelTarget = ""
    pendingRevertPanelOrigin = ""
    pendingRevertFocusTarget = ""
    pendingRevertActivateLua = ""
    previewBusy = false
    reportError("Could not safely close Station before restoring the saved display layout.")
    if (panelWanted && origin) {
      retainPanel(origin)
      retainPanel(undefined, Date.now() + 3000)
    }
  }

  function keepPreview() {
    if (operationState !== "previewing" || !pendingDisplayConfig) return "idle"
    if (previewBusy || migrationPending) return "busy"
    try {
      if (panelWanted) retainPanel(undefined, Date.now() + 3000)
      var source = monitorsSource || ""
      var merged = MonitorsLua.replaceManagedBlock(source, pendingDisplayConfig.block)
      // Personal rules follow the Station block and retain final precedence.
      keepOptions = JSON.parse(JSON.stringify(previewApplied.options))
      previewCountdown.stop()
      startKeepFiles(merged, pendingDisplayConfig.plain, "preview")
      return "started"
    } catch (error) {
      reportError(String(error.message || error))
      return "invalid"
    }
  }

  function startKeepFiles(source, plain, kind) {
    keepSourceBaseline = monitorsSource
    keepDisableToggle = kind === "preview" && pendingDisplayConfig && keepOptions
      ? MonitorsLua.disableToggleToClear(internalDisableSource, pendingDisplayConfig.displays, keepOptions) : ""
    setOperationState("applyingLayout")
    layoutWriteKind = kind || "direct"
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
    invalidateAppliedBinds()
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
    layoutWriteKind = ""
    refresh(true, function() {
      setOperationState("idle")
      root.syncDisplayDraft()
      root.applyRuntime()
      root.armScreenHealthCheck()
    })
  }

  function finishKeep(code, errorText) {
    if (code !== 0) {
      var failedKind = layoutWriteKind
      layoutWriteKind = ""
      reportError(code === 4 ? "Configuration changed while saving; newer edits were preserved." : code === 3 ? "Hyprland rejected the layout; the backup was restored. " + errorText.trim()
        : "Could not save the monitor layout.")
      pendingDisplayConfig = null
      if (code === 3 || code === 4) restoreAppliedLayout()
      else if (failedKind !== "preview") {
        keepOptions = null
        setOperationState("idle")
        syncDisplayDraft()
      }
      else enqueue(["hyprctl", "reload"], function() { root.restoreAppliedLayout() })
      return
    }
    var requestedDisplays = pendingDisplayConfig ? pendingDisplayConfig.displays : []
    var requestedOptions = keepOptions
    publishDisplayOptions(keepOptions)
    pendingDisplayConfig = null
    previewApplied = null
    previewBaseline = null
    keepOptions = null
    layoutWriteKind = ""
    reportError("")
    monitorsFile.reload()
    saveDisplayPreferences()
    refresh(true, function() {
      setOperationState("idle")
      // The config-file watcher has applied the persisted rules. Replaying
      // monitor state here creates another topology operation for no benefit;
      // only rebuild bookkeeping, commit any preview journal, and restore
      // runtime binds erased by a config reload.
      if (requestedDisplays.length && MonitorsLua.changedOutputs(requestedDisplays, requestedOptions, root.monitors, true).length)
        reportError("Personal Hyprland rules override part of this layout. Station shows the applied values.")
      root.updateAssignments()
      root.applyBinds()
      reconcileWorkspace()
      root.armScreenHealthCheck()
    })
  }

  function removeStationBlock() {
    if (operationState !== "idle") return "busy"
    try {
      var source = MonitorsLua.removeManagedBlock(monitorsSource)
      if (source === monitorsSource) return "absent"
      var generated = MonitorsLua.generate(displayDraft, { mode: "extend",
        enabled: displayDraft.map(function(display) { return display.name }), singleTarget: "" })
      keepOptions = { mode: "extend", enabled: displayDraft.map(function(display) { return display.name }), singleTarget: "" }
      startKeepFiles(source, generated.plain, "direct")
      return "started"
    } catch (error) { reportError(String(error.message || error)); return "invalid" }
  }

  function migrateMonitorPrecedence(done) {
    // Existing v2 blocks moved to the front once. Personal Lua bytes survive.
    var info = MonitorsLua.markerInfo(monitorsSource)
    if (!info.starts.length && !info.ends.length) { finishAuthorityMigration(done, true); return }
    try {
      var next = MonitorsLua.migrateBlock(monitorsSource)
      if (next === monitorsSource) { finishAuthorityMigration(done, true); return }
      enqueue(["sh", "-c", Transactions.settings, "sh", monitorsPath, monitorsSource, next], function(code) {
        if (code !== 0) reportError("Could not migrate monitor rule precedence; personal configuration was preserved.")
        monitorsFile.reload()
        if (code === 0) root.finishAuthorityMigration(done, false)
        else done()
      })
    } catch (error) { reportError(String(error)); done() }
  }

  FileView {
    id: monitorsFile
    path: root.monitorsPath
    watchChanges: true
    printErrors: false
    onLoaded: {
      root.monitorsSource = text()
      root.monitorsLoaded = true
      root.ready()
      if (root.started && root.operationState === "idle") root.syncDisplayDraft()
    }
    onLoadFailed: { root.monitorsSource = ""; root.monitorsLoaded = true; root.ready() }
    onFileChanged: reload()
  }

  FileView {
    id: internalDisableFile
    path: root.internalDisablePath
    watchChanges: true
    printErrors: false
    onLoaded: root.internalDisableSource = text()
    onLoadFailed: root.internalDisableSource = ""
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
    id: previewToken
    path: root.stateDir + "/preview.token"
    printErrors: false
    onLoaded: { root.previewFound = true; root.previewLoaded = true; root.ready() }
    onLoadFailed: { root.previewFound = false; root.previewLoaded = true; root.ready() }
  }

  Process {
    id: previewArm
    command: ["touch", root.stateDir + "/preview.token"]
    onExited: function(code) {
      if (code === 0) root.applyPreview()
      else { root.reportError("Could not arm preview recovery."); root.previewBusy = false; root.setOperationState("idle") }
    }
  }

  Process {
    id: keepTransaction
    command: ["sh", "-c", Transactions.keep, "sh", root.candidatePath, root.monitorsPath,
      root.plainCandidatePath, root.plainPath, root.stateDir + "/preview.token", root.keepSourceBaseline, root.internalDisablePath, root.keepDisableToggle]
    property string errors: ""
    stderr: StdioCollector { waitForEnd: true; onStreamFinished: keepTransaction.errors = text }
    onRunningChanged: if (running) errors = ""
    onExited: function(code) { root.finishKeep(code, errors) }
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
}

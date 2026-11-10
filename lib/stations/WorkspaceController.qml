import QtQuick
import Quickshell.Io
import "Grid.js" as Grid
import "../platform/Hypr.js" as Hypr

// One persistent owner of the migration journal, save barriers and retries.
// Service retains operation arbitration, compositor queues and display preview.
// Inputs and finite ports never grant access to the Service QObject.
Item {
  id: root
  property string stateDir: ""
  property string operationState: "idle"
  property int operationGeneration: 0
  property bool removalGraceRunning: false
  property var clients: []
  property var lanes: ({})
  property int currentStation: 1
  property bool legacyWorkspaceGrid: false
  property var previewBaseline: null
  property string panelScreenName: ""
  property string layoutError: ""
  property var targetMapping: null
  property var refresh: null
  property var updateAssignments: null
  property var focusedClient: null
  property var beginMigration: null
  property var setOperationState: null
  property var evalLua: null
  property var recordExpectedEvents: null
  property var reportError: null
  property var setCurrentStation: null
  property var commitMigrationState: null
  property var restorePreviewBaseline: null
  property var finishPreviewApply: null
  property var failPreview: null
  property var focusStatements: null
  property var showStation: null
  property var settle: null
  property var ready: null

  property var workspaceData: ({ mapping: null, pending: null })
  property bool mappingLoaded: false
  property string migrationPhase: ""
  property bool topologyDirty: false
  property int migrationAttempts: 0
  property var migrationFocus: null
  property var migrationCommit: null
  readonly property var workspaceMap: workspaceData.mapping
  // Root/OpenApps consume detached data, never the owner's mutable journal.
  readonly property var snapshot: detached(workspaceData)

  function detached(value) { return JSON.parse(JSON.stringify(value)) }
  function parseJournal(raw) {
    try { return JSON.parse(String(raw || "")) } catch (error) { return null }
  }
  function reload() { workspaceFile.reload() }
  function markTopologyDirty() { topologyDirty = true }
  // Called only after the existing preview fresh-snapshot barrier.
  function clearTopologyDirty() { topologyDirty = false }

  function reconcile() {
    if (operationState === "applyingLayout") return
    if (removalGraceRunning) return
    if (migrationPhase || operationState === "migrating") { topologyDirty = true; return }
    var preview = operationState === "previewing"
    if (!preview) beginMigration()
    refresh(true, function() {
      updateAssignments()
      var target = targetMapping()
      if (!Grid.valid(target)) {
        if (preview) migrationFailed("No usable display after the layout change.")
        else setOperationState("idle")
        return
      }
      try {
        var old = workspaceMap || (legacyWorkspaceGrid ? Grid.legacy(lanes) : target)
        var pending = workspaceData.pending
        var plan = pending ? Grid.resume(pending, target, clients) : Grid.plan(old, target, clients, currentStation)
        if (!preview && previewBaseline) plan = Grid.restorePreview(previewBaseline, plan, clients)
        var focused = focusedClient()
        migrationFocus = focused ? Grid.identity(focused) : null
        // FileView does not emit saved when setText receives identical text.
        // A revision makes every journal attempt an acknowledged disk write,
        // including recovery of an otherwise unchanged plan after restart.
        workspaceData = { mapping: old, pending: plan, preview: detached(previewBaseline),
          revision: Number(workspaceData.revision || 0) + 1 }
        topologyDirty = false
        migrationPhase = "journal"
        workspaceFile.setText(JSON.stringify(workspaceData, null, 2) + "\n")
      } catch (error) { migrationFailed(String(error)) }
    })
  }

  function migrationFailed(message) {
    migrationPhase = ""
    var preview = operationState === "previewing"
    if (!preview) setOperationState("idle")
    reportError("Workspace migration: " + message)
    // Keep the journal for a later retry; never decode partially moved IDs again.
    if (++migrationAttempts <= 3) migrationRetry.restart()
    else if (preview) failPreview(layoutError)
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
      if (layoutError.indexOf("Workspace migration:") === 0) reportError("")
      commitMigrationState(currentStation)
      if (operationState === "previewing") {
        if (topologyDirty || !Grid.equal(workspaceMap, targetMapping())) { reconcile(); return }
        evalLua(Hypr.batch(focusStatements(currentStation, panelScreenName)), function() {
          root.finishPreviewApply()
        })
        return
      }
      restorePreviewBaseline(null)
      setOperationState("idle")
      if (topologyDirty || !Grid.equal(workspaceMap, targetMapping())) { reconcile(); return }
      // Repetitive and Non-repetitive outputs keep what they show.
      if (Grid.mode(workspaceMap) !== "station") { settle(migrationFocus); return }
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
    var rules = Hypr.workspaceRules(Grid.assignments(plan.to))
    var statements = []
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
    recordExpectedEvents({ kinds: ["workspace", "focusedmon"], outputs: Object.keys(affected), until: Date.now() + 2000 })
    // Install the rules separately so a false result from a later idempotent
    // move cannot hide whether future workspaces have the correct owner.
    evalLua(Hypr.batch(rules), function(ruleCode, ruleOutput) {
      if (ruleCode !== 0 || (ruleOutput && ruleOutput.trim() !== "ok")) {
        migrationFailed("compositor rejected the workspace rules")
        return
      }
      evalLua(Hypr.batch(statements), function(moveCode, moveOutput) {
        // Hyprland can apply an earlier dispatch in a Lua batch and still
        // return false for a later no-op. The durable journal and a fresh
        // compositor snapshot, not that aggregate return value, determine
        // whether the migration completed.
        refresh(true, function() {
          if (topologyDirty || !Grid.equal(plan.to, targetMapping())) {
            migrationPhase = ""
            if (operationState !== "previewing") setOperationState("idle")
            reconcile(); return
          }
          var failed = plan.windows.some(function(row) {
            var client = clients.find(function(c) { return Grid.sameClient(row, c) })
            return client && !client.pinned && (Number(client.workspace.id) !== row.to || client.monitor !== row.output)
          })
          if (failed) {
            var rejected = moveCode !== 0 || (moveOutput && moveOutput.trim() !== "ok")
            migrationFailed(rejected ? "compositor rejected the move batch" : "destination verification failed")
            return
          }
          setCurrentStation(plan.station)
          migrationCommit = { mapping: plan.to, pending: null,
            preview: operationState === "previewing" ? detached(previewBaseline) : null, revision: workspaceData.revision + 1 }
          migrationPhase = "commit"
          workspaceFile.setText(JSON.stringify(migrationCommit, null, 2) + "\n")
        })
      })
    })
  }

  FileView {
    id: workspaceFile
    path: root.stateDir + "/workspace-map.json"
    atomicWrites: true
    printErrors: false
    onLoaded: {
      if (root.mappingLoaded) return
      var data = root.parseJournal(text())
      if (!data || (!Grid.valid(data.mapping) && !(data.pending && data.pending.from && data.pending.from.legacy))) {
        root.reportError("Could not read the saved workspace mapping.")
        return
      }
      root.workspaceData = data
      root.restorePreviewBaseline(root.detached(data.preview || null))
      root.mappingLoaded = true
      root.ready()
    }
    onLoadFailed: {
      if (!root.mappingLoaded) { root.mappingLoaded = true; root.ready() }
    }
    onSaved: root.migrationSaved()
    onSaveFailed: root.migrationFailed("could not save the migration journal")
  }

  Timer { id: migrationRetry; interval: 500; onTriggered: root.reconcile() }
}

import QtQuick
import QtTest
import "Probe/stations" as Stations
import "Probe/stations/Grid.js" as Grid

Item {
  id: host
  width: 1; height: 1
  property string operation: "idle"
  property int generation: 0
  property int station: 3
  property var clients: []
  property var target: ({outputs:["A","B"]})
  property var originalBaseline: null
  property string error: ""
  property bool grace: false
  property var jobs: []
  property var trace: []
  property var expected: ({})
  property int commits: 0
  property int finishes: 0
  property int reverts: 0
  property int readyCount: 0
  property bool rejectRules: false
  property bool rejectMoves: false
  property bool falseMoves: false
  property bool previewBusy: true
  property var owner: null

  Component {
    id: factory
    Stations.WorkspaceController {
      stateDir: "/isolated"
      operationState: host.operation
      operationGeneration: host.generation
      removalGraceRunning: host.grace
      clients: host.clients
      lanes: ({A:1,B:2,C:3})
      currentStation: host.station
      legacyWorkspaceGrid: false
      previewBaseline: host.originalBaseline
      panelScreenName: "A"
      layoutError: host.error
      targetMapping: function() { host.trace.push("target"); return host.target }
      refresh: function(include, done) { host.jobs.push({kind:"refresh",done:done}) }
      updateAssignments: function() { host.trace.push("assignments") }
      focusedClient: function() { return host.clients[2] }
      beginMigration: function() { host.trace.push("begin"); host.generation++; host.operation="migrating" }
      setOperationState: function(value) { host.operation=value }
      evalLua: function(lua,done) { host.trace.push("eval"); host.jobs.push({kind:"eval",lua:lua,done:done}) }
      recordExpectedEvents: function(value) { host.trace.push("expect"); host.expected=value }
      reportError: function(value) { host.error=value }
      setCurrentStation: function(value) { host.station=value }
      commitMigrationState: function(value) { host.commits++; host.trace.push("commit") }
      restorePreviewBaseline: function(value) { host.originalBaseline=value }
      finishPreviewApply: function() { host.finishes++ }
      failPreview: function(value) { host.previewBusy=false; host.reverts++; host.error=value }
      focusStatements: function(station,output) { return [] }
      showStation: function(value) { host.trace.push("show:"+value) }
      ready: function() { host.readyCount++ }
    }
  }
  TestCase {
    name: "WorkspaceOwner"
    when: windowShown
    function clone(value) { return JSON.parse(JSON.stringify(value)) }
    function file() {
      for (var i=0;i<host.owner.children.length;i++)
        if (host.owner.children[i].path !== undefined) return host.owner.children[i]
      fail("owner FileView missing")
    }
    function initialWindows() {
      return [1,2,3,4].map(function(id) { return {address:"0x"+id,pid:id,initialClass:"test",
        monitor:"A",workspace:{id:id,name:String(id)}} })
    }
    function init() {
      host.operation="idle"; host.generation=0; host.station=3
      host.target={outputs:["A","B"]}; host.clients=initialWindows()
      host.originalBaseline=null; host.error=""; host.grace=false; host.jobs=[]; host.trace=[]
      host.expected={}; host.commits=0; host.finishes=0; host.reverts=0; host.readyCount=0
      host.rejectRules=false; host.rejectMoves=false; host.falseMoves=false; host.previewBusy=true
      host.owner=factory.createObject(host)
      verify(host.owner !== null)
      file().readText=JSON.stringify({mapping:{outputs:["A"]},pending:null})
      file().loaded()
      verify(host.owner.mappingLoaded); compare(host.readyCount,1)
    }
    function cleanup() { host.owner.destroy(); host.owner=null; host.jobs=[]; wait(0) }
    function step() {
      verify(host.jobs.length>0)
      var job=host.jobs.shift()
      if (job.kind === "refresh") { job.done(); return }
      var rules=job.lua.indexOf("hl.workspace_rule") >= 0
      if (!(rules ? host.rejectRules : host.rejectMoves)) {
        var windows=clone(host.clients), match
        var moves=/window = "address:(0x[0-9a-f]+)", workspace = (\d+), follow = false/g
        while ((match=moves.exec(job.lua)) !== null) {
          var row=windows.find(function(c) { return c.address === match[1] })
          if (row) row.workspace={id:Number(match[2]),name:match[2]}
        }
        var placements=/workspace\.move\(\{ workspace = (\d+), monitor = "([ABC])"/g
        while ((match=placements.exec(job.lua)) !== null)
          windows.filter(function(c) { return c.workspace.id === Number(match[1]) })
            .forEach(function(c) { c.monitor=match[2] })
        host.clients=windows
      }
      if (job.done) job.done((rules ? host.rejectRules : host.rejectMoves || host.falseMoves) ? 1 : 0,"ok")
    }
    function drain() { var n=0; while (host.jobs.length) { verify(++n<100); step() } }
    function journal() { host.owner.reconcile(); drain(); compare(host.owner.migrationPhase,"journal") }
    function move() { file().saved(); drain(); compare(host.owner.migrationPhase,"commit") }
    function test_delayed_journal_and_commit_acks_gate_effects_and_publication() {
      journal()
      compare(file().writes.length,1); compare(host.jobs.length,0)
      compare(host.trace.join(","),"begin,assignments,target")
      compare(host.owner.snapshot.mapping.outputs.join(","),"A")
      move()
      compare(host.clients.map(function(c) { return c.workspace.id }).join(","),"1,3,5,7")
      compare(host.owner.snapshot.mapping.outputs.join(","),"A")
      compare(host.commits,0); compare(host.owner.snapshot.pending.windows[1].station,2)
      file().saved(); drain()
      compare(host.owner.snapshot.mapping.outputs.join(","),"A,B")
      compare(host.owner.snapshot.pending,null); compare(host.commits,1)
      compare(host.operation,"idle"); compare(host.generation,1)
      verify(host.trace.indexOf("expect")<host.trace.indexOf("eval"))
    }
    function test_failed_commit_retries_by_identity_after_real_timer() {
      journal(); move(); file().saveFailed()
      compare(host.owner.snapshot.mapping.outputs.join(","),"A")
      compare(host.owner.migrationAttempts,1)
      tryVerify(function() { return host.jobs.length>0 },1000)
      drain(); compare(file().writes.length,3)
      var retry=JSON.parse(file().writes[2])
      compare(retry.pending.windows.map(function(c) { return c.station }).join(","),"1,2,3,4")
      verify(retry.revision>JSON.parse(file().writes[0]).revision)
      move(); file().saved(); drain()
      compare(host.owner.migrationAttempts,0); compare(host.owner.snapshot.pending,null)
    }
    function test_failed_journal_and_retry_exhaustion_reverts_enclosing_preview() {
      host.operation="previewing"; host.generation=42
      host.originalBaseline=Grid.plan(host.owner.workspaceMap,host.owner.workspaceMap,host.clients,3)
      journal()
      for (var i=0;i<4;i++) {
        compare(host.jobs.length,0); file().saveFailed()
        compare(host.owner.snapshot.mapping.outputs.join(","),"A")
        if (i<3) { tryVerify(function() { return host.jobs.length>0 },1000); drain() }
      }
      compare(host.owner.migrationAttempts,4); compare(host.reverts,1)
      verify(!host.previewBusy); compare(host.generation,42)
      verify(host.trace.indexOf("eval")<0)
    }
    function test_superseding_topology_and_fresh_target_after_delayed_snapshot() {
      host.owner.reconcile(); host.target={outputs:["B"]}; drain()
      compare(JSON.parse(file().writes[0]).pending.to.outputs.join(","),"B")
      file().saved(); step() // rules completion; moves still queued
      host.target={outputs:["A","B"]}; host.owner.markTopologyDirty(); drain()
      compare(host.owner.migrationPhase,"journal"); compare(host.commits,0)
      compare(host.owner.snapshot.mapping.outputs.join(","),"A")
      compare(JSON.parse(file().writes[1]).pending.windows[1].station,2)
      move(); file().saved(); drain()
      compare(host.owner.snapshot.mapping.outputs.join(","),"A,B")
      host.owner.markTopologyDirty(); verify(host.owner.topologyDirty)
      host.owner.clearTopologyDirty(); verify(!host.owner.topologyDirty)
    }
    function test_restart_partial_move_restores_preview_and_detached_journal() {
      host.operation="previewing"; host.generation=42
      host.originalBaseline=Grid.plan(host.owner.workspaceMap,host.owner.workspaceMap,host.clients,3)
      var original=clone(host.originalBaseline)
      journal(); var saved=file().writes[0]
      host.owner.destroy(); wait(0); host.owner=factory.createObject(host)
      file().readText=saved; file().loaded()
      compare(JSON.stringify(host.originalBaseline),JSON.stringify(original))
      var windows=clone(host.clients); windows[1].workspace={id:3,name:"3"}; host.clients=windows
      journal(); move(); file().saved(); drain()
      compare(host.generation,42); compare(host.operation,"previewing"); compare(host.finishes,1)
      compare(JSON.stringify(host.originalBaseline),JSON.stringify(original))
      host.owner.workspaceData.preview.windows[0].station=9
      compare(host.originalBaseline.windows[0].station,1)
      var snapshot=host.owner.snapshot
      snapshot.mapping.outputs.push("C")
      compare(host.owner.workspaceMap.outputs.join(","),"A,B")
    }
    function test_late_callback_after_operation_change_preserves_current_policy() {
      host.operation="previewing"; host.generation=42
      host.originalBaseline=Grid.plan(host.owner.workspaceMap,host.owner.workspaceMap,host.clients,3)
      journal(); file().saved(); compare(host.owner.migrationPhase,"moving")
      // Match abandonPreview while migration is still moving. The already
      // running callback still completes through the existing journal protocol.
      host.generation=43; host.operation="migrating"
      drain(); compare(host.owner.migrationPhase,"commit")
      compare(host.owner.snapshot.mapping.outputs.join(","),"A")
      file().saved(); drain()
      compare(host.generation,43); compare(host.owner.snapshot.pending,null)
      compare(host.finishes,0); compare(host.originalBaseline,null)
      compare(host.owner.snapshot.mapping.outputs.join(","),"A,B")
    }
    function test_failed_rules_moves_and_verified_aggregate_false() {
      journal(); host.rejectRules=true; file().saved(); drain()
      compare(host.owner.migrationPhase,""); compare(file().writes.length,1)
      host.rejectRules=false; host.owner.reconcile(); drain()
      host.rejectMoves=true; file().saved(); drain()
      compare(host.owner.migrationPhase,""); verify(host.owner.workspaceData.pending !== null)
      host.rejectMoves=false; host.falseMoves=true; host.owner.reconcile(); drain()
      move(); file().saved(); drain()
      compare(host.owner.workspaceData.pending,null)
    }
    function test_load_validation_reload_and_grace_gates() {
      host.owner.destroy(); wait(0); host.owner=factory.createObject(host)
      host.readyCount=0
      file().readText="{"; file().loaded()
      verify(!host.owner.mappingLoaded); compare(host.readyCount,0)
      verify(host.error.indexOf("saved workspace mapping")>=0)
      file().loadFailed(); verify(host.owner.mappingLoaded); compare(host.readyCount,1)
      host.owner.reload(); compare(file().reloads,1)
      host.grace=true; host.owner.reconcile(); compare(host.jobs.length,0)
      host.grace=false; host.operation="applyingLayout"
      host.owner.reconcile(); compare(host.jobs.length,0)
    }
  }
}

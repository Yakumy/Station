import QtQuick
import Quickshell
import "Probe" as Station

ShellRoot {
  id: host
  property string directory: __TEMP_DIRECTORY__
  property string operation: "idle"
  property int station: 3
  property var clients: [1,2,3,4].map(function(id) { return {address:"0x"+id,pid:id,
    initialClass:"test",monitor:"A",workspace:{id:id,name:String(id)}} })
  property var originalBaseline: null
  property string error: ""
  property int readyCount: 0
  property int commits: 0
  property int evals: 0
  property int savedCount: 0
  property int failedCount: 0
  property var valid: null
  property var invalid: null
  property var missing: null
  property var failed: null
  property var validFile: null
  property var failedFile: null
  property int stage: 0
  property int ticks: 0
  property int unchangedStart: 0
  property bool invalidSeen: false
  property bool sourceRestored: false
  property bool saveBeforeDispatch: false
  property bool pendingAtDispatch: false
  property bool failureRetained: false

  function check(condition,message) {
    if (!condition) { console.error("WORKSPACE_FILEVIEW_FAIL: "+message); Qt.exit(1) }
  }
  function journalFile(object) {
    for (var i=0;i<object.data.length;i++)
      if (object.data[i].path !== undefined) return object.data[i]
    throw new Error("missing real FileView")
  }
  Component {
    id: factory
    Station.WorkspaceController {
      operationState: host.operation
      currentStation: host.station
      clients: host.clients
      lanes: ({A:1,B:2})
      previewBaseline: host.originalBaseline
      layoutError: host.error
      targetMapping: function() { return {outputs:["A","B"]} }
      refresh: function(include,done) { Qt.callLater(done) }
      updateAssignments: function() {}
      focusedClient: function() { return null }
      beginMigration: function() { host.operation="migrating" }
      setOperationState: function(value) { host.operation=value }
      evalLua: function(lua,done) {
        host.evals++
        host.pendingAtDispatch=host.valid.snapshot.pending !== null
        // The production onSaved handler can run before our signal observer.
        // Defer fake compositor completion so every signal observer has run.
        Qt.callLater(function() {
          host.check(host.savedCount>=1,"dispatch must follow a real journal saved signal")
          host.saveBeforeDispatch=true
          var windows=JSON.parse(JSON.stringify(host.clients)),match
          var moves=/window = "address:(0x[0-9a-f]+)", workspace = (\d+), follow = false/g
          while ((match=moves.exec(lua)) !== null) {
            var row=windows.find(function(c) { return c.address === match[1] })
            if (row) row.workspace={id:Number(match[2]),name:match[2]}
          }
          host.clients=windows
          if (done) done(0,"ok")
        })
      }
      recordExpectedEvents: function(value) {}
      reportError: function(value) {
        host.error=value
        if (value === "Could not read the saved workspace mapping.") host.invalidSeen=true
      }
      setCurrentStation: function(value) { host.station=value }
      commitMigrationState: function(value) { host.commits++ }
      restorePreviewBaseline: function(value) {
        host.originalBaseline=value
        if (value && value.windows.length === 4) host.sourceRestored=true
      }
      finishPreviewApply: function() {}
      failPreview: function(message) { host.check(false,"unexpected preview failure") }
      focusStatements: function(station,output) { return [] }
      showStation: function(value) {}
      ready: function() { host.readyCount++ }
    }
  }
  Component.onCompleted: {
    // One window already moved before the previous process stopped.
    var windows=JSON.parse(JSON.stringify(clients))
    windows[1].workspace={id:3,name:"3"}; clients=windows
    valid=factory.createObject(host,{stateDir:directory+"/valid"})
    invalid=factory.createObject(host,{stateDir:directory+"/invalid"})
    missing=factory.createObject(host,{stateDir:directory+"/missing"})
    failed=factory.createObject(host,{stateDir:directory+"/failure"})
    validFile=journalFile(valid); failedFile=journalFile(failed)
    validFile.saved.connect(function() { host.savedCount++ })
    failedFile.saveFailed.connect(function() { host.failedCount++ })
  }
  Timer {
    interval: 10; running: true; repeat: true
    onTriggered: {
      host.ticks++
      host.check(host.ticks<800,"timeout at stage "+host.stage)
      if (host.stage === 0) {
        if (!host.valid.mappingLoaded || !host.missing.mappingLoaded || !host.failed.mappingLoaded || !host.invalidSeen) return
        host.check(!host.invalid.mappingLoaded,"invalid journal must not unlock startup")
        host.check(host.readyCount===3,"valid, missing and failed loads each notify readiness once")
        host.check(host.missing.workspaceMap===null,"missing journal retains default mapping")
        host.check(host.sourceRestored,"loaded preview baseline restored through finite port")
        host.valid.reload()
        host.valid.reconcile(); host.stage=1
      } else if (host.stage === 1) {
        if (host.commits !== 1 || host.savedCount !== 2) return
        host.check(host.saveBeforeDispatch && host.pendingAtDispatch,"journal must gate real dispatch boundary")
        host.check(host.valid.snapshot.mapping.outputs.join(",")==="A,B","committed map")
        host.check(host.valid.snapshot.pending===null,"pending cleared after commit saved")
        host.check(host.valid.workspaceData.revision===9,"two protocol revisions from initial 7")
        host.check(host.originalBaseline===null,"ordinary commit clears root preview baseline")
        host.check(host.clients.map(function(c) { return c.workspace.id }).join(",")==="1,3,5,7","fake destinations")
        host.validFile.setText(host.validFile.text())
        host.unchangedStart=host.ticks; host.stage=2
      } else if (host.stage === 2) {
        if (host.ticks-host.unchangedStart<15) return
        host.check(host.savedCount===2,"identical text must not synthesize saved")
        var next=JSON.parse(host.validFile.text()); next.revision++
        host.validFile.setText(JSON.stringify(next,null,2)+"\n"); host.stage=3
      } else if (host.stage === 3) {
        if (host.savedCount !== 3) return
        host.check(host.commits===1,"unrelated saved signal in idle must not commit again")
        host.failed.reconcile(); host.stage=4
      } else if (host.stage === 4) {
        if (host.failedCount<1) return
        host.check(host.failed.workspaceData.pending !== null,"failed save retains recovery identities")
        host.check(host.failed.workspaceMap.outputs.join(",")==="A,B","failed save retains original staged map")
        host.check(host.failed.migrationAttempts===1,"failure routed once")
        host.check(host.evals===2,"failed journal dispatches no effects")
        console.log("WORKSPACE_FILEVIEW_PASS: load, invalid/missing, saved/failed, identical text, revisions")
        Qt.quit()
      }
    }
  }
}

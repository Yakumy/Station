import QtQuick
import Quickshell
import "Probe" as Station

ShellRoot {
  id: host
  property string directory: __TEMP_DIRECTORY__
  property string operation: "idle"
  property string error: ""
  property int readyCount: 0
  property int candidateSaves: 0
  property int plainSaves: 0
  property int failedSaves: 0
  property int stage: 0
  property int ticks: 0
  property var owner: null
  property var candidate: null
  property var plain: null
  property var transaction: null
  function check(value,message) {if(!value){console.error("DISPLAY_FILEVIEW_FAIL: "+message);Qt.exit(1)}}
  function file(object,suffix) {
    for(var i=0;i<object.data.length;i++)
      if(object.data[i].path!==undefined && object.data[i].path.endsWith(suffix))return object.data[i]
    throw new Error("missing FileView "+suffix)
  }
  function process(object) {
    for(var i=0;i<object.data.length;i++)
      if(object.data[i].command!==undefined && object.data[i].command[0]==="sh")return object.data[i]
    throw new Error("missing fake process")
  }
  Component {
    id: factory
    Station.DisplayController {
      stateDir: host.directory+"/state"
      monitorsPath: host.directory+"/monitors.lua"
      internalDisablePath: host.directory+"/missing-toggle.lua"
      candidatePath: host.directory+"/state/monitors.lua.candidate"
      plainCandidatePath: host.directory+"/state/monitors-block.plain.lua.candidate"
      plainPath: host.directory+"/state/monitors-block.plain.lua"
      operationState: host.operation
      started: true
      preferences: ({enabled:["A","B"],mode:"extend",singleTarget:"",mirrorSource:""})
      monitors: ["A","B"].map(function(name,i){return {name:name,width:1920,height:1080,
        refreshRate:60,availableModes:["1920x1080@60.00Hz"],x:i*1920,y:0,scale:1,transform:0}})
      lanes: ({A:1,B:2})
      workspaceMap: ({outputs:["A","B"]})
      layoutError: host.error
      setOperationState: function(value){host.operation=value}
      retainPanel: function(screen,until){}
      stopTopologyTimers: function(){}
      clearPanelEvacuation: function(){}
      reportError: function(value){host.error=value}
      ready: function(){host.readyCount++}
      refresh: function(include,done){Qt.callLater(done)}
      invalidateAppliedBinds: function(){}
      applyRuntime: function(){}
      armScreenHealthCheck: function(){}
      enqueue: function(args,done){host.check(false,"unexpected queue effect")}
      launchWatchdog: function(){host.check(false,"side control armed a watchdog")}
    }
  }
  Component.onCompleted: {
    owner=factory.createObject(host)
    candidate=file(owner,"monitors.lua.candidate");plain=file(owner,"monitors-block.plain.lua.candidate")
    transaction=process(owner)
    candidate.saved.connect(function(){host.candidateSaves++})
    plain.saved.connect(function(){host.plainSaves++})
  }
  Timer {
    interval:10;repeat:true;running:true
    onTriggered: {
      host.ticks++;host.check(host.ticks<800,"timeout at stage "+host.stage)
      if(host.stage===0) {
        if(!host.owner.monitorsLoaded || !host.owner.previewLoaded)return
        host.check(!host.owner.previewFound,"missing token must load as absent")
        host.check(host.owner.internalDisableSource==="","missing toggle remains absent")
        console.log("DISPLAY_EDIT_SOURCE");host.stage=1
      } else if(host.stage===1) {
        if(host.owner.monitorsSource!=="-- newer personal source\n")return
        host.check(host.owner.applyDisplaySetting("A","scale",2)==="started","direct setting must start")
        host.stage=2
      } else if(host.stage===2) {
        if(!host.transaction.running)return
        host.check(host.owner.candidateReady && host.owner.plainCandidateReady,"both real save barriers")
        host.check(host.candidateSaves===1 && host.plainSaves===1,"one real saved per candidate")
        host.check(host.transaction.command[9]==="-- newer personal source\n","watched source captured")
        host.transaction.stderr.text=" stderr fixture ";host.transaction.stderr.streamFinished()
        host.transaction.finish(4);host.stage=3
      } else if(host.stage===3) {
        if(host.operation!=="idle")return
        host.check(host.error.indexOf("newer edits were preserved")>=0,"exit callback delivered")
        host.check(host.owner.applyDisplaySetting("A","scale",2)==="started","identical retry")
        host.check(host.transaction.running,"identical text already ready without another saved")
        host.check(host.candidateSaves===1 && host.plainSaves===1,"no synthetic acknowledgment")
        host.transaction.finish(4);host.stage=4
      } else if(host.stage===4) {
        if(host.operation!=="idle")return
        host.owner.destroy()
        host.owner=factory.createObject(host,{candidatePath:host.directory+"/blocked.candidate",
          plainCandidatePath:host.directory+"/state/failure.plain.candidate"})
        host.transaction=host.process(host.owner)
        host.file(host.owner,"blocked.candidate").saveFailed.connect(function(){host.failedSaves++})
        host.stage=5
      } else if(host.stage===5) {
        if(!host.owner.monitorsLoaded)return
        host.check(host.owner.applyDisplaySetting("A","scale",2)==="started","failed candidate scenario starts")
        host.stage=6
      } else if(host.stage===6) {
        if(host.failedSaves<1 || host.operation!=="idle")return
        host.check(!host.transaction.running,"failure cannot launch transaction")
        console.log("DISPLAY_FILEVIEW_PASS: watch/load, dual saves, identical retry, save failure")
        Qt.quit()
      }
    }
  }
}

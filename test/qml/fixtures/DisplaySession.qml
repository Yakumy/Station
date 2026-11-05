import QtQuick
import Quickshell
import "Probe/stations" as Stations
import "Probe/displays" as Displays
import "Probe/displays/Model.js" as Model
import "Probe/stations/Grid.js" as Grid
import "Probe/displays/MonitorsLua.js" as MonitorsLua
import "Probe/platform/Transactions.js" as Transactions
import "Probe/platform/Store.js" as Store
import "Probe/platform/Events.js" as Events

Item {
  id: root
  state: "idle"
  property alias displayOwner: displayController
  property alias workspaceOwner: workspace
  property var config: Store.configDefaults()
  property var persisted: Store.stateDefaults()
  property var monitors: []
  property var removalGraceRunning: removalGrace.running
  property var clients: []
  property var lanes: ({A:1,B:2})
  property var unmanaged: []
  property int currentStation: 2
  property int gen: 0
  property int queuedStation: 0
  property int configGeneration: 0
  property int appliedGeneration: 0
  property bool started: true
  property bool windowSettingsBusy: false
  property string layoutError: ""
  property string observedMonitorSignature: ""
  property var expect: ({kinds:[],outputs:[],until:0})
  property double lastTopologyMs: 0
  property bool panelWanted: true
  property string panelScreenName: "B"
  property double panelTransferUntil: 0
  property int panelEvacuationSerial: 0
  property int panelEvacuationWaiting: 0
  property string panelEvacuationFrom: ""
  property string panelEvacuationTo: ""
  property string panelEvacuationPurpose: ""
  property string stateDir: "/isolated"
  property string monitorsPath: "/isolated/monitors.lua"
  property string internalDisablePath: "/isolated/internal-monitor-disable.lua"
  property string candidatePath: "/isolated/monitors.lua.candidate"
  property string plainCandidatePath: "/isolated/monitors-block.plain.lua.candidate"
  property string plainPath: "/isolated/monitors-block.plain.lua"
  property var jobs: []
  property var effects: []
  property int saves: 0
  property int stateSaves: 0
  property int readiness: 0
  property int healthChecks: 0
  property int bindCalls: 0
  property int authorityCalls: 0
  property bool snapshotBusy: false
  property var snapshotQueue: []
  property var refreshDone: null
  property bool refreshClientsToo: true
  property var live: []
  property var windows: []
  property var initialMonitors: []
  property bool rejectNext: false
  property bool rejectSnapshots: false

  // INSERT_COMPOSITION
  // INSERT_PROJECTIONS
  // INSERT_ROOT_FUNCTIONS
  // INSERT_BARRIER_TIMER

  Timer { id: removalGrace; interval: 5000 }
  Timer { id: reloadDebounce; interval: 300 }
  Timer { id: followFocus; interval: 100 }
  QtObject { id: monitorSnapshot; property bool running: false }
  function copy(value) { return JSON.parse(JSON.stringify(value)) }
  readonly property string operationState: root.state
  function snapshotFailed() { handleSnapshotFailure() }
  function clearQueued() { queuedStation = 0 }
  function followFocusChanged() { followFocus.restart() }
  function invalidate() { appliedGeneration = -1 }
  function continueApply() { displayController.continuePreviewApply() }
  function continueRevert() { displayController.continueRevertPreview() }
  function panelEvacuationTimedOut() { displayController.panelEvacuationTimedOut(panelEvacuationPurpose, panelEvacuationFrom) }
  function saveConfig() { saves++ }
  function saveState() { stateSaves++ }
  function maybeStart() { readiness++ }
  function finishAuthorityMigration(done,required) { authorityCalls++; if (done) done() }
  function applyBinds() { bindCalls++ }
  function armScreenHealthCheck() { healthChecks++ }
  function refreshWindowSettings() {}
  function syncBarBlur() {}
  function focusedClient() { return clients[2] || null }
  function stationFocusStatements(station,output) { return [] }
  function showStation(station) { effects.push("show:"+station) }
  function refresh(include,done) { jobs.push({kind:"snapshot",done:done}) }
  function enqueue(args,done,generation) { jobs.push({kind:"command",args:args,done:done,generation:generation}) }
  function evalLua(lua,done) {
    if (!String(lua || "").trim()) { if (done) done(0,""); return }
    enqueue(["hyprctl","eval",lua],done,configGeneration)
  }
  function file(owner,suffix) {
    for (var i=0;i<owner.data.length;i++)
      if (owner.data[i].path !== undefined && owner.data[i].path.endsWith(suffix)) return owner.data[i]
    throw new Error("missing file "+suffix)
  }
  function process(owner,command) {
    for (var i=0;i<owner.data.length;i++)
      if (owner.data[i].command !== undefined && owner.data[i].command[0] === command) return owner.data[i]
    throw new Error("missing process "+command)
  }
  function initialize(names,recovery) {
    names=names || ["A","B"]
    lanes={};lanes[names[0]]=1;lanes[names[1]]=2
    config=Object.assign(Store.configDefaults(),{enabled:names})
    live=names.map(function(name,i) { return {name:name,id:i,disabled:false,mirrorOf:"none",
      width:1920,height:1080,refreshRate:60,availableModes:["1920x1080@60.00Hz"],
      x:i*1920,y:0,scale:1,transform:0,focused:i===0} })
    initialMonitors=copy(live); monitors=copy(live)
    windows=[1,2,3,4].map(function(id) { return {address:"0x"+id,pid:id,initialClass:"test",
      monitor:id%2 ? names[0]:names[1],workspace:{id:id,name:String(id)},focusHistoryID:id===3?0:id} })
    clients=copy(windows)
    if(recovery) {windows=copy(recovery.windows);clients=copy(windows)}
    file(workspace,"workspace-map.json").readText=recovery ? recovery.journal : JSON.stringify({mapping:{outputs:names},pending:null,revision:0})
    file(workspace,"workspace-map.json").loaded()
    file(displayController,"monitors.lua").readText="-- personal Lua\n"
    file(displayController,"monitors.lua").loaded()
    file(displayController,"preview.token").loadFailed()
    displayController.syncDisplayDraft()
  }
  function apply(lua) {
    var next=copy(live),wins=copy(windows),match
    var focus=lua.match(/hl\.dsp\.focus\(\{ monitor = "([A-Za-z0-9_.:-]+)"/)
    if (focus) { next.forEach(function(m) { m.focused=m.name===focus[1] }); effects.push("focus:"+focus[1]) }
    var rules=/hl\.monitor\(\{ ([^}]+) \}\)/g
    while ((match=rules.exec(lua)) !== null) {
      var fields=match[1],name=fields.match(/output = "([A-Za-z0-9_.:-]+)"/)[1]
      var m=next.find(function(row) { return row.name===name })
      var disabled=fields.match(/disabled = (true|false)/),mirror=fields.match(/mirror = "([^"]*)"/)
      if (disabled) m.disabled=disabled[1]==="true"
      if (mirror) m.mirrorOf=mirror[1] || "none"
      var scale=fields.match(/scale = ([0-9.]+)/),position=fields.match(/position = "(-?\d+)x(-?\d+)"/)
      if (scale) m.scale=Number(scale[1])
      if (position) {m.x=Number(position[1]);m.y=Number(position[2])}
      effects.push("monitor:"+name+":"+(m.disabled?"off":"on"))
      if (!next.some(function(row) {return !row.disabled && row.mirrorOf==="none"})) throw new Error("zero real outputs")
      if (m.disabled || m.mirrorOf!=="none") {
        var survivor=next.find(function(row) {return !row.disabled && row.mirrorOf==="none"})
        wins.filter(function(w) {return w.monitor===name}).forEach(function(w) {w.monitor=survivor.name})
      }
    }
    var moves=/window = "address:(0x[0-9a-f]+)", workspace = (\d+), follow = false/g
    while ((match=moves.exec(lua))!==null) {
      var w=wins.find(function(row) {return row.address===match[1]})
      if (w) w.workspace={id:Number(match[2]),name:match[2]}
    }
    var placements=/workspace\.move\(\{ workspace = (\d+), monitor = "([A-Za-z0-9_.:-]+)"/g
    while ((match=placements.exec(lua))!==null) {
      wins.filter(function(w) {return w.workspace.id===Number(match[1])}).forEach(function(w) {w.monitor=match[2]})
      effects.push("workspace:"+match[1]+":"+match[2])
    }
    live=next; windows=wins
  }
  function step() {
    if (jobs.length) {
      var job=jobs.shift()
      if (job.kind==="snapshot") {
        if (rejectSnapshots) {
          refreshDone=job.done; completeSnapshot(1)
        } else {monitors=copy(live);clients=copy(windows);if(job.done)job.done()}
      } else if (job.generation!==undefined && job.generation!==configGeneration) {
        if(job.done)job.done(1,"Configuration changed before applying the command.")
      } else if (rejectNext) {
        rejectNext=false;if(job.done)job.done(1,"injected rejection")
      } else {
        if (job.args[0]==="hyprctl" && job.args[1]==="eval") apply(job.args[2])
        if (job.args.join(" ")==="hyprctl reload") {effects.push("reload");live=copy(initialMonitors)}
        if(job.done)job.done(0,"ok")
      }
      return true
    }
    var journal=file(workspace,"workspace-map.json")
    if(journal.pendingWrites) {journal.ack();return true}
    var arm=process(displayController,"touch")
    if(arm.running) {arm.finish(0);return true}
    return false
  }
  function drain() { var n=0;while(step())if(++n>200)throw new Error("non-convergent") }
  function closePanel() {effects.push("closed:"+panelEvacuationFrom);acknowledgePanelEvacuation(panelEvacuationWaiting,panelEvacuationFrom)}
  function stablePreview(mode,target) {
    var result=displayController.setModeValue(mode,target || "")
    drain();if(panelEvacuationWaiting)closePanel();drain();return result
  }
  function settleKeep(code,message) {
    var proc=process(displayController,"sh")
    if (!code) {
      var options=displayController.keepOptions
      var displays=displayController.pendingDisplayConfig ? displayController.pendingDisplayConfig.displays : displayDraft
      var states=MonitorsLua.runtimeModeStates(displays,options)
      live=live.map(function(m) {
        var d=states.find(function(d){return d.name===m.name})
        var geometry=displays.find(function(d){return d.name===m.name})
        return Object.assign({},m,{disabled:d.disabled,mirrorOf:d.mirror || "none",
          scale:geometry.scale,x:geometry.x,y:geometry.y,transform:geometry.transform})
      })
      file(displayController,"monitors.lua").readText=file(displayController,"monitors.lua.candidate").text()
    }
    proc.stderr.text=message || "";proc.stderr.streamFinished();proc.finish(code);drain()
  }
}

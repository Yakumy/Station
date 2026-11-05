import QtQuick
import QtTest
import Quickshell

Item {
  id: host
  width: 1; height: 1
  property var session: null
  Component { id: factory; DisplaySession {} }
  TestCase {
    name: "DisplayOwner"
    when: windowShown
    function init() {session=factory.createObject(host);verify(session!==null);session.initialize();Quickshell.launches=[]}
    function cleanup() {if(session)session.destroy();session=null;wait(0)}
    function reset(names) {cleanup();session=factory.createObject(host);session.initialize(names);Quickshell.launches=[]}
    function owner() {return session.displayOwner}
    function file(suffix) {return session.file(owner(),suffix)}
    function proc(command) {return session.process(owner(),command)}
    function preview(mode,target) {compare(session.stablePreview(mode || "single",target || "A"),"started");verify(!session.previewBusy)}
    function revert() {compare(session.revertPreview(""),"started");session.drain();if(session.panelEvacuationWaiting)session.closePanel();session.drain()}
    function acknowledgeCandidates(reverse) {
      file(reverse?"monitors-block.plain.lua.candidate":"monitors.lua.candidate").ack()
      verify(!proc("sh").running)
      file(reverse?"monitors.lua.candidate":"monitors-block.plain.lua.candidate").ack()
      verify(proc("sh").running)
    }
    function test_root_barrier_and_journal_acks_precede_moves() {
      compare(session.setModeValue("single","A"),"started");session.drain()
      verify(session.panelEvacuationWaiting>0);compare(session.effects.length,0)
      var serial=session.panelEvacuationWaiting
      session.acknowledgePanelEvacuation(serial-1,"B")
      session.acknowledgePanelEvacuation(serial,"A")
      compare(session.panelEvacuationWaiting,serial);compare(session.effects.length,0)
      session.closePanel()
      var limit=100
      while(session.migrationPhase!=="journal" && --limit)verify(session.step())
      verify(limit>0);compare(session.workspaceMap.outputs.join(","),"A,B")
      verify(!session.effects.some(function(e){return e.startsWith("workspace:")}))
      session.drain();compare(session.workspaceMap.outputs.join(","),"A")
      compare(session.state,"previewing");compare(session.gen,1);compare(session.previewSeconds,12)
      verify(!session.previewBusy);compare(Quickshell.launches.length,2)
      verify(session.effects.indexOf("closed:B")<session.effects.indexOf("monitor:B:off"))
    }
    function test_disabled_destination_migrates_before_old_output_removal() {
      session.live=session.live.map(function(m){return Object.assign({},m,{disabled:m.name==="B"})})
      session.monitors=session.copy(session.live);session.applyRuntime();session.drain()
      session.panelScreenName="A";session.effects=[];preview("single","B")
      var enabled=session.effects.indexOf("monitor:B:on"),focused=session.effects.indexOf("focus:B")
      var moved=session.effects.findIndex(function(e){return e.startsWith("workspace:")&&e.endsWith(":B")})
      var disabled=session.effects.indexOf("monitor:A:off")
      verify(enabled>=0 && enabled<focused && focused<moved && moved<disabled)
      compare(session.panelScreenName,"B");compare(session.workspaceMap.outputs.join(","),"B")
    }
    function test_both_mirror_sources_revert_and_reedit_keep_original_identities() {
      preview("mirror","");compare(session.workspaceMap.outputs.join(","),"A")
      var original=JSON.stringify(session.previewBaseline)
      var windows=session.copy(session.windows)
      windows.push({address:"0x9",pid:9,initialClass:"new",monitor:"A",workspace:{id:3,name:"3"}})
      session.windows=windows
      preview("single","B");compare(JSON.stringify(session.previewBaseline),original)
      revert();compare(session.state,"idle");compare(session.workspaceMap.outputs.join(","),"A,B")
      compare(session.windows.slice(0,4).map(function(w){return w.workspace.id}).join(","),"1,2,3,4")
      compare(session.swapRole("B",0),"started");session.drain()
      preview("mirror","");compare(session.workspaceMap.outputs.join(","),"B")
      revert();compare(session.state,"idle")
    }
    function test_candidate_orders_and_late_signals_data() {return [{tag:"candidate-first",reverse:false},{tag:"plain-first",reverse:true}]}
    function test_candidate_orders_and_late_signals(data) {
      preview();compare(session.keepPreview(),"started");verify(!proc("sh").running)
      acknowledgeCandidates(data.reverse)
      var args=proc("sh").command
      compare(args.length,12);compare(args[4],session.candidatePath);compare(args[7],session.plainPath)
      compare(args[9],"-- personal Lua\n");compare(args[11],"")
      session.settleKeep(0,"")
      compare(session.state,"idle");compare(session.previewBaseline,null)
      compare(session.config.mode,"single");compare(session.config.singleTarget,"A")
      verify(!proc("sh").running);file("monitors.lua.candidate").saved();file("monitors-block.plain.lua.candidate").saved()
      verify(!proc("sh").running);verify(session.healthChecks>0)
    }
    function test_identical_candidates_and_direct_side_control_do_not_arm_preview() {
      compare(session.applyDisplaySetting("A","scale",1),"ok")
      compare(file("monitors.lua.candidate").writes.length,0)
      compare(session.applyDisplaySetting("A","scale",2),"started")
      compare(session.state,"applyingLayout");compare(session.layoutWriteKind,"control")
      compare(Quickshell.launches.length,0);verify(!proc("touch").running)
      acknowledgeCandidates(false);session.settleKeep(0,"")
      compare(session.state,"idle");compare(session.displayDraft[0].scale,2)
      compare(session.effects.filter(function(e){return e==="reload"}).length,0)
      // A later attempt with identical candidates already satisfies both barriers.
      var text=file("monitors.lua.candidate").text(),plain=file("monitors-block.plain.lua.candidate").text()
      owner().startKeepFiles(text,plain,"direct")
      verify(proc("sh").running);compare(file("monitors.lua.candidate").writes.length,1)
    }
    function test_internal_toggle_only_at_explicit_keep() {
      reset(["eDP-1","HDMI-A-2"]);session.panelScreenName="HDMI-A-2"
      var flag='hl.monitor({ output = "eDP-1", disabled = true })\n'
      file("internal-monitor-disable.lua").readText=flag;file("internal-monitor-disable.lua").loaded()
      preview("single","eDP-1");compare(session.keepDisableToggle,"")
      compare(session.keepPreview(),"started");compare(session.keepDisableToggle,flag)
      acknowledgeCandidates(false);compare(proc("sh").command[11],flag)
      session.settleKeep(0,"");compare(session.state,"idle")
      compare(session.applyDisplaySetting("eDP-1","scale",2),"started")
      compare(session.keepDisableToggle,"")
    }
    function test_candidate_and_process_failure_callbacks_data() {return [
      {tag:"candidate",code:2},{tag:"configerrors",code:3},{tag:"source-conflict",code:4}]}
    function test_candidate_and_process_failure_callbacks(data) {
      preview();session.keepPreview()
      if(data.code===2) {file("monitors.lua.candidate").fail();verify(!proc("sh").running)}
      else {
        acknowledgeCandidates(false);session.live=session.copy(session.initialMonitors)
        file("monitors.lua").readText="-- newer source preserved\n"
        session.settleKeep(data.code," injected error ")
        if(data.code===3)verify(session.layoutError.indexOf("injected error")>=0)
        if(data.code===4)verify(session.layoutError.indexOf("newer edits were preserved")>=0)
      }
      session.drain();compare(session.state,"idle")
      verify(session.layoutError.length>0);compare(session.previewBaseline,null)
    }
    function test_arm_and_snapshot_failures_route_through_owner() {
      session.setModeValue("single","A");verify(proc("touch").running)
      proc("touch").finish(1);compare(session.state,"idle");verify(!session.previewBusy)
      compare(session.effects.length,0);verify(session.layoutError.indexOf("arm preview recovery")>=0)
      reset();session.setModeValue("single","A");session.rejectSnapshots=true;session.drain()
      verify(session.panelEvacuationWaiting>0);compare(session.effects.length,0)
      session.rejectSnapshots=false;session.closePanel();session.drain()
      compare(session.state,"idle");verify(session.layoutError.indexOf("Could not read the display state")>=0)
    }
    function test_focus_activation_and_token_renewal_failures_data() {return [
      {tag:"focus",phase:"focus"},{tag:"activation",phase:"activation"},{tag:"token",phase:"token"}]}
    function test_focus_activation_and_token_renewal_failures(data) {
      if(data.phase==="activation") {
        session.live=session.live.map(function(m){return Object.assign({},m,{disabled:m.name==="B"})})
        session.monitors=session.copy(session.live);session.applyRuntime();session.drain();session.panelScreenName="A"
      }
      session.setModeValue("single","B");session.drain();session.closePanel()
      if(data.phase==="token") {
        var limit=100
        while(!(session.jobs.length && session.jobs[0].args && session.jobs[0].args[0]==="touch") && --limit)verify(session.step())
        verify(limit>0)
      }
      session.rejectNext=true;session.drain()
      if(session.panelEvacuationWaiting) {session.closePanel();session.drain()}
      compare(session.state,"idle");verify(session.layoutError.indexOf("Could not")>=0)
    }
    function test_stale_generation_and_running_effect_callbacks() {
      session.setModeValue("single","A");session.drain();session.closePanel()
      verify(session.jobs.length>0)
      session.handleEvent({name:"configreloaded",data:""});session.drain()
      compare(session.state,"idle");compare(session.gen,3);compare(session.configGeneration,2)
      verify(!session.effects.some(function(e){return e.startsWith("monitor:")}))
      reset();session.setModeValue("single","A");session.drain();session.closePanel()
      var running=session.jobs.shift();verify(running.args[1]==="eval")
      session.apply(running.args[2]);session.handleEvent({name:"configreloaded",data:""})
      running.done(0,"ok");session.drain();compare(session.state,"idle")
      compare(session.config.mode,"single");compare(session.config.singleTarget,"A")
      verify(session.layoutError.indexOf("preview cancelled")>=0)
    }
    function test_external_geometry_observation_cancels_without_monitor_replay() {
      preview();var count=session.effects.filter(function(e){return e.startsWith("monitor:")}).length
      session.live=session.live.map(function(m){return Object.assign({},m,{x:m.x+200})})
      session.observeDesktop();session.drain()
      compare(session.state,"idle");verify(session.layoutError.indexOf("External display change accepted")>=0)
      compare(session.effects.filter(function(e){return e.startsWith("monitor:")}).length,count)
      compare(session.displayDraft[0].x,200)
    }
    function test_partial_restart_restores_original_identities_through_m5_load_callback() {
      session.setModeValue("single","A");session.drain();session.closePanel()
      var limit=100
      while(session.migrationPhase!=="journal" && --limit)verify(session.step())
      verify(limit>0)
      var journal=session.file(session.workspaceOwner,"workspace-map.json").text()
      var windows=session.copy(session.windows)
      windows[1].workspace={id:1,name:"1"}
      cleanup();session=factory.createObject(host)
      session.initialize(undefined,{journal:journal,windows:windows})
      verify(session.previewBaseline!==null);compare(session.previewBaseline.windows.length,4)
      session.applyRuntime();session.drain()
      compare(session.workspaceMap.outputs.join(","),"A,B");compare(session.workspaceData.pending,null)
      compare(session.previewBaseline,null)
      compare(session.windows.map(function(w){return w.workspace.id+":"+w.monitor}).join(","),"1:A,2:B,3:A,4:B")
    }
    function test_both_evacuation_timeout_paths_dispatch_no_destructive_rule() {
      session.setModeValue("single","A");session.drain()
      session.panelEvacuationTimedOut();session.drain()
      compare(session.panelEvacuationPurpose,"revert");verify(session.panelEvacuationWaiting>0)
      session.panelEvacuationTimedOut();session.drain()
      compare(session.panelEvacuationWaiting,0);verify(!session.previewBusy)
      verify(session.layoutError.indexOf("safely close Station")>=0)
      compare(session.effects.length,0)
    }
    function test_revert_preparation_failure_resumes_countdown_and_source_readiness() {
      preview("single","B");session.config=Object.assign({},session.config,{mode:"single",singleTarget:"A"})
      session.revertPreview("");session.closePanel();session.rejectNext=true;session.drain()
      compare(session.state,"previewing");verify(!session.previewBusy);compare(session.previewSeconds,12)
      var before=session.readiness
      file("monitors.lua").loadFailed();verify(session.monitorsLoaded);compare(session.monitorsSource,"")
      verify(session.readiness>before);file("preview.token").loaded();verify(session.previewFound)
      var launches=Quickshell.launches.length;cleanup();wait(30);compare(Quickshell.launches.length,launches)
    }
  }
}

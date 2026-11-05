const test=require('node:test');
const assert=require('node:assert/strict');
const {readFileSync,writeFileSync,mkdtempSync,rmSync,existsSync}=require('node:fs');
const {tmpdir}=require('node:os');
const {join}=require('node:path');
const {runInNewContext}=require('node:vm');
const {createHash}=require('node:crypto');
const {harness,before,current}=require('./helpers/display-transaction.cjs');
const {source,methods,privateHelpers}=require('./helpers/display-owner.cjs');
const {functionFrom}=require('./helpers/workspace-owner.cjs');
const copy=value=>JSON.parse(JSON.stringify(value));

test('display owner has finite ports, one writable preview state and compatible root forwarding',()=>{
  assert.doesNotMatch(source,/property var (station|service|shell)\b|root\.config\b|root\.gen\b|IpcHandler|execDetached/);
  for(const id of ['monitorsFile','internalDisableFile','candidateFile','plainCandidateFile',
    'previewToken','previewArm','keepTransaction','previewCountdown']) {
    assert.doesNotMatch(current,new RegExp('id: '+id+'\\b'));
    assert.match(source,new RegExp('id: '+id+'\\b'));
  }
  for(const field of ['previewBusy','previewBaseline','previewApplied','displayDraft','draftMode',
    'draftMirrorSource','keepOptions','pendingDisplayConfig','previewLoaded','monitorsLoaded']) {
    assert.match(current,new RegExp('readonly property \\w+ '+field+': displayController\\.'));
    assert.doesNotMatch(current,new RegExp('(?:root\\.)?'+field+' = '));
  }
  for(const name of methods.filter(n=>!privateHelpers.includes(n))) {
    const calls=[];
    const c={panelEvacuationPurpose:'revert',panelEvacuationFrom:'A',
      displayController:{[name](...args){calls.push(args);return 'forwarded';}}};
    const fn=functionFrom(current,name,c);
    const args=fn.length ? Array.from({length:fn.length},(_,i)=>'value'+i) : [];
    assert.equal(fn(...args),'forwarded');
    assert.deepEqual(calls,[name==='panelEvacuationTimedOut'?['revert','A']:args]);
  }
});

function preview(h,mode='single',target='A') {
  assert.equal(h.c.setModeValue(mode,target),'started');h.drain();
  assert.equal(h.c.state,'previewing');assert.equal(h.c.previewBusy,false);
}
const scenarios={
  singleKeep(h){preview(h);assert.equal(h.c.keepPreview(),'started');h.drain();},
  singleRevert(h){preview(h);h.c.revertPreview('');h.drain();},
  otherSingleKeep(h){h.c.panelScreenName='A';preview(h,'single','B');h.c.keepPreview();h.drain();},
  mirrorA(h){preview(h,'mirror','');h.c.keepPreview();h.drain();},
  mirrorB(h){h.c.swapRole('B',0);h.drain();preview(h,'mirror','');
    assert.equal(h.c.previewApplied.options.mode,'mirror');h.c.revertPreview('');h.drain();},
  migrateFirst(h){h.setMonitors(h.c.monitors.map(m=>({...m,disabled:m.name==='B'})));
    h.c.applyRuntime();h.drain();h.c.panelScreenName='A';preview(h,'single','B');},
  reeditAndNewClient(h){preview(h);const original=copy(h.c.previewBaseline);
    h.setWindows(h.windows().concat({address:'0x9',pid:9,initialClass:'new',monitor:'A',workspace:{id:3,name:'3'}}));
    h.c.setModeValue('mirror','');h.drain();h.c.setModeValue('extend','');h.drain();
    assert.deepEqual(copy(h.c.previewBaseline),original);h.c.revertPreview('');h.drain();},
  timeout(h){preview(h);h.c.revertPreview('Preview timed out.');h.drain('Preview timed out.');},
  savedSurvivorRevert(h){preview(h,'single','B');
    h.c.config={...h.c.config,mode:'single',singleTarget:'A',enabled:['A','B']};h.c.revertPreview('');h.drain();},
  sideControl(h){h.c.applyDisplaySetting('A','scale',2);h.drain();},
  unchangedControl(h){assert.equal(h.c.applyDisplaySetting('A','scale',1),'ok');h.drain();},
  positionOnly(h){h.c.setDisplayPosition('B',2100,0);h.c.previewLayout();h.drain();
    h.c.setDisplayPosition('B',2300,0);h.c.previewLayout();h.drain();h.c.revertPreview('');h.drain();},
  externalReload(h){preview(h);h.event('configreloaded','');
    h.drain('Display configuration reloaded; preview cancelled.');},
  unexpectedHotplug(h){preview(h);h.event('monitorremoved','A');
    h.drain('Display connection changed; preview cancelled.');},
  candidateFailure(h){preview(h);h.c.candidateFile.setText=()=>h.c.keepFileFailed();
    h.c.keepPreview();h.drain('Could not save the monitor layout.');},
  explicitBlockRemoval(h){h.c.monitorsSource=h.c.MonitorsLua.generate(h.c.displayDraft,
    {mode:'extend',enabled:['A','B']}).block+'\n-- personal\n';
    assert.equal(h.c.removeStationBlock(),'started');h.drain();},
  precedenceMigration(h){h.c.monitorsPath='/fake/monitors.lua';h.c.monitorsSource='-- personal\n'+h.c.MonitorsLua.generate(h.c.displayDraft,
    {mode:'extend',enabled:['A','B']}).block+'\n';h.c.persisted.systemAuthorityVersion=3;
    h.c.migrateMonitorPrecedence(()=>{h.c.completed=true;});h.drain();assert.equal(h.c.completed,true);},
  staleAck(h){preview(h);const count=h.monitorCalls.length;
    h.c.acknowledgePanelEvacuation(h.c.panelEvacuationSerial-1,'A');
    h.c.acknowledgePanelEvacuation(h.c.panelEvacuationSerial,'unknown');
    h.drain();assert.equal(h.monitorCalls.length,count);},
};
for(const [name,run] of Object.entries(scenarios)) test('pre-M6 and display owner effects/state/bytes match: '+name,()=>{
  const old=harness({baseline:true,capture:true}),next=harness({capture:true});
  run(old);run(next);
  assert.deepEqual(next.trace,old.trace);
  assert.deepEqual(next.order,old.order);
  assert.deepEqual(next.writes,old.writes);
  assert.deepEqual(copy(next.snapshot()),copy(old.snapshot()));
});

test('display extraction keeps the exact candidate/toggle argument contract and fixed scripts',()=>{
  assert.equal(createHash('sha256').update(before).digest('hex'),
    '1945107f0eeabb852fd6541591787cd663f832c179c98b6062a2cea21fbf6086');
  const old=before.match(/command: \["sh", "-c", Transactions.keep[^]*?keepDisableToggle\]/)[0];
  const next=source.match(/command: \["sh", "-c", Transactions.keep[^]*?keepDisableToggle\]/)[0];
  assert.equal(next,old);
  assert.match(current,/restorePreviewBaseline: function\(value\) \{ displayController.restorePreviewBaseline\(value\) \}/);
  assert.match(current,/displayController.failPreview\("Could not read the display state/);
  assert.match(current,/launchWatchdog: function\(\) \{\s*Quickshell.execDetached\(\["sh", "-c", Transactions.watchdog, "sh", "20"/);
  assert.match(source,/interval: 1000\s*repeat: true/);
  assert.match(current,/id: panelEvacuationTimeout[^]*?interval: 2500/);
});

test('root startup waits for owner load gates and routes stale-token recovery once',()=>{
  for(const found of [false,true]) {
    const calls=[];
    const c={started:false,dirsReady:true,configLoaded:true,stateLoaded:true,previewLoaded:false,
      mappingLoaded:true,monitorsLoaded:true,previewFound:found,stateDir:'/temporary',
      persisted:{lastStation:3,activeNoticeShown:true},config:{hideNative:true,hideDisplay:true},
      Quickshell:{execDetached(args){calls.push(args);}},
      migrateMonitorPrecedence(done){done();},refresh(include,done){done();},
      applyRuntime(){calls.push('runtime');},acquireStockLeases(){},saveState(){}};
    c.root=c;
    const start=functionFrom(current,'maybeStart',c);
    start();assert.equal(c.started,false);assert.deepEqual(calls,[]);
    c.previewLoaded=true;start();start();
    assert.equal(c.currentStation,3);
    assert.deepEqual(copy(calls),found ? [['rm','-f','/temporary/preview.token'],['hyprctl','reload'],'runtime'] : ['runtime']);
  }
});

for(const [producer,consumer] of [[true,false],[false,true]]) {
  test(`M6 code rollback recovers partial journals/tokens/interrupted candidates: ${producer?'old':'owner'} -> ${consumer?'old':'owner'}`,()=>{
    const directory=mkdtempSync(join(tmpdir(),'station-m6-rollback-'));
    try {
      const original=harness({baseline:producer,capture:true});
      const initial=original.windows();preview(original);
      const journal=join(directory,'workspace-map.json'),token=join(directory,'preview.token');
      const monitors=join(directory,'monitors.lua'),candidate=join(directory,'monitors.lua.candidate');
      const plainCandidate=join(directory,'plain.candidate'),plain=join(directory,'plain.lua');
      writeFileSync(journal,JSON.stringify(original.writes[0],null,2)+'\n');
      writeFileSync(token,'');writeFileSync(monitors,'-- newer personal bytes\n');
      writeFileSync(plain,'retained M2 plain\n');
      original.c.keepPreview();
      writeFileSync(candidate,original.trace.filter(row=>row[0]==='candidate').at(-1)[1]);
      writeFileSync(plainCandidate,original.trace.filter(row=>row[0]==='plainCandidate').at(-1)[1]);
      const candidateBytes=readFileSync(candidate,'utf8'),plainBytes=readFileSync(plainCandidate,'utf8');
      const restarted=harness({baseline:consumer}),c=restarted.c;
      const partial=initial.map((row,i)=>({...row,monitor:'A',workspace:i===1?{id:1,name:'1'}:row.workspace}));
      restarted.setWindows(partial);c.clients=copy(partial);c.mappingLoaded=false;
      c.parseJournal=JSON.parse;c.ready=()=>{};c.text=()=>readFileSync(journal,'utf8');
      // Use the actual composition callback for baseline restoration, then the
      // production M5 load handler. Real signal behavior has separate Qt coverage.
      const rootSource=consumer?before:current;
      const restore=rootSource.match(/restorePreviewBaseline: (function\(value\) \{[^\n]+\})/)[1];
      c.restorePreviewBaseline=runInNewContext('('+restore+')',c);
      const loaded=readFileSync('lib/WorkspaceController.qml','utf8').match(/onLoaded: \{([^]*?)\n    \}/)[1];
      runInNewContext('(function(){'+loaded+'\n})',c)();
      assert.equal(c.mappingLoaded,true);assert.equal(c.previewBaseline.windows.length,4);
      const saved=c.workspaceFile.setText;
      c.workspaceFile.setText=text=>{saved(text);writeFileSync(journal,text);};
      c.stateDir=directory;c.started=false;c.previewLoaded=true;c.previewFound=true;c.monitorsLoaded=true;
      c.persisted.activeNoticeShown=true;c.persisted.systemAuthorityVersion=3;c.acquireStockLeases=()=>{};
      const detached=[];
      c.Quickshell.execDetached=args=>{
        detached.push(copy(args));
        if(args[0]==='rm'){assert.deepEqual(copy(args),['rm','-f',token]);rmSync(token);}
        else assert.deepEqual(copy(args),['hyprctl','reload']);
      };
      c.maybeStart();restarted.drain();
      assert.deepEqual(detached,[['rm','-f',token],['hyprctl','reload']]);
      assert.equal(existsSync(token),false);assert.equal(c.previewBaseline,null);
      assert.deepEqual(restarted.windows().map(w=>[w.workspace.id,w.monitor]),initial.map(w=>[w.workspace.id,w.monitor]));
      const final=JSON.parse(readFileSync(journal,'utf8'));
      assert.equal(final.pending,null);assert.equal(final.preview,null);assert.deepEqual(final.mapping.outputs,['A','B']);
      assert.equal(readFileSync(monitors,'utf8'),'-- newer personal bytes\n');
      assert.equal(readFileSync(candidate,'utf8'),candidateBytes);assert.equal(readFileSync(plainCandidate,'utf8'),plainBytes);
      assert.equal(readFileSync(plain,'utf8'),'retained M2 plain\n');
    } finally {rmSync(directory,{recursive:true,force:true});}
  });
}

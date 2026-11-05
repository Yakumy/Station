const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { join } = require('node:path');
const { tmpdir } = require('node:os');
const { spawnSync } = require('node:child_process');
const T = require('../../lib/platform/Transactions.js');
const L = require('../../lib/displays/MonitorsLua.js');
const flag = 'hl.monitor({ output = "eDP-1", disabled = true })\n';
const displays = [{name:'eDP-1',lane:1}, {name:'HDMI-A-2',lane:2}];
const options = {mode:'extend',enabled:['eDP-1','HDMI-A-2']};
function fixture(t) {
  const dir = fs.mkdtempSync(join(tmpdir(),'station-internal-toggle-'));
  t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));
  const bin=join(dir,'bin'); fs.mkdirSync(bin);
  const toggle=join(dir,'internal-monitor-disable.lua'), monitors=join(dir,'monitors.lua');
  const candidate=join(dir,'candidate'), plain=join(dir,'plain'), token=join(dir,'token');
  const log=join(dir,'calls');
  const env={...process.env,PATH:bin+':'+process.env.PATH,TEST_TOGGLE:toggle,TEST_MONITORS:monitors,TEST_LOG:log};
  function command(name,body) { fs.writeFileSync(join(bin,name),'#!/bin/sh\n'+body,{mode:0o755}); }
  command('sleep','exit 0\n');
  command('hyprctl',`printf '%s\\n' "$*" >> "$TEST_LOG"
case "$1" in
 getoption) printf '{"bool":%s}\\n' "\${TEST_AUTO:-false}" ;;
 eval) printf 'ok\\n' ;;
 reload) [ "\${TEST_FAIL_RELOAD:-0}" = 0 ] ;;
 configerrors)
   if [ "\${TEST_NEW_EDIT:-0}" = 1 ]; then
     printf 'new personal edit\\n' > "$TEST_MONITORS"
     printf 'new toggle edit\\n' > "$TEST_TOGGLE"
   fi
   printf '%s' "\${TEST_ERRORS:-}" ;;
esac
`);
  fs.writeFileSync(toggle,flag); fs.writeFileSync(monitors,'before\n');
  fs.writeFileSync(candidate,'after\n'); fs.writeFileSync(plain,'old plain\n'); fs.writeFileSync(token,'');
  return {dir,bin,toggle,monitors,candidate,plain,token,log,env,command,
    run(extra={},expected=flag) { return spawnSync('sh',['-c',T.keep,'sh',candidate,monitors,candidate,plain,token,'before\n',toggle,expected],{env:{...env,...extra},encoding:'utf8'}); }};
}
test('only the exact Omarchy internal Off flag is cleared when its output is explicitly enabled',()=>{
  assert.equal(L.disableToggleToClear(flag,displays,options),flag);
  for (const source of ['', flag+'-- personal\n', flag.replace('eDP-1','HDMI-A-2'), flag.replace('true','false')])
    assert.equal(L.disableToggleToClear(source,displays,options),'');
  assert.equal(L.disableToggleToClear(flag,displays,{mode:'single',singleTarget:'HDMI-A-2'}),'');
  assert.equal(L.disableToggleToClear(flag,displays,{...options,enabled:['HDMI-A-2']}),'');
  assert.equal(L.disableToggleToClear(flag,[displays[1]],options),'');
});
test('service requests toggle handoff only at Keep, never a side-control save',()=>{
  const {source,ownerFunction}=require('../helpers/display-owner.cjs');
  const c={monitorsSource:'before',internalDisableSource:flag,pendingDisplayConfig:{displays},keepOptions:options,
    MonitorsLua:L,candidateFile:{text:()=> 'candidate'},plainCandidateFile:{text:()=> 'plain'},maybeStartKeep(){}};
  const save=ownerFunction('startKeepFiles',c);
  save('candidate','plain','preview'); assert.equal(c.keepDisableToggle,flag);
  save('candidate','plain','control'); assert.equal(c.keepDisableToggle,'');
  const preview=source.slice(source.indexOf('  function previewLayout('),source.indexOf('  function keepPreview('));
  assert.doesNotMatch(preview,/keepDisableToggle/);
});
test('Keep commits both files with one explicit reload and restores autoreload',t=>{
  const f=fixture(t),r=f.run(); assert.equal(r.status,0,r.stderr);
  assert.equal(fs.existsSync(f.toggle),false); assert.equal(fs.readFileSync(f.monitors,'utf8'),'after\n');
  assert.deepEqual(fs.readdirSync(f.dir).filter(n=>/station-backup/.test(n)),[],'a successful Keep leaves no flag backup');
  assert.equal(fs.existsSync(f.token),false);
  const calls=fs.readFileSync(f.log,'utf8').trim().split('\n');
  assert.equal(calls.filter(x=>x==='reload').length,1);
  assert.ok(calls.indexOf('eval hl.config({misc={disable_autoreload=true}})') < calls.indexOf('reload'));
  assert.equal(calls.at(-1),'eval hl.config({misc={disable_autoreload=false}})');
});
test('ordinary Keep leaves the external Off flag untouched and relies on watched apply',t=>{
  const f=fixture(t),r=f.run({},''); assert.equal(r.status,0,r.stderr);
  assert.equal(fs.readFileSync(f.toggle,'utf8'),flag);
  assert.equal(fs.readFileSync(f.log,'utf8').trim(),'configerrors');
});
test('a changed toggle rejects Keep before either file is modified',t=>{
  const f=fixture(t); fs.writeFileSync(f.toggle,'personal change\n');
  assert.equal(f.run().status,4);
  assert.equal(fs.readFileSync(f.monitors,'utf8'),'before\n');
  assert.equal(fs.readFileSync(f.toggle,'utf8'),'personal change\n');
});
test('a changed monitor file rejects Keep without clearing the toggle',t=>{
  const f=fixture(t); fs.writeFileSync(f.monitors,'personal change\n');
  assert.equal(f.run().status,4); assert.equal(fs.readFileSync(f.toggle,'utf8'),flag);
  assert.equal(fs.readFileSync(f.monitors,'utf8'),'personal change\n');
});
test('config rejection restores both saved files and the prior autoreload setting',t=>{
  const f=fixture(t); assert.equal(f.run({TEST_ERRORS:'invalid layout',TEST_AUTO:'true'}).status,3);
  assert.equal(fs.readFileSync(f.monitors,'utf8'),'before\n');
  assert.equal(fs.readFileSync(f.toggle,'utf8'),flag);
  assert.equal(fs.readFileSync(f.plain,'utf8'),'old plain\n'); assert.ok(fs.existsSync(f.token));
  assert.ok(fs.readFileSync(f.log,'utf8').trim().endsWith('eval hl.config({misc={disable_autoreload=true}})'));
});
test('reload failure restores the Off flag and monitor source',t=>{
  const f=fixture(t); assert.notEqual(f.run({TEST_FAIL_RELOAD:'1'}).status,0);
  assert.equal(fs.readFileSync(f.monitors,'utf8'),'before\n');
  assert.equal(fs.readFileSync(f.toggle,'utf8'),flag);
});
test('rollback preserves newer external edits in both files',t=>{
  const f=fixture(t); assert.equal(f.run({TEST_ERRORS:'error',TEST_NEW_EDIT:'1'}).status,3);
  assert.equal(fs.readFileSync(f.monitors,'utf8'),'new personal edit\n');
  assert.equal(fs.readFileSync(f.toggle,'utf8'),'new toggle edit\n');
});
const installedCommand='/usr/share/omarchy/bin/omarchy-hyprland-monitor-internal';
test('installed omarchy-hyprland-monitor-internal off generates the supported flag (isolated)',
  {skip:!fs.existsSync(installedCommand)},t=>{
  const f=fixture(t),home=join(f.dir,'user');
  const toggles=join(home,'.local/state/omarchy/toggles/hypr'); fs.mkdirSync(toggles,{recursive:true});
  // Redirect only this script's home reference; never alter the process HOME or desktop.
  const script=join(f.dir,'monitor-internal');
  fs.writeFileSync(script,fs.readFileSync(installedCommand,'utf8').replaceAll('$HOME','$STATION_TEST_HOME'));
  f.command('omarchy-hyprland-monitor-laptop','printf "eDP-1\\n"');
  f.command('omarchy-hyprland-monitor-external-active','exit 0');
  f.command('omarchy-hyprland-toggle-disabled','exit 0');
  f.command('omarchy-notification-send','exit 0');
  const r=spawnSync('bash',[script,'off'],{env:{...f.env,STATION_TEST_HOME:home},encoding:'utf8'});
  assert.equal(r.status,0,r.stderr);
  const actual=fs.readFileSync(join(toggles,'internal-monitor-disable.lua'),'utf8');
  assert.equal(actual,flag); assert.equal(L.disableToggleToClear(actual,displays,options),actual);
});

test('the Off flag is parked only when a preview leaves no external output enabled',()=>{
  const park=(source,opts)=>L.disableToggleToPark(source,displays,opts);
  assert.equal(park(flag,{mode:'single',singleTarget:'eDP-1',enabled:['eDP-1','HDMI-A-2']}),flag);
  assert.equal(park(flag,{mode:'extend',enabled:['eDP-1']}),flag);
  assert.equal(park(flag,options),'','an external stays active, so recover is a no-op');
  assert.equal(park(flag,{mode:'mirror',enabled:['eDP-1','HDMI-A-2']}),'','Omarchy counts a mirror as active');
  assert.equal(park(flag,{mode:'single',singleTarget:'HDMI-A-2',enabled:['eDP-1','HDMI-A-2']}),'');
  for (const source of ['',flag+'-- personal\n',flag.replace('eDP-1','HDMI-A-2')])
    assert.equal(park(source,{mode:'single',singleTarget:'eDP-1',enabled:['eDP-1','HDMI-A-2']}),'');
});
function parkRun(f,expected=flag,extra={}) {
  return spawnSync('sh',['-c',T.parkToggle,'sh',f.toggle,join(f.dir,'parked'),expected],{env:{...f.env,...extra},encoding:'utf8'});
}
test('parking moves the exact flag with watches suspended and restores autoreload',t=>{
  const f=fixture(t),r=parkRun(f); assert.equal(r.status,0,r.stderr);
  assert.equal(fs.existsSync(f.toggle),false); assert.equal(fs.readFileSync(join(f.dir,'parked'),'utf8'),flag);
  const calls=fs.readFileSync(f.log,'utf8');
  assert.match(calls,/disable_autoreload=true[\s\S]*disable_autoreload=false/);
  assert.doesNotMatch(calls,/reload\n/,'parking must not reload the saved layout');
  fs.rmSync(f.log); assert.equal(parkRun(f).status,4);
  const g=fixture(t); assert.equal(parkRun(g,'hl.monitor({ output = "eDP-1", disabled = true }) -- other\n').status,4);
  assert.equal(fs.readFileSync(g.toggle,'utf8'),flag,'a changed flag is preserved');
  assert.deepEqual(fs.readdirSync(g.dir).filter(n=>/parked/.test(n)),[]);
});
test('parking restores an already suspended autoreload as suspended',t=>{
  const f=fixture(t); assert.equal(parkRun(f,flag,{TEST_AUTO:'true'}).status,0);
  assert.match(fs.readFileSync(f.log,'utf8'),/disable_autoreload=true\}\}\)\n$/);
});
test('unparking restores the flag once and never replaces a newer one',t=>{
  const f=fixture(t),parked=join(f.dir,'parked'),run=()=>spawnSync('sh',['-c',T.unparkToggle,'sh',parked,f.toggle],{encoding:'utf8'});
  assert.equal(parkRun(f).status,0); assert.equal(run().status,0);
  assert.equal(fs.readFileSync(f.toggle,'utf8'),flag); assert.equal(fs.existsSync(parked),false);
  assert.equal(run().status,0,'unparking with nothing parked is a no-op'); assert.equal(fs.readFileSync(f.toggle,'utf8'),flag);
  fs.writeFileSync(parked,flag); fs.writeFileSync(f.toggle,'newer\n'); assert.equal(run().status,0);
  assert.equal(fs.readFileSync(f.toggle,'utf8'),'newer\n'); assert.equal(fs.existsSync(parked),false);
});
test('the watchdog returns a parked flag before it reloads',t=>{
  const f=fixture(t),parked=join(f.dir,'parked');
  assert.equal(parkRun(f).status,0); fs.rmSync(f.log);
  f.command('stat','printf 0\n');
  const r=spawnSync('sh',['-c',T.watchdog,'sh','20',f.token,parked,f.toggle],{env:f.env,encoding:'utf8'}); assert.equal(r.status,0,r.stderr);
  assert.equal(fs.readFileSync(f.toggle,'utf8'),flag); assert.equal(fs.readFileSync(f.log,'utf8'),'reload\n');
});
function controller(extra={}) {
  const {ownerFunction}=require('../helpers/display-owner.cjs');
  const calls=[],jobs=[];
  const c={operationState:'previewing',parkedTogglePath:'/parked',internalDisablePath:'/flag',parkedToggleSource:'',internalDisableSource:flag,
    previewApplyLua:'final',previewApplyStaged:true,previewApplyExpectedOutputs:['HDMI-A-2'],previewApplyFocusTarget:'eDP-1',
    previewApplyActivateLua:'activate',previewApplyMigrateFirst:true,previewApplyParkToggle:flag,MonitorsLua:L,Transactions:T,
    Hypr:{focusMonitor:n=>'focus:'+n},recordExpectedEvents(){calls.push('expect')},reconcileWorkspace(){calls.push('reconcile')},
    enqueue(a,done){calls.push(a[2]===T.parkToggle?'park':a[2]===T.unparkToggle?'unpark':a.join(' '));jobs.push(()=>done&&done(c.code||0,''))},
    evalLua(l,done){calls.push(l);jobs.push(()=>done(0,c.replies&&/focus/.test(l)?c.replies.shift():'ok'))},
    failPreviewApply(m){calls.push('fail:'+m)},
    focusRetry:{deadline:0,target:'',done:null,stop(){},restart(){jobs.push(()=>c.attemptFocus(this.target,this.done))}},...extra};
  c.root=c;
  for (const name of ['continuePreviewApply','focusOutput','attemptFocus','restoreParkedToggle','settleParkedToggle']) c[name]=ownerFunction(name,c);
  return {c,calls,drain(){while(jobs.length)jobs.shift()();}};
}
test('a preview parks the flag before it enables the target or removes the external',()=>{
  const {c,calls,drain}=controller(); c.continuePreviewApply(); drain();
  assert.deepEqual(calls,['park','expect','activate','focus:eDP-1','reconcile']);
  assert.equal(c.parkedToggleSource,flag);
});
test('a failed park stops the preview before any output changes',()=>{
  const {c,calls,drain}=controller({code:4}); c.continuePreviewApply(); drain();
  assert.equal(calls.length,2); assert.match(calls[1],/^fail:/); assert.equal(c.parkedToggleSource,'');
});
test('focus waits for a just-enabled output and fails on anything else',()=>{
  const notFound='warning: =[C]:-1: hl.focus.monitor: monitor not found';
  let h=controller({replies:[notFound,notFound,'ok']}),result;
  h.c.focusOutput('eDP-1',true,v=>{result=v}); h.drain(); assert.equal(result,true);
  assert.equal(h.calls.filter(l=>/focus/.test(l)).length,3);
  h=controller({replies:[notFound,'ok']}); h.c.focusOutput('eDP-1',false,v=>{result=v}); h.drain();
  assert.equal(result,false,'an output that was already on gets no wait');
  h=controller({replies:['some other failure','ok']}); h.c.focusOutput('eDP-1',true,v=>{result=v}); h.drain(); assert.equal(result,false);
  h=controller({replies:[notFound,'ok']}); h.c.focusOutput('eDP-1',true,v=>{result=v}); h.c.focusRetry.deadline=0; h.drain();
  assert.equal(result,false,'the wait is bounded');
});
test('Keep drops a parked flag only when the accepted layout uses that output',()=>{
  const singleInternal={mode:'single',singleTarget:'eDP-1',enabled:['eDP-1','HDMI-A-2']};
  const singleExternal={mode:'single',singleTarget:'HDMI-A-2',enabled:['eDP-1','HDMI-A-2']};
  let h=controller({parkedToggleSource:flag}); h.c.settleParkedToggle(displays,singleInternal); h.drain();
  assert.deepEqual(h.calls,['rm -f /parked']); assert.equal(h.c.parkedToggleSource,'');
  h=controller({parkedToggleSource:flag}); h.c.settleParkedToggle(displays,singleExternal); h.drain();
  assert.deepEqual(h.calls,['unpark']); assert.equal(h.c.parkedToggleSource,'');
  h=controller(); h.c.settleParkedToggle(displays,singleInternal); h.drain(); assert.deepEqual(h.calls,[]);
});

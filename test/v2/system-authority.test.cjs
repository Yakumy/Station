const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync, mkdtempSync, writeFileSync, mkdirSync, chmodSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { spawnSync } = require('node:child_process');
const { runInNewContext } = require('node:vm');
const Model = require('../../lib/Model.js');
const Grid = require('../../lib/Grid.js');
const Binds = require('../../lib/Binds.js');
const L = require('../../lib/MonitorsLua.js');
const W = require('../../lib/Windows.js');
const S = require('../../lib/SharedConfig.js');
const T = require('../../lib/Transactions.js');
const service = readFileSync('Service.qml', 'utf8');
function fn(name, context) {
  const moved = require('./helpers/bar-settings.cjs').ownerFunction(name, context);
  if (moved) return moved;
  const windowOwner = require('./helpers/window-settings.cjs').ownerFunction(name, context);
  if (windowOwner) return windowOwner;
  const start = service.indexOf('  function ' + name + '(');
  const end = service.indexOf('\n  }', start) + 4;
  return runInNewContext('(' + service.slice(start, end) + ')', context);
}
test('reload never emits monitor or shared appearance writes, even with a disabled saved survivor', () => {
  for (const mode of ['single', 'mirror', 'extend']) {
    const c = { state: 'idle', config: { mode, singleTarget: 'A' },
      updateAssignments() {}, reconcile() {}, refreshWindowSettings() {}, applyBinds() {}, syncBarBlur() {},
      evalLua() { throw Error('Observation attempted a compositor write'); } };
    fn('applyRuntime', c)();
  }
});
test('external mirror source and partial topology determine the workspace map', () => {
  const monitors = [{id:0,name:'A',disabled:false,mirrorOf:'1'}, {id:1,name:'B',disabled:false,mirrorOf:'none'}, {id:2,name:'C',disabled:true,mirrorOf:'none'}];
  const options = Model.observedOptions(monitors);
  assert.equal(options.mode, 'mirror');
  assert.equal(options.mirrorSource, 'B');
  assert.deepEqual(Grid.mapping(monitors, {A:1,B:2,C:3}, options).outputs, ['B']);
  monitors[0].disabled = true;
  assert.equal(Model.observedOptions(monitors).mode, 'single');
  monitors[1].disabled = true;
  assert.equal(Model.observedOptions(monitors), null, 'zero-output interval retains prior bookkeeping');
});
test('numeric mirror IDs match connector targets without repeated rules', () => {
  const displays = [{name:'A',lane:1},{name:'B',lane:2}];
  assert.deepEqual(L.changedOutputs(displays, {mode:'mirror', mirrorSource:'B'},
    [{id:0,name:'A',disabled:false,mirrorOf:'1'}, {id:1,name:'B',disabled:false,mirrorOf:'none'}], false), []);
});
test('personal overrides keep final precedence and their Lua remains opaque', () => {
  const personal = 'local scale = 1.6\nhl.monitor({output="A", scale=scale})\n';
  const result = L.replaceManagedBlock(personal, L.START+'\n-- saved defaults\n'+L.END);
  assert.ok(result.endsWith(personal));
  assert.equal(L.replaceManagedBlock(result, L.START+'\n-- saved defaults\n'+L.END), result);
  const appearance = S.setWindow('hl.config({general={gaps_in=7}})\n', 'rounding', W.settingLua('rounding', 8));
  assert.ok(appearance.indexOf('rounding=8') < appearance.indexOf('gaps_in=7'));
  assert.ok(!appearance.includes('animations'));
  assert.throws(() => S.setWindow(S.START, 'rounding', ''), /markers/);
});
test('observed settings parse actual batch JSON and retain external values', () => {
  const raw = [{css:'7 7 7 7'}, {css:'19 19 19 19'}, {float:0.7}, {int:16}, {bool:true}, [[{name:'windows', enabled:true,speed:8}], []]].map(JSON.stringify).join('\n\n');
  assert.deepEqual(W.observed(raw), {innerGap:14,outerGap:19,split:65,rounding:16,speed:0.5});
  assert.throws(() => W.observed('{}'), /Incomplete/);
});
test('personal binds beat automatic defaults, including digit/code aliases', () => {
  assert.equal(Binds.classify('SUPER + code:10', {ok:true,text:'SUPER + 1 → My personal action'}, []).status, 'conflict');
  assert.equal(Binds.classify('SUPER + CTRL + LEFT', {ok:true,text:'SUPER CTRL LEFT → My action'}, []).status, 'conflict');
  assert.equal(Binds.classify('SUPER + code:10', {ok:true,text:'SUPER + 1 → Switch to workspace 1'}, []).status, 'replacement');
  assert.doesNotMatch(Binds.applyLua([], []), /hl.unbind/);
});
test('settings transaction preserves intervening edits and rolls back only its own failed write', () => {
  const dir = mkdtempSync(join(tmpdir(), 'station-settings-test-'));
  const bin = join(dir, 'bin'); mkdirSync(bin);
  const helper = join(bin, 'hyprctl');
  writeFileSync(helper, '#!/bin/sh\n[ "$1" != configerrors ] || printf "%s" "${TEST_ERRORS:-}"\n'); chmodSync(helper, 0o755);
  const file = join(dir, 'looknfeel.lua');
  const env = {...process.env,PATH:bin+':'+process.env.PATH};
  const run = (before,after,extra={}) => spawnSync('sh',['-c',T.settings,'sh',file,before,after],{env:{...env,...extra},encoding:'utf8'});
  writeFileSync(file,'external\n');
  assert.equal(run('stale\n','bad replacement\n').status,4);
  assert.equal(readFileSync(file,'utf8'),'external\n');
  assert.equal(run('external\n','valid\n').status,0);
  assert.equal(run('valid\n','invalid\n',{TEST_ERRORS:'error'}).status,3);
  assert.equal(readFileSync(file,'utf8'),'valid\n');
});
test('cold configuration applies saved Single only with a physically connected survivor', () => {
  const {monitorRules} = require('./helpers/monitor-lua.cjs');
  const displays = ['A','B'].map((name,i)=>({name,lane:i+1,mode:'1920x1080@60.00Hz',availableModes:['1920x1080@60.00Hz'],x:i*1920,y:0,scale:1,transform:0}));
  const block = L.generate(displays,{mode:'single',singleTarget:'B'}).block;
  const connected = '{open=function(path) if path:match("card0%-B/status$") then return {read=function() return "connected\\n" end, close=function() end} end end}';
  const rules = monitorRules(block,'function() return {} end',connected);
  assert.match(rules[0],/output = "B".*disabled = false/);
  assert.match(rules[1],/output = "A".*disabled = true/);
  assert.ok(monitorRules(block,'function() return {} end').every(rule=>rule.includes('disabled = false')));
  assert.equal(L.migrateBlock(block+'\n'),block+'\n','migration is idempotent');
});
test('queued writes from an obsolete configuration generation never execute', () => {
  const calls = [];
  const c = {configGeneration:2, currentAction:null,
    actionQueue:[{command:['hyprctl','eval','old'],generation:1,done:(code)=>calls.push(code)}],
    action:{running:false}};
  c.runNext = fn('runNext',c);
  c.runNext();
  assert.deepEqual(calls,[1]);
  assert.equal(c.action.command,undefined);
});
test('external bar rows replace pending local values and row removal restores inheritance', () => {
  const c = {configLoaded:true,shell:{barConfig:{id:"yakumy.station"}}, activeStationBar:()=>true,
    hostBarsSignature:JSON.stringify({A:{position:'right',width:80}}),
    observedHostBars:{A:{position:'left'}}, config:{bars:{A:{position:'left'}}},
    pendingMonitorBars:{A:{position:'bottom'}}, validConnector:()=>true,
    parseJson:JSON.parse, Store:require('../../lib/Store.js'),saveConfig(){}};
  const adopt = fn('adoptHostBars',c);
  adopt();
  assert.equal(c.config.bars.A.position,'right');
  assert.equal(c.pendingMonitorBars.A,undefined);
  c.hostBarsSignature='{}'; adopt();
  assert.equal(c.config.bars.A,undefined);
});
test('external slider values are displayed without becoming saved slider stops', () => {
  assert.equal(W.displayValues({speed:1.33,rounding:19.5}).speed,1.33);
  assert.equal(W.displayValues({speed:1.33,rounding:19.5}).rounding,19.5);
});

test('window edits stay busy through read-back and always settle after observation errors', () => {
  for (const outcome of ['applied', 'override', 'save failure', 'read failure', 'malformed', 'generation changed']) {
    const queue = [];
    const c = {Windows:W, Hypr:require('../../lib/Hypr.js'), Style:{}, SharedConfig:S, Transactions:T, configGeneration:1,
      config:{windows:W.clean(null)}, windowSettingsBusy:false, state:'idle',
      appearanceLoaded:true, appearanceSource:'', appearancePath:'/isolated/looknfeel.lua',
      appearanceFile:{reload(){}}, layoutError:'', console:{warn(){}},
      enqueue(command, done, generation) { queue.push({command,done,generation}); }};
    c.root = c;
    c.refreshWindowSettings = fn('refreshWindowSettings',c);
    const set = fn('setWindowSetting',c);
    assert.equal(set('split',65),'ok');
    assert.equal(queue[0].generation,1);
    assert.equal(queue[0].command[2],T.windowSetting);
    assert.match(queue[0].command.at(-1), /assert\(loadfile\(/);
    assert.match(queue[0].command.at(-1), /default_split_ratio=0\.7/);
    assert.doesNotMatch(queue[0].command.at(-1), /gaps_in|rounding|hl\.monitor/);
    assert.equal(c.windowSettingsBusy,true);
    c.refreshWindowSettings();
    assert.equal(queue.length,1,'ordinary polling cannot read during the save');
    queue.shift().done(outcome === 'save failure' ? 4 : 0,'');
    assert.equal(c.windowSettingsBusy,true,'file completion must not release the slider');
    assert.equal(set('rounding',8),'busy','a second save waits for read-back');
    const raw = [{css:'5 5 5 5'}, {css:'10 10 10 10'},
      {float:outcome === 'applied' ? 0.7 : 1}, {int:0}, {bool:true},
      [[{name:'windows',enabled:true,speed:4}],[]]].map(JSON.stringify).join('\n\n');
    if (outcome === 'generation changed') c.configGeneration++;
    queue.shift().done(outcome === 'read failure' ? 1 : 0, outcome === 'malformed' ? '{}' : raw);
    assert.equal(c.windowSettingsBusy,false,outcome+' releases busy');
    if (outcome === 'applied') {
      assert.equal(c.config.windows.split,65);
      assert.equal(c.layoutError,'');
    } else if (outcome === 'override') {
      assert.equal(c.config.windows.split,50);
      assert.match(c.layoutError,/personal Hyprland rule/);
    } else if (outcome === 'save failure') assert.match(c.layoutError,/Configuration changed/);
    else assert.doesNotMatch(c.layoutError,/personal Hyprland rule/,'failed reads cannot diagnose an override');
  }
});

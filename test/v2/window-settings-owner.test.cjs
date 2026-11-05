const test = require('node:test');
const { runtimeSource } = require('./helpers/runtime-source.cjs');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const { ownerFunction, source } = require('./helpers/window-settings.cjs');
const service = runtimeSource();
const W = require('../../lib/Windows.js');
function fixture() {
  const queue = [];
  const c = { Windows:W, SharedConfig:require('../../lib/SharedConfig.js'),
    Transactions:require('../../lib/Transactions.js'), Hypr:require('../../lib/Hypr.js'),
    config:{windows:W.clean(null),other:{preserved:true}}, configGeneration:1, state:'idle',
    appearanceLoaded:true,appearanceSource:'',appearancePath:'/isolated/looknfeel.lua',
    windowSettingsBusy:false,appearanceFile:{reload(){}},Style:{},console:{warn(){}},
    enqueue(command,done,generation) { queue.push({command,done,generation}); } };
  c.root = c;
  c.refreshWindowSettings = ownerFunction('refreshWindowSettings',c);
  c.setWindowSetting = ownerFunction('setWindowSetting',c);
  return {c,queue};
}
const observed = [{css:'5 5 5 5'},{css:'10 10 10 10'},{float:0.7},{int:0},{bool:true},
  [[{name:'windows',enabled:true,speed:4}],[]]].map(JSON.stringify).join('\n\n');

test('one window owner keeps root forwarding and synchronous busy projection', () => {
  assert.match(service,/readonly property alias windowSettingsBusy: windowSettings.windowSettingsBusy/);
  assert.doesNotMatch(service,/property .*appearance(Source|Loaded|Path)|id: appearanceFile/);
  assert.doesNotMatch(source,/property var (station|service|shell)\b|root\.config\b|saveConfig|hl\.monitor|previewBaseline/);
  assert.match(source,/id: appearanceFile[\s\S]*onFileChanged: reload\(\)/);
  assert.match(service,/publishObserved: function\(observed\) \{\s*root.config = Object.assign\(\{\}, root.config, \{ windows: observed \}\)/);
  for (const name of ['setWindowSetting']) {
    const line = service.split('\n').find(line => line.startsWith('  function '+name+'('));
    const calls = [];
    const fn = runInNewContext('('+line+')', {windowSettings:{[name](...args) { calls.push(args); return 'sentinel'; }}});
    const args = ['split',65];
    assert.equal(fn(...args),'sentinel'); assert.deepEqual(calls,[args]);
  }
});
test('read started before an edit cannot overwrite the slider during the save', () => {
  const {c,queue} = fixture();
  let observedRead;
  c.refreshWindowSettings(ok => { observedRead = ok; });
  const before = c.config;
  assert.equal(c.setWindowSetting('split',65),'ok');
  queue.shift().done(0,observed);
  assert.equal(observedRead,false);
  assert.equal(c.config,before);
  assert.equal(c.windowSettingsBusy,true);
  queue.shift().done(0,''); queue.shift().done(0,observed);
  assert.equal(c.config.windows.split,65);
  assert.equal(c.config.other,before.other);
  assert.equal(c.windowSettingsBusy,false);
});
test('validation, load and operation gates reject writes without scheduling effects', () => {
  const {c,queue} = fixture();
  for (const [key,value] of [['unknown',1],['split','65'],['split',Infinity],['split',NaN]])
    assert.equal(c.setWindowSetting(key,value),'invalid');
  c.state = 'previewing'; assert.equal(c.setWindowSetting('split',65),'busy');
  c.state = 'idle'; c.appearanceLoaded = false;
  assert.equal(c.setWindowSetting('split',65),'busy');
  c.appearanceLoaded = true; c.appearanceSource = require('../../lib/SharedConfig.js').START;
  assert.equal(c.setWindowSetting('split',65),'invalid');
  assert.equal(c.windowSettingsBusy,false); assert.equal(queue.length,0);
  assert.match(c.layoutError,/markers/);
});

const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { createHash } = require('node:crypto');
const { runInNewContext } = require('node:vm');
const read = name => readFileSync(name, 'utf8');
const before = read('test/v2/fixtures/pre-m7-panel.qml.txt');
const panel = read('lib/StationPanel.qml');
const session = read('lib/PanelSession.qml');
const controls = read('lib/DisplayControls.qml');
const keys = read('lib/KeybindingsTab.qml');
const Tabs = require('../../lib/Tabs.js');
const Binds = require('../../lib/Binds.js');
const copy = value => JSON.parse(JSON.stringify(value));
function body(source, name) {
  const match = source.match(new RegExp('^  function ' + name + '\\([^\\n]*\\{\\n[\\s\\S]*?^  \\}', 'm'));
  assert.ok(match, name);
  return match[0];
}
function install(source, c) {
  c.root = c; c.Tabs = Tabs; c.Binds = Binds;
  for (const [, name] of source.matchAll(/^  function (\w+)\([^\n]*\{\n/gm))
    c[name] = runInNewContext('(' + body(source, name) + ')', c);
  return c;
}
function harness(source) {
  const trace = [], later = [];
  const c = {
    trace, later, opened: false, available: true, selectedTab: 0, sessionTabRestored: false,
    retainedPanelScreen: null, monitorTransferClosing: false, monitorTransferSerial: 0,
    monitorTransferScreen: '', handledEvacuationSerial: 0, popoutSwitchClosing: false,
    intentPending: false, Quickshell: { screens: [{name:'A'}, {name:'B'}] },
    anchorWindow: {screen: {name:'A'}}, Qt: {callLater(fn) {later.push(fn);}},
    Date: {now: () => 1000}, bar: {moduleWidgets: () => [], activePopout: null},
    reopenTimer: {attempts: 0, start(){trace.push(['retry']);}, stop(){trace.push(['stop']);}},
    monitorTransferAck: {restart(){trace.push(['armAck']);}},
    refreshControls(){trace.push(['refresh']);}, resetScroll(){trace.push(['scroll']);},
    editingBindingId: '', editingModifiers: {}, editingKey: '',
    selectedDisplayName: 'A', brightnessAvailable: true, brightness: 50,
    pendingBrightnessRequest: null, brightnessWrite: {running:false}, brightnessRead: {running:false},
    brightnessDebounce: {restart(){trace.push(['debounce']);}},
    textSizeStops: [9,10,11,12,14,16,20], textSizePreviewIndex: -1, queuedTextSize: -1,
    Style: {font:{baseSize:12}}, textSizeWrite: {running:false},
  };
  c.isAvailable = () => !!c.service;
  c.panel = {anchorWindow: c.anchorWindow};
  c.hideSurface = () => {trace.push(['hide']); c.opened = false;};
  c.showSurface = () => {trace.push(['show']); c.opened = true;};
  c.controller = {hide: c.hideSurface}; c.open = c.showSurface;
  c.service = {panelWanted:false, rememberedTab:0, panelScreenName:'A', panelTransferUntil:2000,
    panelEvacuationSerial:0, panelEvacuationWaiting:0, panelEvacuationFrom:'', previewBusy:false,
    bindStatuses:[{id:'switch-1', combo:'SUPER + 1', status:'conflict'}],
    setBinding(id, combo){trace.push(['binding',id,combo]); return 'ok';},
    acknowledgePanelEvacuation(serial,name){trace.push(['ack',serial,name]);},
  };
  for (const [method, property] of [['setPanelWanted','panelWanted'],['setRememberedTab','rememberedTab'],
    ['setPanelScreenName','panelScreenName'],['setPanelTransferUntil','panelTransferUntil']])
    c.service[method] = value => {trace.push([method,value]); c.service[property]=value;};
  c.directService = c.service; c.bridgeApi = null;
  return install(source, c);
}
function state(c) {
  return copy({trace:c.trace, wanted:c.service.panelWanted, tab:c.service.rememberedTab,
    screen:c.service.panelScreenName, deadline:c.service.panelTransferUntil,
    selectedTab:c.selectedTab, handled:c.handledEvacuationSerial, transfer:c.monitorTransferClosing,
    serial:c.monitorTransferSerial, transferScreen:c.monitorTransferScreen, switchClosing:c.popoutSwitchClosing,
    brightness:c.brightness, pending:c.pendingBrightnessRequest, write:c.brightnessWrite,
    textPreview:c.textSizePreviewIndex, queued:c.queuedTextSize, textWrite:c.textSizeWrite,
    editing:c.editingBindingId, modifiers:c.editingModifiers, key:c.editingKey});
}
// Exact source provenance makes this a rollback/reference fixture, not a second implementation.
test('M7 reference is the exact pre-extraction panel and all owners stay widget-local', () => {
  assert.equal(createHash('sha256').update(before).digest('hex'), '1b12e5a192e1e97c77ed4f4ca9647f9bb4f62b5078c4df28b0f928cae259072c');
  assert.match(panel, /Station\.PanelSession/); assert.match(panel, /Station\.DisplayControls/);
  assert.doesNotMatch(read('Service.qml'), /PanelSession|DisplayControls/);
  assert.doesNotMatch(panel, /function (?:tryRestorePanel|setBrightness|beginBindingEdit)\(/);
  for (const name of ['DisplaysTab','BarTab','WindowsTab','WallpaperTab','KeybindingsTab','SettingsTab',
    'DisplayLayout','BarLayout','WindowsLayout']) assert.doesNotMatch(read('lib/'+name+'.qml'), /panelRoot/);
  const tokens = panel.match(/QtObject \{\n    id: panelTokens[\s\S]*?\n  \}/)[0];
  assert.doesNotMatch(tokens, /service|session|function|\bbar\b/);
  assert.doesNotMatch(session+controls, /import .*BarBridge|execDetached|hyprctl|Transactions/);
  for (const [port, consumers] of [
    ['displaysTabPort', ['DisplaysTab', 'DisplayLayout']], ['barTabPort', ['BarTab', 'BarLayout']],
    ['windowsTabPort', ['WindowsTab', 'WindowsLayout']], ['keybindingsTabPort', ['KeybindingsTab']],
    ['settingsTabPort', ['SettingsTab']], ['panelIntent', ['PanelSession']],
  ]) {
    const source = consumers.map(name => read('lib/'+name+'.qml')).join('\n');
    const consumed = new Set([...source.matchAll(/\bservice\.(\w+)/g)].map(m => m[1]));
    if (port === 'panelIntent') consumed.add('acknowledgePanelEvacuation');
    // Use literal block boundaries so the check is independent of QML naming conventions.
    const start = panel.indexOf('    id: '+port+'\n');
    const block = panel.slice(start, panel.indexOf('\n  }', start));
    const exposed = new Set([...block.matchAll(/(?:property \w+|function) (\w+)/g)].map(m => m[1]));
    assert.deepEqual([...exposed].sort(), [...consumed].sort(), port+' covers precisely its consumers');
  }
});
for (const [name, owner, scenario] of [
  ['explicit dismissal during transfer', session, c => {c.opened=true; c.close();}],
  ['late service intent flush', session, c => {c.opened=true; c.intentPending=true; c.flushIntent(); c.restoreSession();}],
  ['remembered tab restore', session, c => {c.service.rememberedTab=4;c.restoreSession();}],
  ['evacuation closes once with matching serial/output', session, c => {
    Object.assign(c.service,{panelWanted:true,panelEvacuationWaiting:7,panelEvacuationSerial:7,panelEvacuationFrom:'A'});
    c.opened=true;c.handlePanelEvacuation();c.handlePanelEvacuation();}],
  ['evacuation ignores other output', session, c => {
    Object.assign(c.service,{panelEvacuationWaiting:7,panelEvacuationSerial:7,panelEvacuationFrom:'B'});c.handlePanelEvacuation();}],
  ['rebuild waits for connected intended output', session, c => {c.service.panelWanted=true;c.service.panelScreenName='B';c.tryRestorePanel();}],
  ['disconnected intended output falls back', session, c => {c.service.panelWanted=true;c.service.panelScreenName='gone';c.tryRestorePanel();}],
  ['old peer blocks reopen during transfer', session, c => {c.service.panelWanted=true;c.bar.moduleWidgets=()=>[{opened:true}];c.tryRestorePanel();}],
  ['foreign popout dismisses intent', session, c => {c.service.panelWanted=true;c.bar.activePopout={foreign:true};c.settlePopoutSwitch(c.service,null,c.bar,2000);}],
  ['brightness release captures connector and clamps', controls, c => {c.queueBrightness(140);c.selectedDisplayName='B';c.setBrightness(c.brightnessDebounce.pending,c.brightnessDebounce.monitorName);}],
  ['brightness queue captures connector', controls, c => {c.brightnessWrite.running=true;c.setBrightness(80,'A');c.selectedDisplayName='B';}],
  ['text draft and last request queue', controls, c => {c.setTextSizeIndex(3);c.setTextSizeIndex(4);c.setTextSizeIndex(5);c.setTextSizeIndex(6);}],
  ['key draft normalizes modifiers and commits', keys, c => {c.beginBindingEdit(c.service.bindStatuses[0]);c.toggleEditingModifier('CTRL');c.editingKey=' K ';c.applyBindingEdit();}],
]) test('old/new panel effects match: '+name, () => {
  const old = harness(before), next = harness(owner);
  scenario(old);scenario(next);assert.deepEqual(state(next),state(old));
});
test('geometry stabilization and hardware-control callbacks retain their original algorithms', () => {
  const original = before.match(/  QtObject \{\n    id: panelBarFacade[\s\S]*?\n  \}/)[0];
  const moved = session.match(/  property QtObject barFacade: QtObject \{\n    id: panelBarFacade[\s\S]*?\n  \}/)[0];
  assert.equal(moved.replace('property QtObject barFacade: ','').replace('root.anchorWindow','panel.anchorWindow'), original);
  const oldIO = before.slice(before.indexOf('  Process {\n    id: brightnessRead'),before.indexOf('\n  implicitWidth:'));
  const nextIO = controls.slice(controls.indexOf('  Process {\n    id: brightnessRead'),controls.lastIndexOf('\n}')).trimEnd();
  assert.equal(nextIO,oldIO.trimEnd());
});
test('all finite tab ports preserve arguments and synchronous results on direct and bridge paths', () => {
  const blocks = [...panel.matchAll(/  QtObject \{\n    id: (panelIntent|\w+TabPort)\n([\s\S]*?)\n  \}/g)];
  assert.equal(blocks.length,6);
  let calls=0;
  for (const [,id,source] of blocks) for (const [,name,args,code] of source.matchAll(/function (\w+)\(([^)]*)\) \{([^\n]*)\}/g)) {
    for (const bridge of [false,true]) {
      const values=args ? args.split(',').map((_,i)=>i+'-value') : [];
      const target={ [name](...actual){assert.deepEqual(actual,values);calls++;return 'result';} };
      const context={root:{service:bridge ? new Proxy({}, {get:(_,member)=>(...a)=>target[member](...a)}) : target}};
      const fn=runInNewContext('(function('+args+'){'+code+'})',context);
      assert.equal(fn(...values),'result',id+'.'+name);
      context.root.service=null;assert.equal(fn(...values),undefined);
    }
  }
  assert.ok(calls>=60);
});

const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { runInNewContext } = require('node:vm');
const read = name => readFileSync(join(__dirname, '../..', name), 'utf8');
const service = read('Service.qml');
const panel = read('lib/StationPanel.qml');
const proxy = read('lib/BarServiceProxy.qml');
const wallpaper = read('lib/WallpaperProxy.qml');

function qmlFunction(source, name, context = {}) {
  const start = source.indexOf('  function ' + name + '(');
  assert.notEqual(start, -1, name + ' exists');
  const end = source.indexOf('\n  }', start) + 4;
  return runInNewContext('(' + source.slice(start, end) + ')', context);
}

function publisher(root) {
  const block = service.match(/barBridge = BarBridge\.publish\(([\s\S]*?)\n    \}\)/);
  assert.ok(block);
  return runInNewContext('BarBridge.publish(' + block[1] + '\n})', {
    root, BarBridge: { publish: (snapshot, actions) => ({ snapshot, actions }) },
  });
}

test('fallback polls only without the trusted service and removes all direct writes', () => {
  const entry = read('Panel.qml');
  assert.match(entry, /import "lib\/BarBridge\.js" as BarBridge/);
  assert.match(service, /import "lib\/BarBridge\.js" as BarBridge/);
  assert.match(entry, /bridgeCurrent: function\(\) \{ return BarBridge\.current\(\) \}/);
  assert.doesNotMatch(panel, /import "BarBridge\.js"/,
    'Quickshell rewrites nested type imports to qs:///; keep both imports at the entry level');
  assert.match(panel, /typeof bar\.shell\.serviceFor === "function"/);
  assert.match(panel, /service: directService \|\| \(bridgeSnapshot \? bridgeProxy : null\)/);
  assert.match(panel, /running: !root\.directService/);
  assert.match(panel, /interval: root\.opened \? 250 : 1000/);
  assert.doesNotMatch(panel, /\b(?:service|svc)\.\w+\s*=(?!=)/);
  assert.match(service, /BarBridge\.clear\(barBridge\)/);
  const context = { directService: null, bridgeApi: null, bridgeSnapshot: null, bridgeSnapshotText: '' };
  let current = null;
  context.handlePanelEvacuation = () => {};
  context.bridgeCurrent = () => current;
  const sync = qmlFunction(panel, 'syncBridge', context);
  const state = { currentStation: 2 };
  current = { snapshot: () => ({ ...state }) };
  sync();
  assert.equal(context.bridgeApi, current);
  assert.equal(context.bridgeSnapshot.currentStation, 2);
  const first = context.bridgeSnapshot;
  sync();
  assert.equal(context.bridgeSnapshot, first, 'unchanged polls emit no property changes');
  state.currentStation = 3;
  sync();
  assert.equal(context.bridgeSnapshot.currentStation, 3);
  current = null;
  sync();
  assert.equal(context.bridgeApi, null);
  assert.equal(context.bridgeSnapshot, null);
  context.directService = {};
  context.bridgeCurrent = () => { throw Error('trusted bar must not read bridge'); };
  sync();
});

test('snapshot is detached, including wallpaper, with no controller back-reference or manifest source', () => {
  const context = { manifest: { version: 'test', __sourceDir: '/private/source' } };
  for (const [, key] of proxy.matchAll(/snapshot\.(\w+)/g)) context[key] = 0;
  context.config = { hideNative: false, displays: { 'DP-1': { lane: 1 } } };
  context.displayDraft = [{ name: 'DP-1' }];
  context.bindStatuses = [{ id: 'switch-1', status: 'conflict' }];
  context.wallpaper = { draft: { framing: { zoom: 1 } }, layout: { displays: [{ name: 'DP-1' }] }, station: context };
  const snapshot = qmlFunction(service, 'barSnapshot', context);
  const data = snapshot();
  data.config.displays['DP-1'].lane = 3;
  data.displayDraft[0].name = 'fake';
  data.bindStatuses[0].status = 'free';
  data.wallpaper.draft.framing.zoom = 9;
  data.wallpaper.layout.displays.length = 0;
  assert.equal(context.config.displays['DP-1'].lane, 1);
  assert.equal(context.displayDraft[0].name, 'DP-1');
  assert.equal(context.bindStatuses[0].status, 'conflict');
  assert.equal(context.wallpaper.draft.framing.zoom, 1);
  assert.equal(context.wallpaper.layout.displays.length, 1);
  assert.equal(data.wallpaper.station, undefined);
  assert.equal(data.manifest, undefined);
  assert.equal(data.pluginVersion, 'test');
  assert.doesNotMatch(JSON.stringify(data), /private\/source/);
});

test('all proxy actions are explicitly published and preserve synchronous results', () => {
  const calls = [];
  const root = new Proxy({}, { get: (_, name) => name === 'wallpaper'
    ? new Proxy({}, { get: (_, method) => (...args) => { calls.push(['wallpaper.' + method, args]); return 'ok'; } })
    : (...args) => { calls.push([name, args]); return 'ok'; } });
  const { actions } = publisher(root);
  const methods = [...(proxy + wallpaper).matchAll(/\bcall\("(\w+)",/g)].map(m => m[1]);
  assert.deepEqual(Object.keys(actions).sort(), [...methods].sort());
  for (const method of methods) assert.equal(actions[method]('DP-1', 1, true), 'ok', method);
  assert.ok(calls.some(([name]) => name === 'wallpaper.apply'));
  calls.length = 0;
  actions.setSetting('followFocus', false);
  actions.wallpaperFrame({ zoom: 2 });
  assert.deepEqual(calls, [
    ['setSetting', ['followFocus', false]],
    ['wallpaper.frame', [{ zoom: 2 }]],
  ]);
  assert.doesNotMatch(wallpaper, /\b(?:station|target)\s*:/);
});

test('new intent setters reject malformed values at the service boundary', () => {
  const context = { validConnector: name => /^[A-Za-z0-9-]+$/.test(name) };
  for (const [method, property, good, bad] of [
    ['setPanelWanted', 'panelWanted', true, [1, 'true', null]],
    ['setPanelScreenName', 'panelScreenName', 'DP-1', [{}, '../bad', 4]],
    ['setPanelTransferUntil', 'panelTransferUntil', 1234, [NaN, Infinity, -1, '1234']],
    ['setRememberedTab', 'rememberedTab', 4, [-1, 5, 1.5, '2']],
    ['setRememberedDisplayName', 'rememberedDisplayName', 'HDMI-A-1', [{}, 'x;bad', null]],
  ]) {
    const fn = qmlFunction(service, method, context);
    fn(good);
    assert.equal(context[property], good);
    for (const value of bad) { fn(value); assert.equal(context[property], good); }
  }
});

test('deferred popout settlement works after the proxy has been destroyed', () => {
  const settle = qmlFunction(panel, 'settlePopoutSwitch');
  const calls = [];
  const api = { call: (name, args) => calls.push([name, [...args]]) };
  const deadProxy = new Proxy({}, { get() { throw Error('proxy was destroyed'); } });
  const bar = { moduleWidgets: () => [{ opened: true }] };
  settle(deadProxy, api, bar, 0);
  assert.deepEqual(calls.splice(0), [['setPanelWanted', [true]]]);
  bar.moduleWidgets = () => [];
  settle(deadProxy, api, bar, 0);
  assert.deepEqual(calls, [['setPanelWanted', [false]], ['setRememberedTab', [0]]]);
  assert.match(panel, /var svc = directService, api = directService \? null : bridgeApi/);
  assert.match(panel, /settle\(svc, api, barRef, transferUntil\)/);
});

// Catch newly added UI members that would otherwise work only under the stock bar.
test('the proxies cover every service and wallpaper member consumed by the panel', () => {
  const consumers = ['StationPanel', 'DisplaysTab', 'DisplayLayout', 'BarTab', 'SettingsTab',
    'KeybindingsTab', 'WallpaperTab'].map(name => read('lib/' + name + '.qml')).join('\n');
  const members = new Set([...consumers.matchAll(/\bservice\.(\w+)/g)].map(m => m[1]));
  const declared = new Set([...proxy.matchAll(/(?:property \w+|function) (\w+)/g)].map(m => m[1]));
  for (const member of members) assert.ok(declared.has(member), 'service proxy: ' + member);
  const wallConsumers = read('lib/WallpaperTab.qml') + read('lib/WallpaperLayout.qml');
  const wallDeclared = new Set([...wallpaper.matchAll(/(?:property \w+|function) (\w+)/g)].map(m => m[1]));
  for (const [, member] of wallConsumers.matchAll(/\bcontroller\.(\w+)/g))
    assert.ok(wallDeclared.has(member), 'wallpaper proxy: ' + member);
});

test('explicit close clears intent even while the proxy still shows a transfer window', () => {
  const live = { panelWanted: true, rememberedTab: 2, panelTransferUntil: Date.now() + 3000 };
  // Proxy properties keep the last polled snapshot; setters update only the service.
  const stale = {
    ...live,
    setPanelWanted(value) { live.panelWanted = value; },
    setRememberedTab(value) { live.rememberedTab = value; },
    setPanelTransferUntil(value) { live.panelTransferUntil = value; },
  };
  const context = {
    service: stale, opened: true, intentPending: false,
    monitorTransferClosing: false, popoutSwitchClosing: false,
    currentScreenName: () => 'DP-1', reopenTimer: { stop() {} }, controller: {},
  };
  context.flushIntent = qmlFunction(panel, 'flushIntent', context);
  const block = panel.match(/onOpenedChanged: \{([\s\S]*?)\n  \}/);
  const onOpened = runInNewContext('(function() {' + block[1] + '})', context);
  context.controller.hide = () => { context.opened = false; onOpened(); };
  qmlFunction(panel, 'close', context)();
  assert.equal(live.panelTransferUntil, 0);
  assert.equal(live.panelWanted, false, 'dismissal must not wait for another snapshot');
  assert.equal(live.rememberedTab, 0);
});

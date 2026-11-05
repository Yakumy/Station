const test = require('node:test');
const { runtimeSource } = require('../helpers/runtime-source.cjs');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const read = path => readFileSync(path, 'utf8');
const panel = read('lib/panel/StationPanel.qml');
const direct = read('lib/wallpaper/WallpaperController.qml');
const proxySource = read('lib/panel/WallpaperProxy.qml');
const consumers = read('lib/wallpaper/WallpaperTab.qml') + '\n' + read('lib/wallpaper/WallpaperLayout.qml');
const service = runtimeSource();
const Tabs = require('../../lib/panel/Tabs.js');
const ServiceContract = require('../../lib/panel/ServiceContract.js');
const copy = value => JSON.parse(JSON.stringify(value));
const methods = source => new Set([...source.matchAll(/^  function (\w+)\(/gm)].map(m => m[1]));
function multiline(source, name, context) {
  const start = source.indexOf('  function ' + name + '(');
  assert.notEqual(start, -1, name);
  const end = source.indexOf('\n  }', start) + 4;
  assert.ok(end > start, name + ' closing marker');
  return runInNewContext('(' + source.slice(start, end).trim() + ')', context);
}
function bridge(root) {
  const context = {};
  runInNewContext(read('lib/BarBridge.js').replace(/^\.pragma library\s*/, ''), context);
  assert.match(service, /BarBridge\.publish\(function\(\) \{ return ServiceContract\.snapshot\(root\) \}, ServiceContract\.actions\(root\)\)/);
  return context.publish(() => ServiceContract.snapshot(root), ServiceContract.actions(root));
}
function proxy(api) {
  const context = { api };
  for (const match of proxySource.matchAll(/^  function \w+\([^\n]*\) \{[^\n]*\}$/gm)) {
    const name = match[0].match(/function (\w+)/)[1];
    context[name] = runInNewContext('(' + match[0].trim() + ')', context);
  }
  return context;
}
function tabOrder() {
  assert.match(panel, /model: Tabs\.labels\(\)/);
  return Tabs.labels();
}
function chooseHandler() {
  // The consumer aliases root.controller as owner: the old controller.member
  // coverage regex missed this call. Execute that actual production handler.
  const source = read('lib/wallpaper/WallpaperTab.qml');
  const match = source.match(/onClicked: \{\n(\s+var target = root\.scene\.mode[^]*?)\n\s{16}\}/);
  assert.ok(match);
  return match[1];
}

// Pre-fix F1 characterization is preserved in commit 07016a1. These assertions
// now require the corrected consumer contract, with no known-gap exceptions.
test('consumer-required wallpaper methods are present on both direct and proxy paths', () => {
  const aliases = [...consumers.matchAll(/\bvar (\w+) = root\.controller\b/g)].map(m => m[1]);
  assert.ok(aliases.includes('owner'));
  const names = ['controller', ...aliases].join('|');
  const calls = new Set([...consumers.matchAll(new RegExp('\\b(?:' + names + ')\\.(\\w+)\\s*\\(', 'g'))].map(m => m[1]));
  assert.deepEqual([...calls].sort(), ['apply', 'change', 'choose', 'frame', 'frameDisplay', 'reset', 'useTheme']);
  for (const name of calls) assert.ok(methods(direct).has(name), 'direct consumer contract: ' + name);
  const missing = [...calls].filter(name => !methods(proxySource).has(name));
  assert.deepEqual(missing, [], 'consumer aliases must not hide missing proxy methods');
  const published = new Set(Object.keys(ServiceContract.actions({})).filter(name => name.startsWith('wallpaper')));
  assert.equal(published.has('wallpaperChoose'), true);
});

test('all existing common wallpaper commands preserve direct/proxy arguments and synchronous results', () => {
  const calls = [];
  const controller = {};
  const args = { choose: [''], change: ['followTheme', false], frame: [{ zoom: 2, x: 0.2, y: -0.1 }],
    frameDisplay: ['identity', { zoom: 2, x: 0.2, y: 0.1 }],
    reset: [], useTheme: [], apply: [] };
  for (const name of Object.keys(args)) controller[name] = (...values) => {
    calls.push([name, copy(values)]);
    return name === 'choose' ? true : name === 'apply' ? false : name + '-result';
  };
  const api = bridge({ wallpaper: controller });
  const detached = proxy(api);
  for (const [name, values] of Object.entries(args)) {
    const expected = controller[name](...values);
    assert.equal(detached[name](...values), expected, name);
    const [directCall, proxyCall] = calls.splice(0);
    assert.deepEqual(proxyCall, directCall, name + ' arguments');
  }
  for (const unknown of ['wallpaperController', 'constructor', '__proto__'])
    assert.equal(api.call(unknown, []), undefined, unknown + ' remains outside allowlist');
});

test('actual image-button handler opens the chooser and closes the panel on both paths', () => {
  const state = { layout: { displays: [{ identity: 'display-identity' }] }, pickerBusy: false, busy: false, draft: { followTheme: false },
    station: { panelWanted: true }, releasePanel() { state.station.panelWanted = false; }, pickerDelay: { restart() { state.started = true; } } };
  state.choose = multiline(direct, 'choose', state);
  let closed = 0;
  const root = { scene: { mode: 'individual' }, selectedDisplay: { identity: 'display-identity' },
    controller: state, dismiss() { closed++; } };
  const click = runInNewContext('(function() {' + chooseHandler() + '\n})', { root });
  click();
  assert.equal(state.pickerTarget, 'display-identity');
  assert.equal(state.station.panelWanted, false);
  assert.equal(state.started, true);
  assert.equal(closed, 1);
  root.controller = proxy(bridge({ wallpaper: state }));
  assert.doesNotThrow(click);
  assert.equal(closed, 2, 'proxy preserves the synchronous result before panel close');
});

test('direct chooser refuses Follow mode and busy state without opening a picker', () => {
  const state = { layout: { displays: [{ identity: 'display-identity' }] }, pickerBusy: false, busy: false, draft: { followTheme: true },
    station: { panelWanted: true }, releasePanel() { state.station.panelWanted = false; }, pickerDelay: { restart() { assert.fail('must not open picker'); } },
    showNotice(message, urgent) { state.notice = { message, urgent }; } };
  const choose = multiline(direct, 'choose', state);
  assert.equal(choose(''), false);
  assert.equal(state.station.panelWanted, true);
  assert.equal(state.notice.urgent, true);
  state.draft.followTheme = false;
  for (const key of ['pickerBusy', 'busy']) {
    state[key] = true;
    assert.equal(choose('display-identity'), false);
    state[key] = false;
  }
});

test('tab presentation identities agree with all six instantiated feature tabs', () => {
  const order = tabOrder();
  assert.deepEqual(order, ['Displays', 'Bar', 'Windows', 'Wallpaper', 'Keybindings', 'Settings']);
  const rows = [...panel.matchAll(/\b\w+\.(\w+)Tab \{[^\n]*?visible: root\.selectedTab === Tabs\.index\("(\w+)"\)/g)];
  assert.equal(rows.length, order.length);
  for (const [, name, id] of rows) assert.equal(order[Tabs.index(id)], name, name);
  assert.equal(Tabs.index("unknown"), -1);
  for (const value of [-1, 6, 1.5, "2", null, NaN]) assert.equal(Tabs.validIndex(value), false);
  for (let i = 0; i < order.length; i++) {
    assert.equal(Tabs.validIndex(i), true);
    assert.equal(Tabs.next(i, 1), (i + 1) % order.length);
    assert.equal(Tabs.next(i, -1), (i + order.length - 1) % order.length);
  }
});

test('key capture is active only on the opened Keybindings tab without knowing its ordinal', () => {
  const source = read('lib/keybindings/KeybindingsTab.qml');
  const expression = source.match(/available: ([^\n]+)/)[1];
  assert.equal(expression.trim(), 'keybindingsTab.active');
  const active = panel.match(/Keys\.KeybindingsTab \{ active: ([^;]+);/)[1];
  for (const label of tabOrder()) for (const opened of [false, true]) {
    const visible = label === 'Keybindings';
    const enabled = runInNewContext(active, { root: { opened }, visible });
    assert.equal(runInNewContext(expression, { keybindingsTab: { active: enabled } }), opened && visible, label);
  }
});

test('picker success, cancellation and error all restore the named Wallpaper tab', () => {
  const picker = direct.slice(direct.indexOf('    id: picker\n'));
  const match = picker.match(/onExited: function\(code\) \{([^]*?)\n    \}/);
  assert.ok(match);
  for (const code of [0, 1, 2]) {
    const calls = [];
    const panel = { panelWanted: false, rememberedTab: tabOrder().indexOf('Wallpaper') };
    const returnPanel = service.match(/returnPanel: (function\(\) \{[^]*?\n    \})/)[1];
    const root = { returnPanel: runInNewContext('(' + returnPanel + ')', { panel, Tabs }),
      prepareSelection(value) { calls.push(value); }, showNotice() { calls.push('error'); } };
    const exit = runInNewContext('(function(code) {' + match[1] + '\n})', { root, Tabs, result: '/selected/image.png' });
    exit(code);
    assert.equal(panel.panelWanted, true);
    assert.equal(panel.rememberedTab, Tabs.index('wallpaper'), 'return tab for code ' + code);
    assert.deepEqual(calls, code === 0 ? ['/selected/image.png'] : code === 1 ? [] : ['error']);
  }
});

test('both chooser paths reject malformed and unknown identities before releasing panel focus', () => {
  const state = { layout: { displays: [{ identity: 'display-identity' }] },
    pickerBusy: false, busy: false, draft: { followTheme: false },
    station: { panelWanted: true }, releasePanel() { state.station.panelWanted = false; }, pickerDelay: { restart() { state.starts++; } }, starts: 0 };
  state.choose = multiline(direct, 'choose', state);
  const detached = proxy(bridge({ wallpaper: state }));
  for (const choose of [state.choose, detached.choose]) {
    for (const value of [undefined, null, {}, [], 1, 'unknown', '../bad', 'x;lua()'])
      assert.equal(choose(value), false);
    assert.equal(state.station.panelWanted, true);
    assert.equal(state.starts, 0);
  }
});

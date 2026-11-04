const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const read = path => readFileSync(path, 'utf8');
const panel = read('lib/StationPanel.qml');
const direct = read('lib/WallpaperController.qml');
const proxySource = read('lib/WallpaperProxy.qml');
const consumers = read('lib/WallpaperTab.qml') + '\n' + read('lib/WallpaperLayout.qml');
const service = read('Service.qml');
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
  const match = service.match(/barBridge = BarBridge\.publish\(([\s\S]*?)\n    \}\)/);
  assert.ok(match);
  return runInNewContext('BarBridge.publish(' + match[1] + '\n})', { BarBridge: context, root });
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
  const match = panel.match(/model: (\["Displays",[^\n]+\])/);
  assert.ok(match, 'panel presentation order');
  return JSON.parse(match[1]);
}
function chooseHandler() {
  // The consumer aliases root.controller as owner: the old controller.member
  // coverage regex missed this call. Execute that actual production handler.
  const source = read('lib/WallpaperTab.qml');
  const match = source.match(/onClicked: \{\n(\s+var target = root\.scene\.mode[^]*?)\n\s{16}\}/);
  assert.ok(match);
  return match[1];
}

// M0 characterization, NOT an approved behavior contract. M1 must remove the
// named exceptions and change these expectations alongside its production fixes.
// Do not silently widen the known-gap lists to keep future regressions green.
test('F1 characterization: consumer-required wallpaper methods have exactly the known choose gap', () => {
  const aliases = [...consumers.matchAll(/\bvar (\w+) = root\.controller\b/g)].map(m => m[1]);
  assert.ok(aliases.includes('owner'));
  const names = ['controller', ...aliases].join('|');
  const calls = new Set([...consumers.matchAll(new RegExp('\\b(?:' + names + ')\\.(\\w+)\\s*\\(', 'g'))].map(m => m[1]));
  assert.deepEqual([...calls].sort(), ['apply', 'change', 'choose', 'frame', 'reset', 'useTheme']);
  for (const name of calls) assert.ok(methods(direct).has(name), 'direct consumer contract: ' + name);
  const missing = [...calls].filter(name => !methods(proxySource).has(name));
  assert.deepEqual(missing, ['choose'], 'known F1 gap only; M1 must reduce this to []');
  const published = new Set([...service.matchAll(/\b(wallpaper\w+): function/g)].map(m => m[1]));
  assert.equal(published.has('wallpaperChoose'), false, 'F1: chooser absent from publisher as well as proxy');
});

test('all existing common wallpaper commands preserve direct/proxy arguments and synchronous results', () => {
  const calls = [];
  const controller = {};
  const args = { change: ['followTheme', false], frame: [{ zoom: 2, x: 0.2, y: -0.1 }],
    reset: [], useTheme: [], apply: [] };
  for (const name of Object.keys(args)) controller[name] = (...values) => {
    calls.push([name, copy(values)]);
    return name === 'apply' ? false : name + '-result';
  };
  const api = bridge({ wallpaper: controller });
  const detached = proxy(api);
  for (const [name, values] of Object.entries(args)) {
    const expected = controller[name](...values);
    assert.equal(detached[name](...values), expected, name);
    const [directCall, proxyCall] = calls.splice(0);
    assert.deepEqual(proxyCall, directCall, name + ' arguments');
  }
  for (const unknown of ['wallpaperChoose', 'wallpaperController', 'constructor', '__proto__'])
    assert.equal(api.call(unknown, []), undefined, unknown + ' remains outside allowlist');
});

test('F1 characterization: actual image-button handler succeeds directly but throws through the proxy', () => {
  const state = { pickerBusy: false, busy: false, draft: { followTheme: false },
    station: { panelWanted: true }, pickerDelay: { restart() { state.started = true; } } };
  state.choose = multiline(direct, 'choose', state);
  let closed = 0;
  const root = { scene: { mode: 'individual' }, selectedDisplay: { identity: 'display-identity' },
    controller: state, panelRoot: { close() { closed++; } } };
  const click = runInNewContext('(function() {' + chooseHandler() + '\n})', { root });
  click();
  assert.equal(state.pickerTarget, 'display-identity');
  assert.equal(state.station.panelWanted, false);
  assert.equal(state.started, true);
  assert.equal(closed, 1);
  root.controller = proxy(bridge({ wallpaper: state }));
  assert.throws(click, /choose is not a function/, 'known F1 failure before M1');
  assert.equal(closed, 1, 'failed proxy handler never reaches panel close');
});

test('direct chooser refuses Follow mode and busy state without opening a picker', () => {
  const state = { pickerBusy: false, busy: false, draft: { followTheme: true },
    station: { panelWanted: true }, pickerDelay: { restart() { assert.fail('must not open picker'); } },
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
  const rows = [...panel.matchAll(/Station\.(\w+)Tab \{ visible: root\.selectedTab === (\d+)/g)];
  assert.equal(rows.length, order.length);
  for (const [, name, index] of rows) assert.equal(order[Number(index)], name, name);
});

test('F1 characterization: key capture availability still targets Wallpaper instead of Keybindings', () => {
  const source = read('lib/KeybindingsTab.qml');
  const expression = source.match(/available: ([^\n]+)/)[1];
  const context = { keybindingsTab: { panelRoot: { opened: true, selectedTab: tabOrder().indexOf('Keybindings') } } };
  assert.equal(runInNewContext(expression, context), false, 'known F1: key capture unavailable on Keybindings');
  context.keybindingsTab.panelRoot.selectedTab = tabOrder().indexOf('Wallpaper');
  assert.equal(runInNewContext(expression, context), true, 'known F1: availability expression targets Wallpaper');
  context.keybindingsTab.panelRoot.opened = false;
  assert.equal(runInNewContext(expression, context), false, 'closed panel still cannot capture');
});

test('F1 characterization: picker success, cancellation and error all remember Bar rather than Wallpaper', () => {
  const picker = direct.slice(direct.indexOf('    id: picker\n'));
  const match = picker.match(/onExited: function\(code\) \{([^]*?)\n    \}/);
  assert.ok(match);
  for (const code of [0, 1, 2]) {
    const calls = [];
    const root = { station: { panelWanted: false, rememberedTab: tabOrder().indexOf('Wallpaper') },
      prepareSelection(value) { calls.push(value); }, showNotice() { calls.push('error'); } };
    const exit = runInNewContext('(function(code) {' + match[1] + '\n})', { root, result: '/selected/image.png' });
    exit(code);
    assert.equal(root.station.panelWanted, true);
    assert.equal(tabOrder()[root.station.rememberedTab], 'Bar', 'known F1 return tab for code ' + code);
    assert.notEqual(root.station.rememberedTab, tabOrder().indexOf('Wallpaper'));
    assert.deepEqual(calls, code === 0 ? ['/selected/image.png'] : code === 1 ? [] : ['error']);
  }
});

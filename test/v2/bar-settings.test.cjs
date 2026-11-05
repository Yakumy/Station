const test = require('node:test');
const { runtimeSource } = require('./helpers/runtime-source.cjs');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { ownerFunction, source } = require('./helpers/bar-settings.cjs');
const service = runtimeSource();
const copy = value => JSON.parse(JSON.stringify(value));
function owner() {
  const calls = [];
  const c = { preferences: { A: { enabled: true, position: 'top', width: 100 }, B: { enabled: true, position: 'top' } },
    displays: [{ name: 'A', enabled: true, width: 1920, height: 1080 }, { name: 'B', enabled: true, width: 1920, height: 1080 }],
    hostConfig: { id: 'yakumy.station', position: 'top', monitors: {} },
    configLoaded: true, panelWanted: true, pendingMonitorBars: {}, observedHostBars: {},
    monitorBarMinimums: {}, monitorBarMaximumContents: {},
    lastGlobalBarPosition: 'top', globalBarPosition: 'top', focusedBarScreenName: 'A',
    Store: require('../../lib/Store.js'), MonitorsLua: require('../../lib/MonitorsLua.js'),
    Style: { font: { body: 12 }, bar: { sizeHorizontal: 26, sizeVertical: 26 }, spacing: { sm: 4 } },
    persistPreferences(rows) { c.preferences = rows; calls.push('save'); },
    retainPanel(tab) { calls.push('retain:' + tab); }, requestLayerSync() { calls.push('layer'); },
    publishHost(change) { const config = { bar: copy(c.hostConfig) }; change(config); c.hostConfig = config.bar; calls.push('host'); return true; },
  };
  for (const name of [...source.matchAll(/^  function (\w+)\(/gm)].map(m => m[1]))
    c[name] = ownerFunction(name, c);
  return { c, calls };
}

test('bar reconciliation state has one persistent owner and the service retains forwarding methods', () => {
  for (const property of ['pendingMonitorBars', 'observedHostBars', 'lastGlobalBarPosition', 'monitorBarMinimums', 'monitorBarMaximumContents']) {
    assert.match(source, new RegExp('property \\w+ ' + property + ':'));
    assert.doesNotMatch(service, new RegExp('(?<!readonly )property \\w+ ' + property + ':'));
  }
  assert.match(service, /Station\.BarSettingsController \{/);
  assert.doesNotMatch(source, /property var (?:station|shell|config)\b|root\.config\b|workspaceData|IpcHandler/);
  assert.match(service, /preferences: root\.config\.bars/);
  assert.match(service, /readonly property var monitorBarMinimums: barSettings\.monitorBarMinimums/);
  assert.match(source, /interval: 250/);
  const wrappers = [...service.matchAll(/function (\w+)\(([^)]*)\) \{ return barSettings\.(\w+)\(([^)]*)\) \}/g)];
  assert.equal(wrappers.length, 13);
  for (const [, name, args, forwarded, values] of wrappers) {
    assert.equal(name, forwarded); assert.equal(args, values);
    assert.ok(source.includes('  function ' + name + '('), name);
  }
});

test('settings edits use narrow ports and never mutate the caller old preference object', () => {
  const { c, calls } = owner();
  const before = c.preferences;
  assert.equal(c.setMonitorBarWidth('A', 45), 'ok');
  assert.equal(before.A.width, 100);
  assert.equal(c.preferences.A.width, 45);
  assert.deepEqual(calls, ['retain:bar', 'save']);
  assert.equal(c.pendingMonitorBars.A.width, 45);
  assert.equal(c.flushPendingMonitorBars(), false, 'open panel blocks host publication');
  c.panelWanted = false;
  assert.equal(c.flushPendingMonitorBars(), true);
  assert.equal(c.hostConfig.monitors.A.width, 45);
  assert.deepEqual(copy(c.pendingMonitorBars), {});
});

test('external host adoption cancels only changed rows and retains unrelated pending edits', () => {
  const { c } = owner();
  c.observedHostBars = { A: { position: 'top' }, B: { position: 'top' } };
  c.pendingMonitorBars = { A: { width: 45 }, B: { width: 55 } };
  c.hostBarsSignature = JSON.stringify({ A: { position: 'right', width: 80 }, B: { position: 'top' } });
  c.adoptHostBars();
  assert.equal(c.preferences.A.position, 'right');
  assert.equal(c.pendingMonitorBars.A, undefined);
  assert.equal(c.pendingMonitorBars.B.width, 55);
});

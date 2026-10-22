const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');

const read = name => readFileSync(name, 'utf8');
const Store = require('../../lib/Store.js');
const service = read('Service.qml');

function qmlFunction(source, name, context = {}) {
  const start = source.indexOf('  function ' + name + '(');
  assert.notEqual(start, -1, name + ' exists');
  const end = source.indexOf('\n  }', start) + 4;
  return runInNewContext('(' + source.slice(start, end) + ')', context);
}

test('2.2 manifest exposes the full bar alongside the widget and service', () => {
  const manifest = JSON.parse(read('manifest.json'));
  assert.equal(manifest.version, '2.2.0');
  assert.deepEqual(manifest.kinds, ['bar', 'bar-widget', 'service']);
  assert.equal(manifest.entryPoints.bar, 'Bar.qml');
});

test('bar preferences migrate and reject unknown positions', () => {
  assert.equal(Store.CONFIG_VERSION, 3);
  assert.deepEqual(Store.loadConfig({}).bars, {});
  assert.deepEqual(Store.loadConfig({ bars: {
    'DP-1': { enabled: false, position: 'right' },
    'DP-2': { enabled: true, position: 'diagonal' },
    broken: 'bad',
  }}).bars, {
    'DP-1': { enabled: false, position: 'right' },
    'DP-2': { enabled: true, position: 'top' },
    broken: { enabled: true, position: 'top' },
  });
});

test('service refuses to hide the last bar on an enabled output', () => {
  const context = {
    displayDraft: [
      { name: 'DP-1', enabled: true },
      { name: 'DP-2', enabled: true },
      { name: 'DP-3', enabled: false },
    ],
    config: { bars: {
      'DP-1': { enabled: true, position: 'top' },
      'DP-2': { enabled: false, position: 'left' },
      'DP-3': { enabled: true, position: 'bottom' },
    } },
    validConnector: value => /^DP-[1-3]$/.test(value),
    shell: null,
    panelWanted: false,
    panelTransferUntil: 0,
    saveConfig() {},
    publishMonitorBar() { throw new Error('must not publish rejected change'); },
  };
  context.monitorBar = qmlFunction(service, 'monitorBar', context);
  const setEnabled = qmlFunction(service, 'setMonitorBarEnabled', context);
  assert.equal(setEnabled('DP-1', false), 'last-bar');

  context.config.bars['DP-2'].enabled = true;
  context.publishMonitorBar = () => true;
  assert.equal(setEnabled('DP-1', false), 'ok');
  assert.equal(context.config.bars['DP-1'].enabled, false);
});

test('first bar edit activates Station and retires its persisted widget atomically', () => {
  const shellConfig = { bar: {
    id: 'omarchy.bar',
    layout: {
      left: [{ id: 'omarchy.menu' }, { id: 'yakumy.station' }],
      center: [{ id: 'omarchy.clock' }],
      right: [{ id: 'yakumy.station' }, { id: 'omarchy.tray' }],
    },
  } };
  const context = {
    shell: {
      mutateShellConfig(mutator) { mutator(shellConfig); return true; },
    },
  };
  const publish = qmlFunction(service, 'publishMonitorBar', context);
  assert.equal(publish('DP-1', { enabled: true, position: 'right' }), true);
  assert.equal(shellConfig.bar.id, 'yakumy.station');
  assert.deepEqual(JSON.parse(JSON.stringify(shellConfig.bar.monitors['DP-1'])),
    { enabled: true, position: 'right' });
  assert.deepEqual(JSON.parse(JSON.stringify(shellConfig.bar.layout)), {
    left: [{ id: 'omarchy.menu' }],
    center: [{ id: 'omarchy.clock' }],
    right: [{ id: 'omarchy.tray' }],
  });
});

test('upgrading an active Station bar retires the legacy widget row on service load', () => {
  const shellConfig = { bar: {
    id: 'yakumy.station',
    layout: {
      left: [{ id: 'omarchy.menu' }, { id: 'yakumy.station' }],
      center: [],
      right: [],
    },
  } };
  const context = {
    shell: {
      barConfig: shellConfig.bar,
      mutateShellConfig(mutator) { mutator(shellConfig); return true; },
    },
  };
  const reconcile = qmlFunction(service, 'reconcileActiveBarLayout', context);
  assert.equal(reconcile(), true);
  assert.deepEqual(JSON.parse(JSON.stringify(shellConfig.bar.layout.left)),
    [{ id: 'omarchy.menu' }]);
  assert.equal(reconcile(), false, 'reconciliation is idempotent after the legacy row is gone');
});

test('bar tab is read-only for display geometry and exposes all requested controls', () => {
  const panel = read('lib/StationPanel.qml');
  const tab = read('lib/BarTab.qml');
  const layout = read('lib/BarLayout.qml');
  const host = read('Bar.qml');
  const monitorBar = read('lib/MonitorBar.qml');

  assert.match(panel, /\["Displays", "Bar", "Wallpaper", "Keybindings", "Settings"\]/);
  assert.match(tab, /text: "BAR"/);
  assert.match(tab, /Station\.BarLayout/);
  assert.match(layout, /Ui\.ToggleSwitch/);
  for (const side of ['top', 'right', 'bottom', 'left'])
    assert.match(layout, new RegExp('position: "' + side + '"'));
  assert.doesNotMatch(layout, /setDisplayPosition|previewLayout|drag/i);
  assert.match(host, /Variants\s*\{[\s\S]*?model: Quickshell\.screens/);
  assert.match(host, /configuredEnabledCount\(\) > 0/);
  assert.match(host, /onPopoutRequested: root\.closePeerPopouts\(monitorBar\)/);
  assert.match(monitorBar, /function closeActivePopout\(\)/);
  assert.equal((monitorBar.match(/model: root\.targetScreen \? \[root\.targetScreen\] : \[\]/g) || []).length, 3);
});

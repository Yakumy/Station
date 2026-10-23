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

test('an open panel remembers the Bar tab across a bar-surface rebuild', () => {
  const context = {
    displayDraft: [{ name: 'DP-1', enabled: true }],
    config: { bars: { 'DP-1': { enabled: true, position: 'top' } } },
    validConnector: value => value === 'DP-1',
    shell: null,
    panelWanted: true,
    panelTransferUntil: 0,
    rememberedTab: 0,
    saveConfig() {},
    activeStationBar() { return false; },
    publishMonitorBar() { return true; },
  };
  context.monitorBar = qmlFunction(service, 'monitorBar', context);
  const setPosition = qmlFunction(service, 'setMonitorBarPosition', context);

  assert.equal(setPosition('DP-1', 'right'), 'ok');
  assert.equal(context.rememberedTab, 1);
  assert.ok(context.panelTransferUntil > Date.now());
});

test('an active full bar defers its shell.json mirror while the panel is open', () => {
  const pending = [];
  const context = {
    displayDraft: [{ name: 'DP-1', enabled: true }],
    config: { bars: { 'DP-1': { enabled: true, position: 'top' } } },
    validConnector: value => value === 'DP-1',
    shell: { mutateShellConfig() { throw new Error('must not write shell.json while open'); } },
    panelWanted: true,
    panelTransferUntil: 0,
    rememberedTab: 0,
    saveConfig() {},
    activeStationBar() { return true; },
    deferMonitorBarPublish(name, next) { pending.push([name, { ...next }]); },
    publishMonitorBar() { throw new Error('must defer the host write'); },
  };
  context.monitorBar = qmlFunction(service, 'monitorBar', context);
  const setPosition = qmlFunction(service, 'setMonitorBarPosition', context);

  assert.equal(setPosition('DP-1', 'right'), 'ok');
  assert.equal(context.config.bars['DP-1'].position, 'right');
  assert.deepEqual(pending, [['DP-1', { enabled: true, position: 'right' }]]);
});

test('closing the panel flushes all deferred monitor rows in one host write', () => {
  const shellConfig = { bar: { id: 'yakumy.station', monitors: {}, layout: {
    left: [], center: [], right: [],
  } } };
  let writes = 0;
  const context = {
    panelWanted: false,
    pendingMonitorBars: {
      'DP-1': { enabled: true, position: 'right' },
      'DP-2': { enabled: false, position: 'bottom' },
    },
    shell: {
      mutateShellConfig(mutator) { writes++; mutator(shellConfig); return true; },
    },
  };
  context.publishMonitorBars = qmlFunction(service, 'publishMonitorBars', context);
  const flush = qmlFunction(service, 'flushPendingMonitorBars', context);

  assert.equal(flush(), true);
  assert.equal(writes, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(shellConfig.bar.monitors)), {
    'DP-1': { enabled: true, position: 'right' },
    'DP-2': { enabled: false, position: 'bottom' },
  });
  assert.deepEqual(JSON.parse(JSON.stringify(context.pendingMonitorBars)), {});
});

test('full-bar entry reads live service bars before the shell.json mirror', () => {
  const fullBar = read('Bar.qml');
  assert.match(fullBar, /import "lib\/BarBridge\.js" as BarBridge/);
  assert.match(fullBar, /var live = stationBars/);
  assert.match(fullBar, /snapshot\.config\.bars/);
  assert.ok(fullBar.indexOf('var live = stationBars') < fullBar.indexOf('var rows = barConfig'));
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
  context.publishMonitorBars = qmlFunction(service, 'publishMonitorBars', context);
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
  const displayLayout = read('lib/DisplayLayout.qml');
  const wallpaperLayout = read('lib/WallpaperLayout.qml');
  const host = read('Bar.qml');
  const monitorBar = read('lib/MonitorBar.qml');

  assert.match(panel, /\["Displays", "Bar", "Wallpaper", "Keybindings", "Settings"\]/);
  assert.match(tab, /text: "BAR"/);
  assert.match(tab, /Station\.BarLayout/);
  assert.match(layout, /Ui\.ToggleSwitch/);
  for (const side of ['top', 'right', 'bottom', 'left'])
    assert.match(layout, new RegExp('position: "' + side + '"'));
  for (const canvas of [layout, displayLayout, wallpaperLayout]) {
    assert.match(canvas, /horizontalInset: width \* 0\.1/);
    assert.match(canvas, /verticalInset: height \* 0\.1/);
  }
  const preview = layout.slice(layout.indexOf('id: barPreview'), layout.indexOf('\n      Text {', layout.indexOf('id: barPreview')));
  assert.doesNotMatch(preview, /anchors\.(?:left|right|top|bottom)/);
  assert.match(preview, /parent\.width \* 0\.58/);
  assert.match(preview, /parent\.height \* 0\.58/);
  assert.match(layout, /barSetting\.enabled\s*&&\s*monitorCard\.barSetting\.position/);
  assert.match(tab, /PanelSeparator[\s\S]*Style\.space\(64\)/);
  assert.match(panel, /sessionTabRestored/);
  assert.doesNotMatch(layout, /setDisplayPosition|previewLayout|drag/i);
  assert.match(host, /Variants\s*\{[\s\S]*?model: Quickshell\.screens/);
  assert.match(host, /configuredEnabledCount\(\) > 0/);
  assert.match(host, /onPopoutRequested: root\.closePeerPopouts\(monitorBar\)/);
  assert.match(monitorBar, /function closeActivePopout\(\)/);
  assert.equal((monitorBar.match(/model: root\.targetScreen \? \[root\.targetScreen\] : \[\]/g) || []).length, 3);
});

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
  assert.equal(Store.CONFIG_VERSION, 5);
  assert.deepEqual(Store.loadConfig({}).bars, {});
  assert.deepEqual(Store.loadConfig({ bars: {
    'DP-1': { enabled: false, position: 'right', width: 54.6, height: 120.4 },
    'DP-2': { enabled: true, position: 'diagonal', width: 1000, height: 5000 },
    broken: 'bad',
  }}).bars, {
    'DP-1': { enabled: false, position: 'right', width: 55, height: 120 },
    'DP-2': { enabled: true, position: 'top', width: 100, height: 1000 },
    broken: { enabled: true, position: 'top', width: 100, height: 0 },
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
  assert.deepEqual(pending, [['DP-1', { enabled: true, position: 'right', width: 100, height: 0 }]]);
});

test('closing the panel flushes all deferred monitor rows in one host write', () => {
  const shellConfig = { bar: { id: 'yakumy.station', monitors: {}, layout: {
    left: [], center: [], right: [],
  } } };
  let writes = 0;
  const context = {
    panelWanted: false,
    pendingMonitorBars: {
      'DP-1': { enabled: true, position: 'right', width: 72 },
      'DP-2': { enabled: false, position: 'bottom', width: 100 },
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
    'DP-1': { enabled: true, position: 'right', width: 72 },
    'DP-2': { enabled: false, position: 'bottom', width: 100 },
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
  assert.equal(publish('DP-1', { enabled: true, position: 'right', width: 100 }), true);
  assert.equal(shellConfig.bar.id, 'yakumy.station');
  assert.deepEqual(JSON.parse(JSON.stringify(shellConfig.bar.monitors['DP-1'])),
    { enabled: true, position: 'right', width: 100 });
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
  assert.match(tab, /"Selected: " \+ root\.selectedDisplay\.name/);
  assert.match(tab, /Station\.BarLayout/);
  assert.match(tab, /component PositionSelector: Ui\.BorderSurface/);
  assert.match(tab, /text: "POSITION"/);
  assert.match(tab, /value: "top", label: "Top"[\s\S]*?value: "right", label: "Right"[\s\S]*?value: "bottom", label: "Bottom"[\s\S]*?value: "left", label: "Left"/);
  assert.match(tab, /anchors\.verticalCenter: parent\.verticalCenter[\s\S]*?height: Style\.spacing\.controlHeight/);
  assert.equal((tab.match(/height: controlFrame\.height \/ 5/g) || []).length, 4);
  assert.match(tab, /text: "WIDTH"/);
  assert.match(tab, /minimum: 1[\s\S]*?maximum: 100/);
  assert.match(tab, /setMonitorBarWidth\(root\.selectedDisplay\.name, Math\.round\(value\)\)/);
  assert.match(tab, /"Minimum " \+ root\.selectedMinimumWidth \+ "% — bar items overlap\."/);
  assert.match(tab, /text: "HEIGHT"/);
  assert.match(tab, /minimum: root\.selectedMinimumHeight[\s\S]*?maximum: root\.selectedMaximumHeight/);
  assert.match(tab, /setMonitorBarHeight\(root\.selectedDisplay\.name, Math\.round\(value\)\)/);
  assert.match(layout, /selectedDisplayName/);
  assert.match(layout, /displaySelected\(monitorCard\.modelData\.name\)/);
  assert.match(layout, /Color\.menu\.selectedBackground/);
  assert.match(layout, /Ui\.ToggleSwitch/);
  for (const side of ['top', 'right', 'bottom', 'left'])
    assert.match(layout, new RegExp('position: "' + side + '"'));
  for (const canvas of [layout, displayLayout, wallpaperLayout]) {
    assert.match(canvas, /horizontalInset: width \* 0\.1/);
    assert.match(canvas, /verticalInset: height \* 0\.1/);
  }
  const preview = layout.slice(layout.indexOf('id: barPreview'), layout.indexOf('\n      Text {', layout.indexOf('id: barPreview')));
  assert.doesNotMatch(preview, /anchors\.(?:left|right|top|bottom)/);
  assert.match(preview, /parent\.width - canvas\.monitorGap \* 2/);
  assert.match(preview, /parent\.height - canvas\.monitorGap \* 2/);
  assert.match(preview, /position === "left" \? canvas\.monitorGap/);
  assert.match(preview, /parent\.height - height - canvas\.monitorGap/);
  assert.match(layout, /barSetting\.enabled\s*&&\s*monitorCard\.barSetting\.position/);
  assert.match(layout, /effectiveBarHeight \* canvas\.zoom/);
  assert.match(tab, /PanelSeparator[\s\S]*Style\.space\(64\)/);
  assert.match(panel, /sessionTabRestored/);
  assert.doesNotMatch(layout, /setDisplayPosition|previewLayout|drag/i);
  assert.match(host, /Variants\s*\{[\s\S]*?model: Quickshell\.screens/);
  assert.match(host, /configuredEnabledCount\(\) > 0/);
  assert.match(host, /onPopoutRequested: root\.closePeerPopouts\(monitorBar\)/);
  assert.match(monitorBar, /function closeActivePopout\(\)/);
  assert.equal((monitorBar.match(/model: root\.targetScreen \? \[root\.targetScreen\] : \[\]/g) || []).length, 3);
});

test('bar width persists the request while runtime measurements provide a safe minimum', () => {
  let pending = null;
  const context = {
    displayDraft: [{ name: 'DP-1' }],
    config: { bars: { 'DP-1': { enabled: true, position: 'top', width: 100 } } },
    monitorBarMinimums: {},
    validConnector: value => value === 'DP-1',
    shell: { mutateShellConfig() {} },
    panelWanted: true,
    rememberedTab: 0,
    panelTransferUntil: 0,
    saveConfig() {},
    activeStationBar() { return true; },
    deferMonitorBarPublish(name, row) { pending = [name, { ...row }]; },
  };
  context.monitorBar = qmlFunction(service, 'monitorBar', context);
  context.monitorBarMinimum = qmlFunction(service, 'monitorBarMinimum', context);
  const reportMinimum = qmlFunction(service, 'reportMonitorBarMinimum', context);
  const setWidth = qmlFunction(service, 'setMonitorBarWidth', context);

  assert.equal(reportMinimum('DP-1', 63), 'ok');
  assert.equal(context.monitorBarMinimum('DP-1'), 63);
  assert.equal(setWidth('DP-1', 48), 'ok');
  assert.equal(context.config.bars['DP-1'].width, 48);
  assert.deepEqual(pending, ['DP-1', { enabled: true, position: 'top', width: 48, height: 0 }]);
  assert.equal(context.rememberedTab, 1);
  assert.ok(context.panelTransferUntil > Date.now());
  assert.equal(setWidth('DP-1', 0), 'invalid');
  assert.equal(reportMinimum('../bad', 50), 'invalid');
});

test('bar height is per monitor and capped at ten percent of the shorter native side', () => {
  let pending = null;
  const context = {
    displayDraft: [{ name: 'DP-1', width: 1920, height: 1200, scale: 1.25 }],
    config: { bars: { 'DP-1': { enabled: true, position: 'top', width: 100, height: 0 } } },
    validConnector: value => value === 'DP-1',
    shell: { mutateShellConfig() {} },
    panelWanted: true,
    rememberedTab: 0,
    panelTransferUntil: 0,
    saveConfig() {},
    activeStationBar() { return true; },
    deferMonitorBarPublish(name, row) { pending = [name, { ...row }]; },
  };
  context.monitorBar = qmlFunction(service, 'monitorBar', context);
  context.monitorBarMaximumHeight = qmlFunction(service, 'monitorBarMaximumHeight', context);
  const setHeight = qmlFunction(service, 'setMonitorBarHeight', context);

  assert.equal(context.monitorBarMaximumHeight('DP-1'), 120);
  assert.equal(setHeight('DP-1', 120), 'ok');
  assert.equal(context.config.bars['DP-1'].height, 120);
  assert.deepEqual(pending, ['DP-1', { enabled: true, position: 'top', width: 100, height: 120 }]);
  assert.equal(setHeight('DP-1', 121), 'invalid');
});

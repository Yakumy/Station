const test = require('node:test');
const { runtimeSource } = require('../helpers/runtime-source.cjs');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');

const read = name => readFileSync(name, 'utf8');
const { qmlFunction } = require('../helpers/bar-settings.cjs');
const Store = require('../../lib/platform/Store.js');
const service = runtimeSource();

test('bar preferences migrate and reject unknown positions', () => {
  assert.equal(Store.CONFIG_VERSION, 11);
  assert.deepEqual(Store.loadConfig({}).bars, {});
  assert.deepEqual(Store.loadConfig({ bars: {
    'DP-1': { enabled: false, position: 'right', width: 54.6, height: 120.4, background: 'blur', style: 'pill', contentSize: 18.4 },
    'DP-2': { enabled: true, position: 'diagonal', width: 1000, height: 5000, background: 'bad', style: 'unknown', contentSize: 5000 },
    broken: 'bad',
  }}).bars, {
    'DP-1': { enabled: false, position: 'right', width: 55, height: 120, background: 'blur', style: 'pill', contentSize: 18 },
    'DP-2': { enabled: true, position: 'top', width: 100, height: 1000, background: 'solid', style: 'default', contentSize: 1000 },
    broken: { enabled: true, position: 'top', width: 100, height: 0, background: 'solid', style: 'default', contentSize: 0 },
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
    syncBarBlur() {},
    activeStationBar() { return true; },
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

test('turning a bar on or off leaves shell.json alone while the panel is open', () => {
  let published = 0, deferred = null;
  const context = {
    displayDraft: [{ name: 'DP-1', enabled: true }, { name: 'DP-2', enabled: true }],
    config: { bars: { 'DP-1': { enabled: true, position: 'top' }, 'DP-2': { enabled: true, position: 'top' } } },
    validConnector: value => /^DP-/.test(value),
    panelWanted: true, panelTransferUntil: 0, rememberedTab: 0, shell: {},
    saveConfig() {}, syncBarBlur() {},
    activeStationBar() { return true; },
    deferMonitorBarPublish(name, next) { deferred = [name, next.enabled]; },
    publishMonitorBar() { published += 1; return true; },
    publishHost() { return true; },
  };
  context.monitorBar = qmlFunction(service, 'monitorBar', context);
  const setEnabled = qmlFunction(service, 'setMonitorBarEnabled', context);
  assert.equal(setEnabled('DP-2', false), 'ok');
  assert.equal(published, 0, 'a shell.json write rebuilds the widgets, the panel included');
  assert.equal(deferred[0], 'DP-2');
  assert.equal(deferred[1], false);
  assert.equal(context.config.bars['DP-2'].enabled, false, 'Bar.qml follows the live preferences');
  context.panelWanted = false;
  assert.equal(setEnabled('DP-2', true), 'ok');
  assert.equal(published, 1, 'with the panel closed it publishes at once');
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
  assert.equal(context.rememberedTab, require('../../lib/panel/Tabs.js').index('bar'));
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
  assert.deepEqual(pending, [[
    'DP-1', { enabled: true, position: 'right', width: 100, height: 0, background: 'solid', style: 'default', contentSize: 0 },
  ]]);
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
  assert.deepEqual(pending, [
    'DP-1', { enabled: true, position: 'top', width: 48, height: 0, background: 'solid', style: 'default', contentSize: 0 },
  ]);
  assert.equal(context.rememberedTab, require('../../lib/panel/Tabs.js').index('bar'));
  assert.ok(context.panelTransferUntil > Date.now());
  assert.equal(setWidth('DP-1', 0), 'invalid');
  assert.equal(reportMinimum('../bad', 50), 'invalid');
});

test('bar content maximum is reported as runtime geometry and bounded by padded height', () => {
  const context = {
    displayDraft: [{ name: 'DP-1', width: 1920, height: 1200 }],
    config: { bars: { 'DP-1': { enabled: true, position: 'top', width: 100, height: 40 } } },
    monitorBarMaximumContents: {},
    shell: null,
    Style: {
      font: { body: 12 },
      bar: { sizeHorizontal: 26, sizeVertical: 26 },
      spacing: { sm: 4 },
    },
    validConnector: value => value === 'DP-1',
  };
  context.monitorBar = qmlFunction(service, 'monitorBar', context);
  context.monitorBarMaximumHeight = qmlFunction(service, 'monitorBarMaximumHeight', context);
  context.monitorBarRenderedHeight = qmlFunction(service, 'monitorBarRenderedHeight', context);
  context.monitorBarMaximumContent = qmlFunction(service, 'monitorBarMaximumContent', context);
  const reportMaximum = qmlFunction(service, 'reportMonitorBarMaximumContent', context);

  assert.equal(context.monitorBarMaximumContent('DP-1'), 32);
  assert.equal(reportMaximum('DP-1', 27), 'ok');
  assert.equal(context.monitorBarMaximumContent('DP-1'), 27);
  assert.equal(reportMaximum('DP-1', 38), 'ok');
  assert.equal(context.monitorBarMaximumContent('DP-1'), 32,
    'a report cannot exceed the height after both edge insets');
  assert.equal(reportMaximum('../bad', 20), 'invalid');
});

test('bar height is per monitor and capped at five percent of the shorter native side', () => {
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

  assert.equal(context.monitorBarMaximumHeight('DP-1'), 60);
  assert.equal(setHeight('DP-1', 60), 'ok');
  assert.equal(context.config.bars['DP-1'].height, 60);
  assert.deepEqual(pending, [
    'DP-1', { enabled: true, position: 'top', width: 100, height: 60, background: 'solid', style: 'default', contentSize: 0 },
  ]);
  assert.equal(setHeight('DP-1', 61), 'invalid');
});

test('bar background persists per monitor and synchronizes compositor blur', () => {
  let pending = null;
  let blurSyncs = 0;
  const context = {
    displayDraft: [{ name: 'DP-1' }],
    config: { bars: { 'DP-1': {
      enabled: true, position: 'top', width: 100, height: 0, background: 'solid',
    } } },
    validConnector: value => value === 'DP-1',
    shell: { mutateShellConfig() {} },
    panelWanted: true,
    rememberedTab: 0,
    panelTransferUntil: 0,
    saveConfig() {},
    syncBarBlur() { blurSyncs++; },
    activeStationBar() { return true; },
    deferMonitorBarPublish(name, row) { pending = [name, { ...row }]; },
  };
  context.monitorBar = qmlFunction(service, 'monitorBar', context);
  const setBackground = qmlFunction(service, 'setMonitorBarBackground', context);

  assert.equal(setBackground('DP-1', 'blur'), 'ok');
  assert.equal(context.config.bars['DP-1'].background, 'blur');
  assert.equal(blurSyncs, 1);
  assert.deepEqual(pending, ['DP-1', {
    enabled: true, position: 'top', width: 100, height: 0, background: 'blur', style: 'default', contentSize: 0,
  }]);
  assert.equal(setBackground('DP-1', 'glass'), 'invalid');
});

test('bar style persists per monitor and defers the active host mirror', () => {
  let pending = null;
  const context = {
    displayDraft: [{ name: 'DP-1' }],
    config: { bars: { 'DP-1': {
      enabled: true, position: 'top', width: 100, height: 0, background: 'solid', style: 'default',
    } } },
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
  const setStyle = qmlFunction(service, 'setMonitorBarStyle', context);

  assert.equal(setStyle('DP-1', 'pill'), 'ok');
  assert.equal(context.config.bars['DP-1'].style, 'pill');
  assert.deepEqual(pending, ['DP-1', {
    enabled: true, position: 'top', width: 100, height: 0, background: 'solid', style: 'pill', contentSize: 0,
  }]);
  assert.equal(setStyle('DP-1', 'floating'), 'invalid');
});

test('bar content size starts at the Omarchy body size and cannot exceed live geometry', () => {
  let pending = null;
  const context = {
    displayDraft: [{ name: 'DP-1', width: 1920, height: 1200 }],
    config: { bars: { 'DP-1': {
      enabled: true, position: 'top', width: 100, height: 40, background: 'solid',
      style: 'default', contentSize: 0,
    } } },
    Style: { font: { body: 12 }, bar: { sizeHorizontal: 26, sizeVertical: 26 } },
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
  context.monitorBarRenderedHeight = qmlFunction(service, 'monitorBarRenderedHeight', context);
  context.monitorBarMaximumContent = () => 32;
  const setContentSize = qmlFunction(service, 'setMonitorBarContentSize', context);

  assert.equal(context.monitorBarRenderedHeight('DP-1'), 40);
  assert.equal(setContentSize('DP-1', 24), 'ok');
  assert.equal(context.config.bars['DP-1'].contentSize, 24);
  assert.deepEqual(pending, ['DP-1', {
    enabled: true, position: 'top', width: 100, height: 40, background: 'solid',
    style: 'default', contentSize: 24,
  }]);
  assert.equal(setContentSize('DP-1', 11), 'invalid');
  assert.equal(setContentSize('DP-1', 33), 'invalid');
});

test('Omarchy position menu only moves the focused monitor and pins inherited peer edges', () => {
  const host = { bar: { id: 'yakumy.station', position: 'top', monitors: {} } };
  const context = {
    configLoaded: true, globalBarPosition: 'top', lastGlobalBarPosition: '', focusedBarScreenName: 'DP-1',
    config: { bars: { 'DP-1': { position: 'left', width: 65, height: 42, style: 'pill', contentSize: 24 },
      'DP-3': { position: 'right', enabled: false } } },
    displayDraft: [{ name: 'DP-1' }, { name: 'DP-2' }],
    pendingMonitorBars: {}, panelWanted: true, panelTransferUntil: 0,
    validConnector: name => /^DP-[123]$/.test(name),
    activeStationBar: () => true, saveConfig() {},
    shell: { barConfig: host.bar, mutateShellConfig(fn) { fn(host); return true; } },
  };
  for (const name of ['monitorBar', 'deferMonitorBarPublish', 'publishMonitorBars',
    'flushPendingMonitorBars', 'applyBarMenuPosition', 'syncGlobalBarPosition', 'syncFocusedBarMenu'])
    context[name] = qmlFunction(service, name, context);
  context.syncGlobalBarPosition();
  assert.equal(context.config.bars['DP-1'].position, 'left');
  for (const position of ['bottom', 'left', 'right', 'top']) {
    host.bar.position = position;
    context.globalBarPosition = position;
    context.syncGlobalBarPosition();
    assert.equal(context.config.bars['DP-1'].position, position);
    assert.equal(context.config.bars['DP-2'].position, 'top', 'inherited peer keeps its original edge');
    assert.equal(context.config.bars['DP-3'].position, 'right');
  }
  context.focusedBarScreenName = 'DP-2';
  host.bar.position = context.globalBarPosition = 'bottom';
  context.syncGlobalBarPosition();
  assert.equal(context.config.bars['DP-1'].position, 'top');
  assert.equal(context.config.bars['DP-2'].position, 'bottom');
  assert.equal(context.config.bars['DP-1'].width, 65);
  assert.equal(context.config.bars['DP-1'].contentSize, 24);
  assert.equal(context.config.bars['DP-3'].enabled, false);
  assert.equal(context.applyBarMenuPosition('DP-4', 'left', 'top'), 'invalid');
  assert.equal(context.applyBarMenuPosition('DP-1', 'diagonal', 'top'), 'invalid');
  context.panelWanted = false;
  context.flushPendingMonitorBars();
  assert.equal(host.bar.monitors['DP-1'].position, 'top');
  assert.equal(host.bar.monitors['DP-2'].position, 'bottom');
  context.focusedBarScreenName = 'DP-1';
  context.syncFocusedBarMenu();
  assert.equal(host.bar.position, 'top', 'stock menu follows the newly focused bar');
  context.globalBarPosition = host.bar.position;
  context.syncGlobalBarPosition();
  assert.equal(context.config.bars['DP-2'].position, 'bottom', 'focus mirror does not move peers');
  context.ownWrites = {}; // a moment later, when no echo of the mirror can still arrive
  host.bar.position = context.globalBarPosition = 'bottom';
  context.syncGlobalBarPosition();
  assert.equal(context.config.bars['DP-1'].position, 'bottom', 'same menu choice on a second monitor still applies');
});

test('drag completion targets its source monitor even when focus is elsewhere', () => {
  const monitor = read('lib/bars/omarchy/MonitorBar.qml');
  const calls = [];
  const api = { call(name, args) { calls.push([name, [...args]]); return 'ok'; } };
  const request = qmlFunction(read('Bar.qml'), 'requestMonitorPosition', { BarBridge: { current: () => api } });
  for (const connector of ['HDMI-A-1', 'eDP-1']) {
    const context = {
      barMoveCandidate: 'right', barMoveActive: true, position: 'top',
      normalizePosition: value => value,
      positionRequested: position => request({ targetScreenName: connector }, position),
    };
    context.clearBarMove = () => { context.barMoveActive = false; };
    context.setBarPosition = qmlFunction(monitor, 'setBarPosition', context);
    qmlFunction(monitor, 'finishBarMove', context)();
  }
  assert.deepEqual(calls, [['setMonitorBarPosition', ['HDMI-A-1', 'right']],
    ['setMonitorBarPosition', ['eDP-1', 'right']]]);
  assert.match(read('Bar.qml'), /root.requestMonitorPosition\(monitorBar, position\)/);
});

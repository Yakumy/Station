const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { qmlFunction } = require('../helpers/runtime-source.cjs');
const { ownerFunction } = require('../helpers/bar-settings.cjs');
const BarModel = require('../../lib/bars/omarchy/BarModel.js');
const bar = readFileSync('lib/bars/omarchy/MonitorBar.qml', 'utf8');
const clone = value => JSON.parse(JSON.stringify(value));
const layout = () => Object.fromEntries(BarModel.sections.map(section => [section, []]));

test('normalization preserves every section on old and new hosts without duplicate Station widgets', () => {
  for (const sections of [['left', 'center', 'right'], BarModel.sections]) {
    const input = layout();
    input.centerBegin = [{ id: 'omarchy.indicators', customSetting: 3 }];
    input.centerEnd = [{ id: 'omarchy.weather' }];
    input.tray = [{ id: 'yakumy.station' }];
    const context = { BarModel,
      Util: { isPlainObject: BarModel.isPlainObject || (v => !!v && typeof v === 'object'),
        normalizeLayout: value => Object.fromEntries(sections.map(s => [s, clone(value[s] || [])])),
        normalizeLayoutSection: rows => clone(rows || []) },
      pinTrayToInner: BarModel.pinTrayToInner };
    const output = qmlFunction(bar, 'normalizeLayout', context)(input);
    assert.deepEqual(clone(output), input);
    assert.deepEqual(input.left, [], 'normalization does not mutate source data');
  }
});

test('settings changes and structural edits in flanking sections and tray are detected', () => {
  for (const section of ['centerBegin', 'centerEnd', 'tray']) {
    const before = layout(); before[section] = [{ id: 'omarchy.weather', format: 'a' }];
    const after = clone(before); after[section][0].format = 'b';
    assert.deepEqual(BarModel.inlineSettingsDelta(before, after), [
      { region: section, index: 0, entry: after[section][0] },
    ]);
    after[section].push({ id: 'omarchy.clock' });
    assert.equal(BarModel.inlineSettingsDelta(before, after), null);
  }
});

test('activation retires Station rows in all six sections and preserves unrelated entries', () => {
  const config = { bar: { id: 'yakumy.station', layout: layout() } };
  for (const section of BarModel.sections)
    config.bar.layout[section] = [{ id: 'yakumy.station' }, { id: 'keep.' + section }];
  const c = { hostConfig: config, publishHost: change => { change(config); return true; } };
  assert.equal(ownerFunction('reconcileActiveBarLayout', c)(), true);
  for (const section of BarModel.sections)
    assert.deepEqual(config.bar.layout[section], [{ id: 'keep.' + section }]);
});

test('stock leases find widget placement in the new sections', () => {
  const source = readFileSync('lib/bars/StockWidgetLeases.qml', 'utf8');
  for (const section of BarModel.sections) {
    const rows = layout(); rows[section] = [{ id: 'other' }, { id: 'omarchy.monitor' }];
    const locate = qmlFunction(source, 'barPlacement', { BarModel, shell: { barConfig: { bar: { layout: rows } } } });
    assert.deepEqual(clone(locate('omarchy.monitor')), { section, index: 1 });
  }
});

test('drag moves preserve inline settings across every section and reject the tray inside itself', () => {
  const c = { BarModel, Util: { isPlainObject: v => !!v && typeof v === 'object' } };
  c.rawLayoutSection = qmlFunction(bar, 'rawLayoutSection', c);
  c.rawEntryIndex = qmlFunction(bar, 'rawEntryIndex', { root: { entryId: BarModel.entryId } });
  const move = qmlFunction(bar, 'moveModuleInConfig', c);
  const config = { bar: { layout: layout() } };
  config.bar.layout.left = [{ id: 'widget', setting: 7 }, { id: 'omarchy.tray' }];
  let from = 'left';
  for (const to of BarModel.sections.slice(1)) {
    assert.equal(move(config, from, 'widget', to, ''), true);
    assert.deepEqual(config.bar.layout[to], [{ id: 'widget', setting: 7 }]); from = to;
  }
  const before = clone(config);
  assert.equal(move(config, 'left', 'omarchy.tray', 'tray', ''), false);
  assert.deepEqual(config, before);
});

test('the full bar owns one IPC handler and monitor copies only refresh their probe', () => {
  const entry = readFileSync('Bar.qml', 'utf8');
  assert.equal((entry.match(/target: "omarchy.bar"/g) || []).length, 1);
  assert.doesNotMatch(bar, /target: "omarchy.bar"/);
  let refreshed = 0;
  const body = entry.match(/function syncHidden\(\): void \{([\s\S]*?)\n    \}/)[1];
  new Function('root', body)({ instances: [{ syncHidden: () => refreshed++ }, { syncHidden: () => refreshed++ }] });
  assert.equal(refreshed, 2);
});

test('center insertion edges populate empty flanking sections without shifting the clock', () => {
  const calls = [];
  const c = { layoutEntries: region => region === 'center' ? [{ id: 'clock' }] : [],
    entryIndex: BarModel.entryIndex, entryId: BarModel.entryId,
    nextVisibleModuleName: () => '',
    dropBarModule: (...args) => { calls.push(args); return true; } };
  const drop = qmlFunction(bar, 'dropBarModuleAtTarget', c);
  const source = { region: 'left', moduleName: 'widget' };
  const clock = { region: 'center', moduleName: 'clock' };
  assert.equal(drop(source, clock, false), true);
  assert.equal(drop(source, clock, true), true);
  assert.deepEqual(calls, [[source, 'centerBegin', ''], [source, 'centerEnd', '']]);
});

test('the open drawer accepts an empty-section drop, then routes insertion to its widgets', () => {
  const source = { region: 'left', moduleName: 'widget', hostsTraySection: false };
  const host = { width: 100, height: 40, mapFromItem: (_, x, y) => ({ x, y }) };
  const tray = { region: 'right', moduleName: 'omarchy.tray', hostsTraySection: true,
    activeItem: { sectionHost: host } };
  const c = { BarModel, root: { slotWindow: () => null }, barDragWindow: null,
    moduleSlots: [source, tray], vertical: false };
  const drop = qmlFunction(bar, 'moduleDropAtScene', c);
  assert.deepEqual(clone(drop({ x: 20, y: 20 }, source)), { slot: clone(tray), after: false, region: 'tray' });
  const inside = { region: 'tray', moduleName: 'inside', visible: true, width: 40, height: 40,
    x: 0, y: 0, mapToItem: (_, x, y) => ({ x, y }) };
  c.moduleSlots.push(inside);
  assert.equal(drop({ x: 20, y: 20 }, source).slot, inside);
  assert.equal(drop({ x: 120, y: 20 }, source), null, 'closed/off-drawer widgets are not bar targets');
});

test('Station keeps Omarchy indicators in hover-only shape without rewriting the host layout', () => {
  const entry = readFileSync('Bar.qml', 'utf8');
  const apply = qmlFunction(entry, 'applyOmarchyIndicatorHover', { BarModel });
  const input = { layout: layout() };
  input.layout.centerBegin = [{ id: 'omarchy.indicators', items: ['StayAwake'], alwaysShow: true }];
  input.layout.right = [{ id: 'omarchy.indicators' }, { id: 'omarchy.audio' }];
  assert.equal(apply(input), input);
  for (const section of ['centerBegin', 'right'])
    assert.equal(input.layout[section][0].alwaysShow, false, section);
  assert.deepEqual(input.layout.centerBegin[0].items, ['StayAwake']);
  assert.deepEqual(input.layout.right[1], { id: 'omarchy.audio' });
  assert.deepEqual(input.layout.left, []);

  // The inline-settings path patches the running widget instead of rebuilding
  // the bar, so a host alwaysShow is cleared without remounting every module.
  const widget = { settings: { alwaysShow: true } };
  const context = {
    layoutConfig: { centerBegin: [{ id: 'omarchy.indicators' }] },
    entrySettings: BarModel.entrySettings, entryId: BarModel.entryId,
    moduleSlots: [{ region: 'centerBegin', moduleName: 'omarchy.indicators', activeItem: widget }],
  };
  qmlFunction(bar, 'applySettingsDelta', context)([
    { region: 'centerBegin', index: 0, entry: { id: 'omarchy.indicators', alwaysShow: false } },
  ]);
  assert.equal(context.layoutConfig.centerBegin[0].alwaysShow, false);
  assert.equal(widget.settings.alwaysShow, false);
});

test('the bar follows Show Omarchy indicators from the service snapshot', () => {
  const entry = readFileSync('Bar.qml', 'utf8');
  const snapshot = value => ({
    config: { hoverOmarchyIndicators: value, bars: {} }, displayDraft: [] });
  const context = {
    stationBarsKey: '', stationBars: {}, stationBarMaximumHeights: {},
    hoverOmarchyIndicators: false,
    BarBridge: { current: () => ({ snapshot: () => snapshot(true) }) },
  };
  context.root = context;
  const refresh = qmlFunction(entry, 'refreshStationBars', context);
  refresh();
  assert.equal(context.hoverOmarchyIndicators, true);
  context.BarBridge = { current: () => ({ snapshot: () => snapshot(false) }) };
  refresh();
  assert.equal(context.hoverOmarchyIndicators, false);
  context.BarBridge = { current: () => ({ snapshot: () => snapshot(undefined) }) };
  refresh();
  assert.equal(context.hoverOmarchyIndicators, false, 'an absent setting means hover off');
});

test('the bar hides the whole indicator group when the setting is off', () => {
  assert.match(bar, /indicatorHidden: moduleName === "omarchy\.indicators"[\s\S]*?!root\.hoverOmarchyIndicators/);
  assert.match(bar, /visible: !slot\.indicatorHidden/);
  assert.match(bar, /clip: slot\.trayFlowInset > 0 \|\| slot\.dragSource/);
  assert.match(bar, /hoverOmarchyIndicators = config\.hoverOmarchyIndicators === true/);
  assert.doesNotMatch(bar, /clip: true\s*\n\s*z: modulePointer/,
    'a slot that clips its whole subtree hides Omarchy\u2019s out-of-slot hover target');
});

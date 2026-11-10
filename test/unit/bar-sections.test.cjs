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

const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { qmlFunction } = require('../helpers/runtime-source.cjs');
const { ownerFunction } = require('../helpers/bar-settings.cjs');
const BarModel = require('../../lib/bars/omarchy/BarModel.js');
const bar = readFileSync('lib/bars/omarchy/MonitorBar.qml', 'utf8');
const clone = value => JSON.parse(JSON.stringify(value));
const layout = () => Object.fromEntries(BarModel.sections.map(section => [section, []]));

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

test('the full bar owns one IPC handler and monitor copies only refresh their probe', () => {
  const entry = readFileSync('Bar.qml', 'utf8');
  assert.equal((entry.match(/target: "omarchy.bar"/g) || []).length, 1);
  assert.doesNotMatch(bar, /target: "omarchy.bar"/);
  let refreshed = 0;
  const body = entry.match(/function syncHidden\(\): void \{([\s\S]*?)\n    \}/)[1];
  new Function('root', body)({ instances: [{ syncHidden: () => refreshed++ }, { syncHidden: () => refreshed++ }] });
  assert.equal(refreshed, 2);
});

const normalize = entry => typeof entry === 'string' ? (entry ? { id: entry } : null) : (entry && entry.id ? entry : null);
const idsOf = rows => rows.map(entry => BarModel.entryId(normalize(entry)));
const move = (from, index, id, to, before) => config =>
  BarModel.moveEntry(config, { from: { region: from, index, id }, to: { region: to, index: before } }, normalize);
const edit = (config, change) => BarModel.editStationLayout(config, change, normalize);

test('Station draws its widget beside the menu without changing the saved layout', () => {
  const bar = { layout: { ...layout(), left: ['omarchy.menu', { id: 'reel', setting: 3 }] } };
  const before = clone(bar);
  assert.deepEqual(idsOf(BarModel.stationLayout(bar, normalize).left), ['omarchy.menu', 'yakumy.station', 'reel']);
  assert.deepEqual(bar, before);
  assert.deepEqual(idsOf(BarModel.stationLayout({ layout: { left: [{ id: 'reel' }] } }, normalize).left), ['yakumy.station', 'reel'],
    'first without a menu');
  assert.deepEqual(BarModel.stationLayout(null, normalize), { ...layout(), left: [{ id: 'yakumy.station' }] });
});

test('a saved Station row is drawn once, where it is', () => {
  for (const section of BarModel.sections) {
    const bar = { layout: { ...layout(), [section]: [{ id: 'yakumy.station' }] }, stationWidget: { section: 'left', index: 0 } };
    assert.deepEqual(BarModel.stationLayout(bar, normalize), { ...layout(), [section]: [{ id: 'yakumy.station' }] });
  }
});

test('a saved place is clamped, and a malformed one is ignored', () => {
  const bar = stationWidget => ({ layout: { ...layout(), left: ['omarchy.menu'], right: ['a', 'b'] }, stationWidget });
  const at = value => BarModel.stationLayout(bar(value), normalize);
  assert.deepEqual(idsOf(at({ section: 'right', index: 1 }).right), ['a', 'yakumy.station', 'b']);
  assert.deepEqual(idsOf(at({ section: 'right', index: 99 }).right), ['a', 'b', 'yakumy.station']);
  for (const bad of [null, 'right', [], {}, { section: 'nowhere', index: 0 }, { section: 'right', index: -1 },
    { section: 'right', index: 1.5 }, { section: 'right' }, { section: '__proto__', index: 0 }])
    assert.deepEqual(idsOf(at(bad).left), ['omarchy.menu', 'yakumy.station'], JSON.stringify(bad));
});

test('entries Omarchy does not draw do not shift a place', () => {
  const bar = { layout: { ...layout(), left: [], right: [null, 'a', { setting: 1 }, 'b'] }, stationWidget: { section: 'right', index: 1 } };
  assert.deepEqual(BarModel.stationLayout(bar, normalize).right, [null, 'a', { setting: 1 }, { id: 'yakumy.station' }, 'b']);
});

test('dragging Station saves its place, never a layout row', () => {
  const config = { bar: { id: 'yakumy.station', monitors: { 'DP-1': { position: 'left' } },
    layout: { ...layout(), left: ['omarchy.menu', { id: 'reel', setting: 3 }], right: ['a'] } } };
  assert.equal(edit(config, move('left', 1, 'yakumy.station', 'right', 0)), true);
  assert.deepEqual(config.bar.stationWidget, { section: 'right', index: 0 });
  assert.deepEqual(config.bar.layout, { ...layout(), left: ['omarchy.menu', { id: 'reel', setting: 3 }], right: ['a'] });
  assert.deepEqual(config.bar.monitors, { 'DP-1': { position: 'left' } }, 'nothing else changes');
  assert.equal(edit(config, move('right', 0, 'yakumy.station', 'tray', -1)), true);
  assert.deepEqual(config.bar.stationWidget, { section: 'tray', index: 0 });
});

test('a widget dragged around Station lands beside it and keeps its settings', () => {
  const config = { bar: { layout: { ...layout(), left: ['omarchy.menu', { id: 'reel', setting: 3 }] } } };
  // Reel, third as drawn, to before Station.
  assert.equal(edit(config, move('left', 2, 'reel', 'left', 1)), true);
  assert.deepEqual(config.bar.layout.left, ['omarchy.menu', { id: 'reel', setting: 3 }]);
  assert.deepEqual(idsOf(BarModel.stationLayout(config.bar, normalize).left), ['omarchy.menu', 'reel', 'yakumy.station']);
  // And back: an index into the layout as drawn.
  assert.equal(edit(config, move('left', 1, 'reel', 'left', -1)), true);
  assert.deepEqual(idsOf(BarModel.stationLayout(config.bar, normalize).left), ['omarchy.menu', 'yakumy.station', 'reel']);
});

test('moving other widgets does not pin Station, and it follows the menu', () => {
  const config = { bar: { layout: { ...layout(), left: ['omarchy.menu', 'reel'], right: ['a', 'b'] } } };
  assert.equal(edit(config, move('right', 0, 'a', 'right', -1)), true);
  assert.equal('stationWidget' in config.bar, false);
  assert.equal(edit(config, change => BarModel.removeEntry(change, { region: 'left', index: 2, id: 'reel' }, normalize)), true);
  assert.deepEqual(config.bar.layout.left, ['omarchy.menu']);
  assert.equal('stationWidget' in config.bar, false);
});

test('an edit that changes nothing writes nothing', () => {
  const config = { bar: { centerAnchor: 'clock', layout: { center: ['a', 'clock'], left: ['omarchy.menu'] } } };
  const before = clone(config);
  assert.equal(edit(config, move('left', 0, 'not-there', 'right', -1)), false);
  assert.deepEqual(config, before);
  assert.equal(edit(null, () => true), false);
});

test('an older centerAnchor draws, and then saves, as Omarchy migrates it', () => {
  const config = { bar: { centerAnchor: 'omarchy.clock', layout: { left: ['omarchy.menu'], center: ['a', 'b', 'omarchy.clock', 'c'],
    centerBegin: ['x'], centerEnd: ['y'], right: [] } } };
  const drawn = BarModel.stationLayout(config.bar, normalize);
  assert.deepEqual([drawn.centerBegin, drawn.center, drawn.centerEnd], [['x', 'a', 'b'], ['omarchy.clock'], ['c', 'y']]);
  assert.equal(config.bar.centerAnchor, 'omarchy.clock', 'drawing saves nothing');
  assert.equal(edit(config, move('centerEnd', 0, 'c', 'right', -1)), true);
  assert.deepEqual([config.bar.layout.centerBegin, config.bar.layout.center, config.bar.layout.centerEnd, config.bar.layout.right],
    [['x', 'a', 'b'], ['omarchy.clock'], ['y'], ['c']]);
  assert.equal('centerAnchor' in config.bar, false);
  const absent = { centerAnchor: 'gone', layout: { center: ['a', 'b'] } };
  assert.deepEqual(BarModel.stationLayout(absent, normalize).center, ['a', 'b'], 'without its anchor the center stays whole');
});

test('every section takes every kind of widget and gives it back unchanged', () => {
  for (const from of BarModel.sections) for (const to of BarModel.sections) {
    if (from === to) continue;
    const config = { bar: { layout: { ...layout(), [from]: [{ id: 'w', setting: 7 }] }, stationWidget: { section: 'right', index: 0 } } };
    const index = BarModel.stationLayout(config.bar, normalize)[from].findIndex(entry => BarModel.entryId(entry) === 'w');
    assert.equal(edit(config, move(from, index, 'w', to, -1)), true, `${from} to ${to}`);
    assert.deepEqual(config.bar.layout, { ...layout(), [to]: [{ id: 'w', setting: 7 }] });
  }
});

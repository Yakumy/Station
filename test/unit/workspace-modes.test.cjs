const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { runtimeSource, adaptOwners, qmlFunction } = require('../helpers/runtime-source.cjs');
const G = require('../../lib/stations/Grid.js');
const H = require('../../lib/platform/Hypr.js');
const Model = require('../../lib/displays/Model.js');
const Store = require('../../lib/platform/Store.js');
const { outputRows } = require('../../lib/stations/OpenApps.js');
const source = runtimeSource();
const read = path => readFileSync(join(__dirname, '../..', path), 'utf8');

// `spec` is each output's Repetitive count, or the numbers each output owns in
// Non-repetitive, in output order. Omitted, every output gets the default five.
const layoutOf = (outputs, mode, spec) => {
  const layout = { repetitive: {}, nonrepetitive: {} };
  if (Array.isArray(spec)) outputs.forEach((name, i) => { layout[mode][name] = spec[i]; });
  return layout;
};
const map = (outputs, mode, spec) => G.mapping(outputs.map((name, id) => ({ id, name })),
  Object.fromEntries(outputs.map((name, i) => [name, i + 1])), {}, { mode, layout: layoutOf(outputs, mode, spec) });
const range = (a, b) => Array.from({ length: b - a + 1 }, (_, i) => a + i);
const NINE = [range(1, 4), range(5, 9)];
const win = (address, id, monitor) => ({ address, pid: 1, initialClass: 'x', monitor,
  workspace: { id, name: String(id) }, pinned: false });
const apply = (plan, clients) => clients.map(c => {
  const row = plan.windows.find(r => G.sameClient(r, c));
  return row ? { ...c, monitor: row.output, workspace: { id: row.to, name: String(row.to) } } : c;
});

test('each mode assigns the workspaces each monitor gets, as the Workspaces tab shows them', () => {
  // Sync offers three stations: 1, 3 and 5 on the first monitor, 2, 4 and 6 on the second.
  assert.deepEqual(G.assigned('station', ['A', 'B']), [[1, 3, 5], [2, 4, 6]]);
  // Repetitive and Non-repetitive start with five on each monitor.
  assert.deepEqual(G.assigned('repetitive', ['A', 'B']), [range(1, 5), range(1, 5)]);
  assert.deepEqual(G.assigned('nonrepetitive', ['A', 'B', 'C']), [range(1, 5), range(6, 10), range(11, 15)]);
  // Each monitor keeps its own Repetitive count, 1 to 10.
  const counts = { repetitive: { A: 2, B: 7, C: 11 }, nonrepetitive: {} };
  assert.deepEqual(G.assigned('repetitive', ['A', 'B', 'C'], counts), [[1, 2], range(1, 7), range(1, 5)]);
  // Non-repetitive keeps any set the user dragged, while the sets cover 1 to the total.
  const owned = { repetitive: {}, nonrepetitive: { A: [1], B: [2, 3, 4, 5, 6] } };
  assert.deepEqual(G.assigned('nonrepetitive', ['A', 'B'], owned), [[1], [2, 3, 4, 5, 6]]);
  const mixed = { repetitive: {}, nonrepetitive: { A: [1, 3], B: [2, 4] } };
  assert.deepEqual(G.assigned('nonrepetitive', ['A', 'B'], mixed), [[1, 3], [2, 4]]);
  // A gap, a duplicate, an empty monitor or a missing monitor falls back to five each.
  for (const nonrepetitive of [{ A: [1], B: [3] }, { A: [1, 2], B: [2, 3] }, { A: [], B: [1] }, { A: [1, 2] }])
    assert.deepEqual(G.assigned('nonrepetitive', ['A', 'B'], { nonrepetitive }), [range(1, 5), range(6, 10)]);
  assert.equal(G.validOwned([range(1, 10), range(11, 20)]), true);
  assert.equal(G.validOwned([range(1, 11), range(12, 20)]), false);
  assert.equal(G.validOwned([range(1, 10), range(11, 21)]), false);
});

test('mode maps validate, compare by numbering, and Station maps keep the old shape', () => {
  assert.deepEqual(map(['A', 'B'], 'station', 4), { outputs: ['A', 'B'] });
  const rep = map(['A', 'B'], 'repetitive', [3, 4]);
  assert.deepEqual(rep, { outputs: ['A', 'B'], mode: 'repetitive', counts: [3, 4], blocks: [0, 1] });
  assert.deepEqual(map(['A', 'B'], 'nonrepetitive', [[1], [2, 3]]),
    { outputs: ['A', 'B'], mode: 'nonrepetitive', owned: [[1], [2, 3]], counts: [1, 2] });
  // Blocks come from Omarchy's state file; a monitor it has not seen gets the lowest
  // free block, internal panels first, as Omarchy assigns them.
  const known = { byConnector: { 'HDMI-A-2': 1, 'eDP-1': 0 }, taken: [0, 1, 2] };
  assert.deepEqual(G.blocksFor(['HDMI-A-2', 'eDP-1'], known), [1, 0]);
  assert.deepEqual(G.blocksFor(['HDMI-A-2', 'DP-1'], known), [1, 3]);
  assert.deepEqual(G.blocksFor(['DP-1', 'eDP-1'], {}), [1, 0]);
  assert.equal(G.valid({ outputs: ['A', 'B'], mode: 'repetitive', counts: [3, 3], blocks: [1, 1] }), false);
  assert.equal(G.valid({ outputs: ['A', 'B'], mode: 'nonrepetitive', counts: [3, 3], blocks: [0, 1] }), false);
  assert.equal(G.valid({ outputs: ['A', 'B'], mode: 'repetitive', counts: [3, 3] }), true);
  assert.equal(G.equal(rep, Object.assign({}, rep, { blocks: [1, 0] })), false);
  for (const value of [rep, map(['A', 'B'], 'nonrepetitive', NINE)]) assert.equal(G.valid(value), true);
  // Owned lists must match the counts and cover 1 to the total.
  assert.equal(G.valid({ outputs: ['A', 'B'], mode: 'nonrepetitive', counts: [1, 2], owned: [[1], [2, 4]] }), false);
  assert.equal(G.valid({ outputs: ['A', 'B'], mode: 'nonrepetitive', counts: [2, 1], owned: [[1], [2, 3]] }), false);
  assert.equal(G.valid({ outputs: ['A'], mode: 'nonrepetitive', counts: [11] }), false);
  assert.equal(G.valid({ outputs: ['A', 'B'], mode: 'nonrepetitive', counts: [10, 10] }), true);
  assert.equal(G.valid({ outputs: ['A', 'B', 'C'], mode: 'nonrepetitive', counts: [7, 7, 7] }), false);
  assert.equal(G.valid({ outputs: ['A', 'B'], mode: 'repetitive', counts: [3] }), false);
  assert.equal(G.valid({ outputs: ['A'], mode: 'other' }), false);
  assert.equal(G.equal({ outputs: ['A', 'B'] }, map(['A', 'B'], 'station')), true);
  assert.equal(G.equal({ outputs: ['A', 'B'] }, rep), false);
  assert.equal(G.equal(map(['A', 'B'], 'nonrepetitive', NINE), map(['A', 'B'], 'nonrepetitive')), false);
  // The same counts with different numbers are a different map.
  assert.equal(G.equal(map(['A', 'B'], 'nonrepetitive', [[1, 3], [2, 4]]),
    map(['A', 'B'], 'nonrepetitive', [[1, 2], [3, 4]])), false);
  // A map saved before `owned` reads as consecutive blocks.
  assert.equal(G.equal({ outputs: ['A', 'B'], mode: 'nonrepetitive', counts: [5, 5] }, map(['A', 'B'], 'nonrepetitive')), true);
});

test('repetitive uses Omarchy blocks, and non-repetitive owns the numbers each monitor holds', () => {
  const rep = map(['A', 'B'], 'repetitive', [3, 3]);
  assert.equal(G.workspace(3, 'B', rep), 13);
  assert.equal(G.station(13, rep), 3);
  assert.equal(G.slot(13, rep), 1);
  assert.equal(G.slot(10, rep), 0);
  assert.equal(G.contains(21, rep), false);
  assert.deepEqual(G.assignments(rep).slice(0, 4), [[1, 'A'], [11, 'B'], [2, 'A'], [12, 'B']]);
  // A Repetitive map saved before blocks keeps Station's IDs.
  const legacy = { outputs: ['A', 'B'], mode: 'repetitive', counts: [3, 3] };
  assert.equal(G.workspace(3, 'B', legacy), 6);
  assert.equal(G.station(6, legacy), 3);
  const non = map(['A', 'B'], 'nonrepetitive', NINE);
  assert.deepEqual([1, 4, 5, 9, 10].map(id => non.outputs[G.slot(id, non)]), ['A', 'A', 'B', 'B', 'B']);
  assert.equal(G.workspace(5, 'B', non), 5);
  assert.equal(G.workspace(5, 'A', non), null);
  assert.equal(G.home(5, 'A', non), 'B');
  assert.equal(G.contains(20, non), true);
  assert.equal(G.contains(21, non), false);
  assert.deepEqual(G.numbers(non, 1), [5, 6, 7, 8, 9]);
  assert.deepEqual(G.assignments(non).map(([id, output]) => id + output).join(' '),
    '1A 2A 3A 4A 5B 6B 7B 8B 9B 10B 11B 12B 13B 14B 15B 16B 17B 18B 19B 20B');
  // Twenty non-repetitive workspaces: B owns 11 to 20, and the keys' ceiling follows.
  const wide = map(['A', 'B'], 'nonrepetitive', [range(1, 10), range(11, 20)]);
  assert.deepEqual(G.numbers(wide, 1), [11, 12, 13, 14, 15, 16, 17, 18, 19, 20]);
  assert.equal(G.workspace(20, 'B', wide), 20);
  assert.equal(G.home(17, 'A', wide), 'B');
  assert.equal(G.ceiling(wide), 20);
  assert.equal(G.ceiling(rep), 10);
  assert.deepEqual(G.existing([win('0x9', 18, 'B')], [], 3, wide, 'A').slice(-3), [18, 19, 20]);
  assert.deepEqual(H.workspaceRules(G.assignments({ outputs: ['A', 'B'] })), H.compactRules(['A', 'B']));
  // Dragged sets: A owns 1 and 3, B owns 2 and 4, and B takes everything past 4.
  const mixed = map(['A', 'B'], 'nonrepetitive', [[1, 3], [2, 4]]);
  assert.deepEqual([1, 2, 3, 4, 5, 20].map(id => mixed.outputs[G.slot(id, mixed)]), ['A', 'B', 'A', 'B', 'B', 'B']);
  assert.equal(G.workspace(3, 'A', mixed), 3);
  assert.equal(G.home(2, 'A', mixed), 'B');
  assert.deepEqual(G.numbers(mixed, 0), [1, 3]);
});

test('mode changes migrate windows by output and rank, and round trip back to their station', () => {
  const station = { outputs: ['A', 'B'] };
  const non = map(['A', 'B'], 'nonrepetitive', NINE);
  // Station 2 on B is workspace 4; station 5 on A is workspace 9.
  const before = [win('0x1', 4, 'B'), win('0x2', 9, 'A'), win('0x3', 1, 'A')];
  const there = apply(G.plan(station, non, before, 2), before);
  assert.deepEqual(there.map(c => [c.monitor, c.workspace.id]), [['B', 6], ['A', 4], ['A', 1]]);
  const back = apply(G.plan(non, station, there, 2), there);
  assert.deepEqual(back.map(c => [c.monitor, c.workspace.id]), [['B', 4], ['A', 7], ['A', 1]]);
  // Station to Repetitive keeps each window's output and number, in Omarchy's block.
  const rep = map(['A', 'B'], 'repetitive', [3, 3]);
  const repeated = apply(G.plan(station, rep, before, 1), before);
  assert.deepEqual(repeated.map(c => [c.monitor, c.workspace.id]), [['B', 12], ['A', 5], ['A', 1]]);
  const returned = apply(G.plan(rep, station, repeated, 1), repeated);
  assert.deepEqual(returned.map(c => c.workspace.id), before.map(c => c.workspace.id));
  // Between Repetitive maps Omarchy's reconcile owns the windows, so Station moves none.
  assert.deepEqual(G.plan(rep, map(['A'], 'repetitive', [6]), repeated, 1).windows, []);
  // A Repetitive map saved before blocks migrates into the blocks.
  const legacy = { outputs: ['A', 'B'], mode: 'repetitive', counts: [3, 3] };
  assert.deepEqual(apply(G.plan(legacy, rep, before, 1), before).map(c => c.workspace.id), [12, 5, 1]);
  // Into dragged sets a window keeps its output and rank: B's second is 4.
  const mixed = map(['A', 'B'], 'nonrepetitive', [[1, 3], [2, 4]]);
  assert.deepEqual(apply(G.plan(station, mixed, before, 2), before).map(c => [c.monitor, c.workspace.id]),
    [['B', 4], ['A', 3], ['A', 1]]);
});

test('a non-repetitive change hands a number to its new owner and keeps the number', () => {
  const nine = map(['A', 'B'], 'nonrepetitive', NINE), ten = map(['A', 'B'], 'nonrepetitive');
  const before = [win('0x1', 5, 'B'), win('0x2', 6, 'B')];
  const after = apply(G.plan(nine, ten, before, 1), before);
  assert.deepEqual(after.map(c => [c.monitor, c.workspace.id]), [['A', 5], ['B', 6]]);
  // Losing an output keeps the global number on the survivor.
  const single = map(['A'], 'nonrepetitive', [range(1, 9)]);
  assert.deepEqual(apply(G.plan(nine, single, before, 1), before).map(c => [c.monitor, c.workspace.id]), [['A', 5], ['A', 6]]);
  // A journal written for one map retargets to another by the same rules.
  const plan = G.plan({ outputs: ['A', 'B'] }, nine, [win('0x3', 4, 'B')], 1);
  const resumed = G.resume(JSON.parse(JSON.stringify(plan)), { outputs: ['A', 'B'] }, [win('0x3', 4, 'B')]);
  assert.deepEqual(resumed.windows.map(r => [r.output, r.to]), [['B', 4]]);
  // Dragging 5 to A moves its windows to A with the same number.
  const dragged = map(['A', 'B'], 'nonrepetitive', [[1, 2, 3, 4, 5], [6, 7, 8, 9]]);
  assert.deepEqual(apply(G.plan(nine, dragged, before, 1), before).map(c => [c.monitor, c.workspace.id]), [['A', 5], ['B', 6]]);
});

test('navigation steps per output in Repetitive and globally in Non-repetitive', () => {
  const rep = map(['A', 'B'], 'repetitive', [2, 3]);
  const monitors = [{ name: 'A', activeWorkspace: { id: 1 } }, { name: 'B', activeWorkspace: { id: 20 } }];
  assert.deepEqual(G.existing([win('0x1', 9, 'A')], monitors, 3, rep, 'A'), [1, 2, 9]);
  assert.deepEqual(G.existing([], monitors, 3, rep, 'B'), [1, 2, 3, 10]);
  const non = map(['A', 'B'], 'nonrepetitive', [[1, 2], [3, 4]]);
  assert.deepEqual(G.existing([win('0x1', 7, 'B')], monitors, 3, non, 'A'), [1, 2, 3, 4, 7, 20]);
  assert.deepEqual(G.existing([], [], 3, { outputs: ['A', 'B'] }), [1, 2, 3]);
});

test('preferences load the workspace mode, per-monitor layout, indicator style and compact mode', () => {
  const fresh = Store.loadConfig({});
  assert.equal(fresh.workspaceMode, 'station');
  assert.deepEqual(fresh.workspaceLayout, { repetitive: {}, nonrepetitive: {} });
  assert.equal(fresh.indicatorStyle, 'prefixed');
  assert.deepEqual([fresh.compactMode, fresh.showOpenApps], ['hover', true]);
  assert.equal('minStations' in fresh, false);
  assert.equal('workspaceCounts' in fresh, false);
  const saved = Store.loadConfig({ workspaceMode: 'nonrepetitive', indicatorStyle: 'roman', compactMode: 'off', showOpenApps: false,
    minStations: 5, workspaceCounts: { repetitive: 12 },
    workspaceLayout: { repetitive: { A: 7, B: 11, 'bad name': 3 }, nonrepetitive: { A: [3, 1], B: [2, 2], C: [21] } } });
  assert.deepEqual([saved.workspaceMode, saved.indicatorStyle, saved.compactMode, saved.showOpenApps],
    ['nonrepetitive', 'roman', 'off', false]);
  assert.deepEqual(saved.workspaceLayout, { repetitive: { A: 7 }, nonrepetitive: { A: [1, 3] } });
  assert.equal('minStations' in saved, false);
  const bad = Store.loadConfig({ workspaceMode: 'grid', workspaceLayout: [], indicatorStyle: 'emoji', compactMode: 'x' });
  assert.deepEqual([bad.workspaceMode, bad.indicatorStyle, bad.compactMode], ['station', 'prefixed', 'hover']);
  // The dot style is gone: a saved one falls back to the default.
  assert.equal(Store.loadConfig({ indicatorStyle: 'dots' }).indicatorStyle, 'prefixed');
  assert.deepEqual(bad.workspaceLayout, { repetitive: {}, nonrepetitive: {} });
  // The old open apps setting becomes compact mode and the apps switch.
  const migrate = value => { const c = Store.loadConfig({ stationAppsMode: value }); return [c.compactMode, c.showOpenApps, 'stationAppsMode' in c]; };
  assert.deepEqual(migrate('always'), ['off', true, false]);
  assert.deepEqual(migrate('hover'), ['hover', true, false]);
  assert.deepEqual(migrate('hide'), ['on', false, false]);
});

test('Lua helpers validate workspace IDs and connectors', () => {
  assert.match(H.placeWorkspace(5, 'B'), /hl\.get_workspace\(5\).*w\.monitor\.name ~= "B".*workspace = 5, monitor = "B"/);
  assert.match(H.homeWorkspace('B', 5, 10), /a\.id >= 5 and a\.id <= 10/);
  assert.throws(() => H.placeWorkspace(0, 'B'));
  assert.throws(() => H.placeWorkspace(3, 'B"; os.exit()'));
  assert.throws(() => H.homeWorkspace('B', 6, 5));
  assert.match(H.homeWorkspaceAmong('B', [2, 4], 4), /not \(a and \(a\.id == 2 or a\.id == 4 or a\.id > 4\)\).*workspace = 2, monitor = "B"/);
  assert.doesNotMatch(H.homeWorkspaceAmong('A', [1, 3]), /a\.id >/);
  assert.throws(() => H.homeWorkspaceAmong('B', []));
  assert.throws(() => H.homeWorkspaceAmong('B', [0]));
  assert.throws(() => H.workspaceRules([[1, 'bad name']]));
});

test('per-output app rows group by the bar output and its number', () => {
  const rep = map(['A', 'B'], 'repetitive', [3, 3]);
  const rows = outputRows(rep, [win('0x1', 1, 'A'), win('0x2', 12, 'B'), win('0x3', -99, 'A'), win('0x4', 35, 'A')], { address: '0x2' }, null);
  assert.deepEqual(Object.keys(rows), ['A', 'B']);
  assert.deepEqual(rows.A[1].map(x => x.address), ['0x1']);
  assert.deepEqual(rows.B[2].map(x => [x.address, x.focused]), [['0x2', true]]);
  const non = map(['A', 'B'], 'nonrepetitive', NINE);
  assert.deepEqual(Object.keys(outputRows(non, [win('0x1', 7, 'B')], null, null).B), ['7']);
  assert.deepEqual(Object.keys(outputRows(map(['A', 'B'], 'nonrepetitive', [range(1, 10), range(11, 20)]), [win('0x1', 18, 'B')], null, null).B), ['18']);
  assert.deepEqual(outputRows({ outputs: ['A'] }, [win('0x1', 1, 'A')], null, null), {});
});

function switcher(workspaceMap, focused = 'B') {
  const batches = [];
  const c = { Hypr: H, Grid: G, Model, state: 'idle', gen: 0, queuedStation: 0, queuedOutput: '',
    currentStation: 1, persisted: {}, workspaceMap,
    focusedMonitor: () => ({ name: focused }), saveState() {},
    readyForWindows: () => c.state === 'idle',
    workspaceFor: (s, o) => G.workspace(s, o, c.workspaceMap),
    evalLua(lua, done) { batches.push({ lua, done }); } };
  c.root = c;
  adaptOwners(c);
  for (const name of ['begin', 'finish', 'clearQueued', 'showStation', 'showWorkspace', 'stationFocusStatements',
    'settleStatements']) c[name] = qmlFunction(source, name, c);
  return { c, batches };
}

test('switching shows every output in Station mode, one output in Repetitive and the owner in Non-repetitive', () => {
  let { c, batches } = switcher({ outputs: ['A', 'B'] });
  c.showStation(2);
  assert.ok(batches[0].lua.endsWith(H.focusWorkspace(3) + '; ' + H.focusWorkspace(4)));
  ({ c, batches } = switcher(map(['A', 'B'], 'repetitive', [3, 3])));
  c.showStation(2);
  assert.match(batches[0].lua, /focus\(\{ workspace = "12" \}\)\)$/);
  assert.doesNotMatch(batches[0].lua, /focus\(\{ workspace = "2" \}\)/);
  batches[0].done(0, 'ok');
  // A bar click names its own output.
  c.showWorkspace(3, 'A');
  assert.match(batches[1].lua, /focus\(\{ workspace = "3" \}\)\)$/);
  ({ c, batches } = switcher(map(['A', 'B'], 'nonrepetitive', NINE), 'B'));
  c.showStation(2);
  assert.ok(batches[0].lua.endsWith(H.placeWorkspace(2, 'A') + '; ' + H.focusWorkspace(2)));
  // In Station mode a bar click still switches the whole station.
  ({ c, batches } = switcher({ outputs: ['A', 'B'] }, 'A'));
  c.showWorkspace(2, 'B');
  assert.ok(batches[0].lua.endsWith(H.focusWorkspace(4) + '; ' + H.focusWorkspace(3)));
});

test('settling after a non-repetitive or repetitive migration returns each output to its own block', () => {
  const { c } = switcher(map(['A', 'B'], 'nonrepetitive', [[1, 3], [2, 4, 5]]));
  const statements = c.settleStatements(1, 'A');
  assert.deepEqual([...statements], [H.homeWorkspaceAmong('A', [1, 3], null), H.homeWorkspaceAmong('B', [2, 4, 5], 5),
    H.focusMonitor('A')]);
  assert.deepEqual([...switcher(map(['A', 'B'], 'repetitive', [3, 3])).c.settleStatements(1, 'A')],
    [H.homeWorkspace('A', 1, 10), H.homeWorkspace('B', 11, 20), H.focusMonitor('A')]);
});

test('follow focus and station synchronization belong to Station mode only', () => {
  const controller = read('lib/stations/StationController.qml');
  assert.match(controller, /if \(Grid\.mode\(root\.workspaceMap\) !== "station"\) return/);
  assert.match(controller, /var statements = Grid\.mode\(workspaceMap\) === "station" \? stationFocusStatements\(station, client\.monitor\) : \[\]/);
  const owner = read('lib/stations/WorkspaceController.qml');
  assert.match(owner, /if \(Grid\.mode\(workspaceMap\) !== "station"\) \{ settle\(migrationFocus\); return \}/);
});

test('the Workspaces draft applies in one call; map changes are idle-only and start the journaled migration', () => {
  let reconciled = 0, saves = 0;
  const c = { Grid: G, Store, state: 'idle', workspaceData: { pending: null }, removalGrace: { running: false },
    config: Store.loadConfig({}), workspaceMap: { outputs: ['A', 'B'] },
    store: { saveConfig() { saves++; } }, workspace: { reconcile() { reconciled++; } } };
  c.targetMapping = () => G.mapping([{ name: 'A' }, { name: 'B' }], { A: 1, B: 2 }, {},
    { mode: c.config.workspaceMode, layout: c.config.workspaceLayout });
  c.setWorkspaceSetting = qmlFunction(source, 'setWorkspaceSetting', c);
  assert.equal(c.setWorkspaceSetting('workspaces', { compactMode: 'off', showOpenApps: false, indicatorStyle: 'number' }), 'ok');
  assert.deepEqual([c.config.compactMode, c.config.showOpenApps, c.config.indicatorStyle], ['off', false, 'number']);
  assert.equal(reconciled, 0, 'bar options do not renumber');
  for (const bad of [{ workspaceMode: 'grid' }, { compactMode: 'always' }, { indicatorStyle: 'emoji' }, { indicatorStyle: 'dots' }, null])
    assert.equal(c.setWorkspaceSetting('workspaces', bad), 'invalid');
  assert.equal(c.setWorkspaceSetting('workspaces', { workspaceMode: 'nonrepetitive',
    workspaceLayout: { repetitive: {}, nonrepetitive: { A: [1], B: [2, 3, 4, 5, 6] } } }), 'ok');
  assert.equal(reconciled, 1);
  assert.equal(saves, 2, 'one save per apply');
  assert.deepEqual(c.targetMapping().owned, [[1], [2, 3, 4, 5, 6]]);
  c.state = 'migrating';
  assert.equal(c.setWorkspaceSetting('workspaces', { workspaceMode: 'repetitive' }), 'busy');
  assert.equal(c.config.workspaceMode, 'nonrepetitive');
  // Bar options still apply while a migration runs.
  assert.equal(c.setWorkspaceSetting('workspaces', { compactMode: 'on' }), 'ok');
  assert.equal(c.config.compactMode, 'on');
});

test('a first start adopts the workspace rules the user already wrote', () => {
  const rule = (workspace, monitor) => ({ workspaceString: String(workspace), enabled: true, monitor });
  const outputs = ['HDMI-A-1', 'eDP-1'];
  // A split of one range is Non-repetitive with those numbers.
  assert.deepEqual(G.adopt([1, 2, 3].map(n => rule(n, 'HDMI-A-1')).concat([4, 5, 6, 7].map(n => rule(n, 'eDP-1'))), outputs),
    { mode: 'nonrepetitive', layout: { repetitive: {}, nonrepetitive: { 'HDMI-A-1': [1, 2, 3], 'eDP-1': [4, 5, 6, 7] } } });
  // Interleaved numbers stay where the user put them; a gap joins the number below it.
  assert.deepEqual(G.adopt([rule(1, 'eDP-1'), rule(2, 'HDMI-A-1'), rule(5, 'eDP-1')], outputs).layout.nonrepetitive,
    { 'HDMI-A-1': [2, 3, 4], 'eDP-1': [1, 5] });
  // A later rule for the same number wins, as in Hyprland.
  assert.deepEqual(G.adopt([rule(1, 'eDP-1'), rule(2, 'eDP-1'), rule(2, 'HDMI-A-1')], outputs).layout.nonrepetitive,
    { 'HDMI-A-1': [2], 'eDP-1': [1] });
  // A monitor with no rule takes the next five.
  assert.deepEqual(G.adopt([rule(1, 'eDP-1'), rule(2, 'eDP-1')], outputs).layout.nonrepetitive,
    { 'HDMI-A-1': [3, 4, 5, 6, 7], 'eDP-1': [1, 2] });
  // Slots 1 to k of each monitor's own block of ten are Repetitive with k workspaces.
  assert.deepEqual(G.adopt([1, 2, 3].map(n => rule(n, 'eDP-1')).concat([11, 12, 13, 14].map(n => rule(n, 'HDMI-A-1'))), outputs),
    { mode: 'repetitive', layout: { repetitive: { 'HDMI-A-1': 4, 'eDP-1': 3 }, nonrepetitive: {} } });
  // Nothing to keep: no numbered rules, rules for other monitors, Station's own gap
  // rules, one monitor, more than ten on a monitor, or numbers past twenty.
  assert.equal(G.adopt([], outputs), null);
  assert.equal(G.adopt([rule(1, 'DP-9'), { workspaceString: 'm[eDP-1]', gapsOut: [1, 1, 1, 1] }, rule('special:x', 'eDP-1')], outputs), null);
  assert.equal(G.adopt([rule(1, 'eDP-1'), rule(2, 'HDMI-A-1')], ['eDP-1']), null);
  assert.equal(G.adopt([rule(1, 'HDMI-A-1')].concat([2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12].map(n => rule(n, 'eDP-1'))), outputs), null);
  assert.equal(G.adopt([rule(1, 'eDP-1'), rule(25, 'HDMI-A-1')], outputs), null);
  // Whatever it adopts, the saved layout reads back as the same assignment.
  const adopted = G.adopt([rule(1, 'eDP-1'), rule(2, 'HDMI-A-1'), rule(5, 'eDP-1')], outputs);
  assert.deepEqual(G.assigned('nonrepetitive', outputs, Store.workspaceLayout(adopted.layout)), [[2, 3, 4], [1, 5]]);
});

test('the service reads the rules once, before its first start, only on a fresh install', () => {
  const service = readFileSync(join(__dirname, '../../Service.qml'), 'utf8');
  const store = readFileSync(join(__dirname, '../../lib/platform/SettingsStore.qml'), 'utf8');
  assert.match(store, /fresh: configMissing && stateMissing/);
  const start = service.slice(service.indexOf('function maybeStart()'));
  assert.ok(start.indexOf('store.fresh && !workspaceRulesRead') < start.indexOf('started = true'));
  assert.ok(start.indexOf('started = true') < start.indexOf('workspaceAuthority.claim()'));
  assert.match(service, /command: \["hyprctl", "workspacerules", "-j"\]/);
  assert.match(service, /Grid\.adopt\(rules, outputs\)/);
});

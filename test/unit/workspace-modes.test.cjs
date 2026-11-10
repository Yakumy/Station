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

const map = (outputs, mode, total) => G.mapping(outputs.map((name, id) => ({ id, name })),
  Object.fromEntries(outputs.map((name, i) => [name, i + 1])), {}, { mode, counts: { [mode]: total } });
const win = (address, id, monitor) => ({ address, pid: 1, initialClass: 'x', monitor,
  workspace: { id, name: String(id) }, pinned: false });
const apply = (plan, clients) => clients.map(c => {
  const row = plan.windows.find(r => G.sameClient(r, c));
  return row ? { ...c, monitor: row.output, workspace: { id: row.to, name: String(row.to) } } : c;
});

test('each mode assigns the requested workspaces to outputs as the Workspaces tab shows them', () => {
  // Two stations on two monitors: 1 and 3 on the first, 2 and 4 on the second.
  assert.deepEqual(G.assigned('station', 2, 2), [[1, 3], [2, 4]]);
  // Ten repetitive workspaces on three monitors: the remainder joins the last.
  assert.deepEqual(G.assigned('repetitive', 3, 10), [[1, 2, 3], [1, 2, 3], [1, 2, 3, 4]]);
  // Nine non-repetitive workspaces on two monitors.
  assert.deepEqual(G.assigned('nonrepetitive', 2, 9), [[1, 2, 3, 4], [5, 6, 7, 8, 9]]);
  assert.deepEqual(G.assigned('nonrepetitive', 3, 9), [[1, 2, 3], [4, 5, 6], [7, 8, 9]]);
  // Limits keep one workspace per output and no output above ten.
  assert.deepEqual(G.split('repetitive', 3, 29), [9, 10, 10]);
  assert.deepEqual(G.split('nonrepetitive', 3, 1), [1, 1, 1]);
  // Station allows 1 to 5, Repetitive ten per output, Non-repetitive twenty in all.
  assert.deepEqual(G.limits('station', 2), { min: 1, max: 5, fallback: 3 });
  assert.deepEqual(G.limits('repetitive', 3), { min: 3, max: 30, fallback: 15 });
  assert.deepEqual(G.limits('nonrepetitive', 1), { min: 1, max: 10, fallback: 10 });
  assert.deepEqual(G.limits('nonrepetitive', 3), { min: 3, max: 20, fallback: 10 });
  assert.equal(G.total('station', 2, 9), 5);
  assert.equal(G.total('nonrepetitive', 2, 99), 20);
  assert.deepEqual(G.split('nonrepetitive', 2, 20), [10, 10]);
  assert.deepEqual(G.split('nonrepetitive', 3, 20), [6, 6, 8]);
  assert.deepEqual(G.split('repetitive', 2, 99), [10, 10]);
  assert.equal(G.total('repetitive', 2, null), 10);
  assert.equal(G.total('station', 2, 0), 1);
});

test('mode maps validate, compare by numbering, and Station maps keep the old shape', () => {
  assert.deepEqual(map(['A', 'B'], 'station', 4), { outputs: ['A', 'B'] });
  const rep = map(['A', 'B'], 'repetitive', 7);
  assert.deepEqual(rep, { outputs: ['A', 'B'], mode: 'repetitive', counts: [3, 4], blocks: [0, 1] });
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
  for (const value of [rep, map(['A', 'B'], 'nonrepetitive', 9)]) assert.equal(G.valid(value), true);
  assert.equal(G.valid({ outputs: ['A'], mode: 'nonrepetitive', counts: [11] }), false);
  assert.equal(G.valid({ outputs: ['A', 'B'], mode: 'nonrepetitive', counts: [10, 10] }), true);
  assert.equal(G.valid({ outputs: ['A', 'B', 'C'], mode: 'nonrepetitive', counts: [7, 7, 7] }), false);
  assert.equal(G.valid({ outputs: ['A', 'B'], mode: 'repetitive', counts: [3] }), false);
  assert.equal(G.valid({ outputs: ['A'], mode: 'other' }), false);
  assert.equal(G.equal({ outputs: ['A', 'B'] }, map(['A', 'B'], 'station', 9)), true);
  assert.equal(G.equal({ outputs: ['A', 'B'] }, rep), false);
  assert.equal(G.equal(map(['A', 'B'], 'nonrepetitive', 9), map(['A', 'B'], 'nonrepetitive', 10)), false);
});

test('repetitive uses Omarchy blocks, and non-repetitive owns consecutive global numbers', () => {
  const rep = map(['A', 'B'], 'repetitive', 6);
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
  const non = map(['A', 'B'], 'nonrepetitive', 9);
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
  const wide = map(['A', 'B'], 'nonrepetitive', 20);
  assert.deepEqual(G.numbers(wide, 1), [11, 12, 13, 14, 15, 16, 17, 18, 19, 20]);
  assert.equal(G.workspace(20, 'B', wide), 20);
  assert.equal(G.home(17, 'A', wide), 'B');
  assert.equal(G.ceiling(wide), 20);
  assert.equal(G.ceiling(rep), 10);
  assert.deepEqual(G.existing([win('0x9', 18, 'B')], [], 3, wide, 'A').slice(-3), [18, 19, 20]);
  assert.deepEqual(H.workspaceRules(G.assignments({ outputs: ['A', 'B'] })), H.compactRules(['A', 'B']));
});

test('mode changes migrate windows by output and rank, and round trip back to their station', () => {
  const station = { outputs: ['A', 'B'] };
  const non = map(['A', 'B'], 'nonrepetitive', 9);
  // Station 2 on B is workspace 4; station 5 on A is workspace 9.
  const before = [win('0x1', 4, 'B'), win('0x2', 9, 'A'), win('0x3', 1, 'A')];
  const there = apply(G.plan(station, non, before, 2), before);
  assert.deepEqual(there.map(c => [c.monitor, c.workspace.id]), [['B', 6], ['A', 4], ['A', 1]]);
  const back = apply(G.plan(non, station, there, 2), there);
  assert.deepEqual(back.map(c => [c.monitor, c.workspace.id]), [['B', 4], ['A', 7], ['A', 1]]);
  // Station to Repetitive keeps each window's output and number, in Omarchy's block.
  const rep = map(['A', 'B'], 'repetitive', 6);
  const repeated = apply(G.plan(station, rep, before, 1), before);
  assert.deepEqual(repeated.map(c => [c.monitor, c.workspace.id]), [['B', 12], ['A', 5], ['A', 1]]);
  const returned = apply(G.plan(rep, station, repeated, 1), repeated);
  assert.deepEqual(returned.map(c => c.workspace.id), before.map(c => c.workspace.id));
  // Between Repetitive maps Omarchy's reconcile owns the windows, so Station moves none.
  assert.deepEqual(G.plan(rep, map(['A'], 'repetitive', 6), repeated, 1).windows, []);
  // A Repetitive map saved before blocks migrates into the blocks.
  const legacy = { outputs: ['A', 'B'], mode: 'repetitive', counts: [3, 3] };
  assert.deepEqual(apply(G.plan(legacy, rep, before, 1), before).map(c => c.workspace.id), [12, 5, 1]);
});

test('a non-repetitive count change hands a number to its new owner and keeps the number', () => {
  const nine = map(['A', 'B'], 'nonrepetitive', 9), ten = map(['A', 'B'], 'nonrepetitive', 10);
  const before = [win('0x1', 5, 'B'), win('0x2', 6, 'B')];
  const after = apply(G.plan(nine, ten, before, 1), before);
  assert.deepEqual(after.map(c => [c.monitor, c.workspace.id]), [['A', 5], ['B', 6]]);
  // Losing an output keeps the global number on the survivor.
  const single = map(['A'], 'nonrepetitive', 9);
  assert.deepEqual(apply(G.plan(nine, single, before, 1), before).map(c => [c.monitor, c.workspace.id]), [['A', 5], ['A', 6]]);
  // A journal written for one map retargets to another by the same rules.
  const plan = G.plan({ outputs: ['A', 'B'] }, nine, [win('0x3', 4, 'B')], 1);
  const resumed = G.resume(JSON.parse(JSON.stringify(plan)), { outputs: ['A', 'B'] }, [win('0x3', 4, 'B')]);
  assert.deepEqual(resumed.windows.map(r => [r.output, r.to]), [['B', 4]]);
});

test('navigation steps per output in Repetitive and globally in Non-repetitive', () => {
  const rep = map(['A', 'B'], 'repetitive', 5);
  const monitors = [{ name: 'A', activeWorkspace: { id: 1 } }, { name: 'B', activeWorkspace: { id: 20 } }];
  assert.deepEqual(G.existing([win('0x1', 9, 'A')], monitors, 3, rep, 'A'), [1, 2, 9]);
  assert.deepEqual(G.existing([], monitors, 3, rep, 'B'), [1, 2, 3, 10]);
  const non = map(['A', 'B'], 'nonrepetitive', 4);
  assert.deepEqual(G.existing([win('0x1', 7, 'B')], monitors, 3, non, 'A'), [1, 2, 3, 4, 7, 20]);
  assert.deepEqual(G.existing([], [], 3, { outputs: ['A', 'B'] }), [1, 2, 3]);
});

test('preferences load the workspace mode, requested counts and indicator style', () => {
  const fresh = Store.loadConfig({});
  assert.equal(fresh.workspaceMode, 'station');
  assert.deepEqual(fresh.workspaceCounts, { repetitive: null, nonrepetitive: null });
  assert.equal(fresh.indicatorStyle, 'prefixed');
  const saved = Store.loadConfig({ workspaceMode: 'nonrepetitive', workspaceCounts: { repetitive: 12, nonrepetitive: 'x' },
    indicatorStyle: 'roman' });
  assert.deepEqual([saved.workspaceMode, saved.workspaceCounts, saved.indicatorStyle],
    ['nonrepetitive', { repetitive: 12, nonrepetitive: null }, 'roman']);
  const bad = Store.loadConfig({ workspaceMode: 'grid', workspaceCounts: [], indicatorStyle: 'emoji' });
  assert.deepEqual([bad.workspaceMode, bad.indicatorStyle], ['station', 'prefixed']);
});

test('Lua helpers validate workspace IDs and connectors', () => {
  assert.match(H.placeWorkspace(5, 'B'), /hl\.get_workspace\(5\).*w\.monitor\.name ~= "B".*workspace = 5, monitor = "B"/);
  assert.match(H.homeWorkspace('B', 5, 10), /a\.id >= 5 and a\.id <= 10/);
  assert.throws(() => H.placeWorkspace(0, 'B'));
  assert.throws(() => H.placeWorkspace(3, 'B"; os.exit()'));
  assert.throws(() => H.homeWorkspace('B', 6, 5));
  assert.throws(() => H.workspaceRules([[1, 'bad name']]));
});

test('per-output app rows group by the bar output and its number', () => {
  const rep = map(['A', 'B'], 'repetitive', 6);
  const rows = outputRows(rep, [win('0x1', 1, 'A'), win('0x2', 12, 'B'), win('0x3', -99, 'A'), win('0x4', 35, 'A')], { address: '0x2' }, null);
  assert.deepEqual(Object.keys(rows), ['A', 'B']);
  assert.deepEqual(rows.A[1].map(x => x.address), ['0x1']);
  assert.deepEqual(rows.B[2].map(x => [x.address, x.focused]), [['0x2', true]]);
  const non = map(['A', 'B'], 'nonrepetitive', 9);
  assert.deepEqual(Object.keys(outputRows(non, [win('0x1', 7, 'B')], null, null).B), ['7']);
  assert.deepEqual(Object.keys(outputRows(map(['A', 'B'], 'nonrepetitive', 20), [win('0x1', 18, 'B')], null, null).B), ['18']);
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
  ({ c, batches } = switcher(map(['A', 'B'], 'repetitive', 6)));
  c.showStation(2);
  assert.match(batches[0].lua, /focus\(\{ workspace = "12" \}\)\)$/);
  assert.doesNotMatch(batches[0].lua, /focus\(\{ workspace = "2" \}\)/);
  batches[0].done(0, 'ok');
  // A bar click names its own output.
  c.showWorkspace(3, 'A');
  assert.match(batches[1].lua, /focus\(\{ workspace = "3" \}\)\)$/);
  ({ c, batches } = switcher(map(['A', 'B'], 'nonrepetitive', 9), 'B'));
  c.showStation(2);
  assert.ok(batches[0].lua.endsWith(H.placeWorkspace(2, 'A') + '; ' + H.focusWorkspace(2)));
  // In Station mode a bar click still switches the whole station.
  ({ c, batches } = switcher({ outputs: ['A', 'B'] }, 'A'));
  c.showWorkspace(2, 'B');
  assert.ok(batches[0].lua.endsWith(H.focusWorkspace(4) + '; ' + H.focusWorkspace(3)));
});

test('settling after a non-repetitive or repetitive migration returns each output to its own block', () => {
  const { c } = switcher(map(['A', 'B'], 'nonrepetitive', 9));
  const statements = c.settleStatements(1, 'A');
  assert.deepEqual([...statements], [H.homeWorkspace('A', 1, 4), H.homeWorkspace('B', 5, 20), H.focusMonitor('A')]);
  assert.deepEqual([...switcher(map(['A', 'B'], 'repetitive', 6)).c.settleStatements(1, 'A')],
    [H.homeWorkspace('A', 1, 10), H.homeWorkspace('B', 11, 20), H.focusMonitor('A')]);
});

test('follow focus and station synchronization belong to Station mode only', () => {
  const controller = read('lib/stations/StationController.qml');
  assert.match(controller, /if \(Grid\.mode\(root\.workspaceMap\) !== "station"\) return/);
  assert.match(controller, /var statements = Grid\.mode\(workspaceMap\) === "station" \? stationFocusStatements\(station, client\.monitor\) : \[\]/);
  const owner = read('lib/stations/WorkspaceController.qml');
  assert.match(owner, /if \(Grid\.mode\(workspaceMap\) !== "station"\) \{ settle\(migrationFocus\); return \}/);
});

test('workspace mode and count changes are idle-only, clamped, and start the journaled migration', () => {
  let reconciled = 0;
  const c = { Grid: G, state: 'idle', workspaceData: { pending: null }, removalGrace: { running: false },
    config: { workspaceMode: 'station', minStations: 3, workspaceCounts: { repetitive: null, nonrepetitive: null } },
    workspaceTarget: { outputs: ['A', 'B'] }, workspaceMap: { outputs: ['A', 'B'] },
    store: { saveConfig() {} }, workspace: { reconcile() { reconciled++; } } };
  c.targetMapping = () => G.mapping([{ name: 'A' }, { name: 'B' }], { A: 1, B: 2 }, {},
    { mode: c.config.workspaceMode, counts: c.config.workspaceCounts });
  c.setWorkspaceSetting = qmlFunction(source, 'setWorkspaceSetting', c);
  assert.equal(c.setWorkspaceSetting('workspaceCount', 40), 'ok');
  assert.equal(c.config.minStations, 5);
  assert.equal(reconciled, 0, 'a station count does not renumber');
  assert.equal(c.setWorkspaceSetting('workspaceMode', 'grid'), 'invalid');
  assert.equal(c.setWorkspaceSetting('workspaceMode', 'nonrepetitive'), 'ok');
  assert.equal(reconciled, 1);
  assert.equal(c.setWorkspaceSetting('workspaceCount', 1), 'ok');
  assert.equal(c.config.workspaceCounts.nonrepetitive, 2);
  c.state = 'migrating';
  assert.equal(c.setWorkspaceSetting('workspaceCount', 5), 'busy');
  assert.equal(c.config.workspaceCounts.nonrepetitive, 2);
});

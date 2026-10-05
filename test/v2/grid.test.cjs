const test = require('node:test');
const assert = require('node:assert/strict');
const G = require('../../lib/Grid.js');
const H = require('../../lib/Hypr.js');
const S = require('../../lib/Store.js');
const maps = ['A', 'B', 'C', 'AB', 'AC', 'BC', 'ABC', 'BA', 'CBA'].map(s => ({ outputs: s.split('') }));
function windows(map) {
  return Array.from({ length: 10 * map.outputs.length }, (_, i) => ({
    address: '0x' + (i + 1).toString(16), pid: i + 10, initialClass: 'test',
    monitor: map.outputs[i % map.outputs.length], workspace: { id: i + 1, name: String(i + 1) }, pinned: false,
  }));
}
function apply(plan, clients, limit = Infinity) {
  return clients.map(c => {
    const row = plan.windows.slice(0, limit).find(r => G.sameClient(r, c));
    return row ? { ...c, monitor: row.output, workspace: { id: row.to, name: String(row.to) } } : c;
  });
}

test('compact IDs cover every slot for one, two and three outputs', () => {
  for (const map of maps) for (let s = 1; s <= 10; s++) for (const output of map.outputs) {
    const id = G.workspace(s, output, map);
    assert.equal(G.station(id, map), s);
    assert.equal(map.outputs[G.slot(id, map)], output);
  }
  assert.deepEqual([1, 2, 3].map(s => G.workspace(s, 'A', maps[0])), [1, 2, 3]);
  assert.deepEqual([1, 2, 3].map(s => ['A', 'B'].map(o => G.workspace(s, o, { outputs: ['A', 'B'] }))), [[1, 2], [3, 4], [5, 6]]);
});

test('all output-count and role transitions preserve station, retain survivors, and converge', () => {
  for (const from of maps) for (const to of maps) {
    const before = windows(from);
    // Hyprland can move removed-output windows before Station receives the event.
    const displaced = before.map(c => ({ ...c, monitor: to.outputs.includes(c.monitor) ? c.monitor : to.outputs[0] }));
    const plan = G.plan(from, to, displaced, 3);
    const after = apply(plan, displaced);
    assert.equal(plan.windows.length, before.length);
    for (let i = 0; i < before.length; i++) {
      assert.equal(G.station(after[i].workspace.id, to), G.station(before[i].workspace.id, from));
      assert.ok(to.outputs.includes(after[i].monitor));
      if (to.outputs.includes(before[i].monitor)) assert.equal(after[i].monitor, before[i].monitor);
    }
    assert.deepEqual(apply(G.plan(to, to, after, 3), after), after);
  }
});

test('single workspace 3 expands to station 3 on the original display and returns to 3', () => {
  const single = { outputs: ['A'] }, dual = { outputs: ['A', 'B'] };
  const before = [windows(single)[2]];
  const expanded = apply(G.plan(single, dual, before, 3), before);
  assert.equal(expanded[0].workspace.id, 5);
  assert.equal(expanded[0].monitor, 'A');
  const collapsed = apply(G.plan(dual, single, expanded, 3), expanded);
  assert.equal(collapsed[0].workspace.id, 3);
});

test('snapshot-address migration avoids overlapping source/destination contamination', () => {
  for (const from of maps) for (const to of maps) {
    const before = windows(from);
    const plan = G.plan(from, to, before.map(c => ({ ...c, monitor: to.outputs[0] })), 1);
    // Apply one window at a time, including IDs another window still uses.
    let after = before;
    for (const row of plan.windows) after = apply({ windows: [row] }, after);
    assert.equal(new Set(after.map(c => c.address)).size, before.length);
    for (let i = 0; i < before.length; i++)
      assert.equal(G.station(after[i].workspace.id, to), G.station(before[i].workspace.id, from));
  }
});

test('journal resumes partial moves even if topology changes again', () => {
  const from = { outputs: ['A'] }, dual = { outputs: ['A', 'B'] }, triple = { outputs: ['A', 'B', 'C'] };
  const before = windows(from);
  const plan = G.plan(from, dual, before, 3);
  const partial = apply(plan, before, 6);
  for (const target of [dual, triple, { outputs: ['B'] }]) {
    const resumed = G.resume(JSON.parse(JSON.stringify(plan)), target, partial);
    const after = apply(resumed, partial);
    for (let i = 0; i < before.length; i++) assert.equal(G.station(after[i].workspace.id, target), i + 1);
  }
  const reused = partial.map(c => ({ ...c, pid: c.pid + 100 }));
  assert.equal(G.resume(plan, dual, reused).windows.length, 0);
  assert.equal(G.resume(plan, dual, []).windows.length, 0);
});

test('legacy conversion is explicit; single numbering never inherits three-slot decoding', () => {
  const from = G.legacy({ A: 1, B: 2 }), to = { outputs: ['A', 'B'] };
  const before = [{ ...windows(to)[0], workspace: { id: 7, name: '7' } }];
  assert.equal(G.plan(from, to, before, 3).windows[0].to, 5);
  const misplaced = [{ ...windows(to)[0], workspace: { id: 2, name: '2' } }];
  const repaired = G.plan(from, to, misplaced, 1).windows[0];
  assert.equal(repaired.output, 'A');
  assert.equal(repaired.to, 1);
  assert.equal(S.loadState({ version: 1 }).legacyWorkspaceGrid, true);
  assert.equal(S.stateDefaults().legacyWorkspaceGrid, false);
  assert.equal(S.loadState({ version: 2 }).legacyWorkspaceGrid, false);
});

test('pinned, named, special and unmanaged windows are excluded', () => {
  const map = { outputs: ['A', 'B'] }, c = windows(map)[0];
  const excluded = [
    { ...c, pinned: true }, { ...c, workspace: { id: -99, name: 'special:scratchpad' } },
    { ...c, workspace: { id: 1, name: 'custom' } }, { ...c, workspace: { id: 50 } },
    { ...c, monitor: 'D' },
  ];
  assert.deepEqual(G.plan(map, { outputs: ['A'] }, excluded, 1).windows, []);
});

test('active mapping uses dense slots independently of preferred lane numbers', () => {
  const monitors = [{ name: 'A' }, { name: 'B' }, { name: 'C', disabled: true }];
  const lanes = { A: 3, B: 1, C: 2 };
  assert.deepEqual(G.mapping(monitors, lanes, { mode: 'extend' }), { outputs: ['B', 'A'] });
  assert.deepEqual(G.mapping(monitors, lanes, { mode: 'single', singleTarget: 'A' }), { outputs: ['A'] });
  assert.deepEqual(G.mapping(monitors, lanes, { mode: 'mirror' }), { outputs: ['B'] });
  assert.equal(G.valid(G.mapping([], lanes, {})), false);
  assert.equal(G.valid({ outputs: ['A', 'A'] }), false);
});

test('workspace rules cover exactly the new compact range', () => {
  const rules = H.compactRules(['A', 'B']);
  assert.equal(rules.length, 20);
  assert.match(rules[4], /workspace = "5", monitor = "A"/);
  assert.match(rules[19], /workspace = "20", monitor = "B"/);
});

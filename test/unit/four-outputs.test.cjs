// Issue #14: four outputs, simulated with the reporter's exact monitors. No
// compositor or file is touched; the live path is covered in docs/testing.md.
const test = require('node:test');
const assert = require('node:assert/strict');
const M = require('../../lib/displays/Model.js');
const G = require('../../lib/stations/Grid.js');
const L = require('../../lib/displays/MonitorsLua.js');

const monitors = [
  { name: 'HDMI-A-1', description: 'CXK CF15T', width: 1920, height: 1080, x: 3713, y: 1440, transform: 0, availableModes: ['1920x1080@60.00Hz'] },
  { name: 'DP-1', description: 'AOC 27B2 0x00012D5D', width: 1920, height: 1080, x: 6440, y: -355, transform: 3, availableModes: ['1920x1080@60.00Hz'] },
  { name: 'DP-2', description: 'AOC 27B2 0x00012F4C', width: 1920, height: 1080, x: 1920, y: -233, transform: 1, availableModes: ['1920x1080@60.00Hz'] },
  { name: 'DP-3', description: 'AOC U34G2G4R3 0x00000959', width: 3440, height: 1440, x: 3000, y: 0, transform: 0, availableModes: ['3440x1440@144.00Hz'] },
];
const names = monitors.map(m => m.name);

test('the three limits agree on four outputs', () => {
  assert.equal(M.MAX_MONITORS, 4);
  assert.equal(G.MAX_OUTPUTS, M.MAX_MONITORS);
  assert.equal(L.MAX_LANE, M.MAX_MONITORS);
});

test('the reported four monitors all get lanes and none is unmanaged', () => {
  // Reproduces the report: the first three held lanes 1 to 3 before DP-3 appeared.
  const before = M.assignLanes(monitors.slice(0, 3), {}, {});
  const after = M.assignLanes(monitors, before.preferences, before.lanes);
  assert.deepEqual(after.lanes, { 'HDMI-A-1': 1, 'DP-1': 2, 'DP-2': 3, 'DP-3': 4 });
  assert.deepEqual(after.unmanaged, []);
  const fifth = M.assignLanes(monitors.concat([{ name: 'DP-4', description: 'Fifth' }]), after.preferences, after.lanes);
  assert.deepEqual(fifth.unmanaged, ['DP-4'], 'a fifth output stays unmanaged');
});

test('every workspace mode maps all four outputs', () => {
  const { lanes } = M.assignLanes(monitors, {}, {});
  const sync = G.mapping(monitors, lanes, {}, { mode: 'station' });
  assert.deepEqual(sync.outputs, names);
  assert.ok(G.valid(sync));
  const rows = G.assignments(sync);
  assert.equal(rows.length, 40);
  assert.deepEqual(rows.map(r => r[0]).sort((a, b) => a - b), Array.from({ length: 40 }, (_, i) => i + 1));
  for (const name of names) assert.equal(rows.filter(r => r[1] === name).length, 10);
  assert.equal(G.workspace(1, 'DP-3', sync), 4);
  assert.equal(G.station(8, sync), 2);
  assert.equal(G.slot(8, sync), 3);

  const repetitive = G.mapping(monitors, lanes, {}, { mode: 'repetitive', layout: {}, blocks: {} });
  assert.ok(G.valid(repetitive));
  assert.deepEqual(repetitive.counts, [5, 5, 5, 5]);
  assert.deepEqual(repetitive.blocks, [0, 1, 2, 3]);
  assert.equal(G.workspace(1, 'DP-3', repetitive), 31);

  const non = G.mapping(monitors, lanes, {}, { mode: 'nonrepetitive', layout: {} });
  assert.ok(G.valid(non));
  assert.deepEqual(non.owned, [[1, 2, 3, 4, 5], [6, 7, 8, 9, 10], [11, 12, 13, 14, 15], [16, 17, 18, 19, 20]]);
  assert.equal(G.home(17, 'HDMI-A-1', non), 'DP-3');
  assert.equal(G.valid({ outputs: names.concat(['DP-4']) }), false, 'five outputs are not a valid map');
});

test('adding the fourth output keeps every window on its monitor and station', () => {
  const three = { outputs: names.slice(0, 3) };
  const four = { outputs: names };
  const clients = names.slice(0, 3).flatMap((monitor, index) => [1, 2, 3].map(station => ({
    address: '0x' + monitor + station, pid: 1, initialClass: 'app', monitor,
    workspace: { id: G.workspace(station, monitor, three), name: String(G.workspace(station, monitor, three)) },
  })));
  const plan = G.plan(three, four, clients, 1);
  assert.equal(plan.windows.length, 9);
  for (const row of plan.windows) {
    const client = clients.find(c => c.address === row.address);
    assert.equal(row.output, client.monitor);
    assert.equal(row.station, G.station(client.workspace.id, three));
    assert.equal(G.slot(row.to, four), names.indexOf(client.monitor));
  }
});

test('the monitor block accepts lane four and rejects lane five', () => {
  const displays = monitors.map((m, i) => ({ name: m.name, mode: m.availableModes[0], availableModes: m.availableModes,
    x: m.x, y: m.y, scale: 1, transform: m.transform, enabled: true, lane: i + 1 }));
  const generated = L.generate(displays, { mode: 'extend', enabled: names });
  assert.equal(generated.displays[3].lane, 4);
  assert.match(generated.block, /hl\.monitor\(\{ output = "DP-3", mode = "3440x1440@144.00Hz", position = "3000x0"/);
  assert.equal(Object.keys(L.managedGeometry(generated.block)).length, 4);
  assert.equal(L.runtimeModeStates(displays, { mode: 'single', singleTarget: 'DP-3', enabled: names })
    .filter(row => !row.disabled).map(row => row.name).join(), 'DP-3');
  assert.throws(() => L.generate(displays.map((d, i) => i === 3 ? { ...d, lane: 5 } : d), {}), /invalid lane/);
});

const test = require('node:test');
const assert = require('node:assert/strict');
const M = require('../../lib/Model.js');

const presentSets = [[1], [2], [3], [1, 2], [1, 3], [2, 3], [1, 2, 3]];
const laneMap = { A: 1, B: 2, C: 3 };

test('workspace grid is stable and invertible', () => {
  for (let station = 1; station <= 10; station++) for (let lane = 1; lane <= 3; lane++) {
    const id = M.ws(station, lane);
    assert.equal(M.stationOf(id), station);
    assert.equal(M.slotOf(id), lane);
    assert.equal(M.inGrid(id), true);
  }
  for (const id of [-1, 0, 31, 1.5]) assert.equal(M.inGrid(id), false);
});

test('host follows the specified higher-then-lower rule', () => {
  assert.equal(M.host(1, [2, 3]), 2);
  assert.equal(M.host(1, [3]), 3);
  assert.equal(M.host(2, [1, 3]), 3);
  assert.equal(M.host(2, [1]), 1);
  assert.equal(M.host(3, [1, 2]), 2);
  assert.equal(M.host(3, [1]), 1);
  assert.equal(M.host(2, []), null);
});

test('every non-empty present-set transition preserves station and converges', () => {
  for (const from of presentSets) for (const to of presentSets) {
    const clients = [];
    for (let station = 1; station <= 10; station++) for (const lane of from) {
      clients.push({ address: `0x${(station * 10 + lane).toString(16)}`, monitor: ['A', 'B', 'C'][lane - 1],
        pinned: false, workspace: { id: M.ws(station, lane) } });
    }
    const plan = M.planReconcile(clients, to, laneMap);
    const moved = new Map(plan.map(move => [move.address, move.to]));
    const after = clients.map(client => ({ ...client, workspace: { id: moved.get(client.address) ?? client.workspace.id } }));
    for (const client of after) {
      const before = clients.find(value => value.address === client.address);
      assert.equal(M.stationOf(client.workspace.id), M.stationOf(before.workspace.id));
      assert.ok(to.includes(M.slotOf(client.workspace.id)));
    }
    assert.deepEqual(M.planReconcile(after, to, laneMap), []);
    if (to.every(lane => from.includes(lane))) continue;
    // Adding lanes alone does not move anything already on a surviving lane.
    if (from.every(lane => to.includes(lane))) assert.deepEqual(plan, []);
  }
});

test('reconcile ignores pinned, non-grid, and unmanaged clients', () => {
  const clients = [
    { address: '0x1', monitor: 'A', pinned: true, workspace: { id: 1 } },
    { address: '0x2', monitor: 'A', pinned: false, workspace: { id: 31 } },
    { address: '0x3', monitor: 'D', pinned: false, workspace: { id: 1 } },
  ];
  assert.deepEqual(M.planReconcile(clients, [2], laneMap), []);
});

test('lane assignment is stable, reuses absent preferences, and caps at three', () => {
  const first = M.assignLanes([
    { name: 'eDP-1', model: 'Panel' }, { name: 'HDMI-A-1', description: 'Dock A', serial: 'AA' },
  ], { 'Panel@eDP-1': 2, 'Dock A': 1 }, {});
  assert.deepEqual(first.lanes, { 'eDP-1': 2, 'HDMI-A-1': 1 });
  const next = M.assignLanes([
    { name: 'eDP-1', model: 'Panel' }, { name: 'DP-1', description: 'Dock B', serial: 'BB' },
    { name: 'DP-2', description: 'Dock C', serial: 'CC' }, { name: 'DP-3', description: 'Dock D', serial: 'DD' },
  ], { ...first.preferences, 'Dock B': 1 }, { 'eDP-1': 2 });
  assert.equal(next.lanes['eDP-1'], 2);
  assert.equal(next.lanes['DP-1'], 1);
  assert.equal(next.lanes['DP-2'], 3);
  assert.deepEqual(next.unmanaged, ['DP-3']);
});

test('identical descriptions are disambiguated by connector', () => {
  assert.deepEqual(M.identities([
    { name: 'DP-1', description: 'Same', serial: 'X' },
    { name: 'DP-2', description: 'Same', serial: 'X' },
  ]), ['Same@DP-1', 'Same@DP-2']);
});

test('mode present sets and zero-enabled fallback', () => {
  const monitors = [{ name: 'A' }, { name: 'B' }, { name: 'C' }];
  assert.deepEqual(M.presentForMode(monitors, laneMap, 'extend', ['A', 'C'], ''), [1, 3]);
  assert.deepEqual(M.presentForMode(monitors, laneMap, 'mirror', ['B', 'C'], ''), [2]);
  assert.deepEqual(M.presentForMode(monitors, laneMap, 'single', ['A', 'C'], 'C'), [3]);
  assert.deepEqual(M.presentForMode(monitors, laneMap, 'single', [], 'missing'), [1, 2, 3]);
});

test('role change keeps physical monitor and station', () => {
  const clients = [
    { address: '0xa', monitor: 'A', pinned: false, workspace: { id: M.ws(4, 1) } },
    { address: '0xb', monitor: 'B', pinned: false, workspace: { id: M.ws(7, 2) } },
  ];
  assert.deepEqual(M.planRoleChange(clients, { A: 1, B: 2 }, { A: 2, B: 1 }), [
    { address: '0xa', to: M.ws(4, 2) }, { address: '0xb', to: M.ws(7, 1) },
  ]);
});

test('direction and existing-station navigation obey edges', () => {
  assert.equal(M.step('right', 'ltr'), 1);
  assert.equal(M.step('left', 'ltr'), -1);
  assert.equal(M.step('right', 'rtl'), -1);
  assert.equal(M.step('up', 'ltr'), null);
  assert.equal(M.nextExisting(2, 1, [1, 2, 5]), 5);
  assert.equal(M.nextExisting(5, 1, [1, 2, 5]), null);
  assert.equal(M.nextExisting(2, -1, [1, 2, 5]), 1);
});

test('existing stations combine minimum, clients, and active workspaces', () => {
  assert.deepEqual(M.existingStations([{ workspace: { id: 16 } }], [{ activeWorkspace: { id: 25 } }], 3), [1, 2, 3, 6, 9]);
});

test('existing stations exclude unmanaged monitors', () => {
  assert.deepEqual(M.existingStations([
    { monitor: 'A', workspace: { id: 4 } }, { monitor: 'D', workspace: { id: 28 } },
  ], [{ name: 'A', activeWorkspace: { id: 4 } }, { name: 'D', activeWorkspace: { id: 25 } }], 1, ['A']), [1, 2]);
});

test('logical dimensions account for scale and rotation; touching is not overlap', () => {
  assert.deepEqual(M.logicalSize({ width: 3840, height: 2160, scale: 2, transform: 0 }), { width: 1920, height: 1080 });
  assert.deepEqual(M.logicalSize({ width: 3840, height: 2160, scale: 2, transform: 1 }), { width: 1080, height: 1920 });
  assert.deepEqual(M.layoutOverlaps([
    { name: 'A', x: 0, y: 0, width: 1920, height: 1080, scale: 1, transform: 0 },
    { name: 'B', x: 1920, y: 0, width: 1920, height: 1080, scale: 1, transform: 0 },
  ]), []);
  assert.deepEqual(M.layoutOverlaps([
    { name: 'A', x: 0, y: 0, width: 1920, height: 1080, scale: 1, transform: 0 },
    { name: 'B', x: 1910, y: 0, width: 1920, height: 1080, scale: 1, transform: 0 },
  ]), [['A', 'B']]);
});

test('layout positions snap to grid and neighbouring edges', () => {
  const displays = [
    { name: 'A', x: 0, y: 0, width: 1920, height: 1080, scale: 1, transform: 0 },
    { name: 'B', x: 1920, y: 0, width: 1920, height: 1080, scale: 1, transform: 0 },
  ];
  assert.deepEqual(M.snapPosition(displays[1], 1907, 6, displays), { x: 1920, y: 0 });
  assert.deepEqual(M.snapPosition(displays[1], 2003, 37, displays), { x: 2000, y: 40 });
});

test('geometry picks directional neighbours and opposite edges', () => {
  const monitors = [
    { name: 'A', x: 0, y: 0, width: 100, height: 100, scale: 1 },
    { name: 'B', x: 100, y: 0, width: 100, height: 100, scale: 1 },
    { name: 'C', x: 200, y: 100, width: 100, height: 100, scale: 1 },
  ];
  assert.equal(M.neighborMonitor('A', 'right', monitors, ['A', 'B', 'C']), 'B');
  assert.equal(M.neighborMonitor('A', 'left', monitors, ['A', 'B', 'C']), null);
  assert.equal(M.edgeMonitor('left', monitors, ['A', 'B', 'C']), 'A');
  assert.equal(M.edgeMonitor('right', monitors, ['A', 'B', 'C']), 'C');
});

test('mode choices deduplicate labels while retaining exact accepted strings', () => {
  const monitor = { width: 1920, height: 1080, refreshRate: 60.003,
    availableModes: ['1920x1080@60.00Hz', '1920x1080@60.00Hz', '1920x1080@59.94Hz'] };
  assert.equal(M.currentMode(monitor), '1920x1080@60.00Hz');
  assert.deepEqual(M.modeChoices(monitor.availableModes).map(value => value.exact),
    ['1920x1080@60.00Hz', '1920x1080@59.94Hz']);
  assert.deepEqual(M.resolutionChoices(['1920x1080@60.00Hz', '1280x720@60.00Hz']),
    [{ value: '1920x1080', label: '1920x1080' }, { value: '1280x720', label: '1280x720' }]);
  assert.equal(M.modeForResolution(['1280x720@50.00Hz', '1280x720@60.00Hz'],
    '1280x720', '1920x1080@59.94Hz'), '1280x720@60.00Hz');
});

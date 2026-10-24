const test = require('node:test');
const assert = require('node:assert/strict');
const M = require('../../lib/Model.js');

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

test('direction and existing-station navigation obey edges', () => {
  assert.equal(M.step('right', 'ltr'), 1);
  assert.equal(M.step('left', 'ltr'), -1);
  assert.equal(M.step('right', 'rtl'), -1);
  assert.equal(M.step('up', 'ltr'), null);
  assert.equal(M.nextExisting(2, 1, [1, 2, 5]), 5);
  assert.equal(M.nextExisting(5, 1, [1, 2, 5]), null);
  assert.equal(M.nextExisting(2, -1, [1, 2, 5]), 1);
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

test('resizing preserves a shared edge and moves the changed display out of its neighbor', () => {
  const below = { name: 'eDP-1', x: 0, y: 1200, width: 1920, height: 1080, scale: 1, transform: 0 };
  const above = { name: 'HDMI-A-2', x: 0, y: 0, width: 1920, height: 1200, scale: 1, transform: 0 };
  const rotatedAbove = { ...above, transform: 1 };
  assert.deepEqual(M.resizedPosition(above, rotatedAbove, [above, below]), { x: 0, y: -720 });
  assert.deepEqual(M.layoutOverlaps([{ ...rotatedAbove, ...M.resizedPosition(above, rotatedAbove, [above, below]) }, below]), []);

  const right = { name: 'B', x: 1920, y: 0, width: 1920, height: 1080, scale: 1, transform: 0 };
  const left = { name: 'A', x: 0, y: 0, width: 1920, height: 1200, scale: 1, transform: 0 };
  assert.deepEqual(M.resizedPosition(left, { ...left, transform: 1 }, [left, right]), { x: 720, y: 0 });

  const middle = { name: 'M', x: 100, y: 0, width: 100, height: 200, scale: 1, transform: 0 };
  const neighbors = [
    { name: 'L', x: 0, y: 0, width: 100, height: 100, scale: 1, transform: 0 },
    middle,
    { name: 'R', x: 200, y: 0, width: 100, height: 100, scale: 1, transform: 0 },
  ];
  const rotatedMiddle = { ...middle, transform: 1 };
  const moved = M.resizedPosition(middle, rotatedMiddle, neighbors);
  assert.deepEqual(M.layoutOverlaps(neighbors.map(display => display.name === 'M'
    ? { ...rotatedMiddle, ...moved } : display)), []);
  assert.equal(moved.y, 0, 'a horizontal row stays horizontal when growth cannot fit between both neighbors');

  const fractionalBelow = { name: 'FB', x: 0, y: 0, width: 1000, height: 1000, scale: 1, transform: 0 };
  const fractionalAbove = { name: 'FA', x: 0, y: -480, width: 1280, height: 720, scale: 1.5, transform: 0 };
  const fractionalRotation = { ...fractionalAbove, transform: 1 };
  const integer = M.resizedPosition(fractionalAbove, fractionalRotation, [fractionalAbove, fractionalBelow]);
  assert.ok(Number.isInteger(integer.x) && Number.isInteger(integer.y));
  assert.equal(integer.y, -854, 'integer monitor positions round away from the neighbor');
  assert.deepEqual(M.layoutOverlaps([{ ...fractionalRotation, ...integer }, fractionalBelow]), []);
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

const test = require('node:test');
const assert = require('node:assert/strict');
const BarModel = require('../../lib/BarModel.js');

test('positionModules lays a region out horizontally like the Row it replaced', () => {
  const plan = BarModel.positionModules([
    { visible: true, width: 40, height: 30 },
    { visible: true, width: 20, height: 24 },
    { visible: true, width: 0, height: 30 }
  ], false);

  assert.deepEqual(plan.positions.map(function(p) { return p.x }), [0, 40, 60]);
  plan.positions.forEach(function(p) { assert.equal(p.y, 0) });
  assert.equal(plan.width, 60);
  // A horizontal bar centers each slot's height; the widest (tallest) slot
  // carries the region height.
  assert.equal(plan.height, 30);
});

test('positionModules lays a region out vertically for left and right bars', () => {
  const plan = BarModel.positionModules([
    { visible: true, width: 40, height: 30 },
    { visible: true, width: 20, height: 24 }
  ], true);

  assert.deepEqual(plan.positions.map(function(p) { return p.y }), [0, 30]);
  plan.positions.forEach(function(p) { assert.equal(p.x, 0) });
  assert.equal(plan.height, 54);
  // A vertical bar fixes cross sizes to the bar width; the widest slot wins.
  assert.equal(plan.width, 40);
});

test('positionModules skips invisible and missing slots like Row and Column do', () => {
  const plan = BarModel.positionModules([
    { visible: true, width: 40, height: 30 },
    { visible: false, width: 50, height: 40 },
    null,
    { visible: true, width: 10, height: 24 }
  ], false);

  assert.equal(plan.positions[0].x, 0);
  assert.equal(plan.positions[1], null);
  assert.equal(plan.positions[2], null);
  assert.equal(plan.positions[3].x, 40);
  assert.equal(plan.width, 50);
  assert.equal(plan.height, 30);
});

test('positionModules survives a side change by reflowing the same slots', () => {
  const items = [
    { visible: true, width: 40, height: 30 },
    { visible: true, width: 64, height: 24 }
  ];
  const horizontal = BarModel.positionModules(items, false);
  const vertical = BarModel.positionModules(items, true);

  // The second slot follows the first along the flow axis, and both plans
  // and both plans describe the same two slots — nothing is recreated.
  assert.equal(horizontal.positions[1].x, 40);
  assert.equal(vertical.positions[1].y, 30);
  assert.equal(horizontal.positions[1].y, 0);
  assert.equal(vertical.positions[1].x, 0);
});

test('positionModules handles empty and non-array input', () => {
  const plan = BarModel.positionModules([], true);
  assert.deepEqual(plan.positions, []);
  assert.equal(plan.width, 0);
  assert.equal(plan.height, 0);

  const empty = BarModel.positionModules(null, false);
  assert.deepEqual(empty.positions, []);
  assert.equal(empty.width, 0);
});

test('minimumBarLength keeps edge regions clear of an asymmetric centered group', () => {
  assert.equal(BarModel.minimumBarLength(100, 40, 60, 80, 8, 4), 304);
  assert.equal(BarModel.minimumBarLength(100, 0, 0, 80, 8, 4), 200);
  assert.equal(BarModel.minimumBarLength(0, 40, 60, 0, 8, 4), 136);
});

test('popoutAnchor aligns panels corner-to-corner with their bar region', () => {
  assert.equal(BarModel.popoutAnchor('left', 600, 240), 120);
  assert.equal(BarModel.popoutAnchor('center', 600, 240), 300);
  assert.equal(BarModel.popoutAnchor('right', 600, 240), 480);
});

test('MonitorBar hosts module sections without vertical/horizontal Loader swaps', () => {
  const { readFileSync } = require('node:fs');
  const { join } = require('node:path');
  const source = readFileSync(join(__dirname, '..', '..', 'lib', 'MonitorBar.qml'), 'utf8');

  // A side change must reflow instead of destroying the module subtree —
  // an open plugin panel dies with it otherwise.
  assert.doesNotMatch(source, /sourceComponent:\s*root\.vertical\s*\?\s*verticalBar\s*:\s*horizontalBar/);
  assert.doesNotMatch(source, /sourceComponent:\s*root\.vertical\s*\?\s*verticalCenterModules\s*:\s*horizontalCenterModules/);
  assert.doesNotMatch(source, /sourceComponent:\s*root\.vertical\s*\?\s*verticalModuleList\s*:\s*horizontalModuleList/);
  // The positioner keeps one module list for both orientations.
  assert.match(source, /BarModel\.positionModules/);
  assert.match(source, /function alignPopout\(owner\)/);
  assert.match(source, /slot\.activeItem\.data[\s\S]*?objects\[j\] === owner/,
    'Station uses a dedicated popout owner nested inside its slot root');
  assert.match(source, /panel\.anchorItem = slot\.popoutAnchor/);
  assert.match(source, /mask: Region \{[\s\S]*?x: barContent\.x[\s\S]*?width: barContent\.width/);
  assert.match(source, /color: "transparent"[\s\S]*?id: barContent/);
});

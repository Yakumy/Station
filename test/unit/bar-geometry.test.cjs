const test = require('node:test');
const assert = require('node:assert/strict');
const BarModel = require('../../lib/bars/omarchy/BarModel.js');

test('minimumBarLength keeps edge regions clear of an asymmetric centered group', () => {
  assert.equal(BarModel.minimumBarLength(100, 40, 60, 80, 8, 4), 304);
  assert.equal(BarModel.minimumBarLength(100, 0, 0, 80, 8, 4), 200);
  assert.equal(BarModel.minimumBarLength(0, 40, 60, 0, 8, 4), 136);
});

test('maximum content size respects cross-axis padding and along-axis regions', () => {
  assert.equal(BarModel.maximumContentSize(12, 60, 4, 1920,
    100, 40, 60, 80, 8, 4, 0, 0, 0), 52,
  'cross-axis padding is the limiting dimension');
  assert.equal(BarModel.maximumContentSize(12, 60, 4, 360,
    100, 40, 60, 80, 8, 4, 0, 0, 0), 14,
  'left, centered and right regions limit the along axis');
  assert.equal(BarModel.maximumContentSize(12, 24, 8, 10,
    100, 40, 60, 80, 8, 4, 0, 0, 0), 12,
  'the default remains available when the current geometry is already tight');
});

test('popoutAnchor aligns panels corner-to-corner with their bar region', () => {
  assert.equal(BarModel.popoutAnchor('left', 600, 240), 120);
  assert.equal(BarModel.popoutAnchor('center', 600, 240), 300);
  assert.equal(BarModel.popoutAnchor('right', 600, 240), 480);
});

test('MonitorBar draws one arrangement for both orientations from one pool', () => {
  const { readFileSync } = require('node:fs');
  const { join } = require('node:path');
  const source = readFileSync(join(__dirname, '..', '..', 'lib', 'bars/omarchy/MonitorBar.qml'), 'utf8');

  // A side change must reflow instead of destroying the module subtree —
  // an open plugin panel dies with it otherwise.
  assert.doesNotMatch(source, /sourceComponent:\s*root\.vertical\s*\?\s*verticalBar/);
  assert.equal((source.match(/^ +WidgetPool \{/gm) || []).length, 1);
  assert.match(source, /function alignPopout\(owner\)/);
  assert.match(source, /slot\.activeItem\.data[\s\S]*?objects\[j\] === owner/,
    'Station uses a dedicated popout owner nested inside its slot root');
  assert.match(source, /panel\.anchorItem = slot\.popoutAnchor/);
  assert.match(source, /id: stripInputRegion\s+item: barContent/, 'only the drawn bar takes input');
});

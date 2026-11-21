// GitHub issue #23: a collapsed tray drawer's hidden icons claimed clicks meant for
// the visible icons, because the hit test ignored clipping and ancestor visibility.
const test = require('node:test');
const assert = require('node:assert/strict');
const { itemContainsPoint } = require('../../lib/bars/omarchy/BarModel.js');

// Items in one coordinate space: each has an absolute rectangle.
function item(x, y, width, height, parent, extra = {}) {
  return {
    x, y, width, height, parent, visible: true, opacity: 1, enabled: true, clip: false, ...extra,
    mapFromItem(source, px, py) { return { x: source.x + px - this.x, y: source.y + py - this.y } },
    contains(point) { return point.x >= 0 && point.y >= 0 && point.x < this.width && point.y < this.height },
  };
}

test('a target outside its clipped drawer does not take the click', () => {
  const slot = item(0, 0, 100, 30, null);
  const drawer = item(60, 0, 40, 30, slot, { clip: true });
  const hidden = item(20, 0, 30, 30, drawer); // laid out left of the drawer's visible edge
  const shown = item(65, 0, 30, 30, drawer);
  assert.equal(itemContainsPoint(hidden, slot, 30, 10), false);
  assert.equal(itemContainsPoint(shown, slot, 70, 10), true);
  drawer.clip = false;
  assert.equal(itemContainsPoint(hidden, slot, 30, 10), true);
});

test('a hidden, transparent or disabled ancestor hides the target', () => {
  for (const key of ['visible', 'opacity', 'enabled']) {
    const slot = item(0, 0, 100, 30, null);
    const group = item(0, 0, 100, 30, slot);
    const target = item(10, 0, 30, 30, group);
    assert.equal(itemContainsPoint(target, slot, 15, 10), true);
    group[key] = key === 'opacity' ? 0 : false;
    assert.equal(itemContainsPoint(target, slot, 15, 10), false, key);
  }
});

test('a point outside the target, a missing target or a mapping error is no hit', () => {
  const slot = item(0, 0, 100, 30, null);
  const target = item(10, 0, 30, 30, slot);
  assert.equal(itemContainsPoint(target, slot, 50, 10), false);
  assert.equal(itemContainsPoint(null, slot, 15, 10), false);
  target.mapFromItem = () => { throw new Error('destroyed'); };
  assert.equal(itemContainsPoint(target, slot, 15, 10), false);
});

// PR #21: Omarchy's Indicators widget hovers from past its own edges, so a slot
// that always clips never reveals the inactive indicators.
test('a widget slot clips only while dragged or holding the tray drawer', () => {
  const source = require('node:fs').readFileSync(
    require('node:path').join(__dirname, '../../lib/bars/omarchy/MonitorBar.qml'), 'utf8');
  const slot = source.slice(source.indexOf('readonly property real trayFlowInset'));
  const clip = slot.match(/^    clip: (.+)$/m);
  assert.ok(clip, 'slot clip');
  assert.equal(clip[1].trim(), 'slot.trayFlowInset > 0 || slot.dragSource');
});

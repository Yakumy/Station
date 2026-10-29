const test = require('node:test');
const assert = require('node:assert/strict');
const { rows } = require('../../lib/OpenApps.js');
const Store = require('../../lib/Store.js');
const monitor = (id, name, workspace, extra = {}) => ({ id, name, activeWorkspace: { id: workspace }, specialWorkspace: { id: 0 }, ...extra });
const client = (address, monitor, workspace, extra = {}) => ({ address, monitor, workspace: { id: workspace }, mapped: true, class: 'app', ...extra });

test('default-on preference survives old configs and persists explicit off', () => {
  assert.equal(Store.loadConfig({}).showOpenApps, true);
  assert.equal(Store.loadConfig({ showOpenApps: false }).showOpenApps, false);
});
test('each monitor shows its actual active workspace with exactly one focused window', () => {
  const ms = [monitor(0, 'A', 5), monitor(1, 'B', 6)];
  const cs = [client('a', 0, 5), client('b', 1, 6), client('c', 0, 7), client('d', 0, 5)];
  const result = rows(ms, cs, { address: 'd' });
  assert.deepEqual(result.A.map(x => [x.address, x.focused]), [['a', false], ['d', true]]);
  assert.deepEqual(result.B.map(x => [x.address, x.focused]), [['b', false]]);
  assert.equal(rows(ms, cs, {}).A.some(x => x.focused), false);
});
test('migration, role swap, Single/Mirror and restoration follow physical placement', () => {
  const cs = [client('a', 0, 5), client('b', 1, 6)];
  assert.equal(rows([monitor(0, 'A', 5), monitor(1, 'B', 6)], cs, {}).B.length, 1);
  // Partially migrated IDs intentionally do not match any single logical map.
  cs[0].workspace.id = 3;
  assert.equal(rows([monitor(0, 'A', 3), monitor(1, 'B', 6)], cs, {}).B[0].address, 'b');
  cs[1].monitor = 0; cs[1].workspace.id = 3;
  for (const extra of [{ disabled: true }, { mirrorOf: 'A' }]) {
    const result = rows([monitor(0, 'A', 3), monitor(1, 'B', 6, extra)], cs, {});
    assert.equal(result.A.length, 2); assert.equal(result.B, undefined);
  }
  cs[0].workspace.id = 6; cs[1].monitor = 1; cs[1].workspace.id = 5;
  const swapped = rows([monitor(0, 'A', 6), monitor(1, 'B', 5)], cs, {});
  assert.equal(swapped.A[0].address, 'a'); assert.equal(swapped.B[0].address, 'b');
  assert.deepEqual(rows([], cs, {}), {});
});
test('pinned and open scratchpad windows remain local; hidden/unmapped windows stay out', () => {
  const cs = [client('p', 0, 99, { pinned: true }), client('s', 0, -2),
    client('h', 0, 1, { hidden: true }), client('u', 0, 1, { mapped: false }), client('other', 1, 1)];
  assert.deepEqual(rows([monitor(0, 'A', 1)], cs, {}).A.map(x => x.address), ['p']);
  assert.deepEqual(rows([monitor(0, 'A', 1, { specialWorkspace: { id: -2 } })], cs, {}).A.map(x => x.address), ['p', 's']);
});

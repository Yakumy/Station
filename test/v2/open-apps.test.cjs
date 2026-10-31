const test = require('node:test');
const assert = require('node:assert/strict');
const { rows } = require('../../lib/OpenApps.js');
const Store = require('../../lib/Store.js');
const map = { outputs: ['A', 'B'] };
const client = (address, workspace, extra = {}) => ({ address, workspace: { id: workspace }, mapped: true, class: 'app', ...extra });
test('station app mode defaults to hover and migrates the boolean preference', () => {
  assert.equal(Store.loadConfig({}).stationAppsMode, 'hover');
  assert.equal(Store.loadConfig({ showOpenApps: true }).stationAppsMode, 'hover');
  assert.equal(Store.loadConfig({ showOpenApps: false }).stationAppsMode, 'hide');
  assert.equal(Store.loadConfig({ stationAppsMode: 'always' }).stationAppsMode, 'always');
  assert.equal(Store.loadConfig({ stationAppsMode: 'invalid' }).stationAppsMode, 'hover');
  assert.equal('showOpenApps' in Store.loadConfig({ showOpenApps: true }), false);
});
test('stations aggregate every output, include background stations and preserve empty indicators', () => {
  const cs = [client('a', 1), client('b', 2), client('c', 5), client('d', 6)];
  const result = rows(map, cs, { address: 'b' }, null, 3, 2);
  assert.deepEqual(Object.keys(result), ['1', '2', '3']);
  assert.deepEqual(result[1].map(x => [x.address, x.focused]), [['a', false], ['b', true]]);
  assert.deepEqual(result[2], []);
  assert.deepEqual(result[3].map(x => x.address), ['c', 'd']);
  assert.equal(rows(map, cs, {}, null, 1, 1)[1].some(x => x.focused), false);
});
test('journal identity preserves station during partially applied migration', () => {
  const cs = [client('a', 3, { pid: 7, initialClass: 'app' }), client('b', 4)];
  const pending = { windows: [{ address: 'a', pid: 7, initialClass: 'app', station: 3 }] };
  assert.equal(rows(map, cs, {}, pending, 1, 1)[3][0].address, 'a');
  cs[0].pid = 8;
  assert.equal(rows(map, cs, {}, pending, 1, 1)[3], undefined);
  assert.equal(rows({ outputs: ['A'] }, [client('a', 3)], {}, null, 1, 1)[3][0].address, 'a');
});
test('hidden, unmapped, scratchpads and out-of-range workspaces stay out; pins have one home', () => {
  const cs = [client('p', 2, { pinned: true }), client('s', -2), client('h', 1, { hidden: true }),
    client('u', 1, { mapped: false }), client('x', 21)];
  assert.deepEqual(rows(map, cs, {}, null, 1, 1)[1].map(x => x.address), ['p']);
  assert.deepEqual(rows(null, cs, {}, null, 2, 3), { 1: [], 2: [], 3: [] });
});

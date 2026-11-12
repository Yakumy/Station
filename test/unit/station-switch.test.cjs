const test = require('node:test');
const { runtimeSource, adaptOwners, qmlFunction } = require('../helpers/runtime-source.cjs');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const Hypr = require('../../lib/platform/Hypr.js');
const Grid = require('../../lib/stations/Grid.js');
const Model = require('../../lib/displays/Model.js');
const source = runtimeSource();
function harness() {
  const batches = [];
  const c = { Hypr, Grid, Model, state: 'idle', gen: 0, queuedStation: 0,
    currentStation: 1, persisted: {}, workspaceMap: { outputs: ['A', 'B'] },
    focusedMonitor: () => ({ name: 'B' }), saveState() {},
    readyForWindows: () => c.state === 'idle',
    workspaceFor: (s, o) => Grid.workspace(s, o, c.workspaceMap),
    evalLua(lua, done) { batches.push({ lua, done }); },
  };
  c.root = c;
  adaptOwners(c);
  for (const name of ['begin', 'finish', 'clearQueued', 'showStation', 'stationFocusStatements'])
    c[name] = qmlFunction(source, name, c);
  return { c, batches };
}
test('rapid numbered switches retain the last request and return to the occupied station', () => {
  const { c, batches } = harness();
  assert.equal(c.showStation(2), 'started');
  assert.equal(c.currentStation, 1, 'pending switches must not predict the indicator');
  assert.equal(c.showStation(3), 'queued');
  assert.equal(c.showStation(1), 'queued');
  assert.equal(batches.length, 1);
  batches[0].done(0, 'ok');
  assert.equal(batches.length, 2);
  assert.ok(batches[1].lua.endsWith(Hypr.focusWorkspace(1) + '; ' + Hypr.focusWorkspace(2)));
  assert.doesNotMatch(batches[1].lua, /hl\.dsp\.window\.move/);
  batches[1].done(0, 'ok');
  assert.equal(c.currentStation, 1);
  assert.equal(c.persisted.lastStation, 1);
  assert.equal(c.state, 'idle');
});
test('topology interruption cancels pending switches and stale completion', () => {
  const { c, batches } = harness();
  c.showStation(2); c.showStation(1);
  c.begin('migrating');
  batches[0].done(0, 'ok');
  assert.equal(c.queuedStation, 0);
  assert.equal(batches.length, 1);
  assert.equal(c.state, 'migrating');
  assert.equal(c.showStation(3), 'busy');
});
test('Lua error payload cannot record a successful switch; invalid keys cannot replace queued intent', () => {
  const { c, batches } = harness();
  c.showStation(2); c.showStation(1);
  assert.equal(c.showStation(11), 'invalid');
  assert.equal(c.queuedStation, 1);
  batches[0].done(0, 'Lua error');
  assert.equal(c.currentStation, 1);
  assert.equal(c.persisted.lastStation, undefined);
  batches[1].done(0, 'ok');
  assert.equal(c.currentStation, 1);
});

test('BTT and TTB arrows navigate existing stations and stop at the edges', () => {
  for (const direction of ['btt', 'ttb']) {
    for (const [station, arrow, expected] of [
      [2, 'up', direction === 'btt' ? 3 : 1],
      [2, 'down', direction === 'btt' ? 1 : 3],
      [1, direction === 'btt' ? 'down' : 'up', null],
      [3, direction === 'btt' ? 'up' : 'down', null],
      [2, 'left', null], [2, 'right', null],
    ]) {
      const { c, batches } = harness();
      c.config = { direction };
      c.monitors = [{ name: 'A', activeWorkspace: { id: station * 2 - 1 } },
        { name: 'B', activeWorkspace: { id: station * 2 } }];
      c.clients = [];
      c.focusedMonitor = () => c.monitors[1];
      c.refresh = (include, done) => done();
      c.goDirection = qmlFunction(source, 'goDirection', c);
      c.goDirection(arrow);
      assert.equal(batches.length, expected === null ? 0 : 1);
      if (expected !== null) {
        assert.ok(batches[0].lua.endsWith(Hypr.focusWorkspace(expected * 2 - 1) + '; ' + Hypr.focusWorkspace(expected * 2)));
        batches[0].done(0, 'ok');
        assert.equal(c.currentStation, expected);
      }
    }
  }
});

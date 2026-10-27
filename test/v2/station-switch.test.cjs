const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const Hypr = require('../../lib/Hypr.js');
const Grid = require('../../lib/Grid.js');
const Model = require('../../lib/Model.js');
const source = readFileSync('Service.qml', 'utf8');
function harness() {
  const batches = [];
  const c = { Hypr, Grid, Model, state: 'idle', gen: 0, queuedStation: 0,
    currentStation: 1, persisted: {}, workspaceMap: { outputs: ['A', 'B'] },
    focusedMonitor: () => ({ name: 'B' }), saveState() {},
    readyForWindows: () => c.state === 'idle',
    workspaceFor: (s, o) => Grid.workspace(s, o, c.workspaceMap),
    evalLua(lua, done) { batches.push({ lua, done }); },
  };
  for (const name of ['begin', 'finish', 'showStation', 'stationFocusStatements']) {
    const start = source.indexOf('  function ' + name + '(');
    const end = source.indexOf('\n  function ', start + 1);
    c[name] = runInNewContext('(' + source.slice(start, end).trim() + ')', c);
  }
  return { c, batches };
}
test('rapid numbered switches retain the last request and return to the occupied station', () => {
  const { c, batches } = harness();
  assert.equal(c.showStation(2), 'started');
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

// Production function-body characterization with fake Process/timer boundaries.
// These tests never instantiate Station, call hyprctl or write desktop state.
// They do not establish QML signal ordering or actual Wayland unmapping.
const test = require('node:test');
const { runtimeSource, adaptOwners, qmlFunction } = require('../helpers/runtime-source.cjs');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const source = runtimeSource();
const copy = value => JSON.parse(JSON.stringify(value));
function functions(names, state) {
  state.root = state;
  for (const name of names) {
    const start = source.indexOf('  function ' + name + '(');
    const end = source.indexOf('\n  }', start) + 4;
    assert.ok(start >= 0 && end > start, name);
    state[name] = runInNewContext('(' + source.slice(start, end).trim() + ')', state);
  }
  return state;
}
function actionQueue() {
  const c = functions(['enqueue', 'runNext', 'evalLua'], {
    gen: 99, configGeneration: 4, actionQueue: [], currentAction: null,
    action: { running: false, captured: '' },
  });
  const block = source.slice(source.indexOf('    id: action\n'));
  const body = block.match(/onExited: function\(code\) \{([^]*?)\n    \}/);
  assert.ok(body);
  const onExit = runInNewContext('(function(code) {' + body[1] + '\n})', c);
  c.complete = (code, text) => {
    c.action.running = false;
    c.action.captured = text;
    onExit(code);
  };
  return c;
}

test('configuration generation retires queued Lua without cancelling an already executing operation', () => {
  const c = actionQueue(), results = [];
  c.evalLua('first()', (code, reply) => results.push(['first', code, reply]));
  c.evalLua('stale()', (code, reply) => results.push(['stale', code, reply]));
  assert.deepEqual(copy(c.action.command), ['hyprctl', 'eval', 'first()']);
  c.configGeneration++;
  c.gen++; // Distinct operation token must not replace the configuration token.
  c.evalLua('current()', (code, reply) => results.push(['current', code, reply]));
  assert.deepEqual(copy(c.action.command), ['hyprctl', 'eval', 'first()']);
  assert.deepEqual(results, [], 'running job still owns completion');
  c.complete(0, 'first reply');
  assert.equal(results[0][0], 'first');
  assert.equal(results[0][1], 0);
  assert.equal(results[1][0], 'stale');
  assert.equal(results[1][1], 1);
  assert.match(results[1][2], /Configuration changed/);
  assert.deepEqual(copy(c.action.command), ['hyprctl', 'eval', 'current()']);
  c.complete(0, 'current reply');
  assert.deepEqual(results.map(row => row[0]), ['first', 'stale', 'current']);
  assert.equal(c.currentAction, null);
  assert.equal(c.actionQueue.length, 0);
});

test('operation generations alone do not invalidate queued compositor configuration work', () => {
  const c = actionQueue();
  c.action.running = true;
  c.evalLua('sameConfiguration()');
  c.gen++;
  c.action.running = false;
  c.runNext();
  assert.deepEqual(copy(c.action.command), ['hyprctl', 'eval', 'sameConfiguration()']);
  c.complete(0, 'ok');
});

test('snapshot requests retain FIFO callback ownership and per-request client-read intent', () => {
  const calls = [];
  const c = functions(['refresh', 'completeSnapshot'], {
    state: 'idle', snapshotBusy: false, snapshotQueue: [], refreshDone: null,
    refreshClientsToo: false, monitorSnapshot: { running: false },
  });
  c.refresh(true, () => calls.push('migration'));
  c.refresh(false, () => calls.push('observation'));
  c.refresh(true, () => calls.push('window-action'));
  assert.equal(c.refreshClientsToo, true);
  assert.deepEqual(calls, []);
  c.completeSnapshot(0);
  assert.deepEqual(calls, ['migration']);
  assert.equal(c.refreshClientsToo, false);
  assert.equal(c.snapshotBusy, true);
  c.completeSnapshot(0);
  assert.deepEqual(calls, ['migration', 'observation']);
  assert.equal(c.refreshClientsToo, true);
  c.completeSnapshot(0);
  assert.deepEqual(calls, ['migration', 'observation', 'window-action']);
  assert.equal(c.snapshotBusy, false);
  assert.equal(c.refreshDone, null);
});

test('a failed snapshot does not dispatch its success callback or replace the next queued request', () => {
  const calls = [];
  const c = functions(['refresh', 'completeSnapshot', 'handleSnapshotFailure'], {
    state: 'migrating', snapshotBusy: false, snapshotQueue: [], refreshDone: null,
    monitorSnapshot: { running: false }, workspace: { migrationFailed(message) { calls.push(message); } },
    snapshotFailed() { c.handleSnapshotFailure(); },
  });
  c.refresh(true, () => assert.fail('failed snapshot cannot commit a migration'));
  c.refresh(false, () => calls.push('next observed'));
  c.completeSnapshot(1);
  assert.deepEqual(calls, ['could not read compositor state']);
  assert.equal(c.refreshClientsToo, false);
  c.completeSnapshot(0);
  assert.deepEqual(calls, ['could not read compositor state', 'next observed']);
});

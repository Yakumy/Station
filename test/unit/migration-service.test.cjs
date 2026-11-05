const test = require('node:test');
const assert = require('node:assert/strict');
const Grid = require('../../lib/stations/Grid.js');
const Hypr = require('../../lib/platform/Hypr.js');
const { ownerFunction } = require('../helpers/workspace-owner.cjs');
const copy = value => JSON.parse(JSON.stringify(value));
function harness({ from = { outputs: ['A'] }, to = { outputs: ['A', 'B'] }, pending = null } = {}) {
  const writes = [], evals = [];
  const context = {
    Grid, Hypr, state: 'idle', gen: 0, migrationPhase: '', migrationCommit: null, previewBaseline: null,
    topologyDirty: false, migrationAttempts: 0, migrationFocus: null, currentStation: 3,
    layoutError: '', persisted: { legacyWorkspaceGrid: false }, expect: {},
    workspaceData: { mapping: from, pending }, removalGrace: { running: false },
    clients: [1, 2, 3, 4].map(id => ({ address: '0x' + id, pid: id, initialClass: 'test',
      monitor: 'A', workspace: { id, name: String(id) }, focusHistoryID: id === 3 ? 0 : id })),
    begin(next) { context.state = next; return ++context.gen; },
    refresh(include, done) { done(); }, updateAssignments() {},
    targetMapping() { return to; },
    focusedClient() { return context.clients.find(c => c.focusHistoryID === 0); },
    saveState() {}, showStation(s) { context.shown = s; },
    migrationRetry: { restart() { context.retry = true; } },
    workspaceFile: { setText(text) { writes.push(JSON.parse(text)); } },
    evalLua(lua, done) {
      evals.push(lua);
      if (context.reject) { done(1, 'error'); return; }
      // Compositor double applies the actual emitted address-based Lua moves.
      for (const m of lua.matchAll(/window = "address:(0x[0-9a-f]+)", workspace = (\d+), follow = false/g)) {
        const c = context.clients.find(c => c.address === m[1]);
        if (c) c.workspace = { id: Number(m[2]), name: m[2] };
      }
      for (const m of lua.matchAll(/workspace\.move\(\{ workspace = (\d+), monitor = "([A-Z])"/g))
        context.clients.filter(c => c.workspace.id === Number(m[1])).forEach(c => c.monitor = m[2]);
      if (context.rejectAppliedMoves && /workspace\.move/.test(lua)) { done(1, 'false'); return; }
      if (done) done(0, 'ok');
    },
  };
  Object.defineProperty(context, 'workspaceMap', { get: () => context.workspaceData.mapping });
  context.root = context;
  for (const name of ['reconcile', 'migrationFailed', 'migrationSaved', 'executeMigration']) {
    context[name] = ownerFunction(name, context);
  }
  return { c: context, writes, evals };
}

test('service saves plan before moving and saves commit before publishing new numbering', () => {
  const { c, writes, evals } = harness();
  c.reconcile();
  assert.equal(c.state, 'migrating');
  assert.equal(evals.length, 0);
  assert.deepEqual(writes[0].pending.windows.map(w => w.to), [1, 3, 5, 7]);
  c.migrationSaved(); // durable journal acknowledgment
  assert.deepEqual(copy(c.expect.outputs), ['A']); // New empty display B caused no move events.
  assert.deepEqual(c.clients.map(w => w.workspace.id), [1, 3, 5, 7]);
  assert.deepEqual(c.workspaceMap.outputs, ['A']);
  assert.equal(c.state, 'migrating');
  assert.equal(writes[1].pending, null);
  c.migrationSaved(); // durable mapping acknowledgment
  assert.deepEqual(copy(c.workspaceMap.outputs), ['A', 'B']);
  assert.equal(c.workspaceData.pending, null);
  assert.equal(c.shown, 3);
  assert.equal(c.state, 'idle');
});

test('failed moves retain journal and failed journal save does not move windows', () => {
  const failedSave = harness();
  failedSave.c.reconcile();
  failedSave.c.migrationFailed('disk full');
  assert.equal(failedSave.evals.length, 0);
  assert.ok(failedSave.c.workspaceData.pending);
  const failedMove = harness();
  failedMove.c.reconcile();
  failedMove.c.reject = true;
  failedMove.c.migrationSaved();
  assert.equal(failedMove.writes.length, 1);
  assert.ok(failedMove.c.workspaceData.pending);
  assert.deepEqual(failedMove.c.workspaceMap.outputs, ['A']);
});

test('verified destinations commit when Hyprland rejects an already-applied move batch', () => {
  const { c, writes, evals } = harness({ from: { outputs: ['A', 'B'] }, to: { outputs: ['B'] } });
  c.clients.forEach((client, index) => {
    client.monitor = index % 2 ? 'B' : 'A';
    client.workspace = { id: index + 1, name: String(index + 1) };
  });
  c.reconcile();
  c.rejectAppliedMoves = true;
  c.migrationSaved();
  assert.equal(evals.length, 2, 'workspace rules and move dispatches are separate batches');
  assert.ok(writes[1] && writes[1].pending === null,
    'fresh destination verification overrides the aggregate false move result');
  c.migrationSaved();
  assert.deepEqual(c.workspaceMap.outputs, ['B']);
  assert.equal(c.workspaceData.pending, null);
});

test('restarted service uses saved per-window destinations after a partial expansion', () => {
  const original = harness();
  original.c.reconcile();
  const saved = original.writes[0];
  const restarted = harness({ from: saved.mapping, pending: saved.pending });
  // Workspace 2 already became 3; old workspace 3 still exists alongside it.
  restarted.c.clients[1].workspace = { id: 3, name: '3' };
  restarted.c.workspaceData.revision = saved.revision;
  restarted.c.reconcile();
  assert.ok(restarted.writes[0].revision > saved.revision);
  restarted.c.migrationSaved();
  restarted.c.migrationSaved();
  assert.deepEqual(restarted.c.clients.map(w => w.workspace.id), [1, 3, 5, 7]);
});

test('zero-display intervals and removal grace do not replace the saved mapping', () => {
  const absent = harness({ to: { outputs: [] } });
  absent.c.reconcile();
  assert.equal(absent.writes.length, 0);
  assert.deepEqual(absent.c.workspaceMap.outputs, ['A']);
  const grace = harness();
  grace.c.removalGrace.running = true;
  grace.c.reconcile();
  assert.equal(grace.writes.length, 0);
});

test('a failed commit acknowledgment keeps old numbering and retries recorded identities after moves', () => {
  const { c, writes } = harness();
  c.reconcile();
  c.migrationSaved();
  assert.equal(c.migrationPhase, 'commit');
  assert.deepEqual(c.clients.map(client => client.workspace.id), [1, 3, 5, 7]);
  c.migrationFailed('commit disk full');
  assert.deepEqual(c.workspaceMap.outputs, ['A']);
  assert.ok(c.workspaceData.pending);
  assert.equal(c.retry, true);
  c.reconcile();
  assert.deepEqual(writes[2].pending.windows.map(row => row.station), [1, 2, 3, 4],
    'retry must not reinterpret already expanded workspace IDs with the old map');
  c.migrationSaved();
  assert.deepEqual(c.workspaceMap.outputs, ['A']);
  c.migrationSaved();
  assert.deepEqual(copy(c.workspaceMap.outputs), ['A', 'B']);
});

test('nested preview reconciliation preserves the enclosing operation token and original baseline', () => {
  const { c, writes } = harness();
  c.state = 'previewing';
  c.gen = 42;
  c.previewBaseline = Grid.plan(c.workspaceMap, c.workspaceMap, c.clients, c.currentStation);
  const original = copy(c.previewBaseline);
  c.panelScreenName = 'A';
  c.stationFocusStatements = () => [];
  let finished = 0;
  c.finishPreviewApply = () => finished++;
  c.reconcile();
  assert.equal(c.gen, 42);
  assert.equal(c.state, 'previewing');
  assert.deepEqual(writes[0].preview, original);
  c.migrationSaved();
  c.migrationSaved();
  assert.equal(c.gen, 42);
  assert.equal(c.state, 'previewing', 'journal commit must not finish the preview operation');
  assert.deepEqual(copy(c.previewBaseline), original);
  assert.deepEqual(writes[1].preview, original);
  assert.equal(finished, 1);
});

test('repeated identical migration attempts still serialize distinct acknowledgment revisions', () => {
  const { c, writes, evals } = harness();
  c.reconcile();
  c.migrationFailed('first journal write failed');
  c.reconcile();
  assert.equal(evals.length, 0, 'neither attempt has a durable acknowledgment');
  assert.deepEqual(writes[0].pending, writes[1].pending);
  assert.equal(writes[1].revision, writes[0].revision + 1);
  assert.notEqual(JSON.stringify(writes[0]), JSON.stringify(writes[1]),
    'FileView must see changed text so a retried identical plan can emit saved');
});

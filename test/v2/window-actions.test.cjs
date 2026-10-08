const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const Model = require('../../lib/Model.js');
const Hypr = require('../../lib/Hypr.js');
const Grid = require('../../lib/Grid.js');
const vertical = [
  { id: 0, name: 'A', x: 0, y: 1200, width: 1920, height: 1080, scale: 1 },
  { id: 1, name: 'B', x: 0, y: 0, width: 1920, height: 1200, scale: 1 },
];
const source = readFileSync('Service.qml', 'utf8');
function action(context, name) {
  const start = source.indexOf('  function ' + name + '(');
  const end = source.indexOf('\n  function ', start + 1);
  return runInNewContext('(' + source.slice(start, end).trim() + ')', context);
}
function harness({ monitors = vertical, monitor = 0, workspace = 1, native = () => {}, pinned = false } = {}) {
  const calls = [], requests = [];
  let live = { address: '0xabc', pid: 7, initialClass: 'test', monitor, workspace: { id: workspace, name: String(workspace) },
    pinned, at: [10, 10], size: [800, 600], focusHistoryID: 0 };
  const context = {
    Model, Hypr, Grid, monitors, gen: 0, state: 'idle', currentStation: 1, persisted: {},
    workspaceMap: { outputs: monitors.map(m => m.name) }, workspaceData: { pending: null },
    removalGrace: { running: false }, config: { direction: 'ltr' }, lastWindowAction: {},
    clients: [{ address: '0xdef', monitor: 'B', workspace: { id: 2 }, focusHistoryID: 0 }],
    readyForWindows() { return context.state === 'idle'; },
    targetMapping() { return context.workspaceMap; },
    begin(state) { context.state = state; return ++context.gen; },
    finish(gen) { if (gen === context.gen) context.state = 'idle'; },
    parseJson(raw, fallback) { try { return JSON.parse(raw); } catch { return fallback; } },
    refresh(include, done) { context.clients = live ? Model.normalizeClients([structuredClone(live)], monitors) : []; done(); },
    enqueue(command, done) { requests.push(command); done(0, JSON.stringify(live || {})); },
    saveState() {},
    evalLua(lua, done) {
      calls.push(lua);
      const direction = lua.match(/direction = "(left|right|up|down)"/);
      if (direction) native(live, direction[1]);
      const move = lua.match(/window = "address:0xabc", workspace = (\d+), follow = (true|false)/);
      if (move && live) {
        const id = Number(move[1]);
        live.workspace = { id, name: String(id) };
        live.monitor = monitors[(id - 1) % monitors.length].id;
      }
      if (done) done(0, 'ok');
    },
    nativeMoveSettle: { restart() {} },
  };
  context.root = context;
  context.workspaceFor = (s, o) => Grid.workspace(s, o, context.workspaceMap);
  for (const name of ['finishWindowAction', 'windowActionCurrent', 'readActiveWindow', 'stationFocusStatements',
    'syncWindowStation', 'moveActionWindow', 'sendWindow', 'shiftWindow', 'afterNativeMove']) context[name] = action(context, name);
  return { c: context, calls, requests, get live() { return live; }, close() { live = null; },
    settle() { const t = context.nativeMoveSettle; context.afterNativeMove(t.before, t.direction, t.generation); } };
}

test('numeric IDs normalize and activewindow is authoritative over cached focus', () => {
  const h = harness();
  h.c.shiftWindow('up');
  assert.deepEqual(Array.from(h.requests[0]), ['hyprctl', 'activewindow', '-j']);
  assert.match(h.calls[0], /window = "address:0xabc", direction = "up"/);
  assert.doesNotMatch(h.calls[0], /0xdef/);
  h.settle();
  assert.equal(h.live.workspace.id, 2);
  assert.equal(h.live.monitor, 1);
  assert.equal(h.c.lastWindowAction.result, 'moved');
});

test('native tile movement stops before any monitor or station fallback', () => {
  const h = harness({ native: c => { c.at = [400, 10]; } });
  h.c.shiftWindow('right');
  h.settle();
  assert.equal(h.calls.length, 1);
  assert.equal(h.live.workspace.id, 1);
  assert.equal(h.c.lastWindowAction.result, 'native');
  assert.equal(h.c.state, 'idle');
});

test('native monitor crossing synchronizes displays and explicitly focuses the moved window', () => {
  const h = harness({ native: c => { c.monitor = 1; c.workspace = { id: 2, name: '2' }; } });
  h.c.shiftWindow('up');
  h.settle();
  assert.equal(h.c.lastWindowAction.result, 'native');
  const sync = h.calls.at(-1);
  assert.ok(sync.indexOf('workspace = "1"') < sync.indexOf('workspace = "2"'));
  assert.ok(sync.endsWith(Hypr.focusWindow('0xabc')));
});

test('native monitor crossing preserves its station after a display reconnect', () => {
  const h = harness({ native: c => {
    // A reconnected monitor may still advertise an unrelated active workspace.
    c.monitor = 1;
    c.workspace = { id: 12, name: '12' };
  } });
  h.c.shiftWindow('up');
  h.settle();
  assert.equal(h.live.monitor, 1);
  assert.equal(h.live.workspace.id, 2);
  assert.equal(h.c.currentStation, 1);
  assert.equal(h.c.persisted.lastStation, 1);
  assert.equal(h.c.lastWindowAction.result, 'moved');
  assert.equal(h.c.lastWindowAction.afterWorkspace, 2);
  assert.match(h.calls[1], /workspace = 2, follow = true/);
  assert.doesNotMatch(h.calls.at(-1), /workspace = "11"/);
  assert.doesNotMatch(h.calls.at(-1), /workspace = "12"/);
});

test('vertical station crossing preserves the current display and updates both workspaces', () => {
  const h = harness({ monitor: 1, workspace: 2 });
  h.c.shiftWindow('right');
  h.settle();
  assert.equal(h.live.workspace.id, 4);
  assert.equal(h.live.monitor, 1);
  assert.equal(h.c.currentStation, 2);
  assert.equal(h.c.persisted.lastStation, 2);
  const sync = h.calls.at(-1);
  assert.match(sync, /workspace = "3"/);
  assert.match(sync, /workspace = "4"/);
  assert.ok(sync.endsWith(Hypr.focusWindow('0xabc')));
});

test('horizontal outer edge enters opposite display of next station', () => {
  const monitors = vertical.map((m, i) => ({ ...m, x: i * 1920, y: 0, height: 1080 }));
  const h = harness({ monitors, monitor: 1, workspace: 2 });
  h.c.shiftWindow('right'); h.settle();
  assert.equal(h.live.workspace.id, 3);
  assert.equal(h.live.monitor, 0);
});

test('single display supports native-first station fallback with bounded edges', () => {
  const h = harness({ monitors: vertical.slice(0, 1), workspace: 3 });
  h.c.shiftWindow('right'); h.settle();
  assert.equal(h.live.workspace.id, 4);
  const last = harness({ monitors: vertical.slice(0, 1), workspace: 10 });
  last.c.shiftWindow('right'); last.settle();
  assert.equal(last.c.lastWindowAction.result, 'edge');
  assert.equal(last.live.workspace.id, 10);
  const first = harness();
  first.c.shiftWindow('left'); first.settle();
  assert.equal(first.c.lastWindowAction.result, 'edge');
  const bottom = harness();
  bottom.c.shiftWindow('down'); bottom.settle();
  assert.equal(bottom.c.lastWindowAction.result, 'edge');
});

test('RTL reverses the station step without reversing physical monitor movement', () => {
  const h = harness({ workspace: 3 });
  h.c.config.direction = 'rtl';
  h.c.shiftWindow('right'); h.settle();
  assert.equal(h.live.workspace.id, 1);
});

test('closed windows and topology cancellation cannot cause a stale second move', () => {
  const closed = harness();
  closed.c.shiftWindow('right'); closed.close(); closed.settle();
  assert.equal(closed.c.lastWindowAction.result, 'closed');
  assert.equal(closed.calls.length, 1);
  const stale = harness();
  stale.c.shiftWindow('right'); stale.c.gen++; stale.c.state = 'migrating'; stale.settle();
  assert.equal(stale.calls.length, 1);
  assert.equal(stale.c.state, 'migrating');
  const pinned = harness({ pinned: true });
  pinned.c.shiftWindow('right');
  assert.equal(pinned.calls.length, 0);
  assert.equal(pinned.c.lastWindowAction.result, 'unmanaged');
});

test('numbered send uses the same active window, follows on all displays, and silent send keeps focus', () => {
  const follow = harness({ monitor: 1, workspace: 2 });
  follow.c.sendWindow('3', true);
  assert.equal(follow.live.workspace.id, 6);
  assert.equal(follow.c.currentStation, 3);
  assert.match(follow.calls.at(-1), /workspace = "5"/);
  assert.match(follow.calls.at(-1), /workspace = "6"/);
  const silent = harness();
  silent.c.sendWindow('3', false);
  assert.equal(silent.live.workspace.id, 5);
  assert.equal(silent.c.currentStation, 1);
  assert.equal(silent.calls.length, 1);
  assert.equal(silent.c.lastWindowAction.result, 'moved-silently');
});

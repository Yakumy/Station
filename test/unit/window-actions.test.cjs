const test = require('node:test');
const { runtimeSource, adaptOwners, qmlFunction } = require('../helpers/runtime-source.cjs');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const Model = require('../../lib/displays/Model.js');
const Hypr = require('../../lib/platform/Hypr.js');
const Grid = require('../../lib/stations/Grid.js');
const vertical = [
  { id: 0, name: 'A', x: 0, y: 1200, width: 1920, height: 1080, scale: 1 },
  { id: 1, name: 'B', x: 0, y: 0, width: 1920, height: 1200, scale: 1 },
];
// Landscape external output beside a taller, rotated laptop panel, as reported.
const sideBySide = [
  { id: 0, name: 'HDMI-A-1', x: 1920, y: -50, width: 1920, height: 1200, scale: 1 },
  { id: 1, name: 'eDP-1', x: 3840, y: -370, width: 1920, height: 1080, scale: 1, transform: 3 },
];
const source = runtimeSource();
function action(context, name) { return qmlFunction(source, name, context); }
function harness({ monitors = vertical, monitor = 0, workspace = 1, workspaceName = String(workspace), native = () => {}, pinned = false } = {}) {
  const calls = [], requests = [];
  let live = { address: '0xabc', pid: 7, initialClass: 'test', monitor, workspace: { id: workspace, name: workspaceName },
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
  adaptOwners(context);
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

test('BTT and TTB cross vertical station edges on the source output beside a rotated panel', () => {
  for (const direction of ['btt', 'ttb']) {
    for (const arrow of ['up', 'down']) {
      for (const monitor of [0, 1]) {
        for (const crosses of [false, true]) {
          const h = harness({ monitors: sideBySide, monitor, workspace: 5 + monitor, native: c => {
            if (!crosses) return;
            c.monitor = 1 - monitor;
            c.workspace = { id: 6 - monitor, name: String(6 - monitor) };
          } });
          h.c.config.direction = direction;
          h.c.shiftWindow(arrow); h.settle();
          const station = 3 + Model.step(arrow, direction);
          assert.equal(h.live.monitor, monitor);
          assert.equal(h.live.workspace.id, (station - 1) * 2 + monitor + 1);
          assert.equal(h.c.currentStation, station);
          assert.equal(h.c.lastWindowAction.result, 'moved');
          assert.ok(h.calls.at(-1).endsWith(Hypr.focusWindow('0xabc')));
        }
      }
    }
  }
});

test('BTT keeps native tile movement and restores a diagonal crossing at station limits', () => {
  const tile = harness({ monitors: sideBySide, workspace: 5, native: c => { c.at = [10, -100]; } });
  tile.c.config.direction = 'btt';
  tile.c.shiftWindow('up'); tile.settle();
  assert.equal(tile.calls.length, 1);
  assert.equal(tile.c.lastWindowAction.result, 'native');
  for (const [workspace, arrow] of [[19, 'up'], [1, 'down']]) {
    const h = harness({ monitors: sideBySide, workspace, native: c => {
      c.monitor = 1;
      c.workspace = { id: workspace + 1, name: String(workspace + 1) };
    } });
    h.c.config.direction = 'btt';
    h.c.shiftWindow(arrow); h.settle();
    assert.equal(h.live.workspace.id, workspace);
    assert.equal(h.live.monitor, 0);
  }
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

test('numbered sends retrieve scratchpad windows on their current display with and without follow', () => {
  for (const monitors of [vertical, vertical.slice(0, 1)]) {
    for (const monitor of monitors) {
      for (const follow of [true, false]) {
        const h = harness({ monitors, monitor: monitor.id, workspace: -98, workspaceName: 'special:scratchpad' });
        assert.equal(h.c.sendWindow('3', follow), 'started');
        assert.equal(h.live.workspace.id, 2 * monitors.length + monitor.id + 1);
        assert.equal(h.live.monitor, monitor.id);
        assert.equal(h.c.lastWindowAction.beforeWorkspace, -98);
        assert.equal(h.c.lastWindowAction.result, follow ? 'moved' : 'moved-silently');
        assert.equal(h.c.currentStation, follow ? 3 : 1);
        assert.equal(h.calls.length, follow ? 2 : 1);
        assert.equal(h.c.state, 'idle');
        if (follow) assert.ok(h.calls.at(-1).endsWith(Hypr.focusWindow('0xabc')));
      }
    }
  }
});

test('scratchpad retrieval preserves exclusions for pinned, unmanaged, named and other special windows', () => {
  const scratchpad = { workspace: -98, workspaceName: 'special:scratchpad' };
  for (const options of [
    { ...scratchpad, pinned: true },
    { ...scratchpad, monitor: 99 },
    { workspace: -99, workspaceName: 'special:other' },
    { workspace: 1, workspaceName: 'special:scratchpad' },
    { workspace: 1, workspaceName: 'named' },
    { workspace: 99 },
  ]) {
    for (const follow of [true, false]) {
      const h = harness(options);
      h.c.sendWindow('3', follow);
      assert.equal(h.calls.length, 0);
      assert.equal(h.c.lastWindowAction.result, 'unmanaged');
      assert.equal(h.c.state, 'idle');
    }
  }
  const h = harness(scratchpad);
  h.c.shiftWindow('right');
  assert.equal(h.calls.length, 0);
  assert.equal(h.c.lastWindowAction.result, 'unmanaged');
});

const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const Model = require('../../lib/Model.js');
const Hypr = require('../../lib/Hypr.js');
const Grid = require('../../lib/Grid.js');

const monitors = [
  { id: 0, name: 'eDP-1', x: 0, y: 1200, width: 1920, height: 1080, scale: 1 },
  { id: 1, name: 'HDMI-A-2', x: 0, y: 0, width: 1920, height: 1200, scale: 1 },
];
const lanes = { 'eDP-1': 1, 'HDMI-A-2': 2 };
const client = { address: '0xabc', monitor: 0, workspace: { id: 1 }, pinned: false, focusHistoryID: 0 };

function serviceAction(context, name) {
  const source = readFileSync('Service.qml', 'utf8');
  const start = source.indexOf('  function ' + name + '(');
  const end = source.indexOf('\n  function ', start + 1);
  return runInNewContext('(' + source.slice(start, end).trim() + ')', context);
}

test('numeric compositor monitor IDs normalize without confusing IDs and lanes', () => {
  const raw = [client, { ...client, monitor: 1 }, { ...client, monitor: 99 }];
  assert.deepEqual(Model.normalizeClients(raw, monitors).map(c => c.monitor), ['eDP-1', 'HDMI-A-2', '']);
  assert.equal(raw[0].monitor, 0);
  assert.equal(Model.normalizeClients([{ ...client, monitor: 'HDMI-A-2' }], monitors)[0].monitor, 'HDMI-A-2');
});

test('real service arrow action refreshes focus, uses geometry, and applies rules before moving', () => {
  const lua = [];
  const context = {
    Model, Hypr, Grid, monitors, lanes, workspaceMap: { outputs: ['eDP-1', 'HDMI-A-2'] }, readyForWindows: () => true, config: { direction: 'ltr' }, clients: [],
    present: () => [1, 2],
    refresh: (includeClients, done) => {
      if (done) { context.clients = Model.normalizeClients([client], monitors); done(); }
    },
    evalLua: (statement, done) => { lua.push(statement); done(); },
  };
  context.root = context;
  context.workspaceFor = (s, o) => Grid.workspace(s, o, context.workspaceMap);
  context.focusedClient = serviceAction(context, 'focusedClient');
  context.shiftFocusedWindow = serviceAction(context, 'shiftFocusedWindow');
  const shift = serviceAction(context, 'shiftWindow');
  assert.equal(shift('up'), 'started');
  assert.match(lua[0], /workspace = "2", monitor = "HDMI-A-2"/);
  assert.match(lua[0], /window = "address:0xabc", workspace = 2, follow = true/);
  assert.ok(lua[0].indexOf('hl.workspace_rule') < lua[0].indexOf('hl.dispatch'));
  lua.length = 0;
  shift('right');
  assert.match(lua[0], /window = "address:0xabc", workspace = 3, follow = true/);
  lua.length = 0;
  shift('down'); // No monitor below, and Down is not the LTR station axis.
  assert.equal(lua.length, 0);
});

const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const Events = require('../../lib/Events.js');
const MonitorsLua = require('../../lib/MonitorsLua.js');

test('monitor v1 and v2 events require both the expected kind and output', () => {
  const expect = { kinds: ['monitorremoved'], outputs: ['eDP-1'], until: 2000 };
  for (const event of [
    { name: 'monitorremoved', data: 'eDP-1' },
    { name: 'monitorremovedv2', data: '0,eDP-1,Panel, with commas' },
  ]) assert.equal(Events.expected(event, expect, 1000), true);
  assert.equal(Events.expected({ name: 'monitorremoved', data: 'HDMI-A-2' }, expect, 1000), false);
  assert.equal(Events.expected({ name: 'monitoradded', data: 'eDP-1' }, expect, 1000), false);
  assert.equal(Events.expected({ name: 'monitorremovedv2', data: '0' }, expect, 1000), false);
  assert.equal(Events.expected({ name: 'monitorremoved', data: 'eDP-1' }, expect, 2001), false);
});

test('fake service stream ignores Station disable but handles another output added a second later', () => {
  // Execute the actual service handler so passing the event payload, rather
  // than just its name, is covered by the regression.
  const source = readFileSync('Service.qml', 'utf8');
  const start = source.indexOf('  function handleEvent(event) {');
  const end = source.indexOf('\n  Component.onCompleted:', start);
  let now = 1000;
  const expectation = { kinds: ['monitor', 'workspace'], outputs: ['eDP-1'], until: 3000 };
  const calls = [];
  const context = {
    Date: { now: () => now }, state: 'idle', lastTopologyMs: 0,
    Events, expect: expectation,
    refresh: (includeClients, done) => { calls.push('refresh'); done(); },
    updateAssignments: () => calls.push('assign'), applyRuntime: () => calls.push('apply'),
    openPanel: () => calls.push('open'), removalGrace: { stop: () => {}, restart: () => calls.push('remove') },
  };
  const expectedStart = source.indexOf('  function eventExpected(event) {');
  context.eventExpected = runInNewContext('(' + source.slice(expectedStart, start).trim() + ')', context);
  const handler = runInNewContext('(' + source.slice(start, end).trim() + ')', context);
  handler({ name: 'monitorremoved', data: 'eDP-1' });
  assert.deepEqual(calls, []);
  now += 1000;
  handler({ name: 'monitoraddedv2', data: '1,HDMI-A-2,External display' });
  assert.deepEqual(calls, ['refresh', 'assign', 'apply']);
  assert.equal(context.lastTopologyMs, now);
});

test('mode and geometry evaluations attribute only changed outputs', () => {
  const displays = [{ name: 'eDP-1', lane: 1, mode: '1920x1080@60.00Hz', x: 0, y: 0, scale: 1, transform: 0 },
    { name: 'HDMI-A-2', lane: 2, mode: '1920x1080@60.00Hz', x: 1920, y: 0, scale: 1, transform: 0 }];
  const monitors = displays.map(display => ({ ...display, disabled: false, mirrorOf: 'none',
    width: 1920, height: 1080, refreshRate: 60.003 }));
  const single = { mode: 'single', singleTarget: 'HDMI-A-2', enabled: ['eDP-1', 'HDMI-A-2'] };
  assert.deepEqual(MonitorsLua.changedOutputs(displays, single, monitors, false), ['eDP-1']);
  const extend = { mode: 'extend', enabled: ['eDP-1', 'HDMI-A-2'] };
  assert.deepEqual(MonitorsLua.changedOutputs(displays, extend, monitors, true), []);
  const moved = displays.map(display => ({ ...display, x: display.x + (display.name === 'eDP-1' ? 10 : 0) }));
  assert.deepEqual(MonitorsLua.changedOutputs(moved, extend, monitors, true), ['eDP-1']);
});

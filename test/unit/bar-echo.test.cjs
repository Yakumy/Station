// Omarchy's shell re-reads shell.json after a write and can show the file as it was for a
// moment. Station must not take its own replaced value for a request from elsewhere.
const test = require('node:test');
const assert = require('node:assert/strict');
const { ownerFunction } = require('../helpers/bar-settings.cjs');

const row = position => ({ enabled: true, position, width: 100, height: 0, background: 'solid', style: 'default', contentSize: 0 });

// Station's owner over a host whose memory the test can set back, as a late reload does.
function setup() {
  const clock = { now: 1000 };
  const c = {
    Date: { now: () => clock.now },
    configLoaded: true, panelWanted: false, focusedBarScreenName: 'DP-2', lastGlobalBarPosition: 'top',
    pendingMonitorBars: {}, displays: [{ name: 'DP-1' }, { name: 'DP-2' }],
    preferences: { 'DP-1': row('top'), 'DP-2': row('top') },
    hostConfig: { id: 'yakumy.station', position: 'top', monitors: { 'DP-1': row('top'), 'DP-2': row('top') } },
    validConnector: name => /^DP-\d$/.test(name), ownWrites: {}, echoWindow: 1500, echoSettle: { restart() {} },
    retainPanel() {}, writes: 0,
  };
  c.observedHostBars = JSON.parse(JSON.stringify(c.hostConfig.monitors));
  c.persistPreferences = bars => { c.preferences = bars; };
  c.publishHost = change => {
    const scoped = { bar: JSON.parse(JSON.stringify(c.hostConfig)) };
    change(scoped); c.hostConfig = scoped.bar; c.writes++; return true;
  };
  Object.defineProperty(c, 'globalBarPosition', { get: () => c.hostConfig.position });
  for (const name of ['rowText', 'recordOwnWrite', 'ownEcho', 'activeStationBar', 'monitorBar', 'publishMonitorBars', 'publishMonitorBar',
    'deferMonitorBarPublish', 'flushPendingMonitorBars', 'applyBarMenuPosition', 'syncFocusedBarMenu', 'syncGlobalBarPosition',
    'adoptHostBars', 'setMonitorBarPosition', 'settleOwnWrites']) c[name] = ownerFunction(name, c);
  // What the bindings do after the host's config changes.
  c.react = () => { c.adoptHostBars(); c.syncGlobalBarPosition(); c.syncFocusedBarMenu(); };
  c.snapshot = () => JSON.parse(JSON.stringify(c.hostConfig));
  c.positions = () => [c.preferences['DP-2'].position, c.hostConfig.monitors['DP-2'].position];
  c.drag = position => { c.setMonitorBarPosition('DP-2', position); c.react(); };
  return { c, clock };
}

test('a late reload of the previous file does not move the bar back', () => {
  const { c, clock } = setup();
  c.drag('right'); clock.now += 1000;
  const older = c.snapshot();
  c.drag('left');
  const newest = c.snapshot();
  clock.now += 200; c.hostConfig = older; c.react();
  assert.equal(c.preferences['DP-2'].position, 'left');
  clock.now += 100; c.hostConfig = newest; c.react();
  assert.deepEqual(c.positions(), ['left', 'left']);
  assert.equal(c.lastGlobalBarPosition, 'left');
});

test('repeated echoes settle on the last drag and never echo each other', () => {
  const { c, clock } = setup();
  const files = [];
  for (const position of ['right', 'left', 'bottom', 'right', 'top', 'left']) { c.drag(position); files.push(c.snapshot()); clock.now += 60; }
  const writes = c.writes;
  for (const file of [files[2], files[4], files[0], files[3], files[5]]) { clock.now += 90; c.hostConfig = file; c.react(); }
  assert.equal(c.writes, writes, 'an echo is never written back');
  assert.deepEqual(c.positions(), ['left', 'left']);
});

test('an echo another edit saved is corrected once things settle', () => {
  const { c, clock } = setup();
  const older = c.snapshot();
  c.drag('left'); clock.now += 100;
  // A widget drag wrote the whole bar while the old file was showing.
  c.hostConfig = older; c.react();
  assert.deepEqual(c.positions(), ['left', 'top']);
  clock.now += 1600; c.settleOwnWrites(); c.react();
  assert.deepEqual(c.positions(), ['left', 'left']);
  assert.equal(c.hostConfig.position, 'left');
  const writes = c.writes;
  clock.now += 1600; c.settleOwnWrites();
  assert.equal(c.writes, writes, 'and then nothing is left to correct');
});

test('a new value from elsewhere is adopted at once, even right after a drag', () => {
  const { c, clock } = setup();
  c.drag('left'); clock.now += 100;
  c.hostConfig = { ...c.hostConfig, monitors: { ...c.hostConfig.monitors, 'DP-2': row('bottom') } }; c.react();
  assert.equal(c.preferences['DP-2'].position, 'bottom');
  c.hostConfig = { ...c.hostConfig, monitors: { ...c.hostConfig.monitors, 'DP-1': row('right') } }; c.react();
  assert.equal(c.preferences['DP-1'].position, 'right', 'and another monitor is not held back');
});

test('going back to the old edge from elsewhere is adopted after the window', () => {
  const { c, clock } = setup();
  c.drag('left'); clock.now += 1600; c.settleOwnWrites();
  c.hostConfig = { ...c.hostConfig, monitors: { ...c.hostConfig.monitors, 'DP-2': row('top') } }; c.adoptHostBars();
  assert.equal(c.preferences['DP-2'].position, 'top');
});

test('Omarchy\'s position menu still moves the focused monitor\'s bar', () => {
  const { c, clock } = setup();
  c.drag('left'); clock.now += 2000; c.settleOwnWrites();
  c.hostConfig = { ...c.hostConfig, position: 'bottom' }; c.syncGlobalBarPosition(); c.react();
  assert.deepEqual(c.positions(), ['bottom', 'bottom']);
  assert.equal(c.preferences['DP-1'].position, 'top');
});

test('an untouched owner settles without writing', () => {
  const { c } = setup();
  c.settleOwnWrites();
  assert.equal(c.writes, 0);
});

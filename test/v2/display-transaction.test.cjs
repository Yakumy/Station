const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const { monitorRules } = require('./helpers/monitor-lua.cjs');
const source = readFileSync('Service.qml', 'utf8');
const copy = value => JSON.parse(JSON.stringify(value));

// Run the production service functions with asynchronous compositor/saved
// acknowledgments. Monitor events during reload are delivered before Keep's
// completion, exactly where the draft-reset regression occurred.
function harness() {
  const jobs = [], writes = [], monitorCalls = [], order = [], topologyEvents = [];
  const c = {};
  for (const name of ['Model', 'Grid', 'Hypr', 'MonitorsLua', 'Store', 'Transactions', 'Events'])
    c[name] = require('../../lib/' + name + '.js');
  let live = ['A', 'B'].map((name, i) => ({ name, id: i, disabled: false, mirrorOf: 'none',
    width: 1920, height: 1080, refreshRate: 60, x: i * 1920, y: 0, scale: 1, transform: 0,
    availableModes: ['1920x1080@60.00Hz'], focused: i === 0 }));
  let windows = [1, 2, 3, 4].map(id => ({ address: '0x' + id, pid: id, initialClass: 'test',
    monitor: id % 2 ? 'A' : 'B', workspace: { id, name: String(id) }, focusHistoryID: id === 3 ? 0 : id }));
  Object.assign(c, {
    state: 'idle', gen: 0, previewBusy: false, previewAbortReason: '', previewBaseline: null,
    previewApplied: null, previewBefore: [], pendingDisplayConfig: null, keepOptions: null,
    layoutWriteKind: '',
    keepFilesPending: false, candidateReady: false, plainCandidateReady: false,
    config: Object.assign(c.Store.configDefaults(), { enabled: ['A', 'B'] }),
    persisted: c.Store.stateDefaults(), configLoaded: true, dirsReady: true, stateLoaded: true,
    workspaceData: { mapping: { outputs: ['A', 'B'] }, pending: null, revision: 0 },
    lanes: { A: 1, B: 2 }, monitors: copy(live), clients: copy(windows), displayDraft: [],
    migrationPhase: '', migrationAttempts: 0, migrationCommit: null, migrationFocus: null,
    topologyDirty: false, currentStation: 2, layoutError: '', expect: {},
    panelWanted: true, panelScreenName: 'B', panelTransferUntil: 0,
    panelEvacuationSerial: 0, panelEvacuationWaiting: 0,
    panelEvacuationFrom: '', panelEvacuationTo: '', panelEvacuationPurpose: '',
    previewApplyLua: '', previewApplyStaged: false, previewApplyExpectedOutputs: [],
    previewApplyFocusTarget: '', previewApplyActivateLua: '',
    previewApplyMigrateFirst: false,
    previewApplyPanelOrigin: '', previewApplyPanelTarget: '',
    pendingRevertReason: '', pendingRevertPanelTarget: '', pendingRevertPanelOrigin: '',
    pendingRevertFocusTarget: '', pendingRevertActivateLua: '',
    stateDir: '/fake-state', monitorsSource: '',
    configGeneration: 0, appliedGeneration: 0, lastTopologyMs: 0,
    previewCountdown: { running: false, restart() { this.running = true; }, stop() { this.running = false; } },
    removalGrace: { running: false, stop() { this.running = false; } },
    reloadDebounce: { stop() {}, restart() { jobs.push(() => c.applyRuntime()); } },
    migrationRetry: { restart() { jobs.push(() => c.reconcile()); } },
    panelEvacuationTimeout: { running: false,
      restart() { this.running = true; }, stop() { this.running = false; } },
    Quickshell: { execDetached() {} },
    candidateFile: { text: () => c.candidate || '', setText(text) {
      jobs.push(() => { c.candidate = text; c.candidateReady = true; c.maybeStartKeep(); });
    } },
    plainCandidateFile: { text: () => c.plainCandidate || '', setText(text) {
      jobs.push(() => { c.plainCandidate = text; c.plainCandidateReady = true; c.maybeStartKeep(); });
    } },
    configFile: { setText(text) { c.savedConfig = JSON.parse(text); } }, stateFile: { setText() {} },
    monitorsFile: { reload() {} },
    workspaceFile: { setText(text) { writes.push(JSON.parse(text)); jobs.push(() => c.migrationSaved()); } },
  });
  c.root = c;
  Object.defineProperty(c, 'workspaceMap', { get: () => c.workspaceData.mapping });
  Object.defineProperty(c, 'draftEditable', { get: () => ['idle', 'previewing'].includes(c.state) && !c.previewBusy });
  for (const match of source.matchAll(/^  function (\w+)\([^\n]*\{\n[^]*?^  \}/gm))
    c[match[1]] = runInNewContext('(' + match[0].trim() + ')', c);
  let evacuationSerial = 0;
  Object.defineProperty(c, 'panelEvacuationSerial', {
    configurable: true,
    get: () => evacuationSerial,
    set(value) {
      evacuationSerial = value;
      if (value) jobs.push(() => {
        order.push('panel-closed:' + c.panelEvacuationFrom);
        c.acknowledgePanelEvacuation(value, c.panelEvacuationFrom);
      });
    },
  });
  c.applyBinds = () => {};
  c.refresh = (_clients, done) => jobs.push(() => {
    c.monitors = copy(live); c.clients = copy(windows); if (done) done();
  });
  function event(name, output) {
    if (name === 'monitoradded' || name === 'monitorremoved') topologyEvents.push(`${name}:${output}`);
    c.handleEvent({ name, data: output });
  }
  function apply(lua) {
    const focused = lua.match(/hl\.dsp\.focus\(\{ monitor = "([AB])"/);
    if (focused) {
      live.forEach(monitor => { monitor.focused = monitor.name === focused[1]; });
      order.push('focus:' + focused[1]);
    }
    for (const match of lua.matchAll(/hl\.monitor\(\{ ([^}]+) \}\)/g)) {
      const fields = match[1], name = fields.match(/output = "([AB])"/)[1];
      const monitor = live.find(m => m.name === name);
      const disabled = fields.match(/disabled = (true|false)/);
      const mirror = fields.match(/mirror = "([^"]*)"/);
      const scale = fields.match(/scale = ([0-9.]+)/);
      const mode = fields.match(/mode = "(\d+)x(\d+)@(\d+(?:\.\d+)?)Hz"/);
      const position = fields.match(/position = "(-?\d+)x(-?\d+)"/);
      const transform = fields.match(/transform = (\d+)/);
      const old = monitor.disabled;
      // A geometry-only declaration makes its output active during reload.
      // A combined declaration applies its final disabled state atomically.
      if (!disabled && /mode = /.test(fields)) monitor.disabled = false;
      else if (disabled) monitor.disabled = disabled[1] === 'true';
      if (mirror) monitor.mirrorOf = mirror[1] || 'none';
      if (scale) monitor.scale = Number(scale[1]);
      if (mode) {
        monitor.width = Number(mode[1]);
        monitor.height = Number(mode[2]);
        monitor.refreshRate = Number(mode[3]);
      }
      if (position) { monitor.x = Number(position[1]); monitor.y = Number(position[2]); }
      if (transform) monitor.transform = Number(transform[1]);
      monitorCalls.push({ name, disabled: monitor.disabled, mirror: monitor.mirrorOf });
      order.push('monitor:' + name + ':' + (monitor.disabled ? 'off' : (monitor.mirrorOf !== 'none' ? 'mirror' : 'on')));
      assert.ok(live.some(m => !m.disabled && m.mirrorOf === 'none'), 'never remove the last real output');
      if (old !== monitor.disabled) event(monitor.disabled ? 'monitorremoved' : 'monitoradded', name);
      if (monitor.disabled || monitor.mirrorOf !== 'none') {
        const survivor = live.find(m => !m.disabled && m.mirrorOf === 'none');
        windows.filter(w => w.monitor === name).forEach(w => { w.monitor = survivor.name; });
      }
    }
    for (const match of lua.matchAll(/window = "address:(0x\w+)", workspace = (\d+), follow = false/g)) {
      const window = windows.find(w => w.address === match[1]);
      window.workspace = { id: Number(match[2]), name: match[2] };
    }
    for (const match of lua.matchAll(/workspace\.move\(\{ workspace = (\d+), monitor = "([AB])"/g))
      windows.filter(w => w.workspace.id === Number(match[1])).forEach(w => {
        w.monitor = match[2];
        order.push('workspace:' + match[1] + ':' + match[2]);
      });
  }
  c.evalLua = (lua, done) => jobs.push(() => { apply(lua); if (done) done(0, 'ok'); });
  function reload() {
    order.push('reload');
    live.forEach(m => { m.disabled = false; m.mirrorOf = 'none'; event('monitoradded', m.name); });
    event('configreloaded', '');
  }
  c.enqueue = (args, done) => jobs.push(() => {
    if (args.join(' ') === 'hyprctl reload') reload();
    if (done) done(0, '');
  });
  c.previewArm = {};
  Object.defineProperty(c.previewArm, 'running', { set(value) { if (value) jobs.push(() => c.applyPreview()); } });
  c.keepTransaction = {};
  Object.defineProperty(c.keepTransaction, 'running', { set(value) {
    if (value) { c.keepStarted = true; jobs.push(() => {
      order.push('autoreload');
      const connected = live.filter(m => !m.disabled).map(m => `{name=${JSON.stringify(m.name)}}`).join(',');
      apply(monitorRules(c.candidate, `function() return {${connected}} end`).join('\n'));
      event('configreloaded', '');
      jobs.push(() => c.finishKeep(0, ''));
    }); }
  } });
  c.syncDisplayDraft();
  function drain(error = '') {
    let limit = 200;
    while (jobs.length && --limit) jobs.shift()();
    assert.ok(limit, 'transaction converges');
    assert.equal(c.layoutError, error, 'transaction reports the expected result');
  }
  return { c, drain, writes, monitorCalls, order, topologyEvents, windows: () => copy(windows),
    setWindows(value) { windows = copy(value); } };
}

test('Single preview migrates immediately, transfers panel, then Keep survives reload events', () => {
  const h = harness(), c = h.c;
  assert.equal(c.setModeValue('single', 'A'), 'started');
  assert.equal(c.previewCountdown.running, false);
  assert.equal(c.keepPreview(), 'busy');
  h.drain();
  assert.equal(c.state, 'previewing');
  assert.equal(c.previewBusy, false);
  assert.equal(c.panelScreenName, 'A');
  assert.ok(h.order.indexOf('panel-closed:B') < h.order.indexOf('monitor:B:off'),
    'the focused panel surface closes before its output is disabled');
  assert.deepEqual(h.windows().map(w => [w.workspace.id, w.monitor]), [[1, 'A'], [1, 'A'], [2, 'A'], [2, 'A']]);
  assert.equal(c.previewCountdown.running, true);
  assert.equal(c.previewSeconds, 12);
  assert.equal(h.writes[0].preview.windows.length, 4, 'original ownership is durable before migration');
  assert.equal(c.keepPreview(), 'started');
  assert.equal(c.keepStarted, undefined, 'Keep waits for both file acknowledgments');
  const callsBeforeKeep = h.monitorCalls.length;
  const eventsBeforeKeep = h.topologyEvents.slice();
  // Even an unrelated draft reset cannot change the accepted choice.
  c.draftMode = 'extend';
  h.drain();
  assert.equal(c.config.mode, 'single');
  assert.equal(c.savedConfig.singleTarget, 'A');
  assert.deepEqual(copy(c.workspaceMap.outputs), ['A']);
  assert.equal(c.workspaceData.preview, null);
  assert.equal(c.previewBaseline, null);
  assert.equal(c.state, 'idle');
  assert.deepEqual(h.topologyEvents, eventsBeforeKeep,
    'Keep does not remove or re-add an output after the accepted preview');
  assert.equal(h.monitorCalls.length - callsBeforeKeep, 2,
    'the watched config applies one final rule per output without a runtime replay');
});

test('scale side control saves directly with one watched apply and no preview countdown', () => {
  const h = harness(), c = h.c;
  assert.equal(c.applyDisplaySetting('A', 'scale', 2), 'started');
  assert.equal(c.state, 'applyingLayout');
  assert.equal(c.layoutWriteKind, 'control');
  assert.equal(c.previewCountdown.running, false);
  assert.equal(c.workspaceData.preview || null, null);
  h.drain();
  assert.equal(c.state, 'idle');
  assert.equal(c.displayDraft.find(display => display.name === 'A').scale, 2);
  assert.equal(c.displayDraft.find(display => display.name === 'B').scale, 1);
  assert.equal(c.displayDraft.find(display => display.name === 'A').x, 960);
  assert.equal(c.displayDraft.find(display => display.name === 'A').x
    + c.Model.logicalSize(c.displayDraft.find(display => display.name === 'A')).width,
    c.displayDraft.find(display => display.name === 'B').x,
    'scaling the left display keeps its right edge attached to its neighbor');
  assert.deepEqual(c.Model.layoutOverlaps(c.displayDraft), []);
  assert.equal(h.order.filter(item => item === 'autoreload').length, 1);
  assert.equal(h.order.filter(item => item === 'reload').length, 0,
    'the direct write relies on the watched apply and never forces another reload');
  assert.equal(c.previewSeconds || 0, 0);
});

test('scaling the right display retains its attached left edge', () => {
  const h = harness(), c = h.c;
  assert.equal(c.applyDisplaySetting('B', 'scale', 2), 'started');
  h.drain();
  assert.equal(c.displayDraft.find(display => display.name === 'B').x, 1920);
  assert.deepEqual(c.Model.layoutOverlaps(c.displayDraft), []);
});

test('an unchanged side control performs no write or compositor apply', () => {
  const h = harness();
  assert.equal(h.c.applyDisplaySetting('A', 'scale', 1), 'ok');
  h.drain();
  assert.equal(h.c.keepStarted, undefined);
  assert.deepEqual(h.order, []);
});

test('runtime reconciliation leaves matching monitor rules alone', () => {
  const h = harness();
  h.c.applyRuntime(); h.drain();
  assert.deepEqual(h.monitorCalls, []);
  h.c.config.mode = 'single';
  h.c.config.singleTarget = 'A';
  h.c.applyRuntime(); h.drain();
  assert.deepEqual(h.monitorCalls.map(call => call.name), ['B']);
  h.monitorCalls.length = 0;
  h.c.applyRuntime(); h.drain();
  assert.deepEqual(h.monitorCalls, []);
});

test('Single HDMI Keep preserves the accepted topology without re-announcing eDP', () => {
  const h = harness(), c = h.c;
  c.panelScreenName = 'A';
  c.setModeValue('single', 'B');
  h.drain();
  const eventsBeforeKeep = h.topologyEvents.slice();
  const callsBeforeKeep = h.monitorCalls.length;
  assert.equal(c.keepPreview(), 'started');
  h.drain();
  assert.deepEqual(h.topologyEvents, eventsBeforeKeep);
  assert.equal(h.monitorCalls.length - callsBeforeKeep, 2);
  assert.equal(c.config.singleTarget, 'B');
});

test('Single HDMI evacuates an eDP panel and focuses HDMI before disabling eDP', () => {
  const h = harness(), c = h.c;
  c.panelScreenName = 'A';
  assert.equal(c.setModeValue('single', 'B'), 'started');
  h.drain();
  const closed = h.order.indexOf('panel-closed:A');
  const focused = h.order.indexOf('focus:B');
  const disabled = h.order.indexOf('monitor:A:off');
  assert.ok(closed !== -1 && focused !== -1 && disabled !== -1);
  assert.ok(closed < focused, 'release the panel focus grab first');
  assert.ok(focused < disabled, 'focus the surviving output before monitor removal');
  assert.equal(c.panelScreenName, 'B', 'reopen is published only after the monitor rule succeeds');
});

test('saved Single eDP -> Single HDMI migrates windows before removing eDP', () => {
  const h = harness(), c = h.c;
  c.config = Object.assign({}, c.config, { mode: 'single', singleTarget: 'A' });
  c.applyRuntime();
  h.drain();
  c.syncDisplayDraft();
  c.panelScreenName = 'A';
  h.order.length = 0;
  assert.match(c.activationRule('B'), /mode = .*position = .*disabled = false/,
    'a disabled destination needs a full rule that overrides persisted Single state');

  assert.equal(c.setModeValue('single', 'B'), 'started');
  h.drain();

  const enabled = h.order.indexOf('monitor:B:on');
  const focused = h.order.indexOf('focus:B');
  const migrated = h.order.findIndex(item => item.endsWith(':B') && item.startsWith('workspace:'));
  const disabled = h.order.indexOf('monitor:A:off');
  assert.ok(enabled !== -1 && focused !== -1 && migrated !== -1 && disabled !== -1);
  assert.ok(enabled < focused, 'enable HDMI before focusing it');
  assert.ok(focused < migrated, 'focus HDMI before migrating its windows');
  assert.ok(migrated < disabled, 'migrate every client before removing eDP');
  assert.equal(c.panelScreenName, 'B');
  assert.equal(c.state, 'previewing');
});

test('Revert to a different saved Single target prepares that output before reload', () => {
  const h = harness(), c = h.c;
  c.panelScreenName = 'A';
  c.setModeValue('single', 'B');
  h.drain();
  c.config = Object.assign({}, c.config, { mode: 'single', singleTarget: 'A', enabled: ['A', 'B'] });
  h.order.length = 0;
  assert.equal(c.revertPreview(''), 'started');
  h.drain();
  const closed = h.order.indexOf('panel-closed:B');
  const enabled = h.order.indexOf('monitor:A:on');
  const focused = h.order.indexOf('focus:A');
  const reloaded = h.order.indexOf('reload');
  assert.ok(closed !== -1 && enabled !== -1 && focused !== -1 && reloaded !== -1);
  assert.ok(closed < enabled && enabled < focused && focused < reloaded,
    'rollback releases the panel, enables and focuses the saved output, then reloads');
});

test('card Off previews and migrates; Revert restores original window ownership', () => {
  const h = harness(), c = h.c, before = h.windows();
  assert.equal(c.setDisplayEnabled('B', false), 'started');
  h.drain();
  assert.ok(h.monitorCalls.some(call => call.name === 'B' && call.disabled));
  assert.deepEqual(copy(c.workspaceMap.outputs), ['A']);
  assert.equal(c.setDisplayEnabled('A', false), 'invalid', 'the last enabled display is protected');
  c.layoutError = '';
  assert.equal(c.revertPreview(''), 'started');
  h.drain();
  assert.deepEqual(h.windows(), before);
  assert.deepEqual(copy(c.workspaceMap.outputs), ['A', 'B']);
  assert.equal(c.workspaceData.preview, null);
});

test('Single -> Mirror -> Extend re-edits preserve station identities and remain reversible', () => {
  const h = harness(), c = h.c, before = h.windows();
  c.setModeValue('single', 'B'); h.drain();
  assert.deepEqual(h.windows().map(w => [w.workspace.id, w.monitor]), [[1, 'B'], [1, 'B'], [2, 'B'], [2, 'B']]);
  c.setModeValue('mirror', ''); h.drain();
  assert.deepEqual(h.windows().map(w => w.workspace.id), [1, 1, 2, 2]);
  c.setModeValue('extend', ''); h.drain();
  assert.deepEqual(h.windows().map(w => w.workspace.id), [1, 1, 3, 3]);
  c.revertPreview(''); h.drain();
  assert.deepEqual(h.windows(), before);
});

test('restart recovery restores original assignments from the preview journal', () => {
  const h = harness(), before = h.windows();
  h.c.setModeValue('single', 'A'); h.drain();
  const restarted = harness();
  restarted.setWindows(h.windows());
  restarted.c.workspaceData = copy(h.c.workspaceData);
  restarted.c.previewBaseline = copy(h.c.workspaceData.preview);
  restarted.c.applyRuntime(); restarted.drain();
  assert.deepEqual(restarted.windows(), before);
  assert.equal(restarted.c.workspaceData.preview, null);
});

test('timeout restores the original displays and windows after immediate Single migration', () => {
  const h = harness(), before = h.windows();
  h.c.setModeValue('single', 'A'); h.drain();
  h.c.revertPreview('Preview timed out.');
  h.drain('Preview timed out.');
  assert.deepEqual(h.windows(), before);
  assert.equal(h.c.state, 'idle');
});

test('Enable on a Single-mode disabled card returns to Extend and previews it', () => {
  const h = harness(), c = h.c;
  c.setModeValue('single', 'A'); h.drain();
  assert.equal(c.displayEnabled('B'), false);
  assert.equal(c.setDisplayEnabled('B', true), 'started'); h.drain();
  assert.equal(c.draftMode, 'extend');
  assert.equal(c.displayEnabled('B'), true);
  assert.deepEqual(copy(c.workspaceMap.outputs), ['A', 'B']);
});

test('a failed candidate write never starts Keep and rolls back migrated windows', () => {
  const h = harness(), before = h.windows(), c = h.c;
  c.setModeValue('single', 'A'); h.drain();
  c.candidateFile.setText = () => c.keepFileFailed();
  c.keepPreview(); h.drain('Could not save the monitor layout.');
  assert.equal(c.keepStarted, undefined);
  assert.equal(c.config.mode, 'extend');
  assert.deepEqual(h.windows(), before);
});

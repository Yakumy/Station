// Reusable production display/Service scenario driver with fake external effects.
const assert = require('node:assert/strict');
const { runtimeSource, adaptOwners, owners, ownerSource, libPath } = require('./runtime-source.cjs');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const { join } = require('node:path');
const { monitorRules } = require('./monitor-lua.cjs');
const { ownerFunction } = require('./workspace-owner.cjs');
const { ownerFunction: displayFunction, methods: displayMethods } = require('./display-owner.cjs');
const current = runtimeSource();
const copy = value => JSON.parse(JSON.stringify(value));
function harness({ capture = false } = {}) {
  const source = current;
  const trace = [];
  const jobs = [], writes = [], monitorCalls = [], order = [], topologyEvents = [];
  const c = {};
  for (const name of ['Model', 'Grid', 'Hypr', 'MonitorsLua', 'Store', 'Transactions', 'Events'])
    c[name] = require('../../' + libPath(name + '.js'));
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
    screenHealthChecks: 0,
    panelWanted: true, panelScreenName: 'B', panelTransferUntil: 0,
    panelEvacuationSerial: 0, panelEvacuationWaiting: 0,
    panelEvacuationFrom: '', panelEvacuationTo: '', panelEvacuationPurpose: '',
    previewApplyLua: '', previewApplyStaged: false, previewApplyExpectedOutputs: [],
    previewApplyFocusTarget: '', previewApplyActivateLua: '',
    previewApplyMigrateFirst: false, previewApplyParkToggle: '', parkedToggleSource: '',
    previewApplyPanelOrigin: '', previewApplyPanelTarget: '',
    pendingRevertReason: '', pendingRevertPanelTarget: '', pendingRevertPanelOrigin: '',
    pendingRevertFocusTarget: '', pendingRevertActivateLua: '',
    stateDir: '/fake-state', parkedTogglePath: '/fake-state/parked', internalDisablePath: '/fake-toggle', monitorsSource: '', internalDisableSource: '', draftMirrorSource: '', previewObservedSignature: '',
    configGeneration: 0, appliedGeneration: 0, lastTopologyMs: 0,
    previewCountdown: { running: false, restart() { this.running = true; }, stop() { this.running = false; } },
    focusRetry: { deadline: 0, target: '', done: null, stop() {}, restart() { jobs.push(() => c.attemptFocus(this.target, this.done)); } },
    removalGrace: { running: false, stop() { this.running = false; } },
    reloadDebounce: { stop() {}, restart() { jobs.push(() => c.applyRuntime()); } },
    migrationRetry: { restart() { jobs.push(() => c.reconcile()); } },
    panelEvacuationTimeout: { running: false,
      restart() { this.running = true; }, stop() { this.running = false; } },
    Quickshell: { execDetached() {} },
    candidateFile: { text: () => c.candidate || '', setText(text) {
      record('candidate', text);
      jobs.push(() => { c.candidate = text; c.candidateReady = true; c.maybeStartKeep(); });
    } },
    plainCandidateFile: { text: () => c.plainCandidate || '', setText(text) {
      record('plainCandidate', text);
      jobs.push(() => { c.plainCandidate = text; c.plainCandidateReady = true; c.maybeStartKeep(); });
    } },
    configFile: { setText(text) { record('config',text); c.savedConfig = JSON.parse(text); } }, stateFile: { setText(text) { record('state',text); } },
    monitorsFile: { reload() {} },
    workspaceFile: { setText(text) { record('journal',text); writes.push(JSON.parse(text)); jobs.push(() => c.migrationSaved()); } },
  });
  c.root = c;
  if (capture) c.Date = { now: () => 1000 };
  function record(kind, value) { if (capture) trace.push([kind, copy(value)]); }
  Object.defineProperty(c, 'workspaceMap', { get: () => c.workspaceData.mapping });
  Object.defineProperty(c, 'draftEditable', { get: () => ['idle', 'previewing'].includes(c.state) && !c.previewBusy });
  adaptOwners(c);
  for (const match of source.matchAll(/^  function (\w+)\([^\n]*\{\n[^]*?^  \}/gm))
    c[match[1]] = displayFunction(match[1], c) || ownerFunction(match[1], c) || runInNewContext('(' + match[0].trim() + ')', c);
  // Service's one-line members forward to owners; only owners define real one-liners.
  for (const match of owners.map(ownerSource).join('\n').matchAll(/^  function (\w+)\([^\n]*\{[^\n]*\}$/gm))
    if (!c[match[1]]) c[match[1]] = runInNewContext('(' + match[0].trim() + ')', c);
  for (const name of [...displayMethods, 'reconcile', 'migrationFailed', 'migrationSaved', 'executeMigration'])
    c[name] = displayFunction(name, c) || ownerFunction(name, c) || c[name];
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
  c.refreshWindowSettings = () => {};
  // Blur uses a separate compositor probe, not the display transaction queue.
  // Its lease/probe behavior is covered by bar-per-monitor.test.cjs.
  c.syncBarBlur = () => {};
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
  c.evalLua = (lua, done) => {
    record('eval', {lua,expect:c.expect,state:c.state});
    jobs.push(() => {
    apply(lua);
    if (!done) return;
    if (c.rejectAppliedMoves && /workspace\.move/.test(lua)) {
      c.rejectAppliedMoves = false;
      done(1, 'false');
    } else done(0, 'ok');
  });
  };
  function reload() {
    order.push('reload');
    live.forEach(m => { m.disabled = false; m.mirrorOf = 'none'; event('monitoradded', m.name); });
    event('configreloaded', '');
  }
  c.enqueue = (args, done) => {
    record('enqueue',args);
    jobs.push(() => {
    if (args.join(' ') === 'hyprctl reload') reload();
    if (done) done(0, '');
  });
  };
  c.previewArm = {};
  c.armScreenHealthCheck = () => { c.screenHealthChecks++; };
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
  c.Quickshell.execDetached = args => record('detached',args);
  c.syncDisplayDraft();
  function drain(error = '') {
    let limit = 200;
    while (jobs.length && --limit) { jobs.shift()(); record('settledJob', snapshot()); }
    assert.ok(limit, 'transaction converges');
    assert.equal(c.layoutError, error, 'transaction reports the expected result');
  }
  function snapshot() {
    return { state:c.state,gen:c.gen,configGeneration:c.configGeneration,config:c.config,
      draft:c.displayDraft,mode:c.draftMode,single:c.draftSingleTarget,mirror:c.draftMirrorSource,
      baseline:c.previewBaseline,before:c.previewBefore,applied:c.previewApplied,pending:c.pendingDisplayConfig,
      busy:c.previewBusy,seconds:c.previewSeconds,stage:c.previewApplyStaged,migrateFirst:c.previewApplyMigrateFirst,
      writeKind:c.layoutWriteKind,options:c.keepOptions,journal:c.workspaceData,phase:c.migrationPhase,
      screen:c.panelScreenName,serial:c.panelEvacuationSerial,waiting:c.panelEvacuationWaiting,
      clients:c.clients,live:live,windows:windows,error:c.layoutError };
  }
  return { c, live: () => live, drain, writes, trace, snapshot, monitorCalls, order, topologyEvents, event, windows: () => copy(windows),
    setWindows(value) { windows = copy(value); },
    setMonitors(value) { live = copy(value); c.monitors = copy(value); } };
}

module.exports = { harness, current };

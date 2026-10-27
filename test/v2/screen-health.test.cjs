const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const ScreenHealth = require('../../lib/ScreenHealth.js');
const Model = require('../../lib/Model.js');
const MonitorsLua = require('../../lib/MonitorsLua.js');

const active = [
  { name: 'eDP-1', disabled: false, mirrorOf: 'none', width: 1920, height: 1080,
    refreshRate: 60.003, availableModes: ['1920x1080@60.00Hz'], x: 0, y: 0, scale: 1, transform: 0 },
  { name: 'HDMI-A-2', disabled: false, mirrorOf: 'none', width: 1920, height: 1200,
    refreshRate: 59.88, availableModes: ['1920x1200@59.88Hz'], x: 1920, y: 0, scale: 1, transform: 0 },
];

test('detects an enabled output missing from the shell screen list', () => {
  assert.deepEqual(ScreenHealth.missingScreens(active, [{ name: 'HDMI-A-2' }]), ['eDP-1']);
  assert.deepEqual(ScreenHealth.missingScreens(active, active), []);
});

test('does not require shell screens for disabled or mirrored outputs', () => {
  const monitors = [
    { ...active[0], disabled: true },
    { ...active[1], mirrorOf: '0' },
  ];
  assert.deepEqual(ScreenHealth.activeMonitorNames(monitors), []);
  assert.deepEqual(ScreenHealth.missingScreens(monitors, []), []);
});

test('recovery requires another active output that the shell still sees', () => {
  assert.equal(ScreenHealth.recoveryTarget(active, [{ name: 'HDMI-A-2' }]), 'eDP-1');
  assert.equal(ScreenHealth.recoveryTarget([active[0]], []), '', 'never cycle the only active output');
  assert.equal(ScreenHealth.recoveryTarget(active, []), '', 'never cycle when there is no healthy survivor');
});

test('screen recovery is armed only after Keep or Revert has settled', () => {
  const service = readFileSync('Service.qml', 'utf8');
  const restore = service.slice(service.indexOf('  function restoreAppliedLayout() {'),
    service.indexOf('\n  function finishKeep(', service.indexOf('  function restoreAppliedLayout() {')));
  const keep = service.slice(service.indexOf('  function finishKeep('),
    service.indexOf('\n  function maybeStart()', service.indexOf('  function finishKeep(')));
  const preview = service.slice(service.indexOf('  function finishPreviewApply() {'),
    service.indexOf('\n  function applyPreviewSnapshot()', service.indexOf('  function finishPreviewApply() {')));

  assert.match(restore, /state = "idle"[\s\S]*armScreenHealthCheck\(\)/);
  assert.match(keep, /state = "idle"[\s\S]*armScreenHealthCheck\(\)/);
  assert.doesNotMatch(preview, /armScreenHealthCheck/);
  assert.match(service, /monitorRule\(display, \{ geometry: false, disabled: true, mirror: "" \}\)/);
  assert.match(service, /monitorRule\(display, \{ disabled: false, mirror: "" \}\)/);
  assert.doesNotMatch(service, /execDetached\(\["omarchy", "restart", "shell"\]\)/);
});

test('service cycles the stale output and restores its exact validated rule', () => {
  const service = readFileSync('Service.qml', 'utf8');
  function serviceFunction(name, context) {
    const start = service.indexOf('  function ' + name + '(');
    const end = service.indexOf('\n  function ', start + 1);
    return runInNewContext('(' + service.slice(start, end).trim() + ')', context);
  }
  const calls = [];
  let enableTimer = 0;
  const c = {
    ScreenHealth, Model, MonitorsLua, Date, console,
    Quickshell: { screens: [{ name: 'HDMI-A-2' }] },
    monitors: active, lanes: { 'eDP-1': 2, 'HDMI-A-2': 1 }, state: 'idle',
    screenRecoveryActive: false, screenRecoveryAttempts: 0,
    screenRecoveryTarget: '', screenRecoveryRule: '', expect: {}, layoutError: '',
    screenHealthCheck: { restart() {} },
    screenRecoveryEnable: { restart() { enableTimer++; } },
    evalLua(rule, done) { calls.push({ rule, done }); },
    refresh(withClients, done) { assert.equal(withClients, true); done(); },
    reconcile() { c.reconciled = true; },
  };
  c.root = c;
  c.verifyScreenHealth = serviceFunction('verifyScreenHealth', c);
  c.finishScreenRecovery = serviceFunction('finishScreenRecovery', c);

  c.verifyScreenHealth();
  assert.equal(c.state, 'recoveringScreen');
  assert.equal(c.screenRecoveryTarget, 'eDP-1');
  assert.match(calls[0].rule, /output = "eDP-1", disabled = true, mirror = ""/);
  assert.doesNotMatch(calls[0].rule, /mode =|position =|scale =|transform =/);
  calls[0].done(0, 'ok');
  assert.equal(enableTimer, 1);

  c.finishScreenRecovery();
  assert.match(calls[1].rule, /mode = "1920x1080@60\.00Hz"/);
  assert.match(calls[1].rule, /position = "0x0"/);
  assert.match(calls[1].rule, /scale = 1, transform = 0, disabled = false, mirror = ""/);
  calls[1].done(0, 'ok');
  assert.equal(c.state, 'idle');
  assert.equal(c.reconciled, true);
});

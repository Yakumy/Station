const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const ScreenHealth = require('../../lib/ScreenHealth.js');

const active = [
  { name: 'eDP-1', disabled: false, mirrorOf: 'none', width: 1920, height: 1080 },
  { name: 'HDMI-A-2', disabled: false, mirrorOf: 'none', width: 1920, height: 1200 },
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

test('shell recovery is armed only after Keep or Revert has settled', () => {
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
  assert.match(service, /Quickshell\.execDetached\(\["omarchy", "restart", "shell"\]\)/);
});

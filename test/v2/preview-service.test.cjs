const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const Model = require('../../lib/Model.js');
const source = readFileSync('Service.qml', 'utf8');

for (const reason of ['', 'Preview timed out.']) {
  test(`preview restores applied geometry after fresh snapshot: ${reason || 'manual Revert'}`, () => {
    const commands = [];
    let snapshot, runtimeCalls = 0;
    const c = {
      Model, state: 'previewing', gen: 5, appliedGeneration: 5,
      panelWanted: false, panelTransferUntil: 0, previewApplied: {},
      previewBusy: false, previewBaseline: null, previewAbortReason: '', keepOptions: null,
      stateDir: '/tmp/station-test', pendingDisplayConfig: {}, layoutError: '',
      config: { mode: 'extend', singleTarget: '', enabled: ['eDP-1', 'HDMI-A-2'] },
      lanes: { 'eDP-1': 1, 'HDMI-A-2': 2 },
      monitors: [], displayDraft: [{ name: 'eDP-1', x: 900, y: 500, scale: 2 }],
      draftMode: 'mirror', draftSingleTarget: 'HDMI-A-2',
      validConnector() { return true; },
      previewCountdown: { stop() { c.timerStopped = true; } },
      enqueue(args, done) { commands.push({ args, done }); },
      refresh(includeClients, done) { assert.equal(includeClients, true); snapshot = done; },
      applyRuntime() { runtimeCalls++; },
    };
    c.root = c;
    for (const name of ['revertPreview', 'restoreAppliedLayout', 'syncDisplayDraft']) {
      const start = source.indexOf('  function ' + name + '(');
      const end = source.indexOf('\n  function ', start + 1);
      c[name] = runInNewContext('(' + source.slice(start, end).trim() + ')', c);
    }
    assert.equal(c.revertPreview(reason), 'started');
    assert.equal(c.timerStopped, true);
    assert.equal(c.pendingDisplayConfig, null);
    commands.shift().done(0);
    const reload = commands.shift();
    assert.equal(reload.args.join(' '), 'hyprctl reload');
    reload.done(0);
    assert.equal(c.state, 'applyingLayout');
    assert.equal(runtimeCalls, 0);
    assert.equal(c.appliedGeneration, -1);
    // Delayed compositor reply, including geometry different from previewBefore.
    c.monitors = [
      { name: 'eDP-1', x: -1920, y: 2280, width: 1920, height: 1080, scale: 1, transform: 0, refreshRate: 60 },
      { name: 'HDMI-A-2', x: -1920, y: 1080, width: 1920, height: 1200, scale: 1, transform: 0, refreshRate: 60 },
    ];
    snapshot();
    assert.equal(c.state, 'idle');
    assert.equal(c.displayDraft[0].x, -1920);
    assert.equal(c.displayDraft[0].y, 2280);
    assert.equal(c.displayDraft[0].scale, 1);
    assert.equal(c.displayDraft[1].y, 1080);
    assert.equal(c.draftMode, 'extend');
    assert.equal(c.draftSingleTarget, '');
    assert.equal(runtimeCalls, 1);
    assert.equal(c.layoutError, reason);
    assert.equal(c.revertPreview(reason), 'idle');
    assert.equal(commands.length, 0);
  });
}

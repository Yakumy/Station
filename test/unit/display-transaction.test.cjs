const test = require('node:test');
const assert = require('node:assert/strict');
const { harness } = require('../helpers/display-transaction.cjs');
const copy = value => JSON.parse(JSON.stringify(value));

// Run the production service functions with asynchronous compositor/saved
// acknowledgments. Monitor events during reload are delivered before Keep's
// completion, exactly where the draft-reset regression occurred.

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

test('Mirror keeps a panel open on the surviving source and sheds its peer surface first', () => {
  const h = harness(), c = h.c;
  c.panelScreenName = 'A';
  assert.equal(c.setModeValue('mirror', ''), 'started');
  h.drain();
  assert.equal(c.previewBusy, false);
  assert.equal(c.panelScreenName, 'A');
  assert.ok(!h.order.includes('panel-closed:A'), 'the panel on the surviving output stays open');
  const released = h.order.indexOf('panel-peers-released:B');
  assert.ok(released >= 0, 'the leaving output sheds its dismiss surface');
  assert.ok(h.order.slice(0, released).every(item => !item.startsWith('monitor:')),
    'no monitor mutation precedes panel acknowledgement');
});

test('Single on the panel output keeps the panel open, and a panel on the leaving output closes', () => {
  const stays = harness();
  stays.c.panelScreenName = 'A';
  assert.equal(stays.c.setModeValue('single', 'A'), 'started');
  stays.drain();
  assert.ok(stays.order.includes('panel-peers-released:B'));
  assert.ok(!stays.order.some(item => item.startsWith('panel-closed')));
  assert.ok(stays.order.indexOf('panel-peers-released:B') < stays.order.indexOf('monitor:B:off'));

  const moves = harness();
  moves.c.panelScreenName = 'B';
  assert.equal(moves.c.setModeValue('single', 'A'), 'started');
  moves.drain();
  assert.ok(moves.order.includes('panel-closed:B'), 'a panel cannot stay on an output that leaves');
  assert.equal(moves.c.panelScreenName, 'A');
});

test('a hand-off is skipped when no output leaves and the panel stays put', () => {
  const h = harness(), c = h.c;
  c.panelScreenName = 'A';
  assert.equal(c.setDisplayPosition('B', 5000, 0), 'ok');
  assert.equal(c.previewLayout(), 'started');
  h.drain();
  assert.equal(c.panelEvacuationSerial, 0);
  assert.ok(!h.order.some(item => item.startsWith('panel-')));
  // Revert re-applies the old position and removes no output either.
  assert.equal(c.revertPreview(''), 'started');
  h.drain();
  assert.equal(c.panelEvacuationSerial, 0);
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

test('runtime reconciliation adopts external topology without monitor commands', () => {
  const h = harness();
  h.c.applyRuntime(); h.drain();
  assert.deepEqual(h.monitorCalls, []);
  h.c.config.mode = 'single';
  h.c.config.singleTarget = 'A';
  h.c.applyRuntime(); h.drain();
  assert.deepEqual(h.monitorCalls, []);
  assert.equal(h.c.config.mode, 'extend');
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
  h.setMonitors(c.monitors.map(m => ({ ...m, disabled: m.name === 'B' })));
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

test('Mirror source -> Single sink commits moves that verify after an aggregate rejection', () => {
  const h = harness(), c = h.c;
  c.lanes = { A: 2, B: 1 };
  c.syncDisplayDraft();
  c.setModeValue('mirror', ''); h.drain();
  assert.ok(h.monitorCalls.some(call => call.name === 'A' && call.mirror === 'B'));

  c.rejectAppliedMoves = true;
  assert.equal(c.setModeValue('single', 'A'), 'started');
  h.drain();

  assert.equal(c.layoutError, '');
  assert.equal(c.state, 'previewing');
  assert.deepEqual(h.windows().map(window => window.monitor), ['A', 'A', 'A', 'A']);
  assert.deepEqual(c.workspaceMap.outputs, ['A']);
});

test('a Mirror role swap changes the source before migrating workspaces', () => {
  const h = harness(), c = h.c;
  c.setModeValue('mirror', ''); h.drain();
  c.keepPreview(); h.drain();
  assert.equal(c.state, 'idle');
  assert.deepEqual(c.workspaceMap.outputs, ['A']);

  h.monitorCalls.length = 0;
  h.order.length = 0;
  assert.equal(c.swapRole('B', 0), 'started');
  h.drain();

  const source = h.order.indexOf('monitor:B:on');
  const sink = h.order.indexOf('monitor:A:mirror');
  const migrated = h.order.findIndex(item => item.startsWith('workspace:') && item.endsWith(':B'));
  assert.ok(source !== -1 && sink !== -1 && migrated !== -1);
  assert.ok(source < sink, 'the new source is made independent before the old source mirrors it');
  assert.ok(source < migrated && migrated < sink, 'migrate after enabling the new source, before mirroring the old source');
  assert.deepEqual(c.workspaceMap.outputs, ['B']);
  assert.equal(c.layoutError, '');
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


test('an external reload cancels preview without restoring stale monitor intent', () => {
  const h = harness(), c = h.c;
  c.setModeValue('single', 'A'); h.drain();
  h.setMonitors(c.monitors.map(m => ({...m, disabled:m.name === 'A', mirrorOf:'none'})));
  h.monitorCalls.length = 0;
  h.event('configreloaded', '');
  h.drain('Display configuration reloaded; preview cancelled.');
  assert.equal(c.state, 'idle');
  assert.deepEqual(h.monitorCalls, []);
  assert.equal(c.config.singleTarget, 'B');
  assert.deepEqual(c.workspaceMap.outputs, ['B']);
});

for (const mode of ['extend', 'mirror'])
  test(`leaving a saved Single for ${mode} turns the other output back on`, () => {
    const h = harness(), c = h.c;
    c.setModeValue('single', 'A'); h.drain();
    c.keepPreview(); h.drain();
    h.live().find(m => m.name === 'B').disabled = true;
    c.monitors = copy(h.live()); c.syncDisplayDraft();
    assert.equal(c.displayDraft.find(d => d.name === 'B').enabled, false, 'the draft reads Single back as off');
    assert.equal(c.setModeValue(mode, ''), 'started');
    assert.equal(c.displayDraft.every(d => d.enabled), true);
    h.drain();
    assert.equal(h.live().find(m => m.name === 'B').disabled, false);
    assert.equal(c.previewApplied.options.enabled.length, 2);
  });

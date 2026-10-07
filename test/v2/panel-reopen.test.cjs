const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { runInNewContext } = require('node:vm');

const service = readFileSync(join(__dirname, '..', '..', 'Service.qml'), 'utf8');
const panel = readFileSync(join(__dirname, '..', '..', 'lib', 'StationPanel.qml'), 'utf8');

test('the open intent lives on the service, which outlives the widget', () => {
  assert.match(service, /property bool panelWanted: false/);
  assert.match(service, /property string panelScreenName: ""/);
  // The panel dies with the bar widget, so the intent is readable from the
  // IPC status instead of only from a live panel instance.
  assert.match(service, /panelWanted: root\.panelWanted/);
});

test('the panel records its open state and a rebuilt widget claims it back on the same output', () => {
  assert.match(panel, /service\.panelWanted = opened/);
  // The record can be made before the service binding resolves, so the
  // transition is held and replayed instead of dropped.
  assert.match(panel, /intentPending = true\n {6}flushIntent\(\)/);
  assert.match(panel, /if \(!service \|\| !intentPending\) return/);
  assert.match(panel, /if \(!service \|\| !service\.panelWanted\) return/);
  assert.match(panel, /if \(opened && currentScreenName\(\)\) service\.panelScreenName = currentScreenName\(\)/);
  assert.match(panel, /Qt\.callLater\([\s\S]*?if \(root\.tryRestorePanel\(\)\) return/);
  assert.match(panel, /interval: 30/);
  assert.match(panel, /attempts < 100/);
});

function panelFunction(name, context) {
  const start = panel.indexOf('  function ' + name + '(');
  assert.notEqual(start, -1, name + ' exists');
  const end = panel.indexOf('\n  }', start) + '\n  }'.length;
  assert.ok(end > start, name + ' has an end');
  return runInNewContext('(' + panel.slice(start, end).trim() + '\n)', context);
}

test('a rebuilt panel waits for its original output and falls back when that output is gone', () => {
  const serviceState = { panelWanted: true, panelScreenName: 'HDMI-A-2', panelTransferUntil: Date.now() + 3000 };
  const screens = [{ name: 'eDP-1' }, { name: 'HDMI-A-2' }];
  let opened = 0;
  let peers = [];
  const context = {
    service: serviceState,
    bar: { moduleWidgets: () => peers },
    Quickshell: { screens },
    currentScreenName: () => 'eDP-1',
    root: { opened: false, open: () => { opened++; } },
  };
  const restore = panelFunction('tryRestorePanel', context);
  assert.equal(restore(), false);
  assert.equal(opened, 0);
  context.currentScreenName = () => 'HDMI-A-2';
  peers = [{ opened: true }];
  assert.equal(restore(), false, 'an old copy can still be open while being replaced');
  peers = [];
  assert.equal(restore(), true);
  assert.equal(opened, 1);
  context.currentScreenName = () => 'eDP-1';
  screens.pop();
  assert.equal(restore(), true);
  assert.equal(opened, 2);
});

test('closing the panel cancels any pending reopen', () => {
  const handler = panel.match(/onOpenedChanged: \{([\s\S]*?)\n {2}\}/);
  assert.ok(handler, 'onOpenedChanged is a block handler');
  assert.match(handler[1], /flushIntent\(\)/);
  assert.match(handler[1], /reopenTimer\.stop\(\)/);
  const flusher = panel.match(/function flushIntent\(\) \{([\s\S]*?)\n {2}\}/);
  assert.ok(flusher, 'flushIntent is defined');
  assert.match(flusher[1], /service\.panelWanted = opened/);
  assert.match(flusher[1], /if \(!opened\) service\.rememberedTab = 0/);
  assert.match(panel, /function close\(\) \{\n {4}if \(service\) service\.panelTransferUntil = 0/);
});

test('a popout switch hands the intent to the copy that took over', () => {
  const settle = panel.match(/function settlePopoutSwitch\(svc, barRef\) \{([\s\S]*?)\n {2}\}/);
  assert.ok(settle, 'settlePopoutSwitch is defined');
  // Any live copy still showing means the panel is up and the switch was a
  // hand-off (a rebuild replacing us), not a dismissal.
  assert.match(settle[1], /moduleWidgets\("yakumy\.station"\)/);
  assert.match(settle[1], /widgets\[i\]\.opened === true/);
  assert.match(settle[1], /if \(up\) svc\.panelWanted = true/);
  assert.match(settle[1], /barRef\.activePopout\.foreign === true/);
  assert.match(settle[1], /Date\.now\(\) >= svc\.panelTransferUntil/);
  assert.match(settle[1], /svc\.rememberedTab = 0/);

  const handler = panel.match(/onOpenedChanged: \{([\s\S]*?)\n {2}\}/);
  assert.ok(handler, 'onOpenedChanged is a block handler');
  // The bar has not published the new owner from inside the close, so the
  // decision waits for the switch to finish.
  assert.match(handler[1], /else if \(popoutSwitchClosing\)/);
  assert.match(handler[1], /Qt\.callLater\(function\(\) \{ settle\(svc, barRef\) \}\)/);
  // A real close still records immediately.
  assert.match(handler[1], /else if \(!service \|\| Date\.now\(\) >= service\.panelTransferUntil\) \{\n {6}intentPending = true/);
});

test('a real switch to another popup still dismisses Station during a transfer window', () => {
  const settle = panelFunction('settlePopoutSwitch', {});
  const state = { panelWanted: true, rememberedTab: 2, panelTransferUntil: Date.now() + 3000 };
  const bar = { moduleWidgets: () => [], activePopout: { foreign: true } };
  settle(state, bar);
  assert.equal(state.panelWanted, false);
  assert.equal(state.rememberedTab, 0);
  state.panelWanted = true;
  state.rememberedTab = 2;
  bar.activePopout = null;
  settle(state, bar);
  assert.equal(state.panelWanted, true);
  assert.equal(state.rememberedTab, 2);
});

test('display hotplug does not summon a panel the user closed', () => {
  assert.doesNotMatch(service, /updateAssignments\(\); applyRuntime\(\); openPanel\(\)/);
});

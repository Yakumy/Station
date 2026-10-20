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
  assert.match(service, /property string rememberedDisplayName: ""/);
  // The panel dies with the bar widget, so the intent is readable from the
  // IPC status instead of only from a live panel instance.
  assert.match(service, /panelWanted: root\.panelWanted/);
});

test('the selected connector survives a panel rebuild and a temporary draft gap', () => {
  const binding = panel.match(/readonly property string selectedDisplayName: \{([\s\S]*?)\n  \}/);
  assert.ok(binding, 'selected connector is a service-backed binding');
  const state = { rememberedDisplayName: 'HDMI-A-2', displayDraft: [
    { name: 'eDP-1' }, { name: 'HDMI-A-2' },
  ] };
  const context = { service: state };
  const selected = runInNewContext('(function selectedDisplayName() {' + binding[1] + '\n})', context);
  assert.equal(selected(), 'HDMI-A-2');
  state.displayDraft = [{ name: 'eDP-1' }];
  assert.equal(selected(), 'eDP-1', 'inspector has a valid temporary fallback');
  assert.equal(state.rememberedDisplayName, 'HDMI-A-2', 'fallback must not discard the choice');
  state.displayDraft = [{ name: 'eDP-1' }, { name: 'HDMI-A-2' }];
  assert.equal(selected(), 'HDMI-A-2');
  assert.match(panel, /service\.setRememberedDisplayName\(name\)/);
  assert.doesNotMatch(panel, /\n {4}selectedDisplayName = name/);
});

test('the panel records its open state and a rebuilt widget claims it back on the same output', () => {
  assert.match(panel, /service\.setPanelWanted\(opened\)/);
  // The record can be made before the service binding resolves, so the
  // transition is held and replayed instead of dropped.
  assert.match(panel, /intentPending = true\n {6}flushIntent\(\)/);
  assert.match(panel, /if \(!service \|\| !intentPending\) return/);
  assert.match(panel, /if \(!service \|\| !service\.panelWanted\) return/);
  assert.match(panel, /if \(opened && currentScreenName\(\)\) service\.setPanelScreenName\(currentScreenName\(\)\)/);
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
  assert.match(flusher[1], /service\.setPanelWanted\(opened\)/);
  assert.match(flusher[1], /if \(!opened\) service\.setRememberedTab\(0\)/);
  assert.match(panel, /function close\(\) \{\n {4}if \(service\) \{\n {6}service\.setPanelTransferUntil\(0\)/);
});

test('the surviving widget accepts a transfer while the removed output still has an open copy', () => {
  let opened = 0;
  const context = {
    service: { panelWanted: true, panelScreenName: 'eDP-1', panelTransferUntil: Date.now() + 3000 },
    bar: { moduleWidgets: () => [{ opened: true, currentScreenName: () => 'HDMI-A-2' }] },
    Quickshell: { screens: [{ name: 'eDP-1' }, { name: 'HDMI-A-2' }] },
    currentScreenName: () => 'eDP-1',
    root: { opened: false, open() { opened++; } },
  };
  assert.equal(panelFunction('tryRestorePanel', context)(), true);
  assert.equal(opened, 1);
  assert.match(panel, /function onPanelScreenNameChanged\(\)/);
  assert.match(panel, /function onPanelTransferUntilChanged\(\)/);
});

test('a monitor removal closes and acknowledges the old output before reopening elsewhere', () => {
  assert.match(service, /function requestPanelEvacuation\(from, to, purpose\)/);
  assert.match(service, /panelEvacuationWaiting = panelEvacuationSerial \+ 1/);
  assert.match(service, /panelEvacuationSerial = panelEvacuationWaiting/);
  assert.match(service, /evalLua\(Hypr\.focusMonitor\(focusTarget\)/);
  assert.ok(service.indexOf('root.panelScreenName = target') > service.indexOf('root.evalLua(lua'),
    'the destination panel is not reopened until the monitor rule succeeds');
  assert.match(panel, /function closeForMonitorTransfer\(serial, screenName\)/);
  assert.match(panel, /popoutSwitchClosing = true\n {4}controller\.hide\(\)/);
  assert.match(panel, /interval: 180/);
  assert.match(panel, /svc\.acknowledgePanelEvacuation\(serial, screenName\)/);
  const handler = panel.match(/onOpenedChanged: \{([\s\S]*?)\n {2}\}/);
  assert.match(handler[1], /else if \(monitorTransferClosing\)/,
    'the safety close must not be recorded as a user dismissal');
});

test('Revert uses the same safe close when the saved Single target differs', () => {
  assert.match(service, /pendingRevertPanelTarget = panelWanted \? panelTransferTarget\(config\) : ""/);
  assert.match(service, /requestPanelEvacuation\(origin, pendingRevertPanelTarget, "revert"\)/);
  assert.match(service, /if \(purpose === "revert"\) continueRevertPreview\(\)/);
});

test('a popout switch hands the intent to the copy that took over', () => {
  const settle = panel.match(/function settlePopoutSwitch\(svc, api, barRef, transferUntil\) \{([\s\S]*?)\n {2}\}/);
  assert.ok(settle, 'settlePopoutSwitch is defined');
  // Any live copy still showing means the panel is up and the switch was a
  // hand-off (a rebuild replacing us), not a dismissal.
  assert.match(settle[1], /moduleWidgets\("yakumy\.station"\)/);
  assert.match(settle[1], /widgets\[i\]\.opened === true/);
  assert.match(settle[1], /setWanted\(true\)/);
  assert.match(settle[1], /barRef\.activePopout\.foreign === true/);
  assert.match(settle[1], /Date\.now\(\) >= transferUntil/);
  assert.match(settle[1], /setTab\(0\)/);

  const handler = panel.match(/onOpenedChanged: \{([\s\S]*?)\n {2}\}/);
  assert.ok(handler, 'onOpenedChanged is a block handler');
  // The bar has not published the new owner from inside the close, so the
  // decision waits for the switch to finish.
  assert.match(handler[1], /else if \(popoutSwitchClosing\)/);
  assert.match(handler[1], /Qt\.callLater\(function\(\) \{ settle\(svc, api, barRef, transferUntil\) \}\)/);
  // A real close still records immediately.
  assert.match(handler[1], /else if \(!service \|\| Date\.now\(\) >= service\.panelTransferUntil\) \{\n {6}intentPending = true/);
});

test('a real switch to another popup still dismisses Station during a transfer window', () => {
  const settle = panelFunction('settlePopoutSwitch', {});
  const state = { panelWanted: true, rememberedTab: 2, panelTransferUntil: Date.now() + 3000 };
  state.setPanelWanted = value => { state.panelWanted = value; };
  state.setRememberedTab = value => { state.rememberedTab = value; };
  const bar = { moduleWidgets: () => [], activePopout: { foreign: true } };
  settle(state, null, bar, state.panelTransferUntil);
  assert.equal(state.panelWanted, false);
  assert.equal(state.rememberedTab, 0);
  state.panelWanted = true;
  state.rememberedTab = 2;
  bar.activePopout = null;
  settle(state, null, bar, state.panelTransferUntil);
  assert.equal(state.panelWanted, true);
  assert.equal(state.rememberedTab, 2);
});

test('display hotplug does not summon a panel the user closed', () => {
  assert.doesNotMatch(service, /updateAssignments\(\); applyRuntime\(\); openPanel\(\)/);
});

test('hiding either stock bar widget preserves an open panel through the rebuild', () => {
  const setter = service.match(/function setSetting\(name, value\) \{([\s\S]*?)\n {2}\}/);
  assert.ok(setter, 'setSetting is defined');
  assert.match(setter[1], /name === "hideNative"[\s\S]*?panelTransferUntil = Date\.now\(\) \+ 3000/);
  assert.match(setter[1], /name === "hideDisplay"[\s\S]*?panelTransferUntil = Date\.now\(\) \+ 3000/);
});

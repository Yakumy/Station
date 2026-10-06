const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const service = readFileSync(join(__dirname, '..', '..', 'Service.qml'), 'utf8');
const panel = readFileSync(join(__dirname, '..', '..', 'lib', 'StationPanel.qml'), 'utf8');

test('the open intent lives on the service, which outlives the widget', () => {
  assert.match(service, /property bool panelWanted: false/);
  // The panel dies with the bar widget, so the intent is readable from the
  // IPC status instead of only from a live panel instance.
  assert.match(service, /panelWanted: root\.panelWanted/);
});

test('the panel records its open state and a rebuilt widget claims it back', () => {
  assert.match(panel, /service\.panelWanted = opened/);
  // The record can be made before the service binding resolves, so the
  // transition is held and replayed instead of dropped.
  assert.match(panel, /intentPending = true\n {6}flushIntent\(\)/);
  assert.match(panel, /if \(!service \|\| !intentPending\) return/);
  assert.match(panel, /if \(!service \|\| !service\.panelWanted\) return/);
  assert.match(panel, /service\.openPanel\(\) === "true"/);
  // The first ask runs as soon as construction clears, before the retry.
  assert.match(panel, /Qt\.callLater\([\s\S]*?if \(root\.service\.openPanel\(\) === "true"\) return/);
  // summon answers false until the bar registers the slot, so asking once
  // from a just-created widget would lose the panel.
  assert.match(panel, /interval: 30/);
  assert.match(panel, /attempts < 20/);
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
});

test('a popout switch hands the intent to the copy that took over', () => {
  const settle = panel.match(/function settlePopoutSwitch\(svc, barRef\) \{([\s\S]*?)\n {2}\}/);
  assert.ok(settle, 'settlePopoutSwitch is defined');
  // Any live copy still showing means the panel is up and the switch was a
  // hand-off (a rebuild replacing us), not a dismissal.
  assert.match(settle[1], /moduleWidgets\("yakumy\.station"\)/);
  assert.match(settle[1], /widgets\[i\]\.opened === true/);
  assert.match(settle[1], /svc\.panelWanted = up/);
  assert.match(settle[1], /if \(!up\) svc\.rememberedTab = 0/);

  const handler = panel.match(/onOpenedChanged: \{([\s\S]*?)\n {2}\}/);
  assert.ok(handler, 'onOpenedChanged is a block handler');
  // The bar has not published the new owner from inside the close, so the
  // decision waits for the switch to finish.
  assert.match(handler[1], /else if \(popoutSwitchClosing\)/);
  assert.match(handler[1], /Qt\.callLater\(function\(\) \{ settle\(svc, barRef\) \}\)/);
  // A real close still records immediately.
  assert.match(handler[1], /else \{\n {6}intentPending = true/);
});

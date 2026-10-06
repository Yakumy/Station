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
  assert.match(handler[1], /service\.panelWanted = opened/);
  assert.match(handler[1], /reopenTimer\.stop\(\)/);
});

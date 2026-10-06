const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');

const read = (...parts) => readFileSync(join(__dirname, '..', '..', ...parts), 'utf8');
const service = read('Service.qml');
const layout = read('lib', 'DisplayLayout.qml');
const tab = read('lib', 'DisplaysTab.qml');
const panel = read('lib', 'StationPanel.qml');

test('the draft stays editable while a preview is pending', () => {
  assert.match(service, /readonly property bool draftEditable: state === "idle" \|\| state === "previewing"/);
  assert.match(service, /function setDisplayPosition\(name, x, y\) \{\n {4}if \(!draftEditable/);
  assert.match(service, /function previewLayout\(\) \{\n {4}if \(!draftEditable\) return "busy"/);
});

test('a re-edit joins the running session instead of restarting its baseline', () => {
  const body = service.match(/function previewLayout\(\) \{([\s\S]*?)\n {2}\}/);
  assert.ok(body, 'previewLayout is defined');
  // Revert has to mean "back to the layout this session started from", so a
  // second preview must not recapture monitors that already moved.
  assert.match(body[1], /if \(state !== "previewing"\) previewBefore = monitors\.slice\(\)/);
  assert.doesNotMatch(body[1], /\n {6}previewBefore = monitors\.slice\(\)/);
  assert.match(body[1], /begin\("previewing"\)/);
  assert.match(body[1], /previewArm\.running = true/);
});

test('settling a preview still requires one, and unrelated work stays gated on idle', () => {
  assert.match(service, /function revertPreview\(reason\) \{\n {4}if \(state !== "previewing"\)/);
  assert.match(service, /function keepPreview\(\) \{\n {4}if \(state !== "previewing"/);
  assert.match(service, /function removeStationBlock\(\) \{\n {4}if \(state !== "idle"\) return "busy"/);
});

test('every draft control reads the same editable flag', () => {
  assert.match(layout, /if \(!service \|\| !service\.draftEditable\) return/);
  assert.match(layout, /enabled: canvas\.service && canvas\.service\.draftEditable/);
  assert.equal((layout.match(/service\.state !== "idle"/g) || []).length, 0);
  assert.equal((tab.match(/service\.state !== "idle"/g) || []).length, 0);
  assert.equal((tab.match(/!displayTab\.service\.draftEditable/g) || []).length, 5);
  assert.match(panel, /if \(!service \|\| !service\.draftEditable\) return/);
});

test('the panel remembers its tab across a bar rebuild but not across a close', () => {
  assert.match(service, /property int rememberedTab: 0/);
  assert.match(panel, /onSelectedTabChanged: if \(service\) service\.rememberedTab = selectedTab/);
  assert.match(panel, /if \(!opened\) service\.rememberedTab = 0/);
  assert.match(panel, /service\.rememberedTab/);
});

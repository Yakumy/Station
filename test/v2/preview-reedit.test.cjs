const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { runInNewContext } = require('node:vm');
const Model = require('../../lib/Model.js');
const MonitorsLua = require('../../lib/MonitorsLua.js');

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
  assert.match(body[1], /if \(state !== "previewing"\) \{ previewBefore = monitors\.slice\(\); previewApplied = null \}/);
  assert.doesNotMatch(body[1], /\n {6}previewBefore = monitors\.slice\(\)/);
  assert.match(body[1], /begin\("previewing"\)/);
  assert.match(body[1], /previewArm\.running = true/);
});

test('successive position previews reconfigure only the output being moved', () => {
  const before = [
    { name: 'eDP-1', width: 1920, height: 1080, refreshRate: 60, availableModes: ['1920x1080@60.00Hz'], x: 0, y: 0, scale: 1, transform: 0 },
    { name: 'HDMI-A-2', width: 1920, height: 1200, refreshRate: 59.88, availableModes: ['1920x1200@59.88Hz'], x: 1920, y: 0, scale: 1, transform: 0 },
  ];
  const draft = before.map((monitor, index) => ({ ...monitor, mode: monitor.availableModes[0], enabled: true, lane: index + 1 }));
  const calls = [];
  const context = {
    Model, MonitorsLua,
    Quickshell: { execDetached() {} }, Transactions: { watchdog: '' },
    state: 'previewing', stateDir: '/tmp/station-preview-test',
    config: { mode: 'extend', enabled: ['eDP-1', 'HDMI-A-2'] },
    previewBefore: before, previewApplied: null, draftMode: 'extend', draftSingleTarget: '',
    displayDraft: draft, previewCountdown: { restart() {} },
    evalLua(lua) { calls.push(lua); },
  };
  const body = service.match(/  function applyPreview\(\) \{([\s\S]*?)\n  \}/);
  assert.ok(body);
  const apply = runInNewContext('(function applyPreview() {' + body[1] + '\n})', context);
  draft[1].x = 2400;
  context.pendingDisplayConfig = MonitorsLua.generate(draft, { mode: 'extend', enabled: context.config.enabled });
  apply();
  assert.equal((calls[0].match(/hl\.monitor/g) || []).length, 1);
  assert.match(calls[0], /output = "HDMI-A-2"/);
  draft[1].x = 2600;
  context.pendingDisplayConfig = MonitorsLua.generate(draft, { mode: 'extend', enabled: context.config.enabled });
  apply();
  assert.equal((calls[1].match(/hl\.monitor/g) || []).length, 1);
  assert.match(calls[1], /position = "2600x0"/);
  draft[1].scale = 2;
  context.pendingDisplayConfig = MonitorsLua.generate(draft, { mode: 'extend', enabled: context.config.enabled });
  apply();
  assert.ok((calls[2].match(/hl\.monitor/g) || []).length >= 2, 'scale changes keep the full guarded transaction');
});

test('settling a preview still requires one, and unrelated work stays gated on idle', () => {
  assert.match(service, /function revertPreview\(reason\) \{\n {4}if \(state !== "previewing"\)/);
  assert.match(service, /function keepPreview\(\) \{\n {4}if \(state !== "previewing"/);
  assert.match(service, /function removeStationBlock\(\) \{\n {4}if \(state !== "idle"\) return "busy"/);
});

test('every draft control reads the same editable flag', () => {
  assert.match(layout, /if \(!service \|\| !service\.draftEditable\) return/);
  assert.match(layout, /enabled: canvas\.service && canvas\.service\.draftEditable/);
  // Role swaps migrate windows and are intentionally gated on idle; card
  // position and rotation previews still use draftEditable.
  assert.equal((layout.match(/service\.state !== "idle"/g) || []).length, 1);
  assert.equal((tab.match(/service\.state !== "idle"/g) || []).length, 0);
  assert.match(tab, /if \(!service \|\| !selectedDisplay \|\| !service\.draftEditable\) return/);
  assert.match(panel, /if \(!service \|\| !service\.draftEditable\) return/);
});

test('the panel remembers its tab across a bar rebuild but not across a close', () => {
  assert.match(service, /property int rememberedTab: 0/);
  assert.match(panel, /onSelectedTabChanged: if \(service\) service\.rememberedTab = selectedTab/);
  assert.match(panel, /if \(!opened\) service\.rememberedTab = 0/);
  assert.match(panel, /service\.rememberedTab/);
});

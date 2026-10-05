const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');

const read = name => readFileSync(name, 'utf8');

test('panel follows the fixed, non-scrollable reference structure', () => {
  const panel = read('lib/StationPanel.qml');
  const displays = read('lib/DisplaysTab.qml');
  const bindings = read('lib/KeybindingsTab.qml');
  const settings = read('lib/SettingsTab.qml');
  const runtime = [panel, displays, bindings, settings].join('\n');

  assert.doesNotMatch(runtime, /\b(?:ScrollView|Flickable|ListView)\s*\{/);
  assert.match(panel, /Mode: Extend/);
  assert.match(panel, /Direction: LTR/);
  assert.match(displays, /id: leftColumn/);
  assert.match(displays, /id: rightColumn/);
  assert.match(displays, /Station\.DisplayLayout/);
  assert.match(displays, /Ui\.PanelSlider/);
  assert.match(bindings, /bindingGroups/);
  assert.match(settings, /Installed version/);
});

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
  assert.match(displays, /text: "MODE"/);
  assert.match(displays, /text: "DIRECTION"/);
  assert.match(displays, /modeLabelMeasure\.implicitWidth \+ displayTab\.dropdownTrim/);
  assert.match(displays, /directionLabelMeasure\.implicitWidth \+ displayTab\.dropdownTrim/);
  assert.match(displays, /id: leftColumn/);
  assert.match(displays, /id: rightColumn/);
  assert.match(displays, /Station\.DisplayLayout/);
  assert.match(displays, /Ui\.PanelSlider/);
  assert.match(bindings, /bindingGroups/);
  assert.match(settings, /Installed version/);
});

test('scale stays one row of six and the panel reserves room for it', () => {
  const panel = read('lib/StationPanel.qml');
  const displays = read('lib/DisplaysTab.qml');

  // Ui.ButtonGroup never wraps or clips: six chips need ~262px, so the panel
  // must reserve the width that keeps them inside the card. Below that width
  // the 4x chip painted past the panel's right edge.
  assert.match(displays, /id: scaleGroup/);
  assert.match(displays, /\[1, 1\.25, 1\.6, 2, 3, 4\]/);
  const width = panel.match(/fittedContentWidth\(Style\.space\((\d+)\)\)/);
  assert.ok(width, 'panel width is a Style.space request');
  assert.ok(Number(width[1]) >= 920,
    `panel requests ${width[1]} theme units; six scale chips need at least 920`);
});

test('popout owner closes through root, never through the KeyboardPanel id', () => {
  const panel = read('lib/StationPanel.qml');
  const owner = panel.match(/QtObject\s*\{\s*id: popoutOwner([\s\S]*?)\n {2}\}/);
  assert.ok(owner, 'popoutOwner QtObject is present');

  // KeyboardPanel.close() forwards to owner.close(), so this object is on the
  // outside-click and Escape dismissal path. It must reach root.close()
  // directly: `id: panel` belongs to the KeyboardPanel, and that name wins
  // over a local property, so referring to `panel.close()` here recurses into
  // KeyboardPanel.close() until the stack blows and dismissal silently dies.
  assert.match(owner[1], /function close\(\)\s*\{\s*root\.close\(\)\s*\}/);
  assert.match(owner[1], /function closeForPopoutSwitch\(\)\s*\{\s*root\.closeForPopoutSwitch\(\)\s*\}/);
  assert.doesNotMatch(owner[1], /\bpanel\b/);

  // Escape and Tab must stay wired to the panel lifecycle.
  assert.match(panel, /onCloseRequested:\s*root\.close\(\)/);
  assert.match(panel, /focusTarget:\s*keyCatcher/);
});

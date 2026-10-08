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
  assert.match(panel, /prefix: "Mode: "/);
  assert.match(panel, /prefix: "Direction: "/);
  assert.match(displays, /id: leftColumn/);
  assert.match(displays, /id: rightColumn/);
  assert.match(displays, /Station\.DisplayLayout/);
  assert.equal((displays.match(/Ui\.PanelSlider\s*\{/g) || []).length, 5);
  assert.match(displays, /text: "DRAG TO ARRANGE"/);
  assert.match(displays, /"Selected: " \+ displayTab\.selectedDisplay\.name/);
  assert.match(displays, /text: "RESOLUTION"/);
  assert.match(displays, /text: "REFRESH RATE"/);
  assert.match(bindings, /bindingGroups/);
  assert.match(settings, /label: "Hide Omarchy's Display icon"/);
  assert.match(settings, /setSetting\("hideDisplay", !checked\)/);
  assert.match(settings, /Installed version/);
});

test('larger panel reserves the reference canvas and discrete slider stops', () => {
  const panel = read('lib/StationPanel.qml');
  const displays = read('lib/DisplaysTab.qml');

  assert.match(displays, /scaleOptions: \[1, 1\.25, 1\.6, 2, 3, 4\]/);
  assert.match(displays, /resolutionOptions\.length/);
  assert.match(displays, /refreshOptions\.length/);
  const width = panel.match(/fittedContentWidth\(Style\.space\((\d+)\)\)/);
  assert.ok(width, 'panel width is a Style.space request');
  assert.ok(Number(width[1]) >= 996, `panel requests ${width[1]} theme units`);
});

test('bar logo shares the Omarchy menu foreground and size token', () => {
  const panel = read('lib/StationPanel.qml');
  const mark = read('assets/station.svg');

  assert.match(panel, /stationLogoSize:\s*Style\.font\.body \+ Style\.space\(1\)/);
  assert.match(panel, /tint:\s*logoButton\.foreground/);
  assert.match(panel, /id:\s*stationButton[\s\S]*?transform:\s*Translate\s*\{\s*y:\s*Style\.space\(1\)\s*\}/);
  assert.doesNotMatch(panel, /readonly property color barFg/);
  // MultiEffect colorization multiplies the requested tint by source
  // luminance. A white source makes the SVG a pure alpha mask, so a fully
  // covered pixel is exactly the WidgetButton foreground instead of dimmer.
  assert.match(mark, /stroke="white"/);
  assert.match(mark, /stroke-width="54"/);
  assert.doesNotMatch(mark, /(?:stroke-)?opacity=/);
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

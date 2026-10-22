const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');

const read = name => readFileSync(name, 'utf8');

test('panel follows the fixed, non-scrollable reference structure', () => {
  const panel = read('lib/StationPanel.qml');
  const displays = read('lib/DisplaysTab.qml');
  const bindings = read('lib/KeybindingsTab.qml');
  const settings = read('lib/SettingsTab.qml');
  const wallpaper = read('lib/WallpaperTab.qml');
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
  assert.match(displays, /service\.applyDisplaySetting\(selectedDisplay\.name, key, value\)/);
  assert.doesNotMatch(displays, /service\.previewLayout\(\)/);
  assert.match(bindings, /bindingGroups/);
  assert.match(settings, /label: "Hide Omarchy's Display icon"/);
  assert.match(settings, /displayWidgetEnabled === false/);
  assert.match(settings, /setSetting\("hideDisplay", !checked\)/);
  assert.match(settings, /Installed version/);
  assert.match(wallpaper, /height: Style\.space\(370\)/);
  assert.match(wallpaper, /text: "DRAG TO ARRANGE"/);
  assert.match(wallpaper, /id: controlFrame[\s\S]*?height: Style\.space\(370\)/);
  assert.match(wallpaper, /component ModeSelector: Ui\.BorderSurface/);
  assert.match(wallpaper, /value: "span", label: "Span"[\s\S]*?value: "individual", label: "Per monitor"[\s\S]*?value: "same", label: "Same on all"/);
  assert.equal((wallpaper.match(/height: controlFrame\.height \/ 5/g) || []).length, 5);
  assert.match(wallpaper, /id: imageRow[\s\S]*?prefix: "Monitor: "/);
  assert.doesNotMatch(wallpaper, /id: modeRow[\s\S]*?prefix: "Monitor: "[\s\S]*?id: imageRow/);
  assert.doesNotMatch(wallpaper, /prefix: "Mode: "/);
  assert.doesNotMatch(wallpaper, /Drag the monitor group|Updates with Omarchy theme|Keeps these images/);
  assert.doesNotMatch(wallpaper, /text: "(?:−|\+|Fit)"/);
  assert.match(wallpaper, /noticeError \? Color\.urgent : root\.panelRoot\.textDim/);
  assert.match(wallpaper, /if \(owner\.choose\(target\)\) root\.panelRoot\.close\(\)/);
});

test('display notices, labels, zoom buttons and settings switches share the intended alignment and size', () => {
  const displays = read('lib/DisplaysTab.qml');
  const layout = read('lib/DisplayLayout.qml');
  const settings = read('lib/SettingsTab.qml');

  assert.match(displays, /component ControlMessage: Text \{[\s\S]*?anchors\.left: parent\.left[\s\S]*?horizontalAlignment: Text\.AlignLeft/);
  assert.equal((displays.match(/ControlLabel \{\s*text: "(?:BRIGHTNESS|TEXT SIZE \(ALL DISPLAYS\)|SCALE|RESOLUTION|REFRESH RATE)"/g) || []).length, 5);
  assert.match(layout, /glyph: "-", factor: 1 \/ 1\.2 \}, \{ glyph: "\+", factor: 1\.2/);
  assert.match(settings, /component PlainToggleRow: Item \{/);
  assert.match(settings, /height: Style\.space\(48\)/);
  assert.match(settings, /Ui\.ToggleSwitch \{[\s\S]*?trackHeight: Style\.spacing\.controlHeight[\s\S]*?interactive: false/);
  assert.doesNotMatch(settings, /Ui\.Toggle\s*\{/);
});

test('larger panel reserves the reference canvas and discrete slider stops', () => {
  const panel = read('lib/StationPanel.qml');
  const displays = read('lib/DisplaysTab.qml');

  assert.match(displays, /scaleOptions: \[1, 1\.25, 1\.6, 2, 3, 4\]/);
  assert.match(displays, /resolutionOptions\.length/);
  assert.match(displays, /refreshOptions\.length/);
  const width = panel.match(/desiredPanelWidth:\s*Style\.space\((\d+)\)/);
  assert.ok(width, 'panel width is a Style.space request');
  assert.ok(Number(width[1]) >= 996, `panel requests ${width[1]} theme units`);
  assert.match(panel, /fittedContentWidth\(root\.desiredPanelWidth\)/);
});

test('bar logo shares the Omarchy menu foreground and size token', () => {
  const panel = read('lib/StationPanel.qml');
  const bar = read('lib/StationBar.qml');
  const markComponent = read('lib/StationMark.qml');
  const mark = read('assets/station-main-logo-mask.svg');
  const master = read('assets/station-main-logo.svg');

  assert.match(panel, /Station\.StationBar/);
  assert.match(bar, /logoSize: menuInk\.height/);
  assert.match(markComponent, /assets\/station-main-logo-mask\.svg/);
  assert.match(bar, /tint:\s*logoButton\.foreground/);
  assert.doesNotMatch(panel, /readonly property color barFg/);
  // Keep the supplied green master for public artwork, but use its white
  // geometry twin at runtime. MultiEffect preserves source luminance, so only
  // the white mask can reproduce WidgetButton.foreground exactly.
  assert.match(master, /#A6B465/);
  assert.match(mark, /stroke="white"/);
  assert.match(mark, /stroke-width="35"/);
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

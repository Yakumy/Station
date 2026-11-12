const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');

const read = name => readFileSync(name, 'utf8');

test('panel keeps the reference layout inside a fixed viewport', () => {
  const panel = read('lib/panel/StationPanel.qml');
  const displays = read('lib/displays/DisplaysTab.qml');
  const bindings = read('lib/keybindings/KeybindingsTab.qml');
  const settings = read('lib/panel/SettingsTab.qml');
  const wallpaper = read('lib/wallpaper/WallpaperTab.qml');

  assert.doesNotMatch([displays, bindings, settings].join('\n'), /\b(?:ScrollView|Flickable|ListView)\s*\{/);
  assert.match(panel, /contentHeight: panel\.fittedContentHeight\(root\.desiredPanelHeight\)/);
  assert.doesNotMatch(panel, /content\.implicitHeight/);
  assert.match(panel, /ScrollView \{\s*id: tabScroll/);
  assert.match(panel, /height: Math\.max\(0, content\.height - y - \(previewStrip\.visible \? previewStrip\.height : 0\)\)/);
  assert.match(panel, /ScrollBar\.horizontal\.policy: ScrollBar\.AlwaysOff/);
  assert.doesNotMatch(panel, /prefix: "Mode: "/);
  assert.match(displays, /prefix: "Mode: "/);
  assert.doesNotMatch(panel, /prefix: "Direction: "/);
  assert.match(read('lib/stations/WorkspacesTab.qml'), /objectName: "stationsDirectionDropdown"/);
  assert.match(displays, /id: leftColumn/);
  assert.match(displays, /id: rightColumn/);
  assert.match(displays, /Displays\.DisplayLayout/);
  assert.equal((displays.match(/PanelUi\.ControlSlider\s*\{/g) || []).length, 5);
  assert.match(displays, /text: "DRAG TO ARRANGE"/);
  assert.match(displays, /"Selected: " \+ displayTab\.selectedDisplay\.name/);
  assert.match(displays, /text: "RESOLUTION"/);
  assert.match(displays, /text: "REFRESH RATE"/);
  assert.match(displays, /service\.applyDisplaySetting\(selectedDisplay\.name, key, value\)/);
  assert.doesNotMatch(displays, /service\.previewLayout\(\)/);
  assert.match(bindings, /bindingGroups/);
  assert.match(settings, /label: "Show Omarchy Display Icon"/);
  assert.match(settings, /label: "Show Omarchy default workspace indicator"[\s\S]*?!settingsTab\.service\.config\.hideNative[\s\S]*?workspaceWidgetEnabled !== false[\s\S]*?setSetting\("hideNative", checked\)/);
  assert.match(settings, /displayWidgetEnabled !== false/);
  assert.match(settings, /setSetting\("hideDisplay", checked\)/);
  assert.match(settings, /Installed version/);
  assert.match(wallpaper, /height: Style\.space\(370\)/);
  assert.match(wallpaper, /"DRAG TO ARRANGE" : "DRAG TO FRAME · SCROLL TO ZOOM"/);
  assert.match(wallpaper, /id: controlFrame[\s\S]*?height: Style\.space\(370\)/);
  assert.match(wallpaper, /objectName: "wallpaperModeDropdown"/);
  assert.match(wallpaper, /value: "span", label: "Span"[\s\S]*?value: "individual", label: "Per monitor"[\s\S]*?value: "same", label: "Same on all"/);
  assert.equal((wallpaper.match(/height: controlFrame\.height \/ 5/g) || []).length, 5);
  assert.match(wallpaper, /"Selected: " \+ root\.selectedDisplay\.name/);
  assert.doesNotMatch(wallpaper, /Use Omarchy wallpaper|Reset frame|InlineDropdown/);
  assert.doesNotMatch(wallpaper, /prefix: "Mode: "/);
  assert.doesNotMatch(wallpaper, /Drag the monitor group|Updates with Omarchy theme|Keeps these images/);
  assert.doesNotMatch(wallpaper, /text: "(?:−|\+|Fit)"/);
  assert.match(wallpaper, /noticeError \? Color\.urgent : root\.tokens\.textDim/);
  assert.match(wallpaper, /if \(owner\.choose\(target\)\) root\.dismiss\(\)/);
});

test('display notices, labels, zoom buttons and settings switches share the intended alignment and size', () => {
  const displays = read('lib/displays/DisplaysTab.qml');
  const layout = read('lib/displays/DisplayLayout.qml');
  const settings = read('lib/panel/SettingsTab.qml');

  assert.match(displays, /component ControlMessage: Text \{[\s\S]*?anchors\.left: parent\.left[\s\S]*?horizontalAlignment: Text\.AlignLeft/);
  assert.equal((displays.match(/ControlLabel \{\s*text: "(?:BRIGHTNESS|TEXT SIZE \(ALL DISPLAYS\)|SCALE|RESOLUTION|REFRESH RATE)"/g) || []).length, 5);
  assert.match(layout, /glyph: "-", factor: 1 \/ 1\.2 \}, \{ glyph: "\+", factor: 1\.2/);
  assert.match(settings, /component PlainToggleRow: Item \{/);
  assert.match(settings, /height: Style\.space\(48\)/);
  assert.match(settings, /PanelUi\.ToggleSwitch \{[\s\S]*?interactive: false/);
  assert.doesNotMatch(settings, /Ui\.Toggle\s*\{/);
});

test('monitor canvases use the compact spacing token except for continuous Span crops', () => {
  const display = read('lib/displays/DisplayLayout.qml');
  const bar = read('lib/bars/BarLayout.qml');
  const wallpaper = read('lib/wallpaper/WallpaperLayout.qml');

  assert.match(display, /monitorGap: Style\.spacing\.sm/);
  assert.match(bar, /monitorGap: Style\.spacing\.sm/);
  assert.match(wallpaper, /monitorGap: spanning \? 0 : Style\.spacing\.sm/);
});

test('larger panel reserves the reference canvas and discrete slider stops', () => {
  const panel = read('lib/panel/StationPanel.qml');
  const displays = read('lib/displays/DisplaysTab.qml');

  assert.match(displays, /scaleOptions: \[1, 1\.25, 1\.6, 2, 3, 4\]/);
  assert.match(displays, /resolutionOptions\.length/);
  assert.match(displays, /refreshOptions\.length/);
  const width = panel.match(/desiredPanelWidth:\s*Style\.space\((\d+)\)/);
  assert.ok(width, 'panel width is a Style.space request');
  assert.ok(Number(width[1]) >= 996, `panel requests ${width[1]} theme units`);
  assert.match(panel, /fittedContentWidth\(root\.desiredPanelWidth\)/);
});

test('bar logo shares the Omarchy menu foreground and size token', () => {
  const panel = read('lib/panel/StationPanel.qml');
  const bar = read('lib/bars/StationBar.qml');
  const markComponent = read('lib/panel/StationMark.qml');
  const mark = read('assets/station-main-logo-mask.svg');
  const master = read('assets/station-main-logo.svg');

  assert.match(panel, /Bars\.StationBar/);
  assert.match(bar, /logoSize: menuInk\.height/);
  assert.match(markComponent, /assets\/station-main-logo-mask\.svg/);
  assert.match(bar, /tint:\s*logoButton\.foreground/);
  assert.doesNotMatch(panel, /readonly property color barFg/);
  // The runtime vector keeps the artwork geometry and uses the theme tint directly.
  assert.match(markComponent, /Shape.CurveRenderer/);
  assert.doesNotMatch(markComponent, /MultiEffect|layer.enabled/);
  assert.match(master, /#A6B465/);
  assert.match(mark, /stroke="white"/);
  assert.match(mark, /stroke-width="35"/);
  assert.doesNotMatch(mark, /(?:stroke-)?opacity=/);
});

test('popout owner closes through root, never through the KeyboardPanel id', () => {
  const panel = read('lib/panel/StationPanel.qml');
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

test('the preview countdown shows on every tab that has none of its own', () => {
  const panel = read('lib/panel/StationPanel.qml');
  assert.match(panel, /PanelUi\.PreviewStrip \{[\s\S]*?service\.state === "previewing"\s*&& root\.selectedTab !== Tabs\.index\("displays"\)/);
  assert.match(panel, /service: displaysTabPort/);
  const strip = read('lib/panel/PreviewStrip.qml');
  assert.match(strip, /root\.service\.previewSeconds/);
  assert.match(strip, /root\.service\.keepPreview\(\)/);
  assert.match(strip, /root\.service\.revertPreview\(""\)/);
});

test('only Displays layout renders monitor names', () => {
  for (const path of ['lib/bars/BarLayout.qml', 'lib/windows/WindowsLayout.qml',
    'lib/stations/WorkspacesLayout.qml', 'lib/color/ColorLayout.qml', 'lib/wallpaper/WallpaperLayout.qml']) {
    assert.doesNotMatch(read(path), /objectName: "(?:workspaceMonitorName|monitorName)-/);
  }
});

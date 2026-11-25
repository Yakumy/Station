const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');

const read = name => readFileSync(name, 'utf8');
const dropdown = read('lib/panel/ControlDropdown.qml');

test('panel keeps the reference layout inside a fixed viewport', () => {
  const panel = read('lib/panel/StationPanel.qml');
  const displays = read('lib/displays/DisplaysTab.qml');
  const bindings = read('lib/keybindings/KeybindingsTab.qml');
  const settings = read('lib/panel/SettingsTab.qml');
  const workspaces = read('lib/stations/WorkspacesTab.qml');
  const wallpaper = read('lib/wallpaper/WallpaperTab.qml');

  assert.doesNotMatch([displays, bindings, settings].join('\n'), /\b(?:ScrollView|Flickable|ListView)\s*\{/);
  assert.match(panel, /featureGeometry\.stackedHeight/);
  assert.match(panel, /root\.portraitPanelHeight \+ \(root\.portraitDrawerOpen \? featureGeometry\.actionHeight : 0\)/);
  assert.match(panel, /ScrollView \{\s*id: tabScroll/);
  assert.match(panel, /height: Math\.max\(0, content\.height - y - \(previewStrip\.visible \? previewStrip\.height : 0\)\)/);
  assert.match(panel, /ScrollBar\.horizontal\.policy: ScrollBar\.AlwaysOff/);
  assert.match(read('lib/panel/TabRail.qml'), /Flickable \{\s*id: tabRail[\s\S]*?interactive: contentWidth > width/);
  assert.match(read('lib/panel/TabRail.qml'), /WheelHandler \{[\s\S]*?tabRail\.contentX = Math\.max/);
  assert.match(panel, /onTextKey: function\(text, modifiers\)[\s\S]*?text === "q"[\s\S]*?root\.close\(\)/);
  assert.doesNotMatch(panel, /component TabKey: Rectangle/);
  assert.doesNotMatch(panel, /Tabs\.validIndex\(index\)/);
  assert.match(panel, /value: tabScroll\.contentHeight > tabScroll\.height/);
  assert.match(panel, /visible: root\.portraitPanel\s*\n\s*width: parent\.width\s*\n\s*foreground: Commons\.Color\.popups\.text/);
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
  assert.match(workspaces, /readonly property int rowCount: 5/);
  assert.match(workspaces, /readonly property real frameHeight: geometry\.frameHeight/);
  assert.match(workspaces, /Flickable \{[\s\S]*?contentHeight: controlRows\.height/);
  // The frame uses the shared thumb; test/qml/scroll-thumb.py drives its behavior.
  assert.match(workspaces, /PanelUi\.ScrollThumb \{[\s\S]*?objectName: "controlScrollThumb"[\s\S]*?flickable: controlScroll[\s\S]*?color: Commons\.Color\.accent/);
  assert.doesNotMatch(workspaces, /target: controlScroll/);
  assert.match(workspaces, /function effective\(values\)[\s\S]*?Grid\.assigned\("repetitive", outputs, values\.workspaceLayout, values\.stationCount\)[\s\S]*?Grid\.assigned\("nonrepetitive", outputs, values\.workspaceLayout, values\.stationCount\)/);
  assert.match(wallpaper, /height: geometry\.frameHeight/);
  assert.match(wallpaper, /height: root\.narrow \? geometry\.separatorSlot : Style\.space\(428\)/);
  assert.match(wallpaper, /anchors\.horizontalCenter: parent\.horizontalCenter[\s\S]*?width: root\.narrow \? parent\.width[\s\S]*?height: root\.narrow \? Math\.max\(1, Style\.normalBorderWidth\) : parent\.height/);
  assert.match(wallpaper, /"DRAG TO ARRANGE" : "DRAG TO FRAME · SCROLL TO ZOOM"/);
  assert.match(wallpaper, /id: controlFrame[\s\S]*?height: geometry\.frameHeight/);
  assert.match(wallpaper, /objectName: "wallpaperModeDropdown"/);
  assert.match(wallpaper, /value: "span", label: "Span"[\s\S]*?value: "individual", label: "Per monitor"[\s\S]*?value: "same", label: "Same on all"/);
  assert.equal((wallpaper.match(/height: controlFrame\.height \/ 5/g) || []).length, 5);
  assert.match(wallpaper, /"Selected: " \+ root\.selectedDisplay\.name/);
  assert.doesNotMatch(wallpaper, /Use Omarchy wallpaper|Reset frame|InlineDropdown/);
  assert.doesNotMatch(wallpaper, /prefix: "Mode: "/);
  assert.doesNotMatch(wallpaper, /Drag the monitor group|Updates with Omarchy theme|Keeps these images/);
  assert.doesNotMatch(wallpaper, /text: "(?:−|\+|Fit)"/);
  assert.match(wallpaper, /noticeError \? Commons\.Color\.urgent : root\.tokens\.textDim/);
  assert.match(wallpaper, /if \(owner\.choose\(target\)\) root\.dismiss\(\)/);
});

test('display notices, labels, zoom buttons and settings switches share the intended alignment and size', () => {
  const displays = read('lib/displays/DisplaysTab.qml');
  const layout = read('lib/panel/MonitorCanvas.qml');
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
  const canvas = read('lib/panel/MonitorCanvas.qml');
  const wallpaper = read('lib/wallpaper/WallpaperLayout.qml');

  assert.match(canvas, /monitorGap: Style\.spacing\.sm/);
  for (const path of ['displays/DisplayLayout', 'bars/BarLayout', 'windows/WindowsLayout', 'stations/WorkspacesLayout', 'color/ColorLayout']) {
    const layout = read(`lib/${path}.qml`);
    assert.match(layout, /^PanelUi\.MonitorCanvas \{/m, path);
    assert.match(layout, /delegate: PanelUi\.MonitorCard \{/, path);
    assert.doesNotMatch(layout, /monitorGap:|property var bounds/, path);
  }
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
  assert.match(panel, /fittedContentWidth\(root\.portraitPanel \? root\.portraitPanelWidth : root\.desiredPanelWidth\)/);
  assert.match(panel, /portraitPanelWidth: Style\.space\(380\)/);
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

test('all six layouts render shared centered monitor names', () => {
  for (const path of ['lib/displays/DisplayLayout.qml', 'lib/bars/BarLayout.qml', 'lib/windows/WindowsLayout.qml',
    'lib/stations/WorkspacesLayout.qml', 'lib/color/ColorLayout.qml', 'lib/wallpaper/WallpaperLayout.qml']) {
    assert.match(read(path), /PanelUi\.MonitorName \{/);
  }
});

test('overflowing control menus use the shared grabbable scroll thumb', () => {
  assert.match(dropdown, /PanelUi\.ScrollThumb \{[\s\S]*?objectName: "dropdownScrollThumb"[\s\S]*?flickable: optionList[\s\S]*?color: root\.accent/);
  // Hovering the menu alone does not reveal it.
  assert.doesNotMatch(dropdown, /menuHover/);
});

test('the scroll thumb is a thin accent line on a grab strip inside an 80% track', () => {
  const thumb = read('lib/panel/ScrollThumb.qml');
  assert.match(thumb, /readonly property real track: flickable\.height \* 0\.8/);
  assert.match(thumb, /readonly property real trackTop: flickable\.y \+ flickable\.height \* 0\.1/);
  assert.match(thumb, /visible: flickable\.contentHeight > flickable\.height/);
  assert.match(thumb, /MouseArea \{[\s\S]*?hoverEnabled: true[\s\S]*?preventStealing: true/);
  assert.match(thumb, /readonly property bool shown: grab\.containsMouse \|\| grab\.pressed/);
  assert.match(thumb, /width: Style\.space\(1\)[\s\S]*?radius: Style\.cornerRadius[\s\S]*?opacity: root\.shown \? 0\.9 : 0/);
  assert.match(thumb, /property color color: Commons\.Color\.accent/);
});

test('overflowing lists hint that they scroll once per session per key', () => {
  const thumb = read('lib/panel/ScrollThumb.qml');
  const hint = read('lib/panel/ScrollHint.js');
  assert.match(hint, /^\.pragma library/);
  assert.match(thumb, /import "ScrollHint\.js" as ScrollHint/);
  assert.match(thumb, /property bool reduceMotion: Style\.reduceMotion/);
  assert.match(thumb, /if \(!onScreen \|\| reduceMotion \|\|[\s\S]*?ScrollHint\.claim\(hintKey\)/);
  assert.match(dropdown, /flickable: optionList\s+hintKey: "dropdown"/);
  assert.match(read('lib/stations/WorkspacesTab.qml'), /flickable: controlScroll\s+hintKey: "workspacesRows"/);
  // One library copy: only ScrollThumb imports it.
  for (const path of ['lib/panel/ControlDropdown.qml', 'lib/stations/WorkspacesTab.qml'])
    assert.doesNotMatch(read(path), /ScrollHint\.js/);
});

test('row controls share one whole-pixel inset that call sites keep', () => {
  // Rounded up and placed by x: centering rounds to a pixel and could pull a slider
  // left, so its hovered end knob crossed the row title at a small font size.
  const inset = 'readonly property real rowInset: Style.space(8) + Math.ceil((parent.width - Style.space(8) * 2) * 0.005)';
  for (const path of ['lib/panel/ControlSlider.qml', 'lib/panel/ControlDropdown.qml', 'lib/panel/ControlButton.qml']) {
    const source = read(path);
    assert.ok(source.includes(inset), path);
    assert.match(source, /x: rowInset\s+width: parent\.width - rowInset \* 2/, path);
    assert.doesNotMatch(source, /anchors\.centerIn/, path);
  }
  for (const path of ['lib/bars/BarTab.qml', 'lib/displays/DisplaysTab.qml', 'lib/windows/WindowsTab.qml', 'lib/color/ColorMatchTab.qml'])
    assert.doesNotMatch(read(path), /PanelUi\.Control(Slider|Dropdown|Button) \{[^}]*anchors\.centerIn/, path);
});

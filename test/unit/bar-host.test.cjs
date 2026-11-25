const test = require('node:test');
const { runtimeSource } = require('../helpers/runtime-source.cjs');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');

const read = name => readFileSync(name, 'utf8');
const { qmlFunction } = require('../helpers/bar-settings.cjs');
const service = runtimeSource();
const contract = read('lib/panel/ServiceContract.js');

test('4.0 manifest exposes the full bar alongside the widget and service', () => {
  const manifest = JSON.parse(read('manifest.json'));
  assert.equal(manifest.version, '4.5.2');
  assert.deepEqual(manifest.kinds, ['bar', 'bar-widget', 'service']);
  assert.equal(manifest.entryPoints.bar, 'Bar.qml');
});

test('full-bar entry reads live service bars before the shell.json mirror', () => {
  const fullBar = read('Bar.qml');
  assert.match(fullBar, /import "lib\/BarBridge\.js" as BarBridge/);
  assert.match(fullBar, /var live = stationBars/);
  assert.match(fullBar, /snapshot\.config\.bars/);
  assert.ok(fullBar.indexOf('var live = stationBars') < fullBar.indexOf('var rows = barConfig'));
});

test('bar tab is read-only for display geometry and exposes all requested controls', () => {
  const panel = read('lib/panel/StationPanel.qml');
  const tab = read('lib/bars/BarTab.qml');
  const layout = read('lib/bars/BarLayout.qml');
  const monitorCanvas = read('lib/panel/MonitorCanvas.qml');
  const wallpaperLayout = read('lib/wallpaper/WallpaperLayout.qml');
  const host = read('Bar.qml');
  const monitorBar = read('lib/bars/omarchy/MonitorBar.qml');
  const proxy = read('lib/panel/BarServiceProxy.qml');

  assert.match(read('lib/panel/TabRail.qml'), /model: Tabs\.labels\(\)/);
  assert.deepEqual(require('../../lib/panel/Tabs.js').labels(), ["Displays", "Workspaces", "Bar", "Windows", "Color Match", "Wallpaper", "Keybindings", "Settings"]);
  assert.match(tab, /"Selected: " \+ root\.selectedDisplay\.name/);
  assert.match(tab, /Bars\.BarLayout/);
  assert.doesNotMatch(tab, /component PositionSelector|text: "POSITION"/);
  assert.match(tab, /text: "CONTENT SIZE"/);
  assert.match(tab, /minimum: root\.selectedMinimumContentSize[\s\S]*?maximum: root\.selectedMaximumContentSize/);
  assert.match(tab, /setMonitorBarContentSize\(root\.selectedDisplay\.name, Math\.round\(value\)\)/);
  assert.match(tab, /"Maximum " \+ root\.selectedMaximumContentSize \+ " px — content needs more bar space\."/);
  assert.equal((tab.match(/height: controlFrame\.height \/ 5/g) || []).length, 5);
  assert.match(tab, /text: "WIDTH"/);
  assert.match(tab, /minimum: 1[\s\S]*?maximum: 100/);
  assert.match(tab, /setMonitorBarWidth\(root\.selectedDisplay\.name, Math\.round\(value\)\)/);
  assert.match(tab, /"Minimum " \+ root\.selectedMinimumWidth \+ "% — bar items overlap\."/);
  assert.match(tab, /text: "HEIGHT"/);
  assert.match(tab, /minimum: root\.selectedMinimumHeight[\s\S]*?maximum: root\.selectedMaximumHeight/);
  assert.match(tab, /setMonitorBarHeight\(root\.selectedDisplay\.name, Math\.round\(value\)\)/);
  assert.ok(tab.indexOf('id: contentSizeRow') < tab.indexOf('id: heightRow'));
  assert.ok(tab.indexOf('id: heightRow') < tab.indexOf('id: widthRow'));
  assert.match(tab, /text: "BACKGROUND"/);
  assert.match(tab, /PanelUi\.ControlDropdown[\s\S]*?value: "solid", label: "Solid color"[\s\S]*?value: "transparent", label: "Transparent"[\s\S]*?value: "blur", label: "Blur"/);
  assert.match(tab, /setMonitorBarBackground\(root\.selectedDisplay\.name, value\)/);
  assert.match(tab, /Binding \{[\s\S]*?target: backgroundDropdown[\s\S]*?property: "value"[\s\S]*?value: root\.selectedBar\.background/,
    'the host dropdown writes its own value, so an external Binding must keep it monitor-specific');
  assert.match(tab, /text: "STYLE"/);
  assert.match(tab, /value: "default", label: "Omarchy default"[\s\S]*?value: "pill", label: "Pill"/);
  assert.match(tab, /setMonitorBarStyle\(root\.selectedDisplay\.name, value\)/);
  assert.match(tab, /Binding \{[\s\S]*?target: styleDropdown[\s\S]*?property: "value"[\s\S]*?value: root\.selectedBar\.style/);
  assert.match(layout, /selectedDisplayName/);
  assert.match(layout, /displaySelected\(monitorCard\.modelData\.name\)/);
  assert.match(read('lib/panel/MonitorCard.qml'), /Color\.menu\.selectedBackground/);
  assert.match(layout, /Ui\.ToggleSwitch/);
  for (const side of ['top', 'right', 'bottom', 'left'])
    assert.match(layout, new RegExp('position: "' + side + '"'));
  for (const canvas of [monitorCanvas, wallpaperLayout]) {
    assert.match(canvas, /horizontalInset: width \* 0\.1/);
    assert.match(canvas, /verticalInset: Math\.max\(height \* 0\.1, Style\.font\.caption \+ Style\.spacing\.sm \* 2\)/);
  }
  const preview = layout.slice(layout.indexOf('id: barPreview'), layout.indexOf('\n      Text {', layout.indexOf('id: barPreview')));
  assert.doesNotMatch(preview, /anchors\.(?:left|right|top|bottom)/);
  assert.match(preview, /parent\.width - canvas\.barEdgeGap \* 2/);
  assert.match(preview, /parent\.height - topInset - bottomInset/);
  assert.match(preview, /position === "left" \? canvas\.barEdgeGap/);
  assert.match(preview, /parent\.height - height - bottomInset/);
  assert.doesNotMatch(layout, /objectName: "monitorName-/);
  assert.match(layout, /barEnabled\s*&&\s*monitorCard\.barSetting\.position/);
  assert.match(layout, /effectiveBarHeight \* canvas\.zoom/);
  assert.match(tab, /PanelSeparator[\s\S]*Style\.space\(64\)/);
  assert.match(read('lib/panel/PanelSession.qml'), /sessionTabRestored/);
  assert.doesNotMatch(layout, /setDisplayPosition|previewLayout|drag/i);
  assert.match(host, /Variants\s*\{[\s\S]*?model: Quickshell\.screens/);
  assert.match(host, /configuredEnabledCount\(\) > 0/);
  assert.match(host, /onPopoutRequested: root\.closePeerPopouts\(monitorBar\)/);
  assert.match(host, /onBackgroundModeRequested: function\(mode\) \{ root\.requestMonitorBackground\(monitorBar, mode\) \}/);
  assert.match(monitorBar, /function closeActivePopout\(\)/);
  assert.match(monitorBar, /onDoubleClicked:[\s\S]*?root\.cycleBackground\(\)/);
  assert.match(monitorBar, /backgroundMode === "blur" \? Util\.alpha\(Commons\.Color\.bar\.background, 0\.01\)/);
  assert.match(monitorBar, /barStyle === "pill"/);
  assert.match(monitorBar, /radius: Math\.min\(width, height\) \/ 2/);
  assert.match(monitorBar, /panelThickness: barSize \+ edgeInset/);
  assert.match(monitorBar, /edgeInset: barStyle === "pill" \|\| backgroundMode !== "transparent"\s+\? Math\.round\(Style\.space\(8\)\) : 0/);
  assert.doesNotMatch(monitorBar, /edgeCenterOffset|insetPresentation/);
  assert.match(monitorBar, /exclusionMode: root\.barHidden \? ExclusionMode\.Ignore : ExclusionMode\.Normal\s+exclusiveZone: thickness/);
  assert.match(monitorBar, /function thicknessFor\(screen\) \{\s+return root\.panelThickness/);
  assert.match(monitorBar, /pillOuterMargin: root\.edgeInset/);
  assert.match(monitorBar, /pillInset: 0/);
  assert.match(monitorBar, /pillOuterMargin \+ pillPadding : Style\.space\(8\)/);
  assert.match(monitorBar, /parent\.width - width - barContent\.edgeMargin/);
  assert.match(monitorBar, /parent\.height - height - barContent\.edgeMargin/);
  assert.match(monitorBar, /effectiveContentSize \/ defaultContentSize/);
  assert.match(monitorBar, /contentZoom: \(widgetSizedContent \? 1 : root\.contentScale\) \/ inheritedScale/);
  assert.equal((monitorBar.match(/scale: host\.contentZoom/g) || []).length, 3);
  assert.doesNotMatch(monitorBar, /layer\.enabled: host\.contentZoom/);
  assert.match(monitorBar, /item\.renderType = Text\.QtRendering/);
  assert.match(monitorBar, /transformOrigin: Item\.TopLeft/);
  assert.match(monitorBar, /baseContentWidth \* contentZoom/);
  assert.match(monitorBar, /baseContentHeight \* contentZoom/);
  assert.match(monitorBar, /function applyContentImageZoom\(\)/);
  assert.match(monitorBar, /item\.sourceSize\.width = Math\.max\(1, Math\.round\(baseline\.width \* zoom\)\)/);
  assert.match(monitorBar, /onBaseContentWidthChanged: scheduleContentImageZoom\(\)/);
  assert.match(monitorBar, /property real effectiveContentSize: root\.effectiveContentSize/);
  assert.doesNotMatch(monitorBar, /applyNativeContentSize|nativeSizeBaselines|baseline\.fontSize|item\.font\.pixelSize = customized/);
  assert.match(monitorBar, /maximumContentSize: measuredMaximumContentSize/);
  assert.match(monitorBar, /root\.measuredMaximumContentSize = maximumContentSize/);
  assert.match(host, /reportMonitorBarMaximumContent/);
  assert.match(contract, /monitorBarMaximumContents: service\.monitorBarMaximumContents/);
  assert.match(contract, /reportMonitorBarMaximumContent: function/);
  assert.match(contract, /monitorBarMaximumContent: function/);
  assert.match(proxy, /monitorBarMaximumContents/);
  assert.match(proxy, /function reportMonitorBarMaximumContent/);
  assert.match(proxy, /function monitorBarMaximumContent/);
  assert.match(read('lib/bars/StationBar.qml'), /font\.pixelSize: root\.contentFontSize/);
  assert.doesNotMatch(read('lib/panel/StationPanel.qml'), /nativeContentSized/);
  assert.equal((monitorBar.match(/model: root\.targetScreen \? \[root\.targetScreen\] : \[\]/g) || []).length, 3);
});

test('bar blur respects global compositor settings', () => {
  const scripts = [];
  let saves = 0;
  const context = {
    displays: [{ name: 'DP-1' }],
    config: { bars: { 'DP-1': {
      enabled: true, position: 'top', width: 100, height: 0, background: 'blur',
    } } },
    persisted: { barBlurLease: null },
    shell: null,
    barBlurSyncQueued: false,
    clearLegacyLease() { if (context.persisted.barBlurLease) { context.persisted.barBlurLease = null; context.saveState(); } },
    parseJson(raw, fallback) { try { return JSON.parse(raw); } catch { return fallback; } },
    saveState() { saves++; },
    evalLua(script) { scripts.push(script); },
    Hypr: require('../../lib/platform/Hypr.js'),
    Qt: { callLater(fn) { fn(); } },
  };
  context.barSettings = { monitorBar: name => context.config.bars[name] };
  context.monitorBar = qmlFunction(service, 'monitorBar', context);
  context.barBlurWanted = qmlFunction(service, 'barBlurWanted', context);
  const finishProbe = qmlFunction(service, 'finishBarBlurProbe', context);

  context.blurPasses = 3;
  context.forcedBlur = null;
  // Global blur is off and a bar wants it: turn it on, for this configuration only.
  finishProbe(0, '{"bool":false}\n{"int":8}\n{"int":1}');
  assert.equal(context.persisted.barBlurLease, null);
  assert.match(scripts.at(-1), /station_bar_blur_rule:set_enabled\(true\)/);
  assert.match(scripts.at(-1), /blur = \{ enabled = true, passes = 3 \}/);
  assert.match(scripts.at(-1), /no_blur = true/);
  assert.equal(context.forcedBlur.passes, 1);
  // Already on and held by Station: nothing to change.
  finishProbe(0, '{"bool":true}\n{"int":8}\n{"int":3}');
  assert.doesNotMatch(scripts.at(-1), /hl.config/);
  // The last Blur bar left: return exactly what was found.
  context.config.bars['DP-1'].background = 'solid';
  finishProbe(0, '{"bool":true}\n{"int":8}\n{"int":3}');
  assert.match(scripts.at(-1), /station_bar_blur_rule:set_enabled\(false\)/);
  assert.match(scripts.at(-1), /blur = \{ enabled = false, passes = 1 \}/);
  assert.match(scripts.at(-1), /station_window_no_blur_rule:set_enabled\(false\)/);
  assert.equal(context.forcedBlur, null);
  // Blur the user enabled themselves is left alone in both directions.
  finishProbe(0, '{"bool":true}\n{"int":4}\n{"int":2}');
  assert.doesNotMatch(scripts.at(-1), /hl.config/);
  context.config.bars['DP-1'].background = 'blur';
  finishProbe(0, '{"bool":true}\n{"int":4}\n{"int":2}');
  assert.doesNotMatch(scripts.at(-1), /hl.config|no_blur/);
  assert.equal(context.forcedBlur, null);
  assert.equal(saves, 0);
});


test('a monitor without a Station row shows the host bar background', () => {
  const BarModel = require('../../lib/bars/omarchy/BarModel.js');
  assert.equal(BarModel.hostBackground({ background: 'none' }), 'transparent');
  assert.equal(BarModel.hostBackground({ background: 'glassy' }), 'blur');
  assert.equal(BarModel.hostBackground({ background: 'opaque' }), 'solid');
  assert.equal(BarModel.hostBackground({ transparent: true }), 'transparent');
  assert.equal(BarModel.hostBackground({}), 'solid');
  assert.equal(BarModel.hostBackground(null), 'solid');

  const context = { config: { bars: {} }, shell: { barConfig: { bar: { position: 'left', background: 'none' } } } };
  const monitorBar = qmlFunction(service, 'monitorBar', context);
  assert.deepEqual(JSON.parse(JSON.stringify(monitorBar('DP-1'))), {
    enabled: true, position: 'left', width: 100, height: 0, background: 'transparent', style: 'default', contentSize: 0,
  });
  // A saved row is an explicit edit and wins over the host.
  context.config.bars['DP-1'] = { enabled: true, position: 'top', background: 'solid' };
  assert.equal(monitorBar('DP-1').background, 'solid');

  // Bar.qml renders the same fallback.
  const bar = read('Bar.qml');
  assert.match(bar, /import "lib\/bars\/omarchy\/BarModel\.js" as BarModel/);
  assert.match(bar, /\? entry\.background : BarModel\.hostBackground\(copy\)/);
});

// Omarchy 4.0.0.r7840 dropped the center-reveal properties from PluginBarApi. QML
// throws on an undeclared property, which used to skip the click-target sync.
test('plugin bar api binding skips properties the host api does not declare', () => {
  const source = read('lib/bars/omarchy/MonitorBar.qml');
  const declared = ['pluginId', 'foreground', 'barForeground', 'background', 'urgent', 'fontFamily',
    'position', 'vertical', 'barSize', 'transparent', 'foregroundAnimationEnabled',
    'activePopout', 'clickTargets', 'layoutConfig', 'foreignPopoutMarker'];
  const strictApi = names => new Proxy(Object.fromEntries(names.map(name => [name, null])), {
    has: (target, key) => key in target,
    set: (target, key, value) => {
      if (!(key in target)) throw new Error('Cannot assign to non-existent property "' + String(key) + '"');
      target[key] = value;
      return true;
    }
  });
  const root = { centerSectionRevealHeld: true, centerHoverRevealSuppressed: true, activePopout: null,
    pluginOwnsBarObject: () => false, pluginClickTargets: id => ['target:' + id],
    publicLayoutConfig: () => ({ right: [] }) };
  const context = { root, Qt: { binding: read => read() } };
  root.syncPluginBarApiObjects = qmlFunction(source, 'syncPluginBarApiObjects', context);
  const bind = qmlFunction(source, 'bindPluginBarApi', context);

  const current = strictApi(declared);
  current.pluginId = 'third.party';
  bind(current);
  assert.deepEqual(current.clickTargets, ['target:third.party']);

  const older = strictApi(declared.concat(['centerSectionRevealHeld', '_centerHoverRevealSuppressed']));
  older.pluginId = 'third.party';
  bind(older);
  assert.equal(older.centerSectionRevealHeld, true);
  assert.equal(older._centerHoverRevealSuppressed, true);
  assert.deepEqual(older.clickTargets, ['target:third.party']);
});

test('the full bar answers Omarchy panel hotkeys from the focused monitor', () => {
  const bar = read('Bar.qml');
  const monitor = (name, id) => ({ targetScreenName: name, targetScreen: {},
    panelWidgetIdAt: (region, index) => region + ':' + index + ':' + id });
  const context = { instances: [monitor('DP-1', 'a'), monitor('HDMI-A-2', 'b')],
    Hyprland: { focusedMonitor: { name: 'HDMI-A-2' } } };
  context.preferredInstance = qmlFunction(bar, 'preferredInstance', context);
  const panelWidgetIdAt = qmlFunction(bar, 'panelWidgetIdAt', context);
  assert.equal(panelWidgetIdAt('right', '2'), 'right:2:b');
  context.instances = [];
  assert.equal(panelWidgetIdAt('right', '1'), '');
});

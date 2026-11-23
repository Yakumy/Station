const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync, readdirSync } = require('node:fs');
const { join } = require('node:path');
const { strandsLayers } = require('../../lib/platform/HyprlandVersion.js');

const read = path => readFileSync(path, 'utf8');
function qmlFiles(dir) {
  return readdirSync(dir, { withFileTypes: true }).flatMap(entry => {
    const path = join(dir, entry.name);
    if (entry.isDirectory()) return qmlFiles(path);
    return entry.name.endsWith('.qml') ? [path] : [];
  });
}
const sources = ['Bar.qml', 'Panel.qml', 'Service.qml', ...qmlFiles('lib')];

// Omarchy removed Ui.ScreenMoveRemap (basecamp/omarchy#17229). A reference to the
// host's type makes the bar fall back to the stock bar and stops the service loading.
test('no surface depends on the host for ScreenMoveRemap', () => {
  for (const path of sources) {
    const uses = [...read(path).matchAll(/^\s*((?:\w+\.)?)ScreenMoveRemap\s*\{/gm)];
    for (const use of uses) {
      assert.equal(use[1], 'Platform.', path + ' takes ScreenMoveRemap from lib/platform');
      assert.match(read(path), /^import "(?:\.\.\/)*(?:lib\/)?platform" as Platform$/m, path + ' imports lib/platform');
    }
  }
});

test('the bar and the wallpaper surfaces use the guard after a monitor move', () => {
  const bar = read('lib/bars/omarchy/MonitorBar.qml');
  const wallpaper = read('lib/wallpaper/WallpaperController.qml');
  assert.match(bar, /Platform\.ScreenMoveRemap \{\s*id: remapGuard\s*window: barWindow\s*\}/);
  assert.match(bar, /visible: !remapGuard\.remapping/);
  assert.match(wallpaper, /Platform\.ScreenMoveRemap \{ id: remap; window: surface \}/);
  assert.match(wallpaper, /visible: [^\n]*!remap\.remapping/);
});

// A remap rebuilds the bar's window under its widgets. A widget that binds an item's
// parent to that window's contentItem then crashes the shell inside Qt.
test('the guard remaps only on Hyprland versions that strand a moved layer', () => {
  const guard = read('lib/platform/ScreenMoveRemap.qml');
  assert.match(guard, /property bool needed: false/);
  assert.match(guard, /onTriggered: if \(root\.needed\) root\.remapping = true/);
  assert.equal([...guard.matchAll(/remapping = true/g)].length, 1, 'nothing else starts a remap');
  assert.match(guard, /command: \["hyprctl", "version", "-j"\]/);
  const version = value => strandsLayers(JSON.stringify(value));
  for (const old of ['0.55.4', '0.56.2', '0.9.0']) assert.equal(version({ version: old }), true, old);
  for (const current of ['0.57.0', '0.57.2', '0.58.0', '0.100.1', '1.0.0']) assert.equal(version({ version: current }), false, current);
  assert.equal(version({ tag: 'v0.56.2' }), true);
  assert.equal(version({ tag: 'v0.57.2-3-gabcdef' }), false);
  for (const unknown of ['', 'not json', 'null', '[]', '{}', '{"version":"unknown"}']) assert.equal(strandsLayers(unknown), false, unknown);
});

test('the local guard keeps the contract its owners bind to', () => {
  const guard = read('lib/platform/ScreenMoveRemap.qml');
  assert.match(guard, /required property var window/);
  assert.match(guard, /property bool remapping: false/);
  assert.match(guard, /function onXChanged\(\) \{ settleTimer\.restart\(\) \}/);
  assert.match(guard, /function onYChanged\(\) \{ settleTimer\.restart\(\) \}/);
  assert.doesNotMatch(guard, /import qs\./, 'the guard needs nothing from the host shell');
});

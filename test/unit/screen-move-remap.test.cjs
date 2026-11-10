const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync, readdirSync } = require('node:fs');
const { join } = require('node:path');

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

test('the bar and the wallpaper surfaces still remap after a monitor move', () => {
  const bar = read('lib/bars/omarchy/MonitorBar.qml');
  const wallpaper = read('lib/wallpaper/WallpaperController.qml');
  assert.match(bar, /Platform\.ScreenMoveRemap \{\s*id: remapGuard\s*window: barWindow\s*\}/);
  assert.match(bar, /visible: !remapGuard\.remapping/);
  assert.match(wallpaper, /Platform\.ScreenMoveRemap \{ id: remap; window: surface \}/);
  assert.match(wallpaper, /visible: [^\n]*!remap\.remapping/);
});

test('the local guard keeps the contract its owners bind to', () => {
  const guard = read('lib/platform/ScreenMoveRemap.qml');
  assert.match(guard, /required property var window/);
  assert.match(guard, /property bool remapping: false/);
  assert.match(guard, /function onXChanged\(\) \{ settleTimer\.restart\(\) \}/);
  assert.match(guard, /function onYChanged\(\) \{ settleTimer\.restart\(\) \}/);
  assert.doesNotMatch(guard, /import qs\./, 'the guard needs nothing from the host shell');
});

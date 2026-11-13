const test = require('node:test');
const { runtimeSource } = require('../helpers/runtime-source.cjs');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { runInNewContext } = require('node:vm');

const Position = require('../../lib/panel/PanelPosition.js');
const Store = require('../../lib/platform/Store.js');
const service = runtimeSource();
const panel = readFileSync(join(__dirname, '..', '..', 'lib', 'panel/StationPanel.qml'), 'utf8');
const settings = readFileSync(join(__dirname, '..', '..', 'lib', 'panel/SettingsTab.qml'), 'utf8');

test('Bar landscape remains the default; legacy positions migrate and only named styles persist', () => {
  assert.equal(Store.configDefaults().panelPosition, 'bar-landscape');
  assert.equal(Store.loadConfig({}).panelPosition, 'bar-landscape');
  assert.equal(Store.loadConfig({ panelPosition: 'left' }).panelPosition, 'bar-landscape');
  assert.equal(Store.loadConfig({ panelPosition: 'center' }).panelPosition, 'center-landscape');
  assert.equal(Store.loadConfig({ panelPosition: 'bar-portrait' }).panelPosition, 'bar-portrait');
  assert.equal(Store.loadConfig({ panelPosition: 'bar-wide' }).panelPosition, 'bar-landscape');
  assert.equal(Store.loadConfig({ panelPosition: 'bar-tall' }).panelPosition, 'bar-portrait');
  assert.equal(Store.loadConfig({ panelPosition: 'center-wide' }).panelPosition, 'center-landscape');
  assert.equal(Store.loadConfig({ panelPosition: 'outside' }).panelPosition, 'bar-landscape');

  const start = service.indexOf('  function setSetting(name, value) {');
  const end = service.indexOf('\n  }', start) + '\n  }'.length;
  const config = Store.configDefaults();
  let saves = 0;
  const context = { config, store: { saveConfig() { saves++; } }, root: null };
  const setSetting = runInNewContext('(' + service.slice(start, end).trim() + '\n)', context);
  assert.equal(setSetting('panelPosition', 'bar-portrait'), 'ok');
  assert.equal(context.config.panelPosition, 'bar-portrait');
  assert.equal(saves, 1);
  assert.equal(setSetting('panelPosition', 'outside'), 'invalid');
  assert.equal(setSetting('panelPosition', 'bar-tall'), 'invalid');
  assert.equal(context.config.panelPosition, 'bar-portrait');
  assert.equal(saves, 1);
});

test('Center puts the card midpoint at the selected screen midpoint on every bar edge', () => {
  const screenW = 1920, screenH = 1080, barW = 24, barH = 24;
  const cardW = 830, cardH = 500, margin = 8, defaultGap = 8;
  for (const barPos of ['top', 'bottom', 'left', 'right']) {
    const gap = Position.centerGap(barPos, screenW, screenH, barW, barH,
      cardW, cardH, margin, defaultGap);
    // Match the host KeyboardPanel's centerOnBar cardOrigin equations.
    const x = barPos === 'left' ? barW + gap
      : barPos === 'right' ? screenW - barW - cardW - gap
      : (screenW - cardW) / 2;
    const y = barPos === 'top' ? barH + gap
      : barPos === 'bottom' ? screenH - barH - cardH - gap
      : (screenH - cardH) / 2;
    assert.ok(Math.abs(x + cardW / 2 - screenW / 2) <= 0.5, barPos + ' horizontal center');
    assert.ok(Math.abs(y + cardH / 2 - screenH / 2) <= 0.5, barPos + ' vertical center');
  }
});

test('Center keeps the panel clear of the bar when the screen is too small', () => {
  assert.equal(Position.centerGap('top', 600, 400, 24, 24, 830, 500, 8, 8), 8);
  assert.equal(Position.centerGap('top', 0, 0, 0, 0, 830, 500, 8, 8), 8);
});

test('Settings and the live panel bind to the persisted position', () => {
  assert.match(settings, /text: "Panel opening position"/);
  assert.match(settings, /value: "bar-landscape", label: "Bar landscape"/);
  assert.match(settings, /value: "bar-portrait", label: "Bar portrait"/);
  assert.match(settings, /value: "center-landscape", label: "Center landscape"/);
  assert.match(settings, /setSetting\("panelPosition", value\)/);
  assert.match(panel, /centerOnBar: root\.service && root\.service\.config\.panelPosition === "center-landscape"/);
  assert.match(panel, /portraitPanelWidth: Style\.space\(380\)/);
  assert.match(panel, /PanelPosition\.centerGap\(barPos, screenW, screenH, barThickness, barThickness,/);
  assert.match(service, /panelPosition: root\.config\.panelPosition/);
});

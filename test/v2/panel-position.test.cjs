const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { runInNewContext } = require('node:vm');

const Position = require('../../lib/PanelPosition.js');
const Store = require('../../lib/Store.js');
const service = readFileSync(join(__dirname, '..', '..', 'Service.qml'), 'utf8');
const panel = readFileSync(join(__dirname, '..', '..', 'lib', 'StationPanel.qml'), 'utf8');
const settings = readFileSync(join(__dirname, '..', '..', 'lib', 'SettingsTab.qml'), 'utf8');

test('Bar remains the default; saved position accepts only Bar or Center', () => {
  assert.equal(Store.configDefaults().panelPosition, 'left');
  assert.equal(Store.loadConfig({}).panelPosition, 'left');
  assert.equal(Store.loadConfig({ panelPosition: 'center' }).panelPosition, 'center');
  assert.equal(Store.loadConfig({ panelPosition: 'outside' }).panelPosition, 'left');

  const start = service.indexOf('  function setSetting(name, value) {');
  const end = service.indexOf('\n  }', start) + '\n  }'.length;
  const config = Store.configDefaults();
  let saves = 0;
  const context = { config, saveConfig() { saves++; }, root: null };
  const setSetting = runInNewContext('(' + service.slice(start, end).trim() + '\n)', context);
  assert.equal(setSetting('panelPosition', 'center'), 'ok');
  assert.equal(context.config.panelPosition, 'center');
  assert.equal(saves, 1);
  assert.equal(setSetting('panelPosition', 'outside'), 'invalid');
  assert.equal(context.config.panelPosition, 'center');
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

test('a cross-axis edge waits for matching thin bar-window geometry', () => {
  assert.equal(Position.stableBarPosition('left', 'top', 28, 1080, 26), 'left');
  assert.equal(Position.stableBarPosition('left', 'top', 1920, 1080, 26), 'left');
  assert.equal(Position.stableBarPosition('left', 'top', 1920, 26, 26), 'top');
  assert.equal(Position.stableBarPosition('right', 'bottom', 28, 1080, 26), 'right');
  assert.equal(Position.stableBarPosition('right', 'bottom', 1920, 26, 26), 'bottom');
  assert.equal(Position.stableBarPosition('left', 'right', 0, 0), 'right');
  assert.equal(Position.stableBarPosition('top', 'bottom', 0, 0), 'bottom');
  assert.equal(Position.stableBarPosition('left', 'top', 0, 0), 'left');
});

test('Settings and the live panel bind to the persisted position', () => {
  assert.match(settings, /text: "Panel opening position"/);
  assert.match(settings, /value: "left", label: "Bar"/);
  assert.match(settings, /value: "center", label: "Center"/);
  assert.match(settings, /setSetting\("panelPosition", value\)/);
  assert.match(panel, /centerOnBar: root\.service && root\.service\.config\.panelPosition === "center"/);
  assert.match(panel, /PanelPosition\.centerGap\(/);
  assert.match(service, /panelPosition: root\.config\.panelPosition/);
});

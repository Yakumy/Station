const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const source = readFileSync('lib/StationPanel.qml', 'utf8');

function harness() {
  const c = {
    selectedDisplayName: 'A', brightnessAvailable: true, brightness: 50,
    pendingBrightnessRequest: null,
    brightnessWrite: { running: false },
    brightnessDebounce: { restart() {} },
    textSizeStops: [9, 10, 11, 12, 14, 16, 20], textSizePreviewIndex: -1,
    queuedTextSize: -1, Style: { font: { baseSize: 12 } },
    textSizeWrite: { running: false },
  };
  c.root = c;
  for (const match of source.matchAll(/^  function (\w+)\([^\n]*\{\n[^]*?^  \}/gm))
    c[match[1]] = runInNewContext('(' + match[0].trim() + ')', c);
  return c;
}

test('a delayed brightness change stays on the monitor selected at release', () => {
  const c = harness();
  c.queueBrightness(70);
  c.selectedDisplayName = 'B';
  c.setBrightness(c.brightnessDebounce.pending, c.brightnessDebounce.monitorName);
  assert.equal(c.brightnessWrite.command.at(-2), 'A');
  assert.equal(c.brightnessWrite.command.at(-1), '70%');
  assert.equal(c.brightness, 50, 'the selected monitor does not show another monitor brightness');
});

test('a brightness change queued behind a running write retains its target', () => {
  const c = harness();
  c.brightnessWrite.running = true;
  c.setBrightness(80, 'A');
  c.selectedDisplayName = 'B';
  c.brightnessWrite.running = false;
  const pending = c.pendingBrightnessRequest;
  c.setBrightness(pending.value, pending.monitorName);
  assert.equal(c.brightnessWrite.command.at(-2), 'A');
  assert.equal(c.brightnessWrite.command.at(-1), '80%');
});

test('releasing the current text-size stop does not run the global font command', () => {
  const c = harness();
  c.setTextSizeIndex(3);
  assert.equal(c.textSizeWrite.running, false);
  c.setTextSizeIndex(4);
  assert.equal(c.textSizeWrite.command.at(-1), '14');
  c.setTextSizeIndex(4);
  assert.equal(c.queuedTextSize, -1);
});

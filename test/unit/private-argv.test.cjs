// File text never travels in argv, where other local accounts can read it from the
// process list. The transactions read it from stdin with sizes in argv, and fail
// closed on a short or overlong input.
const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync, mkdtempSync, writeFileSync, mkdirSync, chmodSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { spawnSync } = require('node:child_process');
const T = require('../../lib/platform/Transactions.js');

const repo = join(__dirname, '..', '..');
const read = path => readFileSync(join(repo, path), 'utf8');

test('part sizes are UTF-8 byte lengths and parts join in order', () => {
  for (const text of ['', 'a', 'héllo', '日本語', '😀 x', 'line\nnext\n', '\'$(id)"\\'])
    assert.equal(T.utf8Length(text), Buffer.byteLength(text), JSON.stringify(text));
  assert.deepEqual(T.stdinParts(['é', '', 'b']), { sizes: ['2', '0', '1'], input: 'éb' });
});

test('no transaction expands file text from a positional argument', () => {
  for (const name of ['keep', 'settings', 'windowSetting', 'colorMatch', 'parkToggle']) {
    assert.doesNotMatch(T[name], /printf '%s' "\$(before|after|toggle_before)"/, name);
    assert.match(T[name], /read_part/, name);
    assert.match(T[name], /end_input/, name);
  }
});

test('a short, overlong or malformed input fails closed before the file changes', () => {
  const dir = mkdtempSync(join(tmpdir(), 'station-private-argv-'));
  const bin = join(dir, 'bin'); mkdirSync(bin);
  writeFileSync(join(bin, 'hyprctl'), '#!/bin/sh\nexit 0\n'); chmodSync(join(bin, 'hyprctl'), 0o755);
  writeFileSync(join(bin, 'sleep'), '#!/bin/sh\nexit 0\n'); chmodSync(join(bin, 'sleep'), 0o755);
  const file = join(dir, 'looknfeel.lua');
  const env = { ...process.env, PATH: bin + ':' + process.env.PATH };
  const run = (sizes, input) => spawnSync('sh', ['-c', T.settings, 'sh', file, ...sizes], { input, env, encoding: 'utf8' });
  writeFileSync(file, 'one\n');
  const parts = T.stdinParts(['one\n', 'two\n']);
  assert.equal(run(parts.sizes, parts.input.slice(0, -1)).status, 2, 'short');
  assert.equal(run(parts.sizes, parts.input + 'x').status, 2, 'overlong');
  assert.equal(run(['4', '-1'], parts.input).status, 2, 'malformed size');
  assert.equal(readFileSync(file, 'utf8'), 'one\n');
  assert.equal(run(parts.sizes, parts.input).status, 0);
  assert.equal(readFileSync(file, 'utf8'), 'two\n');
});

test('every caller passes file text as input and only sizes in argv', () => {
  const display = read('lib/displays/DisplayController.qml');
  assert.match(display, /stdinParts\(\[parkToggle\]\)\s*enqueue\(\["sh", "-c", Transactions.parkToggle, "sh", internalDisablePath, parkedTogglePath, parkParts.sizes\[0\]\]/);
  assert.match(display, /\}, parkParts.input\)/);
  assert.match(display, /stdinParts\(\[monitorsSource, next\]\)\s*enqueue\(\["sh", "-c", Transactions.settings, "sh", monitorsPath, parts.sizes\[0\], parts.sizes\[1\]\]/);
  const color = read('lib/color/ColorMatchController.qml');
  assert.match(color, /stdinParts\(\[fileSource, text\]\)\s*var argv = \["sh", "-c", Transactions.colorMatch, "sh", togglePath, profileDir, parts.sizes\[0\], parts.sizes\[1\], plan.action, lua\]/);
  assert.match(color, /\}, parts.input\)/);
  const windows = read('lib/windows/WindowSettingsController.qml');
  assert.match(windows, /stdinParts\(\[appearanceSource, source\]\)/);
  assert.match(windows, /\}, configGeneration, parts.input\)/);
  for (const [path, text] of [['DisplayController', display], ['ColorMatchController', color], ['WindowSettingsController', windows]])
    assert.doesNotMatch(text, /"sh", [^\]\n]*(monitorsSource|appearanceSource|fileSource|keepSourceBaseline|keepDisableToggle)/, path);
  const service = read('Service.qml');
  assert.equal((service.match(/compositor.enqueue\(command, done, undefined, input\)/g) || []).length, 2);
  assert.match(service, /compositor.enqueue\(command, done, generation, input\)/);
  const lane = read('lib/platform/CompositorLane.qml');
  assert.match(lane, /action.stdinEnabled = currentAction.input !== null\s*action.running = true/);
  assert.match(lane, /onStarted: \{\s*if \(input === null\) return\s*write\(input\)\s*input = null\s*stdinEnabled = false/);
});

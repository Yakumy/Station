// Omarchy's display panel re-applies its saved choice per monitor after
// hypr/monitors.lua on every load (default/hypr/monitor-settings.lua). Keep must
// save Station's values there first, or the reload silently undoes the edit.
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const { join } = require('node:path');
const { tmpdir } = require('node:os');
const { spawnSync } = require('node:child_process');
const T = require('../../lib/platform/Transactions.js');
const L = require('../../lib/displays/MonitorsLua.js');

const laptop = { name: 'eDP-1', mode: '1920x1080@60.00Hz', availableModes: ['1920x1080@60.00Hz'],
  x: 3840, y: 0, scale: 1.25, transform: 3, lane: 1 };
const external = { name: 'HDMI-A-2', mode: '1920x1200@59.88Hz', availableModes: ['1920x1200@59.88Hz'],
  x: -1920, y: 320, scale: 1, transform: 0, lane: 2 };
const both = ['eDP-1', 'HDMI-A-2'];

test('Keep saves every shown output in the form Omarchy accepts', () => {
  // Production passes generate()'s validated displays, which drop availableModes.
  assert.equal(L.panelSettingsArgs(L.generate([laptop, external], { mode: 'extend', enabled: both }).displays,
    { mode: 'extend', enabled: both }).length, 10);
  assert.deepEqual(L.panelSettingsArgs([laptop, external], { mode: 'extend', enabled: both }), [
    'eDP-1', '1.25', '1920x1080@60.00', '3840x0', '3',
    'HDMI-A-2', '1', '1920x1200@59.88', '-1920x320', '0']);
  // Omarchy skips mirrored and disabled outputs, so Station saves nothing for them.
  assert.deepEqual(L.panelSettingsArgs([laptop, external], { mode: 'mirror', enabled: both }).length, 5);
  assert.deepEqual(L.panelSettingsArgs([laptop, external], { mode: 'single', singleTarget: 'HDMI-A-2', enabled: both })[0], 'HDMI-A-2');
  assert.deepEqual(L.panelSettingsArgs([laptop, external], { mode: 'extend', enabled: ['eDP-1'] })[0], 'eDP-1');
  assert.equal(L.panelSettingsArgs([laptop, external], { mode: 'extend', enabled: ['eDP-1'] }).length, 5);
  assert.throws(() => L.panelSettingsArgs([{ ...laptop, name: 'eDP-1"' }], { mode: 'extend' }));
  assert.throws(() => L.panelSettingsArgs([{ ...laptop, mode: 'preferred' }], { mode: 'extend' }));
  assert.throws(() => L.panelSettingsArgs([{ ...laptop, scale: '1; rm' }], { mode: 'extend' }));
});

test('the controller passes the saved values to Keep after the fixed arguments', () => {
  const { source, ownerFunction } = require('../helpers/display-owner.cjs');
  const c = { monitorsSource: 'before', internalDisableSource: '', pendingDisplayConfig: L.generate([laptop, external], { mode: 'extend', enabled: both }),
    keepOptions: { mode: 'extend', enabled: both }, MonitorsLua: L,
    candidateFile: { text: () => 'candidate' }, plainCandidateFile: { text: () => 'plain' }, maybeStartKeep() {} };
  ownerFunction('startKeepFiles', c)('candidate', 'plain', 'control');
  assert.equal(c.keepPanelSettings.length, 10);
  assert.match(source, /parts\.sizes\[1\]\]\n\s*\.concat\(root\.keepPanelSettings\)/);
});

function fixture(t, settings) {
  const dir = fs.mkdtempSync(join(tmpdir(), 'station-panel-settings-'));
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }));
  const bin = join(dir, 'bin'); fs.mkdirSync(bin);
  const state = join(dir, 'state'), file = join(state, 'omarchy', 'monitors', 'settings');
  const monitors = join(dir, 'monitors.lua'), candidate = join(dir, 'candidate');
  const plain = join(dir, 'plain'), token = join(dir, 'token'), log = join(dir, 'calls');
  const command = (name, body) => fs.writeFileSync(join(bin, name), '#!/bin/sh\n' + body, { mode: 0o755 });
  command('sleep', 'exit 0\n');
  command('hyprctl', `printf '%s\\n' "$*" >> "$TEST_LOG"
[ "$1" = configerrors ] && printf '%s' "\${TEST_ERRORS:-}"
[ "$1" = configerrors ] && [ -f "$TEST_SETTINGS" ] && cp "$TEST_SETTINGS" "$TEST_SEEN"
exit 0
`);
  // Stands in for Omarchy's command: one line per output, the newest last.
  command('omarchy-hyprland-monitor-persist', `printf 'persist %s\\n' "$*" >> "$TEST_LOG"
[ "\${TEST_FAIL_PERSIST:-0}" = 0 ] || exit 1
mkdir -p "$(dirname "$TEST_SETTINGS")"
printf '%s\\t%s\\t%s\\t%s\\t%s\\n' "$3" "$4" "$2" "$5" "$1" >> "$TEST_SETTINGS"
`);
  if (settings !== undefined) { fs.mkdirSync(join(state, 'omarchy', 'monitors'), { recursive: true }); fs.writeFileSync(file, settings); }
  fs.writeFileSync(monitors, 'before\n'); fs.writeFileSync(candidate, 'after\n');
  fs.writeFileSync(plain, 'old plain\n'); fs.writeFileSync(token, '');
  const env = { ...process.env, PATH: bin + ':/usr/bin:/bin', XDG_STATE_HOME: state,
    TEST_LOG: log, TEST_SETTINGS: file, TEST_SEEN: join(dir, 'seen') };
  return { dir, file, monitors, log, seen: join(dir, 'seen'),
    run(rows, extra = {}) {
      const p = T.stdinParts(['before\n', '']);
      return spawnSync('/bin/sh', ['-c', T.keep, 'sh', candidate, monitors, candidate, plain, token, p.sizes[0], join(dir, 'toggle'), p.sizes[1], ...rows],
        { input: p.input, env: { ...env, ...extra }, encoding: 'utf8' });
    } };
}
const rows = L.panelSettingsArgs([laptop, external], { mode: 'extend', enabled: both });

test('Keep saves Omarchy panel choices before the watched reload reads them', t => {
  const f = fixture(t, '\t3840x0\t1\t\tChimei\n');
  const r = f.run(rows); assert.equal(r.status, 0, r.stderr);
  const calls = fs.readFileSync(f.log, 'utf8').trim().split('\n');
  assert.deepEqual(calls.slice(0, 2), ['persist eDP-1 1.25 1920x1080@60.00 3840x0 3', 'persist HDMI-A-2 1 1920x1200@59.88 -1920x320 0']);
  assert.match(fs.readFileSync(f.seen, 'utf8'), /1920x1080@60.00\t3840x0\t1.25\t3\teDP-1/, 'saved before the reload settled');
  assert.equal(fs.readFileSync(f.monitors, 'utf8'), 'after\n');
  assert.deepEqual(fs.readdirSync(join(f.file, '..')).filter(n => /station-backup/.test(n)), []);
});

test('a rejected Keep restores Omarchy panel choices with monitors.lua', t => {
  const before = '\t3840x0\t1\t\tChimei\n';
  const f = fixture(t, before);
  assert.equal(f.run(rows, { TEST_ERRORS: 'bad rule' }).status, 3);
  assert.equal(fs.readFileSync(f.file, 'utf8'), before);
  assert.equal(fs.readFileSync(f.monitors, 'utf8'), 'before\n');
  assert.deepEqual(fs.readdirSync(join(f.file, '..')).filter(n => /station-backup/.test(n)), []);
});

test('a rejected Keep removes Omarchy panel choices it created', t => {
  const f = fixture(t);
  assert.equal(f.run(rows, { TEST_ERRORS: 'bad rule' }).status, 3);
  assert.equal(fs.existsSync(f.file), false);
});

test('a failed save leaves monitors.lua and Omarchy panel choices untouched', t => {
  const before = '\t3840x0\t1\t\tChimei\n';
  const f = fixture(t, before);
  assert.equal(f.run(rows, { TEST_FAIL_PERSIST: '1' }).status, 2);
  assert.equal(fs.readFileSync(f.file, 'utf8'), before);
  assert.equal(fs.readFileSync(f.monitors, 'utf8'), 'before\n');
});

test('Keep without rows or without the Omarchy command saves nothing', t => {
  const f = fixture(t, 'kept\n');
  assert.equal(f.run([]).status, 0);
  assert.doesNotMatch(fs.readFileSync(f.log, 'utf8'), /persist/);
  // An older Omarchy has no such command: PATH holds only the tools Keep uses.
  const g = fixture(t, 'kept\n');
  fs.rmSync(join(g.dir, 'bin', 'omarchy-hyprland-monitor-persist'));
  const tools = join(g.dir, 'tools'); fs.mkdirSync(tools);
  for (const tool of ['cat', 'cmp', 'cp', 'date', 'dirname', 'basename', 'find', 'sort', 'awk', 'head', 'wc', 'mv', 'rm', 'mktemp', 'chmod', 'mkdir'])
    fs.symlinkSync(spawnSync('sh', ['-c', 'command -v ' + tool], { encoding: 'utf8' }).stdout.trim(), join(tools, tool));
  assert.equal(g.run(rows, { PATH: join(g.dir, 'bin') + ':' + tools }).status, 0);
  assert.equal(fs.readFileSync(g.file, 'utf8'), 'kept\n');
});

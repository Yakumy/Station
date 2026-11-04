// M2 negative compatibility evidence: execute the real historical payload with
// fake desktop commands and temporary file arguments. No live shell is loaded.
const test = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, mkdirSync, readFileSync, writeFileSync, chmodSync, rmSync } = require('node:fs');
const { createHash } = require('node:crypto');
const { spawnSync } = require('node:child_process');
const { join } = require('node:path');
const { tmpdir } = require('node:os');
const legacy = readFileSync(join(__dirname, 'fixtures/legacy-plain-cleanup.sh'), 'utf8');
const current = require('../../lib/Recovery.js').cleanup;
assert.equal(createHash('sha256').update(legacy).digest('hex'),
  '2f0516178852c2a63a92c8746725c39fa55c89b8a787de8b3a7aaffaa596c00f');
const original = 'personal-before\n-- >>> station (managed; edited by the Station panel) >>>\n'
  + 'hl.monitor({ output = "A", scale = 1.6, disabled = true, mirror = "B" })\n'
  + '-- <<< station <<<\npersonal-after\n';
function run(t, script, { plain, enabled = false } = {}) {
  const root = mkdtempSync(join(tmpdir(), 'station-plain-compat-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const state = join(root, 'state'), bin = join(root, 'bin'), monitors = join(root, 'monitors.lua');
  mkdirSync(state); mkdirSync(bin);
  writeFileSync(monitors, original);
  if (plain !== undefined) writeFileSync(join(state, 'monitors-block.plain.lua'), plain);
  const commands = {
    'omarchy-shell': '#!/bin/sh\n[ "$2" = ping ] && exit 0\nprintf \'[{"id":"yakumy.station","enabled":%s}]\\n\' "$PLUGIN_ENABLED"\n',
    omarchy: '#!/bin/sh\nprintf "omarchy %s\\n" "$*" >> "$CALL_LOG"\n',
    hyprctl: '#!/bin/sh\nprintf "hyprctl %s\\n" "$*" >> "$CALL_LOG"\n',
    sleep: '#!/bin/sh\nexit 0\n', // Skip elapsed time, retain the payload's control flow.
  };
  for (const [name, body] of Object.entries(commands)) {
    const path = join(bin, name); writeFileSync(path, body); chmodSync(path, 0o755);
  }
  // All desktop entry points in either pinned payload are replaced above.
  for (const name of ['omarchy-shell', 'omarchy', 'hyprctl'])
    assert.ok(readFileSync(join(bin, name), 'utf8').startsWith('#!/bin/sh'));
  const log = join(root, 'commands.log'); writeFileSync(log, '');
  const result = spawnSync('/bin/sh', ['-c', script, 'sh', state, monitors,
    'left', '0', '0', 'right', '0', '0'], { encoding: 'utf8', timeout: 10000,
    cwd: root, env: { ...process.env, HOME: root, XDG_CONFIG_HOME: join(root, 'config'),
      XDG_STATE_HOME: state, WAYLAND_DISPLAY: '', HYPRLAND_INSTANCE_SIGNATURE: '',
      DBUS_SESSION_BUS_ADDRESS: '', PATH: bin + ':' + process.env.PATH,
      CALL_LOG: log, PLUGIN_ENABLED: String(enabled) } });
  assert.equal(result.status, 0, result.stderr || String(result.error));
  return { source: readFileSync(monitors, 'utf8'), commands: readFileSync(log, 'utf8') };
}

test('M2 blocker: an old detached payload cannot neutralize mode rules without its plain copy', t => {
  const result = run(t, legacy);
  assert.equal(result.source, original, 'legacy cleanup silently leaves disable/mirror rules in place');
  assert.equal(result.commands, 'hyprctl reload\n');
});

test('M2 blocker: leaving an old plain copy can replay stale geometry through an old payload', t => {
  const result = run(t, legacy, { plain: 'hl.monitor({ output = "A", scale = 1.1 })\n' });
  assert.match(result.source, /scale = 1.1/);
  assert.doesNotMatch(result.source, /scale = 1.6/);
  assert.ok(result.source.startsWith('personal-before\n'));
  assert.ok(result.source.endsWith('personal-after\n'));
});

test('current detached cleanup neutralizes current rules with no plain copy', t => {
  const result = run(t, current);
  assert.match(result.source, /scale = 1.6, disabled = false, mirror = ""/);
  assert.equal(result.commands, 'hyprctl reload\n');
});

test('both old and current detached payloads skip cleanup after an enabled shell restart', t => {
  for (const script of [legacy, current]) {
    const result = run(t, script, { enabled: true });
    assert.equal(result.source, original);
    assert.equal(result.commands, '');
  }
});

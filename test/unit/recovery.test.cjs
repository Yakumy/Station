const test = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, mkdirSync, writeFileSync, readFileSync, chmodSync, rmSync, existsSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { spawnSync, spawn } = require('node:child_process');
const R = require('../../lib/platform/Recovery.js');
const T = require('../../lib/platform/Transactions.js');

test('cleanup waits for shell, distinguishes restart, restores lease, clears it, and reloads', () => {
  assert.match(R.cleanup, /omarchy-shell shell ping/);
  assert.match(R.cleanup, /\.id == "yakumy\.station" and \.enabled == true/);
  assert.match(R.cleanup, /omarchy bar move omarchy\.workspaces/);
  assert.match(R.cleanup, /omarchy bar move omarchy\.monitor/);
  assert.match(R.cleanup, /\.stockLease = null \| \.displayLease = null \| \.appliedBinds = \[\]/);
  assert.match(R.cleanup, /hyprctl reload/);
});

test('preview and Keep templates use positional arguments and rollback on config errors', () => {
  assert.match(T.watchdog, /sleep "\$1"/);
  assert.match(T.watchdog, /\[ -e "\$2" \]/);
  assert.match(T.keep, /\[ ! -L "\$monitors" \]/);
  assert.match(T.keep, /hyprctl configerrors/);
  assert.match(T.keep, /cp -- "\$backup" "\$monitors"/);
  assert.match(T.keep, /if \[ -n "\$toggle_backup" \]; then\n  hyprctl reload/,
    'only a toggle handoff explicitly reloads the successful transaction');
  assert.match(T.keep, /disable_autoreload=true/);
  assert.match(T.keep, /cmp -s "\$candidate" "\$monitors"/,
    'rollback preserves newer external edits');
  assert.match(T.keep, /NR > 5/);
});

test('watchdog reverts an abandoned preview but stands down on a re-armed token', async () => {
  // previewArm touches the token before every apply, so a watchdog from an
  // earlier preview must not roll back a session the user is still editing.
  const root = mkdtempSync(join(tmpdir(), 'station-watchdog-'));
  try {
    const bin = join(root, 'bin');
    const log = join(root, 'hyprctl.log');
    mkdirSync(bin);
    writeFileSync(join(bin, 'hyprctl'), `#!/bin/sh\nprintf '%s\\n' "$@" >> ${JSON.stringify(log)}\n`);
    chmodSync(join(bin, 'hyprctl'), 0o755);
    const env = { ...process.env, PATH: `${bin}:${process.env.PATH}` };
    const run = (window, token) => new Promise((resolve) => {
      spawn('sh', ['-c', T.watchdog, 'sh', window, token], { env })
        .on('exit', (code) => resolve(code));
    });

    const fresh = join(root, 'fresh.token');
    writeFileSync(fresh, '');
    const pending = run('2', fresh);
    await new Promise((resolve) => setTimeout(resolve, 1500));
    // A later preview applies inside the window: this watchdog stands down.
    writeFileSync(fresh, '');
    assert.equal(await pending, 0);
    assert.ok(existsSync(fresh), 'a token re-armed by a newer preview is kept');
    assert.ok(!existsSync(log), 'no reload while a newer preview owns the session');

    const stale = join(root, 'stale.token');
    writeFileSync(stale, '');
    assert.equal(spawnSync('touch', ['-d', '10 seconds ago', stale]).status, 0);
    assert.equal(await run('1', stale), 0);
    assert.ok(!existsSync(stale), 'an untouched token is consumed');
    assert.match(readFileSync(log, 'utf8'), /reload/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('cleanup neutralizes current generated mode fields without restoring stale geometry', () => {
  const root = mkdtempSync(join(tmpdir(), 'station-cleanup-'));
  try {
    const state = join(root, 'state');
    const bin = join(root, 'bin');
    mkdirSync(state); mkdirSync(bin);
    const monitors = join(root, 'monitors.lua');
    writeFileSync(join(state, 'monitors-block.plain.lua'), 'hl.monitor({ output = "A", scale = 1 })\n');
    writeFileSync(join(state, 'state.json'), JSON.stringify({
      stockLease: { wasEnabled: true }, displayLease: { wasEnabled: true }, appliedBinds: ['x'],
    }));
    writeFileSync(monitors, 'before\n-- >>> station (managed; edited by the Station panel) >>>\nlocal up = {}\nhl.monitor({ output = "A", scale = 1.6, disabled = true })\n-- <<< station <<<\nafter\n');
    const commands = {
      'omarchy-shell': '#!/bin/sh\n[ "$2" = ping ] && exit 0\nprintf "[]\\n"\n',
      omarchy: '#!/bin/sh\nexit 0\n',
      hyprctl: '#!/bin/sh\nexit 0\n',
    };
    for (const [name, body] of Object.entries(commands)) {
      const path = join(bin, name); writeFileSync(path, body); chmodSync(path, 0o755);
    }
    const result = spawnSync('sh', ['-c', R.cleanup, 'sh', state, monitors,
      'left', '1', '0', 'right', '5', '0'],
      { encoding: 'utf8', env: { ...process.env, PATH: `${bin}:${process.env.PATH}` } });
    assert.equal(result.status, 0, result.stderr);
    const cleaned = readFileSync(monitors, 'utf8');
    assert.match(cleaned, /output = "A", scale = 1.6, disabled = false/);
    assert.doesNotMatch(cleaned, /disabled = true/);
    assert.deepEqual(JSON.parse(readFileSync(join(state, 'state.json'), 'utf8')),
      { stockLease: null, displayLease: null, appliedBinds: [] });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test('cleanup argv restores only leases Station took and rejects malformed ones', () => {
  const taken = { section: 'center', index: 2, wasEnabled: true, disabledByStation: true };
  const unowned = { section: 'right', index: 5, wasEnabled: false, disabledByStation: false };
  const argv = R.cleanupCommand('/state', '/monitors.lua', taken, unowned);
  assert.deepEqual(argv.slice(0, 3), ['sh', '-c', R.cleanup]);
  assert.deepEqual(argv.slice(3), ['sh', '/state', '/monitors.lua', 'center', '2', '1', 'right', '5', '0']);
  for (const bad of [null, { section: 'top', index: 1, wasEnabled: true, disabledByStation: true },
    { section: 'left', index: -1, wasEnabled: true, disabledByStation: true }]) {
    const fallback = R.cleanupCommand('/s', '/m', bad, bad);
    assert.deepEqual(fallback.slice(6), ['left', '0', '0', 'right', '0', '0']);
  }
});

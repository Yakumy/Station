const test = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, mkdirSync, writeFileSync, readFileSync, chmodSync, rmSync, existsSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { spawnSync, spawn } = require('node:child_process');
const R = require('../../lib/Recovery.js');
const T = require('../../lib/Transactions.js');

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
  const successPath = T.keep.slice(0, T.keep.indexOf('if [ -n "$errors" ]'));
  assert.doesNotMatch(successPath, /hyprctl reload/,
    'Keep must not force a second reload after accepting an already-live preview');
  assert.match(T.keep.slice(T.keep.indexOf('if [ -n "$errors" ]')), /hyprctl reload/,
    'an invalid candidate still forces the restored backup to load');
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
    await new Promise((resolve) => setTimeout(resolve, 1000));
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

test('cleanup executable replaces the literal-parenthesis marker block with plain geometry', () => {
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
    writeFileSync(monitors, 'before\n-- >>> station (managed; edited by the Station panel) >>>\nlocal up = {}\nhl.monitor({ output = "A", disabled = true })\n-- <<< station <<<\nafter\n');
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
    assert.match(cleaned, /output = "A", scale = 1/);
    assert.doesNotMatch(cleaned, /local up|disabled/);
    assert.deepEqual(JSON.parse(readFileSync(join(state, 'state.json'), 'utf8')),
      { stockLease: null, displayLease: null, appliedBinds: [] });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

const test = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, mkdirSync, writeFileSync, readFileSync, chmodSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { spawnSync } = require('node:child_process');
const R = require('../../lib/Recovery.js');
const T = require('../../lib/Transactions.js');

test('cleanup waits for shell, distinguishes restart, restores lease, clears it, and reloads', () => {
  assert.match(R.cleanup, /omarchy-shell shell ping/);
  assert.match(R.cleanup, /\.id == "yakumy\.station" and \.enabled == true/);
  assert.match(R.cleanup, /omarchy bar move omarchy\.workspaces/);
  assert.match(R.cleanup, /\.stockLease = null \| \.appliedBinds = \[\]/);
  assert.match(R.cleanup, /hyprctl reload/);
});

test('preview and Keep templates use positional arguments and rollback on config errors', () => {
  assert.match(T.watchdog, /sleep "\$1"/);
  assert.match(T.watchdog, /\[ -e "\$2" \]/);
  assert.match(T.keep, /\[ ! -L "\$monitors" \]/);
  assert.match(T.keep, /hyprctl configerrors/);
  assert.match(T.keep, /cp -- "\$backup" "\$monitors"/);
  assert.match(T.keep, /NR > 5/);
});

test('cleanup executable replaces the literal-parenthesis marker block with plain geometry', () => {
  const root = mkdtempSync(join(tmpdir(), 'station-cleanup-'));
  try {
    const state = join(root, 'state');
    const bin = join(root, 'bin');
    mkdirSync(state); mkdirSync(bin);
    const monitors = join(root, 'monitors.lua');
    writeFileSync(join(state, 'monitors-block.plain.lua'), 'hl.monitor({ output = "A", scale = 1 })\n');
    writeFileSync(join(state, 'state.json'), JSON.stringify({ stockLease: { wasEnabled: true }, appliedBinds: ['x'] }));
    writeFileSync(monitors, 'before\n-- >>> station (managed; edited by the Station panel) >>>\nlocal up = {}\nhl.monitor({ output = "A", disabled = true })\n-- <<< station <<<\nafter\n');
    const commands = {
      'omarchy-shell': '#!/bin/sh\n[ "$2" = ping ] && exit 0\nprintf "[]\\n"\n',
      omarchy: '#!/bin/sh\nexit 0\n',
      hyprctl: '#!/bin/sh\nexit 0\n',
    };
    for (const [name, body] of Object.entries(commands)) {
      const path = join(bin, name); writeFileSync(path, body); chmodSync(path, 0o755);
    }
    const result = spawnSync('sh', ['-c', R.cleanup, 'sh', state, monitors, 'left', '1', '0'],
      { encoding: 'utf8', env: { ...process.env, PATH: `${bin}:${process.env.PATH}` } });
    assert.equal(result.status, 0, result.stderr);
    const cleaned = readFileSync(monitors, 'utf8');
    assert.match(cleaned, /output = "A", scale = 1/);
    assert.doesNotMatch(cleaned, /local up|disabled/);
    assert.deepEqual(JSON.parse(readFileSync(join(state, 'state.json'), 'utf8')),
      { stockLease: null, appliedBinds: [] });
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

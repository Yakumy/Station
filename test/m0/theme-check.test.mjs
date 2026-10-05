import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { spawnSync } from 'node:child_process';

test('CI accepts tokens and rejects hex palettes in future plugin sources', () => {
  const directory = mkdtempSync(join(tmpdir(), 'station-theme-'));
  const run = () => spawnSync(process.execPath, ['tools/v2/check-theme-tokens.mjs', directory], { encoding: 'utf8' });
  try {
    writeFileSync(join(directory, 'Panel.qml'), 'Rectangle { color: Color.popups.background; radius: Style.cornerRadius }');
    assert.equal(run().status, 0);
    for (const colour of ['abcdef', '123', 'abcd', '12345678']) {
      writeFileSync(join(directory, 'Panel.qml'), `Rectangle { color: "${String.fromCharCode(35)}${colour}" }`);
      assert.equal(run().status, 1);
    }
  } finally {
    rmSync(directory, { recursive: true, force: true });
  }
  assert.equal(run().status, 1, 'missing source must fail');
});

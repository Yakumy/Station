const test = require('node:test');
const assert = require('node:assert/strict');
const {mkdtempSync, rmSync} = require('node:fs');
const {tmpdir} = require('node:os');
const {join} = require('node:path');
const {spawnSync} = require('node:child_process');

test('wallpaper renderer refuses inaccessible Wayland before launching Quickshell', () => {
  const runtime = mkdtempSync(join(tmpdir(), 'station-no-wayland-'));
  try {
    const result = spawnSync('python3', ['tools/v2/check-wallpaper.py', join(runtime, 'renders')], {
      cwd: join(__dirname, '..', '..'),
      env: {...process.env, XDG_RUNTIME_DIR: runtime, WAYLAND_DISPLAY: 'missing-wayland-socket'},
      encoding: 'utf8',
    });
    const output = result.stdout + result.stderr;
    assert.equal(result.status, 1);
    assert.match(output, /Wallpaper render check needs access to the Wayland socket/);
    assert.doesNotMatch(output, /Launching config|quickshell has crashed/i);
  } finally {
    rmSync(runtime, {recursive: true, force: true});
  }
});

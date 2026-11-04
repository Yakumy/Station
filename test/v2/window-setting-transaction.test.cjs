const test = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, writeFileSync, readFileSync, mkdirSync, chmodSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { spawnSync } = require('node:child_process');
const T = require('../../lib/Transactions.js');

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), 'station-window-setting-'));
  const bin = join(dir,'bin'); mkdirSync(bin);
  const file = join(dir,'looknfeel.lua');
  const log = join(dir,'calls');
  writeFileSync(file,'before\n');
  const helper = join(bin,'hyprctl');
  writeFileSync(helper, `#!/bin/sh
printf '%s\\n' "$*" >> "$TEST_LOG"
case "$1" in
  getoption) printf '{"bool":%s}\\n' "\${TEST_AUTO:-false}" ;;
  eval)
    case "$2" in
      *disable_autoreload=true*)
        if [ "\${TEST_CONFLICT:-}" = yes ]; then printf 'external\\n' > "$TEST_FILE"; fi
        if [ "\${TEST_SUSPEND_FAIL:-}" = yes ]; then printf 'failed\\n'; exit 0; fi
        printf 'ok\\n' ;;
      *disable_autoreload=false*) printf 'ok\\n' ;;
      *)
        [ "$(cat "$TEST_FILE")" = after ] || exit 9
        if [ "\${TEST_NEWER:-}" = yes ]; then printf 'newer\\n' > "$TEST_FILE"; fi
        if [ "\${TEST_APPLY_FAIL:-}" = yes ]; then printf 'lua error\\n'; else printf 'ok\\n'; fi ;;
    esac ;;
  reload) printf 'ok\\n' ;;
  *) exit 8 ;;
esac
`);
  chmodSync(helper,0o755);
  const sleep = join(bin,'sleep');
  writeFileSync(sleep,'#!/bin/sh\nexit 99\n'); chmodSync(sleep,0o755);
  return {file,log,run(extra={}) {
    return spawnSync('sh',['-c',T.windowSetting,'sh',file,'before\n','after\n','explicit setting'], {
      env:{...process.env,PATH:bin+':'+process.env.PATH,TEST_FILE:file,TEST_LOG:log,...extra},encoding:'utf8',timeout:3000,
    });
  }};
}

test('explicit window saves apply directly without a sleep or reload and restore autoreload', () => {
  for (const auto of ['false','true']) {
    const f = fixture(); const r = f.run({TEST_AUTO:auto});
    assert.equal(r.status,0,r.stderr);
    assert.equal(readFileSync(f.file,'utf8'),'after\n');
    assert.deepEqual(readFileSync(f.log,'utf8').trim().split('\n'),[
      'getoption misc:disable_autoreload -j',
      'eval hl.config({misc={disable_autoreload=true}})',
      'eval explicit setting',
      `eval hl.config({misc={disable_autoreload=${auto}}})`,
    ]);
  }
});

test('window save compares the source again after suspending watches', () => {
  const f = fixture(); const r = f.run({TEST_CONFLICT:'yes'});
  assert.equal(r.status,4,r.stderr);
  assert.equal(readFileSync(f.file,'utf8'),'external\n');
  const calls = readFileSync(f.log,'utf8');
  assert.doesNotMatch(calls,/explicit setting|reload\n/);
  assert.match(calls,/disable_autoreload=false/);
});

test('a rejected runtime apply rolls back only its own file and reloads for recovery', () => {
  for (const newer of ['no','yes']) {
    const f = fixture(); const r = f.run({TEST_APPLY_FAIL:'yes',TEST_NEWER:newer});
    assert.equal(r.status,3,r.stderr);
    assert.equal(readFileSync(f.file,'utf8'),newer === 'yes' ? 'newer\n' : 'before\n');
    assert.match(readFileSync(f.log,'utf8'),/reload\neval hl.config\(\{misc=\{disable_autoreload=false/);
  }
});

test('a failed watch suspension never writes or applies a setting', () => {
  const f = fixture(); const r = f.run({TEST_SUSPEND_FAIL:'yes'});
  assert.equal(r.status,3,r.stderr);
  assert.equal(readFileSync(f.file,'utf8'),'before\n');
  assert.doesNotMatch(readFileSync(f.log,'utf8'),/explicit setting|reload\n/);
});

test('a newer source written during apply is preserved and reported as a conflict', () => {
  const f = fixture(); const r = f.run({TEST_NEWER:'yes'});
  assert.equal(r.status,4,r.stderr);
  assert.equal(readFileSync(f.file,'utf8'),'newer\n');
  assert.match(readFileSync(f.log,'utf8'),/reload\n/);
});

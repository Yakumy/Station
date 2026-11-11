const test = require('node:test');
const assert = require('node:assert/strict');
const { mkdtempSync, writeFileSync, readFileSync, mkdirSync, chmodSync, existsSync, readdirSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { spawnSync } = require('node:child_process');
const C = require('../../lib/color/ColorMatch.js');
const T = require('../../lib/platform/Transactions.js');
const Store = require('../../lib/platform/Store.js');
const Recovery = require('../../lib/platform/Recovery.js');

const close = (a, b, epsilon = 1e-6) => Math.abs(a - b) < epsilon;
const u32 = (bytes, at) => ((bytes[at] << 24) | (bytes[at + 1] << 16) | (bytes[at + 2] << 8) | bytes[at + 3]) >>> 0;
const s15 = (bytes, at) => (u32(bytes, at) | 0) / 65536;
const tag = (bytes, name) => {
  const count = u32(bytes, 128);
  for (let i = 0; i < count; i++) {
    const at = 132 + i * 12;
    if (String.fromCharCode(...bytes.slice(at, at + 4)) === name) return { offset: u32(bytes, at + 4), size: u32(bytes, at + 8) };
  }
  return null;
};
const colorant = (bytes, name) => { const t = tag(bytes, name); return [0, 1, 2].map(i => s15(bytes, t.offset + 8 + i * 4)); };

test('values clamp to their ranges and the defaults are neutral', () => {
  assert.deepEqual(C.clean(null), { temperature: 6500, tint: 0, brightness: 100, gamma: 100, saturation: 100 });
  assert.equal(C.isNeutral({}), true);
  assert.deepEqual(C.clean({ temperature: 12000, tint: -500, brightness: 3, gamma: 'x', saturation: 149.6 }),
    { temperature: 9000, tint: -100, brightness: 50, gamma: 100, saturation: 150 });
  assert.equal(C.clean({ temperature: 6449 }).temperature, 6400, 'temperature moves in 100 K steps');
  assert.deepEqual(C.cleanAll({ a: {}, b: { tint: 10 }, c: 'bad' }), { b: { temperature: 6500, tint: 10, brightness: 100, gamma: 100, saturation: 100 } });
});

test('white balance gains: identity at 6500 K, warm lowers blue, cool lowers red, never above 1', () => {
  assert.deepEqual(C.gains({}).map(v => Math.round(v * 1e6) / 1e6), [1, 1, 1]);
  const warm = C.gains({ temperature: 4500 }), cool = C.gains({ temperature: 9000 });
  assert.ok(warm[0] === 1 && warm[1] < 1 && warm[2] < warm[1]);
  assert.ok(cool[2] === 1 && cool[0] < cool[1]);
  const magenta = C.gains({ tint: 100 }), green = C.gains({ tint: -100 });
  assert.ok(close(magenta[1], 0.7) && magenta[0] === 1 && magenta[2] === 1);
  assert.ok(green[1] === 1 && close(green[0], 0.7) && close(green[2], 0.7));
  assert.deepEqual(C.gains({ brightness: 80 }).map(v => Math.round(v * 100) / 100), [0.8, 0.8, 0.8]);
  for (const t of [4000, 5000, 6500, 7500, 9000]) for (const tint of [-100, 0, 100])
    assert.ok(Math.max(...C.gains({ temperature: t, tint })) <= 1 + 1e-12);
});

test('the profile is a well-formed ICC v4 display profile with sRGB colorants when neutral', () => {
  const bytes = C.profileBytes({});
  assert.equal(u32(bytes, 0), bytes.length);
  assert.equal(bytes.length % 4, 0);
  assert.equal(u32(bytes, 8), 0x04300000);
  assert.equal(String.fromCharCode(...bytes.slice(12, 24)), 'mntrRGB XYZ ');
  assert.equal(String.fromCharCode(...bytes.slice(36, 40)), 'acsp');
  assert.ok(close(s15(bytes, 68), 0.9642, 1e-4) && close(s15(bytes, 72), 1, 1e-4));
  for (const name of ['desc', 'cprt', 'wtpt', 'rXYZ', 'gXYZ', 'bXYZ', 'rTRC', 'gTRC', 'bTRC', 'chad']) {
    const t = tag(bytes, name);
    assert.ok(t && t.offset % 4 === 0 && t.offset + t.size <= bytes.length, name);
  }
  assert.equal(tag(bytes, 'rTRC').offset, tag(bytes, 'bTRC').offset, 'one shared tone curve: Hyprland rejects split curves');
  assert.ok(close(colorant(bytes, 'rXYZ')[0], 0.4360747, 1e-4));
  // The colorants sum to the D50 white, so white stays white.
  const white = [0, 1, 2].map(i => colorant(bytes, 'rXYZ')[i] + colorant(bytes, 'gXYZ')[i] + colorant(bytes, 'bXYZ')[i]);
  assert.ok(close(white[0], 0.9642, 5e-4) && close(white[1], 1, 5e-4) && close(white[2], 0.8249, 5e-4));
});

test('a warm profile describes a stronger blue primary, so lcms sends less blue', () => {
  const neutral = C.profileBytes({}), warm = C.profileBytes({ temperature: 4500 });
  assert.ok(colorant(warm, 'bXYZ')[2] > colorant(neutral, 'bXYZ')[2] * 1.5);
  assert.ok(close(colorant(warm, 'rXYZ')[0], colorant(neutral, 'rXYZ')[0], 1e-4));
  const curve = C.toneCurve({ gamma: 140 }, 1024), base = C.toneCurve({}, 1024);
  assert.equal(curve[0], 0); assert.equal(curve[1023], 1);
  // The profile describes the display as brighter in the midtones, so lcms sends
  // darker midtones (live-checked: mid-grey 128 became 96 at gamma 1.40).
  assert.ok(curve[512] > base[512], 'higher gamma describes brighter display midtones');
});

test('base64, hash and file names are deterministic and content addressed', () => {
  assert.equal(C.base64([0, 1, 2, 255]), Buffer.from([0, 1, 2, 255]).toString('base64'));
  const bytes = C.profileBytes({ tint: 5 });
  assert.deepEqual([...Buffer.from(C.base64(bytes), 'base64')], bytes);
  const a = C.profile('HDMI-A-2', { tint: 5 }), b = C.profile('HDMI-A-2', { tint: 6 });
  assert.match(a.file, /^HDMI-A-2-[0-9a-f]{8}\.icc$/);
  assert.notEqual(a.file, b.file);
  assert.equal(C.profile('HDMI-A-2', {}), null);
  assert.throws(() => C.profile('HDMI"; os.execute("x', { tint: 5 }), /connector/);
});

test('the toggle file round-trips, guards missing profiles and rejects unsafe paths', () => {
  const rows = [{ name: 'eDP-1', file: 'eDP-1-0000abcd.icc' }, { name: 'DP-1', file: 'DP-1-1234abcd.icc' }];
  const text = C.source('/home/u/.local/state/omarchy/station/color', rows);
  assert.ok(text.startsWith(C.HEADER));
  assert.match(text, /pcall\(hl\.monitor/);
  assert.match(text, /io\.open\(path, "rb"\)/);
  assert.deepEqual(C.rows(text), [rows[1], rows[0]]);
  assert.equal(C.source('/x', []), '');
  assert.deepEqual(C.rows('hl.monitor({ output = "A" })\nstation_icc("A", "/x/evil.lua")'), []);
  assert.throws(() => C.source('relative', rows), /directory/);
  assert.throws(() => C.source('/a"b', rows), /directory/);
  assert.throws(() => C.rule('A', '/x', '../y.icc'), /profile name/);
  assert.equal(C.rule('A', '/x', 'A-0000abcd.icc'), 'hl.monitor({ output = "A", icc = "/x/A-0000abcd.icc" })');
});

test('changes apply live, and only removing a connected profile needs a reload', () => {
  const a1 = { name: 'A', file: 'A-00000001.icc' }, a2 = { name: 'A', file: 'A-00000002.icc' }, b = { name: 'B', file: 'B-00000001.icc' };
  assert.deepEqual(C.change([], [a1], ['A']), { action: 'eval', rows: [a1] });
  assert.deepEqual(C.change([a1, b], [a2, b], ['A', 'B']), { action: 'eval', rows: [a2] });
  assert.deepEqual(C.change([a1], [a1], ['A']), { action: 'none', rows: [] });
  assert.deepEqual(C.change([a1, b], [b], ['A', 'B']), { action: 'reload', rows: [] });
  assert.deepEqual(C.change([a1, b], [b], ['B']), { action: 'none', rows: [] }, 'a disconnected row is not applied');
});

test('settings follow the display identity, skip HDR, and absent connectors keep their rows', () => {
  const settings = { 'Dell U24': { temperature: 5000 } };
  const moved = C.desired(settings, [{ name: 'DP-1', identity: 'Dell U24' }], [{ name: 'HDMI-A-2', file: 'HDMI-A-2-00000001.icc' }]);
  assert.deepEqual(moved.map(row => row.name), ['DP-1', 'HDMI-A-2']);
  assert.deepEqual(C.plan(settings, [{ name: 'DP-1', identity: 'Dell U24', hdr: true }]), []);
  assert.deepEqual(C.plan(settings, [{ name: 'DP-1', identity: 'Other' }]), []);
});

test('saved settings load as an object of objects and removal deletes the toggle file', () => {
  assert.deepEqual(Store.configDefaults().colorMatch, {});
  assert.deepEqual(Store.loadConfig({ colorMatch: { a: { tint: 1 }, b: 3 } }).colorMatch, { a: { tint: 1 } });
  assert.deepEqual(Store.loadConfig({ colorMatch: [1] }).colorMatch, {});
  const argv = Recovery.cleanupCommand('/s', '/m', null, null, '/w.lua', '/c.lua');
  assert.deepEqual(argv.slice(-2), ['/w.lua', '/c.lua']);
  assert.match(Recovery.cleanup, /rm -f -- "\$color_toggle"/);
  assert.ok(Recovery.cleanup.indexOf('color_toggle') < Recovery.cleanup.indexOf('hyprctl reload'));
});

function fixture() {
  const dir = mkdtempSync(join(tmpdir(), 'station-color-'));
  const bin = join(dir, 'bin'); mkdirSync(bin);
  const file = join(dir, 'toggles', 'station-color.lua');
  const profiles = join(dir, 'color');
  const log = join(dir, 'calls');
  writeFileSync(join(bin, 'hyprctl'), `#!/bin/sh
printf '%s\\n' "$*" >> "$TEST_LOG"
case "$1" in
  getoption) printf '{"bool":%s}\\n' "\${TEST_AUTO:-false}" ;;
  eval)
    case "$2" in
      *disable_autoreload*) printf 'ok\\n' ;;
      *) if [ "\${TEST_APPLY_FAIL:-}" = yes ]; then printf 'hl.monitor: error applying field icc\\n'; else printf 'ok\\n'; fi ;;
    esac ;;
  reload) printf 'ok\\n' ;;
  *) exit 8 ;;
esac
`);
  chmodSync(join(bin, 'hyprctl'), 0o755);
  return { file, profiles, log, run(before, after, action, lua, pairs = [], extra = {}) {
    return spawnSync('sh', ['-c', T.colorMatch, 'sh', file, profiles, before, after, action, lua, ...pairs], {
      env: { ...process.env, PATH: bin + ':' + process.env.PATH, TEST_LOG: log, ...extra }, encoding: 'utf8', timeout: 5000 });
  } };
}

test('the apply writes profiles first, evals with watches suspended, and restores autoreload', () => {
  const f = fixture();
  const p = C.profile('A', { temperature: 5000 });
  const text = C.source(f.profiles, [p]);
  const r = f.run('', text, 'eval', C.rule('A', f.profiles, p.file), [p.file, p.base64], { TEST_AUTO: 'true' });
  assert.equal(r.status, 0, r.stdout + r.stderr);
  assert.equal(readFileSync(f.file, 'utf8'), text);
  assert.deepEqual([...readFileSync(join(f.profiles, p.file))], C.profileBytes({ temperature: 5000 }));
  const calls = readFileSync(f.log, 'utf8').trim().split('\n');
  assert.deepEqual(calls, ['getoption misc:disable_autoreload -j', 'eval hl.config({misc={disable_autoreload=true}})',
    'eval ' + C.rule('A', f.profiles, p.file), 'eval hl.config({misc={disable_autoreload=true}})']);
});

test('a reset removes the file, reloads once and prunes unused profiles', () => {
  const f = fixture();
  const p = C.profile('A', { temperature: 5000 });
  const text = C.source(f.profiles, [p]);
  assert.equal(f.run('', text, 'eval', C.rule('A', f.profiles, p.file), [p.file, p.base64]).status, 0);
  const r = f.run(text, '', 'reload', '');
  assert.equal(r.status, 0, r.stdout);
  assert.equal(existsSync(f.file), false);
  assert.deepEqual(readdirSync(f.profiles), []);
  assert.equal(readFileSync(f.log, 'utf8').trim().split('\n').filter(line => line === 'reload').length, 1);
});

test('a rejected profile restores the file and reloads; a changed file is never overwritten', () => {
  const f = fixture();
  const p = C.profile('A', { temperature: 5000 });
  const text = C.source(f.profiles, [p]);
  const failed = f.run('', text, 'eval', C.rule('A', f.profiles, p.file), [p.file, p.base64], { TEST_APPLY_FAIL: 'yes' });
  assert.equal(failed.status, 3);
  assert.match(failed.stdout, /error applying field icc/);
  assert.equal(existsSync(f.file), false);
  assert.ok(readFileSync(f.log, 'utf8').includes('reload'));
  mkdirSync(join(f.file, '..'), { recursive: true });
  writeFileSync(f.file, 'external\n');
  assert.equal(f.run('', text, 'eval', '', [p.file, p.base64]).status, 4);
  assert.equal(readFileSync(f.file, 'utf8'), 'external\n');
  assert.equal(f.run('', text, 'eval', '', ['../evil.icc', 'AA==']).status, 2);
  assert.equal(f.run('', text, 'bogus', '').status, 2);
});

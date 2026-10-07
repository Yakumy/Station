const test = require('node:test');
const assert = require('node:assert/strict');
const L = require('../../lib/MonitorsLua.js');

function displays() {
  return [
    { name: 'eDP-1', mode: '1920x1200@59.88Hz', availableModes: ['1920x1200@59.88Hz'], x: 0, y: 0, scale: 1, transform: 0, lane: 1 },
    { name: 'HDMI-A-2', mode: '1920x1080@60.00Hz', availableModes: ['1920x1080@60.00Hz'], x: 1920, y: 0, scale: 1.25, transform: 0, lane: 2 },
  ];
}

test('generator requires allowlisted modes and safe connector names', () => {
  const badMode = displays(); badMode[0].mode = 'preferred';
  assert.throws(() => L.generate(badMode, { mode: 'extend' }), /not available/);
  const badName = displays(); badName[0].name = 'DP-1"; bad()';
  assert.throws(() => L.generate(badName, { mode: 'extend' }), /invalid connector/);
});

test('single mode guards every disable and never places mode state in plain copy', () => {
  const output = L.generate(displays(), { mode: 'single', singleTarget: 'HDMI-A-2', enabled: ['eDP-1', 'HDMI-A-2'] });
  assert.match(output.block, /pcall\(hl\.get_monitors\)/);
  assert.match(output.block, /if up\["HDMI-A-2"\] then/);
  for (const line of output.block.split('\n').filter(line => /disabled = true/.test(line))) {
    assert.match(line, /if up\[.*\] and up_count > 1 then/);
  }
  assert.doesNotMatch(output.plain, /disabled|mirror|local up/);
  assert.match(output.plain, /mode = "1920x1080@60\.00Hz"/);
});

test('mirror explicitly clears stale mirror state on its source', () => {
  const output = L.generate(displays(), { mode: 'mirror', enabled: ['eDP-1', 'HDMI-A-2'] });
  assert.match(output.block, /output = "eDP-1", disabled = false, mirror = ""/);
  assert.match(output.block, /output = "HDMI-A-2", disabled = false, mirror = "eDP-1"/);
});

test('runtime mode always emits explicit disabled and mirror state', () => {
  const rules = L.runtimeModeRules([{ name: 'A', lane: 1 }, { name: 'B', lane: 2 }],
    { mode: 'single', singleTarget: 'B', enabled: ['A', 'B'] });
  assert.match(rules[0], /disabled = true, mirror = ""/);
  assert.match(rules[1], /disabled = false, mirror = ""/);
  const fallback = L.runtimeModeRules([{ name: 'A', lane: 1 }],
    { mode: 'single', singleTarget: 'missing', enabled: [] });
  assert.match(fallback[0], /disabled = false/);
});

test('position-only preview touches only the moved output', () => {
  const before = displays().map(display => ({ ...display, enabled: true }));
  const after = before.map(display => ({ ...display }));
  after[1].x = 2400;
  const rules = L.positionOnlyRules(before, after, 'extend', 'extend');
  assert.equal(rules.length, 1);
  assert.match(rules[0], /output = "HDMI-A-2"/);
  assert.doesNotMatch(rules[0], /eDP-1/);
  assert.deepEqual(L.positionOnlyRules(after, after, 'extend', 'extend'), []);
  after[1].scale = 2;
  assert.equal(L.positionOnlyRules(before, after, 'extend', 'extend'), null);
  assert.equal(L.positionOnlyRules(before, before, 'mirror', 'extend'), null);
});

test('managed block is unique, replaced at EOF, and malformed markers fail closed', () => {
  const generated = L.generate(displays(), { mode: 'extend', enabled: ['eDP-1', 'HDMI-A-2'] });
  const once = L.replaceManagedBlock('require("defaults")\n', generated.block);
  const twice = L.replaceManagedBlock(once, generated.block);
  assert.equal((twice.match(/>>> station/g) || []).length, 1);
  assert.equal(twice, once);
  assert.ok(twice.trimEnd().endsWith(L.END));
  assert.equal(L.removeManagedBlock(once).trim(), 'require("defaults")');
  assert.throws(() => L.replaceManagedBlock(`${L.START}\nbroken\n`, generated.block), /invalid Station markers/);
});

test('rules for managed outputs outside the block are reported', () => {
  const source = 'hl.monitor({ output = "eDP-1", scale = 2 })\n';
  assert.deepEqual(L.externalRuleConflicts(source, ['eDP-1', 'HDMI-A-2']), ['eDP-1']);
});

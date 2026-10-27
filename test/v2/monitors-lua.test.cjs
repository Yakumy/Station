const test = require('node:test');
const assert = require('node:assert/strict');
const L = require('../../lib/MonitorsLua.js');
const { monitorRules } = require('./helpers/monitor-lua.cjs');

function displays() {
  return [
    { name: 'eDP-1', mode: '1920x1200@59.88Hz', availableModes: ['1920x1200@59.88Hz'], x: 0, y: 0, scale: 1, transform: 0, lane: 1 },
    { name: 'HDMI-A-2', mode: '1920x1080@60.00Hz', availableModes: ['1920x1080@60.00Hz'], x: 1920, y: 0, scale: 1.25, transform: 0, lane: 2 },
  ];
}

const savedModes = [
  { mode: 'extend', enabled: ['eDP-1', 'HDMI-A-2'] },
  { mode: 'extend', enabled: ['eDP-1'] },
  { mode: 'single', singleTarget: 'eDP-1' },
  { mode: 'single', singleTarget: 'HDMI-A-2' },
  { mode: 'mirror', enabled: ['eDP-1', 'HDMI-A-2'] },
];

test('cold or failed discovery preserves saved geometry without disabling or mirroring', () => {
  const saved = displays();
  saved[1].x = 0;
  saved[1].y = -864;
  for (const options of savedModes) {
    const block = L.generate(saved, options).block;
    for (const discovery of [
      'function() return {} end', 'nil',
      'function() error("discovery unavailable") end',
      'function() return "invalid" end',
      'function() return {{}, {name=false}} end',
    ]) {
      const rules = monitorRules(block, discovery);
      assert.deepEqual(rules, saved.map(d => L.monitorRule(d, { disabled: false, mirror: '' })),
        `${JSON.stringify(options)} with ${discovery}`);
    }
  }
});

test('warm reload applies each final display state once with no fallback replay', () => {
  for (const options of savedModes) {
    const saved = displays();
    const rules = monitorRules(L.generate(saved, options).block);
    const expected = L.runtimeModeStates(saved, options).map(state => {
      const display = saved.find(d => d.name === state.name);
      return L.monitorRule(display, { disabled: state.disabled, mirror: state.mirror });
    });
    assert.deepEqual(rules.slice().sort(), expected.sort(), JSON.stringify(options));
  }
});

test('missing saved survivor leaves the remaining display enabled with saved geometry', () => {
  for (const options of [
    { mode: 'single', singleTarget: 'HDMI-A-2' },
    { mode: 'mirror', enabled: ['HDMI-A-2'] },
    { mode: 'extend', enabled: ['HDMI-A-2'] },
  ]) {
    const saved = displays();
    const rules = monitorRules(L.generate(saved, options).block,
      'function() return {{name="eDP-1"}} end');
    assert.deepEqual(rules, saved.map(d => L.monitorRule(d, { disabled: false, mirror: '' })));
  }
});

test('generator requires allowlisted modes and safe connector names', () => {
  const badMode = displays(); badMode[0].mode = 'preferred';
  assert.throws(() => L.generate(badMode, { mode: 'extend' }), /not available/);
  const badName = displays(); badName[0].name = 'DP-1"; bad()';
  assert.throws(() => L.generate(badName, { mode: 'extend' }), /invalid connector/);
});

test('single mode guards the layout with its survivor and persists disabled outputs', () => {
  const output = L.generate(displays(), { mode: 'single', singleTarget: 'HDMI-A-2', enabled: ['eDP-1', 'HDMI-A-2'] });
  const rules = monitorRules(output.block);
  assert.match(output.block, /pcall\(hl\.get_monitors\)/);
  assert.match(output.block, /if up\["HDMI-A-2"\] then/);
  assert.equal(rules.length, 2, 'persist exactly one final rule per output');
  for (const line of rules) {
    assert.match(line, /mode = .*position = .*scale = .*transform = /);
    assert.match(line, /disabled = (?:true|false), mirror = /);
  }
  assert.match(output.block, /if up\["HDMI-A-2"\] then[\s\S]*output = "eDP-1".*disabled = true/);
  assert.doesNotMatch(output.plain, /disabled|mirror|local up/);
  assert.match(output.plain, /mode = "1920x1080@60\.00Hz"/);
});

test('extend Off is guarded by an intended survivor, not the disabled output', () => {
  const output = L.generate(displays(), { mode: 'extend', enabled: ['eDP-1'] });
  assert.match(output.block, /if up\["eDP-1"\] then/);
  assert.match(output.block, /output = "HDMI-A-2".*disabled = true/);
  assert.doesNotMatch(output.block, /if up\["HDMI-A-2"\].*disabled = true/);
});

test('mirror explicitly clears stale mirror state on its source', () => {
  const output = L.generate(displays(), { mode: 'mirror', enabled: ['eDP-1', 'HDMI-A-2'] });
  assert.match(output.block, /output = "eDP-1".*disabled = false, mirror = ""/);
  assert.match(output.block, /output = "HDMI-A-2".*disabled = false, mirror = "eDP-1"/);
});

test('runtime mode always emits explicit disabled and mirror state', () => {
  const rules = L.runtimeModeRules([{ name: 'A', lane: 1 }, { name: 'B', lane: 2 }],
    { mode: 'single', singleTarget: 'B', enabled: ['A', 'B'] });
  assert.match(rules[0], /output = "B", disabled = false, mirror = ""/);
  assert.match(rules[1], /output = "A", disabled = true, mirror = ""/);
  const fallback = L.runtimeModeRules([{ name: 'A', lane: 1 }],
    { mode: 'single', singleTarget: 'missing', enabled: [] });
  assert.match(fallback[0], /disabled = false/);
});

test('mode switches establish their surviving output before mirroring or disabling the old one', () => {
  const single = L.generate(displays(), { mode: 'single', singleTarget: 'HDMI-A-2', enabled: ['eDP-1', 'HDMI-A-2'] }).block;
  const singleRules = monitorRules(single);
  assert.match(singleRules[0], /output = "HDMI-A-2".*disabled = false/);
  assert.match(singleRules[1], /output = "eDP-1".*disabled = true/);
  const mirror = L.runtimeModeRules([{ name: 'eDP-1', lane: 2 }, { name: 'HDMI-A-2', lane: 1 }],
    { mode: 'mirror', enabled: ['eDP-1', 'HDMI-A-2'] });
  assert.match(mirror[0], /output = "HDMI-A-2", disabled = false, mirror = ""/);
  assert.match(mirror[1], /output = "eDP-1", disabled = false, mirror = "HDMI-A-2"/);
  const persistedMirror = L.generate(displays().map((display, i) => ({ ...display, lane: 2 - i })),
    { mode: 'mirror', enabled: ['eDP-1', 'HDMI-A-2'] }).block;
  const mirrorRules = monitorRules(persistedMirror);
  assert.match(mirrorRules[0], /output = "HDMI-A-2".*disabled = false, mirror = ""/);
  assert.match(mirrorRules[1], /output = "eDP-1".*disabled = false, mirror = "HDMI-A-2"/);
});

test('every two-display mode transition keeps a real unmirrored output active', () => {
  const displays = [{ name: 'A', lane: 2 }, { name: 'B', lane: 1 }];
  const choices = [
    { mode: 'extend', enabled: ['A', 'B'] },
    { mode: 'mirror', enabled: ['A', 'B'] },
    { mode: 'single', singleTarget: 'A', enabled: ['A', 'B'] },
    { mode: 'single', singleTarget: 'B', enabled: ['A', 'B'] },
  ];
  for (const from of choices) for (const to of choices) {
    const current = Object.fromEntries(L.runtimeModeStates(displays, from).map(state => [state.name, { ...state }]));
    for (const rule of L.runtimeModeRules(displays, to)) {
      const [, name, disabled, mirror] = rule.match(/output = "([AB])", disabled = (true|false), mirror = "([AB]?)"/);
      current[name] = { disabled: disabled === 'true', mirror };
      assert.ok(Object.values(current).some(state => !state.disabled && !state.mirror),
        `${from.mode}:${from.singleTarget || ''} -> ${to.mode}:${to.singleTarget || ''} lost its last output at ${rule}`);
    }
  }
});

test('mode-only previews never reapply output geometry', () => {
  const before = displays();
  const rules = L.modeOnlyRules(before, before,
    { mode: 'single', singleTarget: 'eDP-1', enabled: ['eDP-1', 'HDMI-A-2'] },
    { mode: 'single', singleTarget: 'HDMI-A-2', enabled: ['eDP-1', 'HDMI-A-2'] });
  assert.equal(rules.length, 2);
  assert.match(rules[0], /output = "HDMI-A-2"/);
  assert.ok(rules.every(rule => !/mode = |position = |scale = |transform = /.test(rule)));
  const changed = before.map(display => ({ ...display }));
  changed[0].scale = 2;
  assert.equal(L.modeOnlyRules(before, changed, { mode: 'extend' }, { mode: 'extend' }), null);
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

test('managed geometry retains the independent layout while Mirror runtime overlaps outputs', () => {
  const saved = displays();
  saved[0].x = 1920;
  saved[0].y = -60;
  saved[1].x = 0;
  saved[1].y = 0;
  const block = L.generate(saved.map((display, index) => ({ ...display, lane: 2 - index })),
    { mode: 'mirror', enabled: ['eDP-1', 'HDMI-A-2'] }).block;
  const geometry = L.managedGeometry(block);
  assert.deepEqual(geometry['eDP-1'], {
    name: 'eDP-1', mode: '1920x1200@59.88Hz', x: 1920, y: -60, scale: 1, transform: 0,
  });
  assert.deepEqual(geometry['HDMI-A-2'], {
    name: 'HDMI-A-2', mode: '1920x1080@60.00Hz', x: 0, y: 0, scale: 1.25, transform: 0,
  });
});

test('managed geometry ignores malformed blocks and conflicting duplicate rules', () => {
  assert.deepEqual(L.managedGeometry('hl.monitor({ output = "eDP-1" })'), {});
  const conflict = `${L.START}\n`
    + 'hl.monitor({ output = "eDP-1", mode = "1920x1200@59.88Hz", position = "0x0", scale = 1, transform = 0, disabled = false, mirror = "" })\n'
    + 'hl.monitor({ output = "eDP-1", mode = "1920x1200@59.88Hz", position = "1920x0", scale = 1, transform = 0, disabled = false, mirror = "" })\n'
    + `${L.END}\n`;
  assert.deepEqual(L.managedGeometry(conflict), {});
});

test('rules for managed outputs outside the block are reported', () => {
  const source = 'hl.monitor({ output = "eDP-1", scale = 2 })\n';
  assert.deepEqual(L.externalRuleConflicts(source, ['eDP-1', 'HDMI-A-2']), ['eDP-1']);
});

const test = require('node:test');
const assert = require('node:assert/strict');
const B = require('../../lib/Binds.js');
const H = require('../../lib/Hypr.js');
const S = require('../../lib/Store.js');

test('binding normalization ignores modifier order and aliases arrows', () => {
  assert.equal(B.normalize('shift + control + SUPER + ←'), 'SUPER+CTRL+SHIFT+LEFT');
  assert.equal(B.normalize('MOD4  ALT  1'), 'SUPER+ALT+1');
  assert.equal(B.validCombo('CTRL + SUPER + LEFT'), true);
  assert.equal(B.validCombo('LEFT'), false);
});

test('hyprctl and literal Lua fallbacks can add conflicts', () => {
  const hypr = B.parseHypr(JSON.stringify([{ modmask: 68, key: 'LEFT', keycode: 0, description: 'group' },
    { modmask: 64, key: '', keycode: 10, description: 'code bind' }]));
  assert.deepEqual(hypr, [{ combo: 'SUPER+CTRL+LEFT', description: 'group', source: 'hyprctl' }]);
  assert.deepEqual(B.parseLua('-- o.bind("SUPER + Z")\no.bind("SUPER + X", "Mine", "cmd")'),
    [{ combo: 'SUPER+X', description: 'Personal bindings.lua', source: 'lua' }]);
});

test('custom bindings retain action identity and stop being automatic replacements', () => {
  const custom = B.effectiveDefinitions({ 'go-left': 'SUPER + CTRL + J' });
  const left = custom.find(value => value.id === 'go-left');
  assert.equal(left.combo, 'SUPER + CTRL + J');
  assert.equal(left.replacement, false);
  assert.equal(left.defaultCombo, 'SUPER + CTRL + LEFT');
});

test('menu parser and classification preserve unknown semantics', () => {
  const text = 'CTRL + SUPER + LEFT → Move grouped window focus left\nSUPER + X → Personal';
  assert.deepEqual(B.parseMenu(text)[0], { combo: 'SUPER+CTRL+LEFT', description: 'Move grouped window focus left', source: 'menu' });
  assert.equal(B.classify('CTRL+SUPER+LEFT', { ok: true, text }, []).status, 'replacement');
  assert.equal(B.classify('SUPER+X', { ok: true, text }, []).status, 'conflict');
  assert.equal(B.classify('SUPER+Y', { ok: true, text }, []).status, 'free');
  assert.equal(B.classify('SUPER+Y', { ok: false, text: '' }, []).status, 'unverified');
  assert.equal(B.classify('SUPER+Y', { ok: false, text: '' }, [{ combo: 'SUPER Y' }]).status, 'conflict');
});

test('M1 bind table contains all actions and only approved defaults replace', () => {
  const definitions = B.definitions();
  assert.equal(definitions.length, 36);
  assert.equal(definitions.filter(value => value.replacement).length, 32);
  assert.ok(definitions.some(value => value.combo === 'SUPER + CTRL + LEFT' && value.replacement));
  const lua = B.applyLua(definitions.slice(0, 1), []);
  assert.match(lua, /hl\.unbind\("SUPER \+ code:10"\)/);
  assert.match(lua, /omarchy-shell yakumy\.station switchStation 1/);
  const changed = B.applyLua([{ ...definitions[0], combo: 'SUPER + X', replacement: false }], ['SUPER + code:10']);
  assert.match(changed, /hl\.unbind\("SUPER \+ code:10"\)/);
  assert.doesNotMatch(changed, /hl\.unbind\("SUPER \+ X"\)/);
});

test('hypr generators validate every external value', () => {
  assert.equal(H.connector('DP-1'), 'DP-1');
  assert.throws(() => H.connector('DP-1"; os.execute("bad")'), /invalid connector/);
  assert.throws(() => H.address('not-an-address'), /invalid window address/);
  assert.throws(() => H.workspace(31), /invalid workspace/);
  assert.equal(H.moveWindow('0xabc', 4, false), 'hl.dispatch(hl.dsp.window.move({ window = "address:0xabc", workspace = 4, follow = false }))');
  const rules = H.compactRules(['A', 'C']);
  assert.equal(rules.length, 20);
  assert.match(rules[3], /workspace = "4", monitor = "C"/);
  const blur = H.barBlur(true, { enabled: true, size: 8, passes: 3 });
  assert.match(blur, /name = "station-bar-blur"/);
  assert.match(blur, /namespace = "omarchy-bar"/);
  assert.match(blur, /ignore_alpha = 0/);
  assert.match(blur, /set_enabled\(true\)/);
  assert.match(blur, /blur = \{ enabled = true, size = 8, passes = 3 \}/);
  assert.match(H.barBlur(false), /set_enabled\(false\)/);
  assert.doesNotMatch(H.barBlur(false), /hl\.config/);
});

test('store defaults and migrations constrain public values', () => {
  assert.equal(S.STATE_VERSION, 4);
  const config = S.loadConfig({ mode: 'bad', direction: 'bad', graceMs: 999999, minStations: 0, lanes: [] });
  assert.equal(config.mode, 'extend');
  assert.equal(config.direction, 'ltr');
  assert.equal(config.graceMs, 30000);
  assert.equal(config.minStations, 3);
  assert.deepEqual(config.lanes, {});
  assert.equal(config.hideNative, true);
  assert.equal(config.hideDisplay, false);
  assert.equal(S.loadConfig({ hideNative: false, hideDisplay: true }).hideDisplay, true);
  assert.equal(S.loadConfig({ graceMs: 0 }).graceMs, 0);
  const state = S.loadState({ lastStation: 99 });
  assert.equal(state.lastStation, 10);
  assert.equal(state.displayLease, null);
  assert.equal(state.barBlurLease, null);
  assert.deepEqual(S.loadState({ barBlurLease: { originalEnabled: false, changed: true } }).barBlurLease,
    { originalEnabled: false, changed: true, originalSize: null, originalPasses: null });
});


test('bindings use v1 direct exec dispatchers and exact stock modifier spelling', () => {
  const definitions = B.definitions();
  const lua = B.applyLua(definitions, []);
  assert.match(lua, /hl\.bind\("SHIFT \+ CTRL \+ SUPER \+ LEFT", hl\.dsp\.exec_cmd\("omarchy-shell yakumy\.station shiftWindow left"\)/);
  assert.match(lua, /hl\.unbind\("SUPER \+ CTRL \+ LEFT"\)/);
  assert.match(lua, /hl\.unbind\("SUPER \+ CTRL \+ RIGHT"\)/);
  assert.doesNotMatch(lua, /o\.bind/);
});

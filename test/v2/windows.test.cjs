const {test} = require('node:test');
const assert = require('node:assert/strict');
const W = require('../../lib/Windows.js');
test('window settings clamp numeric preferences and reject injected values', () => {
  assert.deepEqual(W.clean({innerGap:Infinity, outerGap:-10, split:900, rounding:'os.execute()', speed:NaN}),
    {innerGap:10, outerGap:0, split:75, rounding:0, speed:1});
  assert.equal(W.lua({innerGap:40}).includes('gaps_in=20'), true);
  assert.equal(W.lua({speed:0}).includes('animations={enabled=false}'), true);
  assert.equal(W.lua({speed:2}).includes('speed=2'), true);
  assert.equal(W.lua({split:75}).includes('default_split_ratio=0.5'), true);
  assert.doesNotMatch(W.lua({outerGap:80}), /monitor|reserved|layer_rule/);
});

test('outer gaps omit only the enabled bar edge on each monitor', () => {
  for (const edge of ['top', 'right', 'bottom', 'left']) {
    const gaps = W.gaps({outerGap:30}, {position:edge, enabled:true});
    for (const side of Object.keys(gaps)) assert.equal(gaps[side], side === edge ? 0 : 30);
  }
  assert.deepEqual(W.gaps({outerGap:30}, {position:'top', enabled:false}), {top:30,right:30,bottom:30,left:30});
  assert.match(W.gapRules({outerGap:30}, {'DP-1':{position:'left'}}), /workspace="m\[DP-1\]",gaps_out=\{top=30,right=30,bottom=30,left=0\}/);
  assert.throws(() => W.gapRules({}, {'bad"]':{}}), /invalid connector/);
  assert.match(W.lua({split:28}), /default_split_ratio=1.44/);
});

test('speed has nine discrete positions with normal speed at the midpoint', () => {
  assert.equal(W.speeds.length, 9);
  assert.equal(W.speeds[4], 1);
  for (const speed of W.speeds) assert.equal(W.clean({speed}).speed, speed);
  assert.equal(W.clean({speed:10}).speed, 2);
  assert.match(W.lua({speed:0.25}), /speed=16/);
});

test('window rounding leaves the shell corner token unchanged', () => {
  assert.doesNotMatch(W.lua({rounding:30}), /decoration/);
  assert.match(W.lua({rounding:30}), /hl.window_rule.*rounding=30/);
});

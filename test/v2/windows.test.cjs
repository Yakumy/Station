const {test} = require('node:test');
const assert = require('node:assert/strict');
const W = require('../../lib/Windows.js');
test('window settings clamp numeric preferences and reject injected values', () => {
  assert.deepEqual(W.clean({innerGap:Infinity, outerGap:-10, split:900, rounding:'os.execute()', speed:NaN}),
    {innerGap:10, outerGap:0, split:75, rounding:0, speed:1});
  assert.equal(W.lua({innerGap:40}).includes('gaps_in=20'), true);
  assert.equal(W.lua({speed:0}).includes('animations={enabled=false}'), true);
  assert.equal(W.lua({speed:8}).includes('speed=0.5'), true);
  assert.equal(W.lua({split:75}).includes('default_split_ratio=1.5'), true);
  assert.doesNotMatch(W.lua({outerGap:80}), /monitor|reserved|layer_rule/);
});

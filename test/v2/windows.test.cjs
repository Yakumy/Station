const {test} = require('node:test');
const assert = require('node:assert/strict');
const W = require('../../lib/Windows.js');
const P = require('../../lib/WindowPreview.js');

test('preview transfers one window at a time and reflows every occupied tile', () => {
  const areas = [{x:0,y:0,width:500,height:300}, {x:600,y:0,width:500,height:400},
    {x:0,y:500,width:400,height:300}];
  for (const swapped of [false, true]) {
    const start = P.frame(areas, [0,1], swapped, 0, 35, 10);
    const middle = P.frame(areas, [0,1], swapped, 1, 35, 10);
    const end = P.frame(areas, [0,1], swapped, 2, 35, 10);
    assert.deepEqual(middle[0], areas[0], 'remaining window fills source');
    assert.ok(middle[2].width < areas[1].width);
    const outgoing = swapped ? 3 : 1, returning = swapped ? 1 : 3;
    assert.ok(middle[returning].height < start[returning].height, 'resident shrinks for arrival');
    assert.equal(middle[outgoing].x, middle[returning].x);
    assert.equal(middle[outgoing].y, middle[returning].y + middle[returning].height + 10);
    assert.deepEqual(end, P.frame(areas, [0,1], !swapped, 0, 35, 10), 'replay starts without a jump');
    for (let i = 0; i < 6; i++) {
      assert.deepEqual(P.rect(i, areas, [0,1], swapped, 1, 35, 10), middle[i]);
      const halfway = P.rect(i, areas, [0,1], swapped, 0.5, 35, 10);
      for (const key of ['x','y','width','height']) assert.equal(halfway[key], (start[i][key] + middle[i][key]) / 2);
    }
    assert.deepEqual(start.slice(4), middle.slice(4), 'third monitor stays still');
  }
  assert.deepEqual(P.frame(areas, [1], false, 0, 50, 0), P.frame(areas, [1], false, 2, 50, 0));
  assert.deepEqual(P.frame(areas, [0,2], false, 0, 50, 0).slice(2,4),
    P.frame(areas, [0,2], false, 1, 50, 0).slice(2,4), 'disabled monitor excluded');
});
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

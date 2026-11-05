const {test} = require('node:test');
const assert = require('node:assert/strict');
const W = require('../../lib/windows/Windows.js');
const P = require('../../lib/windows/WindowPreview.js');

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
    assert.ok(middle[2].height < start[2].height, 'next window shrinks for arrival');
    assert.equal(middle[returning].x, areas[1].x, 'resident WINDOW remains left');
    assert.equal(middle[outgoing].x, middle[2].x);
    assert.equal(middle[2].y, middle[outgoing].y + middle[outgoing].height + 10);
    assert.deepEqual(end, P.frame(areas, [0,1], !swapped, 0, 35, 10), 'replay starts without a jump');
    for (let i = 0; i < 6; i++) {
      assert.deepEqual(P.rect(i, areas, [0,1], swapped, 1, 35, 10), middle[i]);
      const halfway = P.rect(i, areas, [0,1], swapped, 0.5, 35, 10);
      for (const key of ['x','y','width','height']) assert.equal(halfway[key], (start[i][key] + middle[i][key]) / 2);
    }
    assert.deepEqual(start.slice(4), middle.slice(4), 'third monitor stays still');
    for (const frame of [start, end]) {
      for (const monitor of [0, 1, 2]) {
        const next = frame[monitor * 2];
        const window = frame.find((rect, id) => id % 2 === 1 && rect.y === next.y && rect.x < next.x
          && rect.x >= areas[monitor].x);
        assert.ok(window, 'WINDOW stays left of NEXT WINDOW');
        assert.equal(next.width, (areas[monitor].width - 10) * 0.35);
      }
    }
  }
  assert.deepEqual(P.frame(areas, [1], false, 0, 50, 0), P.frame(areas, [1], false, 2, 50, 0));
  assert.deepEqual(P.frame(areas, [0,2], false, 0, 50, 0).slice(2,4),
    P.frame(areas, [0,2], false, 1, 50, 0).slice(2,4), 'disabled monitor excluded');
});
test('window settings clamp numeric preferences and reject injected values', () => {
  assert.deepEqual(W.clean({innerGap:Infinity, outerGap:-10, split:900, rounding:'os.execute()', speed:NaN}),
    {innerGap:10, outerGap:0, split:75, rounding:0, speed:1});
  assert.equal(W.settingLua('innerGap', 40).includes('gaps_in=20'), true);
  assert.equal(W.settingLua('speed', 0).includes('animations={enabled=false}'), true);
  assert.equal(W.settingLua('speed', 2).includes('speed=2'), true);
  assert.equal(W.settingLua('split', 75).includes('default_split_ratio=0.5'), true);
  assert.doesNotMatch(W.settingLua('outerGap', 80), /monitor|reserved|layer_rule/);
});

test('all bars respect the observed global outer gap', () => {
  for (const edge of ['top', 'right', 'bottom', 'left']) {
    for (const background of ['solid', 'transparent', 'blur']) {
      for (const style of ['default', 'pill']) {
        for (const enabled of [true, false]) {
          for (const outerGap of [0, 30, 160]) {
            const bar = {position:edge, enabled, background, style};
            const gaps = W.gaps({outerGap}, bar);
            const omit = false;
            for (const side of Object.keys(gaps)) {
              assert.equal(gaps[side], omit && side === edge ? 0 : outerGap,
                JSON.stringify({bar, outerGap, side}));
            }
          }
        }
      }
    }
  }
  assert.deepEqual(W.gaps({outerGap:30}, {position:'top'}), {top:30,right:30,bottom:30,left:30});
  assert.match(W.settingLua('split', 28), /default_split_ratio=1.44/);
});

test('speed has nine discrete positions with normal speed at the midpoint', () => {
  assert.equal(W.speeds.length, 9);
  assert.equal(W.speeds[4], 1);
  for (const speed of W.speeds) assert.equal(W.clean({speed}).speed, speed);
  assert.equal(W.clean({speed:10}).speed, 2);
  assert.match(W.settingLua('speed', 0.25), /speed=16/);
});

test('rounding edits the shared compositor setting', () => {
  assert.match(W.settingLua('rounding', 30), /decoration/);
  assert.deepEqual(W.limits.rounding, [0, 20, 0]);
  for (const radius of [20, 21, 32, 40, 999]) {
    assert.equal(W.clean({rounding:radius}).rounding, 20);
    assert.match(W.settingLua('rounding', radius), /hl.config.*rounding=20/);
    assert.doesNotMatch(W.settingLua('rounding', radius), /rounding=(21|32|40|999)\b/);
  }
});

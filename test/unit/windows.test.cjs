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
test('three-monitor preview visits every enabled output and replays continuously', () => {
  const areas = [{x:0,y:0,width:500,height:300}, {x:600,y:0,width:500,height:400},
    {x:0,y:500,width:400,height:300}];
  for (let rotation = 0; rotation < 3; rotation++) {
    const start = P.frame(areas, [0,1,2], rotation, 0, 35, 10);
    const end = P.frame(areas, [0,1,2], rotation, 3, 35, 10);
    assert.deepEqual(end, P.frame(areas, [0,1,2], (rotation + 1) % 3, 0, 35, 10));
    for (let i = 1; i < 6; i += 2) assert.notDeepEqual(start[i], end[i]);
    for (let stage = 0; stage <= 3; stage++) {
      const frame = P.frame(areas, [0,1,2], rotation, stage, 35, 10);
      for (let i = 0; i < 6; i++) assert.deepEqual(P.rect(i, areas, [0,1,2], rotation, stage, 35, 10), frame[i]);
    }
  }
});
test('single enabled monitor swaps sides twice and leaves disabled outputs still', () => {
  const areas = [{x:0,y:0,width:500,height:300}, {x:600,y:0,width:500,height:400}];
  const start = P.frame(areas, [1], 0, 0, 35, 10);
  const middle = P.frame(areas, [1], 0, 1, 35, 10);
  const end = P.frame(areas, [1], 0, 2, 35, 10);
  assert.deepEqual(start[2], middle[3]);
  assert.deepEqual(start[3], middle[2]);
  assert.deepEqual(start, end);
  assert.deepEqual(start.slice(0,2), middle.slice(0,2));
  assert.ok(P.rect(3, areas, [1], 0, 0.5, 35, 10).x > start[3].x);
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

test('a transparent default bar removes the outer gap and a Pill bar uses its safe space', () => {
  for (const edge of ['top', 'right', 'bottom', 'left']) {
    for (const background of ['solid', 'transparent', 'blur']) {
      for (const style of ['default', 'pill']) {
        for (const enabled of [true, false]) {
          for (const outerGap of [0, 30, 160]) {
            const bar = {position:edge, enabled, background, style};
            const gaps = W.gaps({outerGap}, bar, 7);
            const omit = enabled && style !== 'pill' && background === 'transparent';
            for (const side of Object.keys(gaps)) {
              const pill = enabled && style === 'pill' && side === edge;
              assert.equal(gaps[side], pill ? 7 : omit && side === edge ? 0 : outerGap,
                JSON.stringify({bar, outerGap, side}));
            }
          }
        }
      }
    }
  }
  assert.deepEqual(W.gaps({outerGap:30}, {position:'top'}), {top:30,right:30,bottom:30,left:30});
  assert.deepEqual(W.gaps({outerGap:30}, {position:'left', enabled:true, background:'transparent', style:'pill'}, 7), {top:30,right:30,bottom:30,left:7});
  assert.deepEqual(W.gaps({outerGap:30}, {position:'top', enabled:true, background:'blur', style:'pill'}, 7), {top:7,right:30,bottom:30,left:30});
  assert.deepEqual(W.gaps({outerGap:30}, {position:'top', enabled:true, background:'solid', style:'default'}, 7), {top:30,right:30,bottom:30,left:30});
  const rules = W.gapRules({outerGap:20}, {'DP-1':{position:'top',enabled:true,background:'transparent'}, 'eDP-1':{position:'bottom',enabled:true,background:'solid'}});
  assert.match(rules, /m\[DP-1\]",gaps_out=\{top=0,right=20,bottom=20,left=20\}/);
  assert.match(rules, /m\[eDP-1\]",gaps_out=\{top=20,right=20,bottom=20,left=20\}/);
  assert.equal(W.gapRules({outerGap:20}, {'DP-1':{position:'top'}, 'eDP-1':{position:'top'}}, ['eDP-1']).split(';').length, 1);
  assert.throws(() => W.gapRules({}, {'x"]);os.exit()':{}}));
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

test('bar gap sync writes runtime rules only for Transparent bars and undoes them afterwards', () => {
  const { ownerSource, qmlFunction } = require('../helpers/runtime-source.cjs');
  const source = ownerSource('bars/BarLayerSync');
  const bars = { 'DP-1': { enabled: true, position: 'top', background: 'transparent' },
    'eDP-1': { enabled: true, position: 'top', background: 'solid' } };
  const sent = [];
  const c = { active: true, windowValues: { outerGap: 20 }, gapRuled: {}, Windows: W, pillGap: 7,
    displays: [{ name: 'DP-1' }, { name: 'eDP-1' }, { name: 'HDMI-A-1', disabled: true }],
    monitorBar: name => bars[name], evalLua: lua => sent.push(lua) };
  const sync = qmlFunction(source, 'syncBarGaps', c);
  sync();
  assert.equal(sent.length, 1);
  assert.match(sent[0], /m\[DP-1\]",gaps_out=\{top=0,/);
  assert.doesNotMatch(sent[0], /eDP-1|HDMI/);
  bars['DP-1'].background = 'blur';
  sync();
  assert.match(sent[1], /m\[DP-1\]",gaps_out=\{top=20,right=20,bottom=20,left=20\}/);
  bars['eDP-1'].style = 'pill';
  sync();
  assert.match(sent[2], /m\[eDP-1\]",gaps_out=\{top=7,right=20,bottom=20,left=20\}/);
  bars['eDP-1'].style = 'default'; sent.length = 2;
  sync();
  assert.equal(sent.length, 3);
  c.windowValues = {}; sync();
  assert.equal(sent.length, 3);
});

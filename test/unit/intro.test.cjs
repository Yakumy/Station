const {test} = require('node:test');
const assert = require('node:assert/strict');
const intro = require('../../lib/wallpaper/Intro.js');
const wallpaper = require('../../lib/wallpaper/Wallpaper.js');
const source = '/state/theme/backgrounds/totoro.webp';
const status = {source_rects: 1, intro: true, ready: true, media_id: 7,
  intro_path: '/state/theme/backgrounds/intros/totoro.mp4'};
const scene = {mode: 'span', followTheme: true, source, framing: {zoom: 2, x: 0.25, y: 0.75}};
const layout = wallpaper.topology([
  {name: 'A', width: 1920, height: 1080, x: -1920, y: 0},
  {name: 'B', width: 1080, height: 1920, x: 0, y: 0}], ['A','B']);
test('intro rectangles are precisely the still crops, normalized across the span', () => {
  const req = intro.request(status, scene, layout, 3840, 2160, wallpaper.crop);
  assert.equal(req.media_id, 7);
  assert.equal(req.outputs[0].x + req.outputs[0].width, req.outputs[1].x);
  req.outputs.forEach((r, i) => {
    const c = wallpaper.crop(scene, layout, layout.displays[i], 3840, 2160);
    assert.deepEqual([r.x*3840, r.y*2160, r.width*3840, r.height*2160], [c.x,c.y,c.width,c.height]);
    assert.ok(r.x >= 0 && r.y >= 0 && r.x+r.width <= 1 && r.y+r.height <= 1);
  });
});
test('only a ready matching intro may replace a followed wallpaper', () => {
  for (const value of [null, {...status, source_rects: undefined}, {...status, intro: false},
    {...status, ready: false}, {...status, error: "decode failed"}, {...status, media_id: 1.5}, {...status, intro_path: '/other/totoro.mp4'},
    {...status, intro_path: '/state/theme/backgrounds/intros/totoro.mp4/other'}]) {
    assert.equal(intro.request(value, scene, layout, 3840, 2160, wallpaper.crop), null);
  }
  assert.equal(intro.request(status, {...scene, followTheme:false}, layout, 3840,2160, wallpaper.crop), null);
  assert.equal(intro.request(status, scene, layout, 0,0, wallpaper.crop), null);
});

test('per-monitor framing uses the same crop as the stationary image', () => {
  for (const mode of ['same', 'individual']) {
    const framed = {...scene, mode, frames: {[mode]: {A: {zoom: 3, x: 0.9, y: 0.1}}}};
    const req = intro.request(status, framed, layout, 3840,2160, wallpaper.crop);
    req.outputs.forEach((r, i) => {
      const c = wallpaper.crop(framed, layout, layout.displays[i], 3840,2160);
      assert.deepEqual([r.x,r.y,r.width,r.height], [c.x/3840,c.y/2160,c.width/3840,c.height/2160]);
    });
  }
});

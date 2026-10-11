const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const W = require('../../lib/Wallpaper.js');
const M = require('../../lib/Model.js');

const monitor = (name, extra = {}) => ({ name, width: 1920, height: 1080, x: 0, y: 0,
  scale: 1, transform: 0, mirrorOf: 'none', ...extra });
function layout(monitors) { return W.topology(monitors, M.identities(monitors)); }

test('stacked monitors recommend their combined native extent, including negative origins', () => {
  const l = layout([monitor('eDP-1', {x: -1920, y: 1080}), monitor('HDMI-A-2', {x: -1920, y: -120, height: 1200})]);
  assert.deepEqual(W.recommendation(l, {}), {width: 1920, height: 2280});
  assert.equal(l.displays[0].y, 1200);
});
test('rotation, mixed density, gaps, and disabled/mirror outputs share one logical geometry', () => {
  const l = layout([monitor('A', {width: 3840, height: 2160, scale: 2}),
    monitor('B', {transform: 1, x: 2020}), monitor('C', {disabled: true}), monitor('D', {mirrorOf: 'A'})]);
  assert.equal(l.displays.length, 2);
  assert.deepEqual(W.recommendation(l, {}), {width: 6200, height: 3840});
  assert.deepEqual(W.recommendation(l, {zoom: 2}), {width: 12400, height: 7680});
});
test('Span stays inside the image at every zoom/pan and adjacent crops share an edge', () => {
  const l = layout([monitor('A'), monitor('B', {x: 1920})]);
  for (const size of [[600, 2000], [7680, 2160], [500, 500]]) {
    for (const zoom of [1, 2, 8]) for (const x of [-2, 0, .5, 1, 2]) {
      const c = W.composition(l, ...size, {zoom, x, y: x});
      assert.ok(c.x >= 0 && c.y >= 0);
      assert.ok(c.x + c.width <= size[0] + 1e-6);
      assert.ok(c.y + c.height <= size[1] + 1e-6);
      assert.equal(c.x + l.displays[0].width * c.unit, c.x + l.displays[1].x * c.unit);
    }
  }
});
test('default follows Omarchy, theme profiles return, pinned images ignore background changes', () => {
  assert.equal(W.resolve({}, 'theme-A', '/a.jpg').source, '/a.jpg');
  const s = {mode: 'span', profiles: {'theme-A': {source: '/saved.jpg', framing: {zoom: 3}}}, pinned: {source: '/pinned.jpg'}};
  assert.equal(W.resolve(s, 'theme-A', '/a.jpg').framing.zoom, 3);
  assert.equal(W.resolve(s, 'theme-B', '/b.jpg').source, '/b.jpg');
  assert.equal(W.resolve(s, 'theme-A', '/a.jpg').source, '/saved.jpg');
  assert.equal(W.resolve({...s, followTheme: false}, 'theme-B', '/b.jpg').source, '/pinned.jpg');
});
test('per-display images follow physical identity, with a shared fallback on new displays', () => {
  const p = {mode: 'individual', source: '/base.jpg', perDisplay: {'known': '/second.jpg'}};
  assert.equal(W.sourceFor(p, {identity: 'known'}), '/second.jpg');
  assert.equal(W.sourceFor(p, {identity: 'new'}), '/base.jpg');
});
test('malformed settings are bounded; remote and control-character paths are rejected', () => {
  assert.equal(W.path('https://example.com/image.png'), '');
  assert.equal(W.path('/tmp/a\nb.jpg'), '');
  assert.equal(W.path('/tmp/$(touch bad); " wallpaper.png'), '/tmp/$(touch bad); " wallpaper.png');
  assert.deepEqual(W.framing({zoom: Infinity, x: -5, y: 50}), {zoom: 1, x: 0, y: 1});
  assert.equal(W.settings({mode: 'unknown', profiles: []}).mode, 'same');
});

function controller() {
  const source = fs.readFileSync('lib/WallpaperController.qml', 'utf8');
  const methods = source.slice(source.indexOf('  function reset()'), source.indexOf('\n  Instantiator'));
  const c = {Wallpaper: W, Qt: {callLater: () => {}}, Image: {Ready: 1, Loading: 2, Null: 0, Error: 3},
    draft: {mode: 'span', followTheme: true, source: '/tmp/image.png', perDisplay: {}, framing: W.framing({})},
    dirty: true, busy: false, pendingSave: false, serial: 0, themeKey: 'original', preferences: W.settings({}),
    layout: layout([monitor('A')]), validation: {count: 1, objectAt: () => ({status: 1})},
    station: {stateDir: '/tmp/station-test', config: {}, saveConfig() {this.saved = true},
      enqueue(argv, done) {this.argv = argv; this.done = done}},
    picker: {running: false}, pickerDelay: {restart() {}}, applied: {source: '/tmp/image.png'}};
  c.root = c;
  vm.createContext(c); vm.runInContext(methods, c);
  return c;
}
test('Apply snapshots through positional arguments and commits only after a successful copy', () => {
  const c = controller(); c.draft.source = '/tmp/$(touch bad); " image.png';
  c.apply(); c.checkImages();
  assert.equal(c.station.config.wallpaper, undefined);
  assert.equal(c.station.argv[5], c.draft.source);
  assert.ok(!c.station.argv[2].includes(c.draft.source));
  c.station.done(0);
  assert.equal(c.station.saved, true);
  assert.equal(c.busy, true);
  c.preferenceSaved();
  assert.equal(c.busy, false);
  assert.match(c.station.config.wallpaper.profiles.original.source, /^\/tmp\/station-test\/wallpapers\//);
});
test('image decode failure, copy failure, and superseded completion never commit', () => {
  let c = controller(); c.validation.objectAt = () => ({status: 3}); c.apply(); c.checkImages();
  assert.equal(c.busy, false); assert.equal(c.station.argv, undefined);
  c = controller(); c.apply(); c.checkImages(); c.station.done(1);
  assert.equal(c.station.saved, undefined); assert.equal(c.dirty, true);
  c = controller(); c.apply(); c.checkImages(); c.serial++; c.station.done(0);
  assert.equal(c.station.saved, undefined);
});
test('failed preference persistence restores the prior wallpaper without discarding the draft', () => {
  const c = controller();
  c.station.config.wallpaper = {mode: 'same', followTheme: false, pinned: {source: '/old.png'}};
  c.apply(); c.checkImages(); c.station.done(0); c.preferenceFailed();
  assert.equal(c.station.config.wallpaper.pinned.source, '/old.png');
  assert.equal(c.draft.source, '/tmp/image.png');
  assert.equal(c.dirty, true);
});
test('snapshot script preserves literal filenames and refuses to overwrite a prior snapshot', () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'station-wallpaper-copy-'));
  try {
    const c = controller();
    c.station.stateDir = directory;
    c.draft.source = path.join(directory, '$(touch OWNED); " image.png');
    fs.writeFileSync(c.draft.source, 'fixture bytes');
    c.apply(); c.checkImages();
    const [command, ...args] = c.station.argv;
    const run = () => spawnSync(command, args, {cwd: directory, encoding: 'utf8'});
    assert.equal(run().status, 0);
    assert.equal(fs.readFileSync(args.at(-1), 'utf8'), 'fixture bytes');
    assert.equal(fs.existsSync(path.join(directory, 'OWNED')), false);
    assert.notEqual(run().status, 0);
  } finally { fs.rmSync(directory, {recursive: true, force: true}); }
});

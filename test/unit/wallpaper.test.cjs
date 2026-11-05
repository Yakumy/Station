const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const W = require('../../lib/wallpaper/Wallpaper.js');
const M = require('../../lib/displays/Model.js');

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
  assert.equal(W.resolve(s, 'theme-A', '/a.jpg', '17:42').source, '/a.jpg');
  assert.equal(W.resolve(s, 'theme-A', '/a.jpg', '17:42').revision, '17:42');
  assert.equal(W.resolve({...s, followTheme: false}, 'theme-B', '/b.jpg').source, '/pinned.jpg');
  assert.equal(W.resolve({...s, followTheme: false}, 'theme-B', '/b.jpg').safe, false);
  assert.equal(W.resolve({...s, followTheme: false, pinned: {...s.pinned, safe: true}},
    'theme-B', '/b.jpg').safe, true);
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
test('per-monitor frames default to a centered fill, and resetting one removes it', () => {
  const display = {identity: 'A', width: 1000, height: 1000, x: 0, y: 0};
  assert.deepEqual(W.crop({mode: 'same'}, {}, display, 2000, 1000),
    {unit: 1, x: 500, y: 0, width: 1000, height: 1000});
  let scene = {mode: 'same', frames: {}};
  scene = W.withFrame(scene, 'A', {zoom: 2, x: 0, y: 1});
  assert.deepEqual(W.frameFor(scene, display), {zoom: 2, x: 0, y: 1});
  assert.equal(W.hasFrame(scene, display), true);
  assert.equal(W.hasFrame({...scene, mode: 'individual'}, display), false, 'each mode keeps its own frames');
  assert.equal(W.hasFrame(W.withFrame(scene, 'A', {}), display), false);
  assert.equal(W.withFrame({mode: 'span'}, 'A', {zoom: 2}).frames, undefined, 'Span keeps one group framing');
  assert.equal(W.hasFrame(scene, null), false);
});
test('frames persist per profile, stay bounded, and an old profile loads with none', () => {
  assert.deepEqual(W.profile({}).frames, {same: {}, individual: {}});
  const frames = JSON.parse('{"same":{"A":{"zoom":99,"x":-1,"y":0.5},"__proto__":{"zoom":2},"B":5,"C":{"zoom":1}}}');
  assert.deepEqual(W.profile({frames}).frames.same, {A: {zoom: 8, x: 0, y: 0.5}});
  const s = {mode: 'same', profiles: {t: {frames: {same: {A: {zoom: 3}}}}}, pinned: {frames: {same: {A: {zoom: 4}}}, safe: true, source: '/p.png'}};
  assert.equal(W.frameFor(W.resolve(s, 't', '/a.jpg'), {identity: 'A'}).zoom, 3);
  assert.equal(W.frameFor(W.resolve(s, 'other', '/a.jpg'), {identity: 'A'}).zoom, 1);
  assert.equal(W.frameFor(W.resolve({...s, followTheme: false}, 't', '/a.jpg'), {identity: 'A'}).zoom, 4);
  assert.equal(W.hasFrame(W.resolve(s, 't', '/a.jpg'), {identity: 'constructor'}), false);
});
test('panning moves the image with the pointer and every frame stays inside the image', () => {
  const display = {identity: 'A', width: 1000, height: 1000};
  // The crop slides left when the image moves right.
  const moved = W.panned(display, 2000, 1000, {}, 100, 0);
  assert.equal(W.composition(display, 2000, 1000, moved).x, 400);
  assert.equal(moved.y, 0.5, 'no slack: the short axis stays put');
  assert.equal(W.panned(display, 2000, 1000, {}, 100000, 0).x, 0);
  assert.equal(W.panned(display, 2000, 1000, {}, -100000, 0).x, 1);
  assert.deepEqual(W.panned(display, 0, 0, {zoom: 2}, 10, 10), {zoom: 2, x: 0.5, y: 0.5}, 'image not loaded');
  for (const [w, h] of [[2000, 1000], [600, 2000], [1000, 1000]])
    for (const zoom of [1, 2, 8]) for (const x of [0, .3, 1]) {
      const c = W.composition(display, w, h, {zoom, x, y: x});
      assert.ok(c.x >= 0 && c.y >= 0 && c.x + c.width <= w + 1e-6 && c.y + c.height <= h + 1e-6);
      assert.ok(Math.abs(c.width - c.height) < 1e-6, 'the crop keeps the monitor shape');
    }
});
test('zooming keeps the image point under the pointer, and zooming back out returns to fill', () => {
  const display = {identity: 'A', width: 1000, height: 1000};
  const source = (frame, px, py) => { const c = W.composition(display, 4000, 2000, frame); return [c.x + px * c.unit, c.y + py * c.unit]; };
  const start = {zoom: 2, x: 0.3, y: 0.6};
  const next = W.zoomed(display, 4000, 2000, start, 1.5, 250, 700);
  assert.equal(next.zoom, 3);
  source(start, 250, 700).forEach((value, i) => assert.ok(Math.abs(value - source(next, 250, 700)[i]) < 1e-6));
  assert.equal(W.zoomed(display, 4000, 2000, {zoom: 8}, 2, 0, 0).zoom, 8);
  assert.equal(W.zoomed(display, 4000, 2000, {}, 0.5, 0, 0).zoom, 1);
  let frame = {};
  for (let i = 0; i < 7; i++) frame = W.zoomed(display, 2000, 1000, frame, 1.1, 500, 500);
  for (let i = 0; i < 7; i++) frame = W.zoomed(display, 2000, 1000, frame, 1 / 1.1, 500, 500);
  assert.equal(frame.zoom, 1, 'rounding does not leave a monitor framed');
  assert.equal(W.hasFrame(W.withFrame({mode: 'same'}, 'A', frame), display), false);
});
test('a frame is dropped with the image it framed', () => {
  const scene = {perDisplay: {own: '/own.png'}, frames: {same: {A: {zoom: 2}}, individual: {own: {zoom: 2}, shared: {zoom: 3}}}};
  assert.deepEqual(Object.keys(W.framesWithoutImage(scene, 'own').individual), ['shared']);
  assert.deepEqual(Object.keys(W.framesWithoutImage(scene, 'own').same), ['A']);
  const all = W.framesWithoutImage(scene, '');
  assert.deepEqual(all.same, {});
  assert.deepEqual(Object.keys(all.individual), ['own']);
});

function controller() {
  const source = fs.readFileSync('lib/wallpaper/WallpaperController.qml', 'utf8');
  const methods = source.slice(source.indexOf('  function showNotice('), source.indexOf('\n  Instantiator'));
  const c = {Tabs: require('../../lib/panel/Tabs.js'), Wallpaper: W, Qt: {callLater: () => {}}, Image: {Ready: 1, Loading: 2, Null: 0, Error: 3},
    draft: {mode: 'span', followTheme: true, source: '/tmp/image.png', perDisplay: {}, framing: W.framing({}), safe: true},
    dirty: true, busy: false, pickerBusy: false, pendingSave: false, repairPending: false,
    repairPrevious: null, repairLegacyKey: '', importBusy: false, failedLegacyKey: '',
    pickerTarget: '', serial: 0,
    themeKey: 'original', preferences: W.settings({}),
    layout: layout([monitor('A')]), validation: {count: 1, objectAt: () => ({status: 1})},
    station: {stateDir: '/tmp/station-test', pluginDir: process.cwd(), configLoaded: true,
      config: {}, saveConfig() {this.saved = true},
      enqueue(argv, done) {this.argv = argv; this.done = done}},
    enqueue(argv, done) {c.station.enqueue(argv, done)},
    publishPreferences(value) {c.station.config = Object.assign({}, c.station.config, {wallpaper: value})},
    savePreferences() {c.station.saveConfig()},
    releasePanel() {c.station.panelWanted = false},
    picker: {running: false}, pickerDelay: {restarts: 0, restart() {this.restarts++}},
    applied: {source: '/tmp/image.png'}};
  c.root = c;
  // The controller's data inputs, backed by the fake composition root.
  for (const [key, read] of Object.entries({stateDir: () => c.station.stateDir, pluginDir: () => c.station.pluginDir,
    configLoaded: () => c.station.configLoaded, savedPreferences: () => c.station.config.wallpaper}))
    Object.defineProperty(c, key, {get: read, configurable: true});
  vm.createContext(c); vm.runInContext(methods, c);
  return c;
}
test('Follow Omarchy blocks local selection and keeps the panel open with an error', () => {
  const c = controller();
  c.station.panelWanted = true;
  assert.equal(c.choose(c.layout.displays[0].identity), false);
  assert.equal(c.notice, 'Turn off Follow Omarchy wallpaper to select your own wallpaper.');
  assert.equal(c.noticeError, true);
  assert.equal(c.station.panelWanted, true);
  assert.equal(c.pickerDelay.restarts, 0);

  c.change('followTheme', false);
  assert.equal(c.notice, '');
  assert.equal(c.noticeError, false);
  assert.equal(c.choose(c.layout.displays[0].identity), true);
  assert.equal(c.station.panelWanted, false);
  assert.equal(c.pickerDelay.restarts, 1);
});
test('framing a monitor marks the draft dirty, survives Apply and ignores an unknown monitor', () => {
  const c = controller();
  const id = c.layout.displays[0].identity;
  c.draft.mode = 'individual'; c.dirty = false;
  c.frameDisplay('someone-else', {zoom: 2});
  assert.equal(c.dirty, false);
  c.frameDisplay(id, {zoom: 2, x: 0.25, y: 0.5});
  assert.equal(c.dirty, true);
  c.apply(); c.checkImages(); c.station.done(0); c.preferenceSaved();
  const saved = c.station.config.wallpaper.profiles.original.frames.individual[id];
  assert.deepEqual({...saved}, {zoom: 2, x: 0.25, y: 0.5});
  c.draft = {...c.draft, mode: 'span', frames: {}}; c.dirty = false;
  c.frameDisplay(id, {zoom: 2});
  assert.equal(c.dirty, false, 'Span frames the group instead');
});
test('choosing an image clears the frame made for the previous one', () => {
  const c = controller(); const id = c.layout.displays[0].identity;
  c.draft = {...c.draft, followTheme: false, mode: 'individual', frames: {same: {[id]: {zoom: 2}}, individual: {[id]: {zoom: 3}}}};
  c.acceptSanitized('/tmp/station-test/wallpapers/a/one.png', id);
  assert.equal(c.draft.frames.same[id].zoom, 2);
  assert.equal(c.draft.frames.individual[id], undefined);
  c.acceptSanitized('/tmp/station-test/wallpapers/a/two.png', '');
  assert.deepEqual({...c.draft.frames.same}, {});
});
test('the desktop surface stays stock only for a monitor with no frame', () => {
  const source = fs.readFileSync('lib/wallpaper/WallpaperController.qml', 'utf8');
  assert.match(source, /readonly property bool stock:[^\n]*\n\s*&& !Wallpaper\.hasFrame\(root\.applied, display\)/);
});
test('a picker result is staged before it can change an Image source', () => {
  const c = controller(); c.change('followTheme', false);
  const original = c.draft.source;
  c.prepareSelection('/tmp/foreign wallpaper.png');
  assert.equal(c.draft.source, original);
  assert.equal(c.importBusy, true);
  assert.deepEqual(Array.from(c.station.argv.slice(0, 3)),
    ['perl', path.join(process.cwd(), 'lib/wallpaper/SanitizeWallpaper.pl'), '/tmp/foreign wallpaper.png']);
  assert.ok(!c.station.argv[1].includes(c.station.argv[2]));
  const prepared = c.station.argv[3] + '/image.png';
  c.station.done(0, prepared + '\n');
  assert.equal(c.importBusy, false);
  assert.equal(c.draft.source, prepared);
  assert.equal(c.draft.safe, true);
});
test('a persisted safety marker is accepted only for Station-private paths', () => {
  const c = controller();
  let scene = {followTheme: false, source: '/tmp/foreign.png', perDisplay: {}, safe: true};
  assert.equal(c.secureStoredScene(scene).safe, false);
  scene = {followTheme: false, source: '/tmp/station-test/wallpapers/safe/image.png',
    perDisplay: {}, safe: true};
  assert.equal(c.secureStoredScene(scene).safe, true);
});
test('an older pinned wallpaper is gated and restaged before rendering', () => {
  const c = controller();
  c.dirty = false;
  c.applied = {mode: 'same', followTheme: false, source: '/tmp/old.png',
    perDisplay: {}, framing: W.framing({}), safe: false};
  c.preferences = W.settings({mode: 'same', followTheme: false,
    pinned: {source: '/tmp/old.png'}});
  c.station.config.wallpaper = c.preferences;
  c.prepareLegacyWallpaper();
  assert.equal(c.importBusy, true);
  assert.equal(c.station.argv[2], '/tmp/old.png');
  const prepared = c.station.argv[3] + '/image.png';
  c.station.done(0, prepared + '\n');
  assert.equal(c.repairPending, true);
  assert.equal(c.station.config.wallpaper.pinned.safe, true);
  assert.equal(c.station.config.wallpaper.pinned.source, prepared);
  c.applied = W.resolve(c.station.config.wallpaper, '', '', '');
  c.preferenceSaved();
  assert.equal(c.importBusy, false);
  assert.equal(c.draft.source, prepared);
});
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

test('the theme watch names both directories as arguments and ignores unrelated files', () => {
  const W = require('../../lib/wallpaper/Wallpaper.js');
  assert.equal(W.directory('/a/b/c.jpg'), '/a/b');
  assert.equal(W.directory('relative.jpg'), '');
  assert.deepEqual(W.watchCommand('/state', '/images').slice(-3), ['--', '/state', '/images']);
  assert.deepEqual(W.watchCommand('/state', '').slice(-2), ['--', '/state']);
  assert.deepEqual(W.watchCommand('/state', '/state').slice(-2), ['--', '/state']);
  assert.equal(W.watchRelevant('/state/theme.name', '/state', '/images/a.jpg'), true);
  assert.equal(W.watchRelevant('/images/a.jpg', '/state', '/images/a.jpg'), true);
  assert.equal(W.watchRelevant('/images/other.jpg', '/state', '/images/a.jpg'), false);
  assert.equal(W.watchRelevant('/state-other/x', '/state', '/images/a.jpg'), false);
});

const inotify = require('node:child_process').spawnSync('inotifywait', ['--help']).error ? 'inotifywait is not installed' : false;
test('the real watch reports Omarchy background, theme and in-place image changes', { skip: inotify }, async t => {
  const fs = require('node:fs'), { join } = require('node:path'), { tmpdir } = require('node:os');
  const W = require('../../lib/wallpaper/Wallpaper.js');
  const root = fs.mkdtempSync(join(tmpdir(), 'station-theme-watch-'));
  const state = join(root, 'current'), images = join(root, 'images'), image = join(images, 'a.jpg');
  fs.mkdirSync(state); fs.mkdirSync(images); fs.writeFileSync(image, 'a'); fs.writeFileSync(join(state, 'theme.name'), 'one\n');
  const [program, ...args] = W.watchCommand(state, images);
  const watch = require('node:child_process').spawn(program, args);
  t.after(() => { watch.kill(); fs.rmSync(root, { recursive: true, force: true }); });
  let out = '';
  watch.stdout.on('data', d => { out += d; });
  await new Promise(done => { let err = ''; watch.stderr.on('data', d => { err += d; if (err.includes('Watches established')) done(); }); });
  const changed = async action => {
    out = ''; action();
    for (let i = 0; i < 100 && !out; i++) await new Promise(done => setTimeout(done, 10));
    await new Promise(done => setTimeout(done, 30));
    return out.trim().split('\n').map(line => W.watchRelevant(line, state, image));
  };
  const link = join(state, 'background');
  assert.ok((await changed(() => fs.symlinkSync(image, link))).includes(true), 'a new background link');
  assert.ok((await changed(() => { fs.symlinkSync(join(images, 'b.jpg'), link + '.tmp'); fs.renameSync(link + '.tmp', link); })).includes(true), 'ln -nsf renames over it');
  assert.ok((await changed(() => fs.writeFileSync(join(state, 'theme.name'), 'two\n'))).includes(true), 'a theme name');
  assert.ok((await changed(() => { fs.writeFileSync(image + '.tmp', 'b'); fs.renameSync(image + '.tmp', image); })).includes(true), 'an image replaced in place');
  assert.deepEqual([...new Set(await changed(() => fs.writeFileSync(join(images, 'other.jpg'), 'x')))], [false], 'other files do not count');
});

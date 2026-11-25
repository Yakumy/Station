const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const W = require('../../lib/wallpaper/Wallpaper.js');
const { monitor, layout, controller } = require('../helpers/wallpaper-controller.cjs');

const themes = W.themeList(JSON.stringify([
  {name: 'nord', label: 'Nord', preview: '/omarchy/themes/nord/preview.png', default: '/omarchy/themes/nord/backgrounds/2.jpg',
    backgrounds: [
      {path: '/omarchy/themes/nord/backgrounds/1.jpg', file: '1.jpg', omarchy: '/state/current/theme/backgrounds/1.jpg'},
      {path: '/omarchy/themes/nord/backgrounds/2.jpg', file: '2.jpg', omarchy: '/state/current/theme/backgrounds/2.jpg'}]},
  {name: 'tokyo-night', label: 'Tokyo Night', preview: '/omarchy/themes/tokyo-night/preview.png',
    backgrounds: [{path: '/omarchy/themes/tokyo-night/backgrounds/a.jpg', file: 'a.jpg', omarchy: '/tmp/theme.png'},
      {path: '/omarchy/themes/tokyo-night/backgrounds/b.jpg', file: 'b.jpg', omarchy: '/state/current/theme/backgrounds/b.jpg'}]}]));
function themed() {
  const c = controller();
  c.themes = themes; c.themeName = 'tokyo-night'; c.homeDir = '/home/test'; c.pendingTheme = ''; c.pendingBackground = '';
  c.themeSwitchName = ''; c.themeSwitchExited = false;
  c.themeSwitch = {running: false, command: []};
  c.themeSwitchTimeout = {restarts: 0, restart() {this.restarts++}, stop() {}};
  c.reads = 0; c.readTheme = () => { c.reads++ };
  return c;
}
test('the theme list is bounded, rejects unsafe names and paths, and falls back to a listed default', () => {
  const list = W.themeList(JSON.stringify([
    {name: '../x', backgrounds: []}, {name: '-x', backgrounds: []}, {name: 'Upper', backgrounds: []},
    {name: 'ok', default: '/elsewhere.jpg', backgrounds: [{path: 'relative.jpg', omarchy: '/a'},
      {path: '/a\nb.jpg', omarchy: '/a'}, {path: '/good.jpg', omarchy: '/state/good.jpg', file: 'good.jpg'}]}]));
  assert.deepEqual(list.map(theme => theme.name), ['ok']);
  assert.deepEqual(list[0].backgrounds.map(item => item.path), ['/good.jpg']);
  assert.equal(list[0].default, '/good.jpg');
  assert.equal(list[0].preview, '/good.jpg');
  assert.deepEqual(W.themeList('not json'), []);
});
test('a new theme is recorded as remembered, then applied, through positional arguments only', () => {
  const background = W.themeBackground(W.themeEntry(themes, 'nord'), '/omarchy/themes/nord/backgrounds/1.jpg');
  const argv = W.themeCommand('nord', background, '/home/test/.local/state/omarchy/theme-backgrounds');
  assert.deepEqual(argv.slice(3), ['station-theme', '/home/test/.local/state/omarchy/theme-backgrounds/nord',
    '/state/current/theme/backgrounds/1.jpg', 'nord']);
  assert.doesNotMatch(argv[2], /nord|backgrounds/);
  assert.equal(W.themeCommand('$(touch x)', background, '/r'), null);
  assert.deepEqual(W.backgroundCommand(background), ['omarchy', 'theme', 'bg', 'set', '/state/current/theme/backgrounds/1.jpg']);
});
test('the real script records the remembered background before running omarchy theme set', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'station-theme-'));
  const bin = path.join(dir, 'bin'); fs.mkdirSync(bin);
  fs.writeFileSync(path.join(bin, 'omarchy'), '#!/bin/sh\nprintf "%s\\n" "$@" > "$OUT"\n', {mode: 0o755});
  const argv = W.themeCommand('nord', {omarchy: '/state/current/theme/backgrounds/a b;$(x).jpg'}, path.join(dir, 'remembered'));
  const run = spawnSync(argv[0], argv.slice(1), {env: {...process.env, PATH: bin + ':' + process.env.PATH, OUT: path.join(dir, 'out')}});
  assert.equal(run.status, 0, String(run.stderr));
  assert.equal(fs.readFileSync(path.join(dir, 'remembered', 'nord'), 'utf8'), '/state/current/theme/backgrounds/a b;$(x).jpg\n');
  assert.equal(fs.readFileSync(path.join(dir, 'out'), 'utf8'), 'theme\nset\nnord\n');
  fs.rmSync(dir, {recursive: true});
});
test('previewing a theme changes nothing in Omarchy and shows the background it opens on', () => {
  const c = themed();
  c.dirty = false;
  assert.equal(c.previewTheme('missing'), false);
  assert.equal(c.previewTheme('nord'), true);
  assert.equal(c.pendingTheme, 'nord');
  assert.equal(c.pendingBackground, '/omarchy/themes/nord/backgrounds/2.jpg');
  assert.equal(c.draft.source, '/omarchy/themes/nord/backgrounds/2.jpg');
  assert.equal(c.draft.followTheme, true);
  assert.equal(c.dirty, true);
  assert.equal(c.themeSwitch.running, false);
  assert.equal(c.previewTheme('tokyo-night'), true, 'the current theme clears the pending one');
  assert.equal(c.pendingTheme, '');
  assert.equal(c.draft.source, '/tmp/theme.png');
  c.previewTheme('nord');
  c.reset();
  assert.equal(c.pendingTheme, '');
  assert.equal(c.pendingBackground, '');
});
test('with Follow off a theme preview keeps the pinned wallpaper', () => {
  const c = themed();
  c.draft = {...c.draft, followTheme: false, source: '/tmp/station-test/wallpapers/a/pinned.png'};
  c.previewTheme('nord');
  assert.equal(c.draft.source, '/tmp/station-test/wallpapers/a/pinned.png');
  assert.match(c.notice, /Follow Omarchy theme is off/);
});
test('a shared theme background becomes Omarchy\'s background and turns Follow on', () => {
  const c = themed();
  c.draft = {...c.draft, followTheme: false};
  assert.equal(c.previewBackground('/not/listed.jpg', ''), false);
  assert.equal(c.previewBackground('/omarchy/themes/tokyo-night/backgrounds/b.jpg', ''), true);
  assert.equal(c.pendingBackground, '/omarchy/themes/tokyo-night/backgrounds/b.jpg');
  assert.equal(c.draft.followTheme, true);
  assert.equal(c.draft.source, '/omarchy/themes/tokyo-night/backgrounds/b.jpg');
  c.previewBackground('/omarchy/themes/tokyo-night/backgrounds/a.jpg', '');
  assert.equal(c.pendingBackground, '', 'the live background is not pending');
  assert.equal(c.draft.source, '/tmp/theme.png');
});
test('a per-monitor theme background becomes only that monitor\'s private image', () => {
  const c = themed();
  c.layout = layout([monitor('A'), monitor('B', {x: 1920})]);
  c.draft = {...c.draft, mode: 'individual'};
  const target = c.layout.displays[1].identity;
  c.previewTheme('nord');
  assert.equal(c.previewBackground('/omarchy/themes/nord/backgrounds/1.jpg', 'unknown'), false);
  assert.equal(c.previewBackground('/omarchy/themes/nord/backgrounds/1.jpg', target), true);
  assert.equal(c.station.argv[2], '/omarchy/themes/nord/backgrounds/1.jpg');
  c.station.done(0, '/tmp/station-test/wallpapers/a/1.jpg\n');
  assert.equal(c.station.argv[2], '/omarchy/themes/nord/backgrounds/2.jpg', 'other monitors keep the theme preview');
  c.station.done(0, '/tmp/station-test/wallpapers/b/2.jpg\n');
  assert.equal(c.draft.followTheme, false);
  assert.equal(JSON.stringify(c.draft.perDisplay), JSON.stringify({[target]: '/tmp/station-test/wallpapers/a/1.jpg'}));
  assert.equal(c.draft.source, '/tmp/station-test/wallpapers/b/2.jpg');
  assert.equal(c.pendingTheme, 'nord', 'the theme itself is still global');
});
test('Apply runs Omarchy first and saves the wallpaper only after the new theme is read', () => {
  const c = themed();
  let saved = 0;
  c.checkImages = () => { saved++ };
  c.previewTheme('nord');
  c.apply();
  assert.equal(c.busy, true);
  assert.equal(c.themeSwitch.running, true);
  assert.deepEqual(c.themeSwitch.command.slice(4), ['/home/test/.local/state/omarchy/theme-backgrounds/nord',
    '/state/current/theme/backgrounds/2.jpg', 'nord']);
  assert.equal(c.pending, undefined, 'no wallpaper job before Omarchy finishes');
  c.themeSwitchEnded(0);
  assert.equal(c.reads, 1);
  c.finishThemeSwitch(false);
  assert.equal(c.busy, true, 'a read still naming the old theme does not finish');
  c.themeName = 'nord'; c.themePath = '/state/current/theme/backgrounds/2.jpg'; c.themeKey = '["nord","/state/current/theme/backgrounds/2.jpg"]';
  c.finishThemeSwitch(false);
  assert.equal(c.pendingTheme, '');
  assert.equal(c.draft.source, '/state/current/theme/backgrounds/2.jpg');
  assert.equal(c.pending.key, '["nord","/state/current/theme/backgrounds/2.jpg"]');
  assert.equal(c.busy, true, 'the normal Apply continues');
});
test('a failed or unreported theme switch keeps the choice and frees Apply', () => {
  const c = themed();
  c.previewTheme('nord'); c.apply();
  c.themeSwitchEnded(1);
  assert.equal(c.busy, false);
  assert.equal(c.pendingTheme, 'nord');
  assert.equal(c.noticeError, true);
  c.apply(); c.themeSwitchEnded(0);
  c.finishThemeSwitch(true);
  assert.equal(c.busy, false);
  assert.equal(c.pendingTheme, 'nord');
  assert.match(c.notice, /did not report/);
});
test('a background for the current theme uses omarchy theme bg set', () => {
  const c = themed();
  c.previewBackground('/omarchy/themes/tokyo-night/backgrounds/b.jpg', '');
  c.apply();
  assert.deepEqual(c.themeSwitch.command, ['omarchy', 'theme', 'bg', 'set', '/state/current/theme/backgrounds/b.jpg']);
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
test('ListThemes.pl mirrors Omarchy\'s background order, remembered choice and repo-theme limits', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'station-themes-'));
  const make = (file, text = 'x') => { fs.mkdirSync(path.dirname(file), {recursive: true}); fs.writeFileSync(file, text); };
  const user = path.join(dir, 'user'), official = path.join(dir, 'official'), own = path.join(dir, 'own');
  const remembered = path.join(dir, 'remembered'), current = path.join(dir, 'current', 'theme');
  make(path.join(official, 'nord', 'colors.toml'));
  make(path.join(official, 'nord', 'preview.png'));
  make(path.join(official, 'nord', 'backgrounds', '1-a.jpg'));
  make(path.join(official, 'nord', 'backgrounds', '2-b.webp'));
  make(path.join(official, 'nord', 'backgrounds', '3-c.mp4'));
  make(path.join(own, 'nord', '0-mine.png'));
  make(path.join(remembered, 'nord'), path.join(current, 'backgrounds', '2-b.webp') + '\n');
  make(path.join(official, 'empty', 'backgrounds', 'intros', 'x.mp4'));
  make(path.join(user, 'cloned', '.git', 'HEAD'));
  make(path.join(user, 'cloned', 'colors.toml'));
  make(path.join(user, 'cloned', 'backgrounds', 'real.jpg'));
  make(path.join(dir, 'secret.jpg'));
  fs.symlinkSync(path.join(dir, 'secret.jpg'), path.join(user, 'cloned', 'backgrounds', 'link.jpg'));
  fs.symlinkSync(path.join(dir, 'secret.jpg'), path.join(user, 'cloned', 'preview.png'));
  make(path.join(user, 'Bad Name', 'colors.toml'));
  const run = spawnSync('perl', ['lib/wallpaper/ListThemes.pl', user, official, own, remembered, current], {encoding: 'utf8'});
  assert.equal(run.status, 0, run.stderr);
  const list = W.themeList(run.stdout);
  assert.deepEqual(list.map(theme => theme.name), ['cloned', 'nord']);
  const nord = list[1];
  assert.equal(nord.label, 'Nord');
  assert.deepEqual(nord.backgrounds.map(item => item.file), ['0-mine.png', '1-a.jpg', '2-b.webp']);
  assert.equal(nord.backgrounds[0].omarchy, path.join(own, 'nord', '0-mine.png'));
  assert.equal(nord.backgrounds[1].omarchy, path.join(current, 'backgrounds', '1-a.jpg'));
  assert.equal(nord.default, path.join(official, 'nord', 'backgrounds', '2-b.webp'));
  assert.equal(nord.preview, path.join(official, 'nord', 'preview.png'));
  const cloned = list[0];
  assert.deepEqual(cloned.backgrounds.map(item => item.file), ['real.jpg']);
  assert.equal(cloned.preview, path.join(user, 'cloned', 'backgrounds', 'real.jpg'));
  fs.rmSync(dir, {recursive: true});
});

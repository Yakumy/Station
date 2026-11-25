// The wallpaper owner's production functions on a fake composition root.
const fs = require('node:fs');
const vm = require('node:vm');
const W = require('../../lib/wallpaper/Wallpaper.js');
const M = require('../../lib/displays/Model.js');

const monitor = (name, extra = {}) => ({ name, width: 1920, height: 1080, x: 0, y: 0,
  scale: 1, transform: 0, mirrorOf: 'none', ...extra });
function layout(monitors) { return W.topology(monitors, M.identities(monitors)); }

function controller() {
  const source = fs.readFileSync('lib/wallpaper/WallpaperController.qml', 'utf8');
  const methods = source.slice(source.indexOf('  function showNotice('), source.indexOf('\n  Instantiator'));
  const c = {Tabs: require('../../lib/panel/Tabs.js'), Wallpaper: W, Qt: {callLater: () => {}}, Image: {Ready: 1, Loading: 2, Null: 0, Error: 3},
    draft: {mode: 'span', followTheme: true, source: '/tmp/image.png', perDisplay: {}, framing: W.framing({}), safe: true},
    dirty: true, busy: false, pickerBusy: false, pendingSave: false, repairPending: false,
    repairPrevious: null, repairLegacyKey: '', importBusy: false, failedLegacyKey: '',
    pickerTarget: '', serial: 0, themes: [], themeName: '', pendingTheme: '', pendingBackground: '',
    themeSwitchName: '', themeSwitchExited: false,
    themeKey: 'original', themePath: '/tmp/theme.png', themeRevision: 'revision', preferences: W.settings({}),
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
module.exports = { monitor, layout, controller };

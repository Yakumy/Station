// Read-only M0 evidence. Never reloads, dispatches, installs, or edits config.
import { spawnSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { performance } from 'node:perf_hooks';

function command(argv) {
  const start = performance.now();
  const result = spawnSync(argv[0], argv.slice(1), { encoding: 'utf8', timeout: 10000 });
  if (result.error || result.status !== 0) throw new Error(`${argv[0]} probe failed: ${result.error?.message || result.stderr || result.stdout}`);
  return { text: result.stdout.trim(), ms: performance.now() - start };
}
function json(argv) { return JSON.parse(command(argv).text); }
const files = [
  'shell.qml', 'services/PluginRegistry.qml', 'Commons/Color.qml',
  'Ui/Panel.qml', 'Ui/KeyboardPanel.qml',
  'plugins/panels/monitor/manifest.json', 'plugins/panels/monitor/Panel.qml',
  'plugins/panels/monitor/Model.js',
];
const report = { capturedAt: new Date().toISOString(), sourceHashes: {} };
for (const file of files) {
  report.sourceHashes[file] = createHash('sha256').update(readFileSync(`/usr/share/omarchy/shell/${file}`)).digest('hex');
}
report.hyprlandVersion = json(['hyprctl', 'version', '-j']).version;
report.monitors = json(['hyprctl', 'monitors', 'all', '-j']).map(m => ({
  name: m.name, width: m.width, height: m.height, scale: m.scale,
  transform: m.transform, disabled: m.disabled, mirrorOf: m.mirrorOf,
  availableModes: m.availableModes,
}));
const plugins = json(['omarchy-shell', 'shell', 'listPlugins']);
if (!Array.isArray(plugins)) throw new Error('listPlugins is not an array');
report.plugins = { shape: 'array', fields: Object.keys(plugins[0] || {}),
  stationInstalled: plugins.some(p => p.id === 'yakumy.station'),
  stockEnabled: plugins.find(p => p.id === 'omarchy.workspaces')?.enabled };
report.jq = command(['jq', '--version']).text;
// eval reports "ok" rather than serialising returned Lua values. Assertions
// test constructors without dispatching them; never confuse this with focus.
const assertions = {
  focusConstructors: 'assert(hl.dsp.focus({ workspace = "1" }) ~= nil); assert(hl.dsp.focus({ monitor = "eDP-1" }) ~= nil)',
  warmGetMonitors: 'local ok, list = pcall(hl.get_monitors); assert(ok); assert(type(list) == "table"); assert(#list > 0); for _, m in ipairs(list) do assert(type(m.name) == "string") end',
};
report.assertions = {};
for (const [name, lua] of Object.entries(assertions)) {
  const result = command(['hyprctl', 'eval', lua]).text;
  if (result !== 'ok') throw new Error(`${name}: ${result}`);
  report.assertions[name] = result;
}
const bindings = command(['omarchy', 'menu', 'keybindings', '--print']).text;
report.bindingExamples = bindings.split('\n').filter(line =>
  /Move window silently to workspace (1|10)$|Move grouped window focus (left|right)$/.test(line));
const samples = [];
for (let i = 0; i < 20; i++) {
  const result = command(['omarchy-shell', 'shell', 'ping']);
  if (!result.text) throw new Error('empty shell ping response');
  samples.push(result.ms);
}
const sorted = [...samples].sort((a, b) => a - b);
report.shellPing = { samplesMs: samples, p50Ms: sorted[9], p95Ms: sorted[18],
  note: 'CLI ping round trip only; not service routing or press-to-switch latency.' };
console.log(JSON.stringify(report, null, 2));

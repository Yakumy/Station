// Scenario tests execute production function bodies from the runtime owners.
// Owner files come first so a public Service forwarder never shadows the body.
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const root = join(__dirname, '../../..');
const owners = ['CompositorLane', 'SettingsStore', 'PanelIntent', 'StationController', 'KeybindingsController',
  'StockWidgetLeases', 'ScreenRecovery', 'BarLayerSync'];
const read = path => readFileSync(join(root, path), 'utf8');
const ownerSource = name => read(`lib/${name}.qml`);
const runtimeSource = () => [...owners.map(ownerSource), read('Service.qml')].join('\n');
module.exports = { owners, ownerSource, runtimeSource };

// Scenario tests share one flat namespace. Route owner ids and finite ports back
// into it, so each scenario still exercises the same bodies and observable state.
function adaptOwners(c) {
  for (const id of ['compositor', 'store', 'stations', 'panel', 'keybindings', 'barLayers', 'leases',
    'screenRecovery', 'windowSettings']) if (!Object.hasOwn(c, id)) c[id] = c;
  for (const [key, read] of Object.entries({
    operationState: () => c.state,
    removalGraceRunning: () => !!(c.removalGrace && c.removalGrace.running),
  })) if (!Object.hasOwn(c, key)) Object.defineProperty(c, key, { get: read, configurable: true });
  c.recordExpectedEvents ||= value => { c.expect = value; };
  c.setOperationState ||= value => { c.state = value; };
  c.reportError ||= value => { c.layoutError = value; };
  c.rememberStation ||= station => {
    c.persisted.lastStation = station;
    if (c.saveState) c.saveState();
  };
  c.continueApply ||= () => c.continuePreviewApply();
  c.continueRevert ||= () => c.continueRevertPreview();
  c.reconcile ||= undefined;
  return c;
}
module.exports.adaptOwners = adaptOwners;

// Compile one production function, one-line or multi-line, against a test context.
function qmlFunction(source, name, context) {
  const start = source.indexOf('  function ' + name + '(');
  if (start < 0) throw new Error('missing function ' + name);
  const lineEnd = source.indexOf('\n', start);
  const end = source.slice(start, lineEnd).trimEnd().endsWith('}') ? lineEnd : source.indexOf('\n  }', start) + 4;
  return require('node:vm').runInNewContext('(' + source.slice(start, end).trim() + ')', context);
}
module.exports.qmlFunction = qmlFunction;

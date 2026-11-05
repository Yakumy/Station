const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { runInNewContext } = require('node:vm');
const source = readFileSync(join(__dirname, '../../lib/bars/BarSettingsController.qml'), 'utf8');

// Compatibility adapter for pre-extraction characterization fixtures. Existing
// scenarios keep their config/host doubles; production functions now execute in
// the owner's explicit data/port surface. No whole Service is passed to it.
function ownerFunction(name, context) {
  const start = source.indexOf('  function ' + name + '(');
  if (start < 0) return null;
  const getter = (key, read) => {
    if (!Object.prototype.hasOwnProperty.call(context, key))
      Object.defineProperty(context, key, { get: read, configurable: true });
  };
  getter('preferences', () => context.config && context.config.bars || {});
  getter('displays', () => context.displayDraft || []);
  getter('hostConfig', () => context.shell && context.shell.barConfig || null);
  getter('publishHost', () => context.shell && typeof context.shell.mutateShellConfig === 'function'
    ? context.shell.mutateShellConfig.bind(context.shell) : null);
  context.persistPreferences ||= bars => {
    context.config = Object.assign({}, context.config, { bars }); context.saveConfig();
  };
  context.retainPanel ||= tab => {
    if (tab) context.rememberedTab = require('../../lib/panel/Tabs.js').index(tab);
    context.panelTransferUntil = Date.now() + 3000;
  };
  context.requestLayerSync ||= () => { context.syncBarBlur(); if (context.syncBarGaps) context.syncBarGaps(); };
  const lineEnd = source.indexOf('\n', start);
  const end = source.slice(start, lineEnd).trimEnd().endsWith('}') ? lineEnd : source.indexOf('\n  }', start) + 4;
  return runInNewContext('(' + source.slice(start, end) + ')', context);
}
module.exports = { ownerFunction, source };

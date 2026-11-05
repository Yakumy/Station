const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { runInNewContext } = require('node:vm');
const source = readFileSync(join(__dirname, '../../lib/windows/WindowSettingsController.qml'), 'utf8');

// Keep the existing temporal characterization scenarios. Only their external
// config/error/style boundaries are adapted to the owner's finite ports.
function ownerFunction(name, context) {
  const start = source.indexOf('  function ' + name + '(');
  if (start < 0) return null;
  for (const [key, read] of Object.entries({
    appliedSettings: () => context.config.windows,
    operationState: () => context.state,
  })) {
    if (!Object.prototype.hasOwnProperty.call(context, key))
      Object.defineProperty(context, key, { get: read, configurable: true });
  }
  context.publishObserved ||= windows => { context.config = Object.assign({}, context.config, { windows }); };
  context.reportError ||= message => { context.layoutError = message; };
  context.refreshStyle ||= () => { if (typeof context.Style.scheduleRefresh === 'function') context.Style.scheduleRefresh(); };
  const end = source.indexOf('\n  }', start) + 4;
  return runInNewContext('(' + source.slice(start, end) + ')', context);
}
module.exports = { ownerFunction, source };

const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { runInNewContext } = require('node:vm');
const source = readFileSync(join(__dirname, '../../../lib/WorkspaceController.qml'), 'utf8');
const baseline = readFileSync(join(__dirname, '../fixtures/pre-m5-migration.qml.txt'), 'utf8');
const names = ['reconcile', 'migrationFailed', 'migrationSaved', 'executeMigration'];

function functionFrom(text, name, context) {
  const start = text.indexOf('  function ' + name + '(');
  if (start < 0) return null;
  const lineEnd = text.indexOf('\n', start);
  const end = text.slice(start, lineEnd).endsWith('}') ? lineEnd : text.indexOf('\n  }', start) + 4;
  return runInNewContext('(' + text.slice(start, end) + ')', context);
}

// Retain the existing service/display scenarios and assertions. Adapt only
// external ports; these fixtures execute the production owner's four bodies.
function adapt(context) {
  for (const [key, read] of Object.entries({
    operationState: () => context.state,
    operationGeneration: () => context.gen,
    removalGraceRunning: () => context.removalGrace.running,
    legacyWorkspaceGrid: () => context.persisted.legacyWorkspaceGrid,
  })) {
    if (!Object.prototype.hasOwnProperty.call(context, key))
      Object.defineProperty(context, key, { get: read, configurable: true });
  }
  context.detached ||= value => JSON.parse(JSON.stringify(value));
  context.beginMigration ||= () => context.begin('migrating');
  context.setOperationState ||= value => { context.state = value; };
  context.recordExpectedEvents ||= value => { context.expect = value; };
  context.reportError ||= value => { context.layoutError = value; };
  context.setCurrentStation ||= value => { context.currentStation = value; };
  context.commitMigrationState ||= value => {
    context.persisted.legacyWorkspaceGrid = false;
    context.persisted.lastStation = value;
    context.saveState();
  };
  context.restorePreviewBaseline ||= value => { context.previewBaseline = value; };
  context.failPreview ||= value => { context.previewBusy = false; context.revertPreview(value); };
  context.focusStatements ||= (...args) => context.stationFocusStatements(...args);
  context.workspace = {
    markTopologyDirty: () => { context.topologyDirty = true; },
    clearTopologyDirty: () => { context.topologyDirty = false; },
  };
}
function ownerFunction(name, context) {
  if (!names.includes(name)) return null;
  adapt(context);
  return functionFrom(source, name, context);
}
module.exports = { source, baseline, names, functionFrom, ownerFunction, adapt };

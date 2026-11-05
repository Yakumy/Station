const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { functionFrom } = require('./workspace-owner.cjs');
const source = readFileSync(join(__dirname, '../../../lib/DisplayController.qml'), 'utf8');
const methods = [...source.matchAll(/^  function (\w+)\(/gm)].map(m => m[1]);
const privateHelpers = ['detached','validConnector','reloadPreviewToken','restorePreviewBaseline','failPreview','previewMirrorSource'];

// Keep existing Service-level scenarios and assertions. Only root effects and
// observations are adapted; every transferred body comes from the real owner.
function adapt(c) {
  for (const [key, read] of Object.entries({
    operationState: () => c.state,
    operationGeneration: () => c.gen,
    preferences: () => c.config,
    migrationPending: () => !!(c.workspaceData && c.workspaceData.pending),
  })) if (!Object.hasOwn(c,key)) Object.defineProperty(c,key,{get:read,configurable:true});
  c.beginPreview ||= () => c.begin('previewing');
  c.beginRevert ||= () => { c.gen++; };
  c.invalidatePreviewOperation ||= () => { c.gen++; c.configGeneration++; };
  c.setOperationState ||= value => { c.state=value; };
  c.reportError ||= value => { c.layoutError=value; };
  c.recordExpectedEvents ||= value => { c.expect=value; };
  c.reconcileWorkspace ||= () => c.reconcile();
  c.clearWorkspaceTopologyDirty ||= () => c.workspace.clearTopologyDirty();
  c.retainPanel ||= (screen,until) => {
    if (screen !== undefined) c.panelScreenName=screen;
    if (until !== undefined) c.panelTransferUntil=until;
  };
  c.stopTopologyTimers ||= () => { c.removalGrace.stop(); c.reloadDebounce.stop(); };
  c.publishDisplayOptions ||= options => {
    c.config.enabled=options.enabled.slice(); c.config.mode=options.mode;
    c.config.singleTarget=options.singleTarget || ''; c.config.mirrorSource=options.mirrorSource || '';
    c.config=Object.assign({},c.config);
  };
  c.saveDisplayPreferences ||= () => c.saveConfig();
  c.invalidateAppliedBinds ||= () => { c.appliedGeneration=-1; };
  c.launchWatchdog ||= () => c.Quickshell.execDetached(['sh','-c',c.Transactions.watchdog,'sh','20',c.stateDir+'/preview.token']);
  c.ready ||= () => c.maybeStart();
  c.detached ||= functionFrom(source,'detached',c);
  if (!c.displayController) {
    c.displayController={};
    for (const name of privateHelpers)
      c.displayController[name]=functionFrom(source,name,c);
    for (const name of methods.filter(n => !privateHelpers.includes(n)))
      c.displayController[name]=(...args) => c[name](...args);
    c.displayController.previewMirrorSource=functionFrom(source,'previewMirrorSource',c);
    for (const key of ['previewFound','previewLoaded','monitorsLoaded','previewObservedSignature'])
      Object.defineProperty(c.displayController,key,{get:()=>c[key],configurable:true});
  }
}
function ownerFunction(name,c) {
  if (!methods.includes(name) || privateHelpers.includes(name)) return null;
  adapt(c);
  const fn=functionFrom(source,name,c);
  return name === 'panelEvacuationTimedOut'
    ? () => fn(c.panelEvacuationPurpose,c.panelEvacuationFrom) : fn;
}
module.exports={source,methods,privateHelpers,ownerFunction,adapt};

const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync, writeFileSync, mkdtempSync, rmSync } = require('node:fs');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const { runInNewContext } = require('node:vm');
const { source, baseline, names, functionFrom, adapt } = require('./helpers/workspace-owner.cjs');
const Grid = require('../../lib/Grid.js');
const Hypr = require('../../lib/Hypr.js');
const OpenApps = require('../../lib/OpenApps.js');
const service = readFileSync('Service.qml', 'utf8');
const copy = value => JSON.parse(JSON.stringify(value));

// Both implementations use the same fake external boundaries. Journal text and
// the complete ordered effect/checkpoint trace are compared, not source layout.
function harness(implementation, journal = null) {
  const trace = [], writes = [], jobs = [];
  const c = {
    Grid, Hypr, Date: { now: () => 1000 }, state:'idle', gen:0,
    migrationPhase:'', migrationCommit:null, topologyDirty:false, migrationAttempts:0,
    migrationFocus:null, previewBaseline:null, layoutError:'', currentStation:3,
    persisted:{legacyWorkspaceGrid:false}, removalGrace:{running:false}, lanes:{A:1,B:2,C:3},
    workspaceData:journal ? JSON.parse(journal) : {mapping:{outputs:['A']},pending:null},
    target:{outputs:['A','B']}, expect:{}, panelScreenName:'A', previewBusy:true,
    clients:[1,2,3,4].map(id => ({address:'0x'+id,pid:id,initialClass:'test',monitor:'A',
      workspace:{id,name:String(id)},focusHistoryID:id === 3 ? 0 : id})),
    begin(state) { trace.push(['begin',state]); c.state = state; return ++c.gen; },
    refresh(include, done) { trace.push(['refresh',include]); jobs.push(done); },
    updateAssignments() { trace.push(['assignments']); },
    targetMapping() { trace.push(['target',copy(c.target)]); return c.target; },
    focusedClient() { return c.clients.find(row => row.focusHistoryID === 0); },
    saveState() { trace.push(['saveState',copy(c.persisted)]); },
    showStation(s) { trace.push(['show',s]); },
    stationFocusStatements(s,output) { trace.push(['focusStatements',s,output]); return []; },
    finishPreviewApply() { trace.push(['finishPreview',c.gen]); },
    revertPreview(reason) { trace.push(['revert',reason,c.previewBusy]); },
    migrationRetry:{ restart() { trace.push(['retry',500]); } },
    workspaceFile:{ setText(text) { trace.push(['write',text]); writes.push(text); } },
    evalLua(lua,done) {
      trace.push(['eval',lua,copy(c.expect)]);
      if (done) jobs.push(() => {
        if (!c.reject) {
          for (const m of lua.matchAll(/window = "address:(0x[0-9a-f]+)", workspace = (\d+), follow = false/g)) {
            const client = c.clients.find(row => row.address === m[1]);
            if (client) client.workspace = {id:Number(m[2]),name:m[2]};
          }
          for (const m of lua.matchAll(/workspace\.move\(\{ workspace = (\d+), monitor = "([ABC])"/g))
            c.clients.filter(row => row.workspace.id === Number(m[1])).forEach(row => { row.monitor = m[2]; });
        }
        done(c.reject || c.falseMoves && /workspace\.move/.test(lua) ? 1 : 0,'ok');
      });
    },
  };
  if (journal) c.previewBaseline = copy(c.workspaceData.preview || null);
  c.root = c;
  Object.defineProperty(c,'workspaceMap',{get:() => c.workspaceData.mapping});
  if (implementation === 'owner') adapt(c);
  for (const name of names) c[name] = functionFrom(implementation === 'owner' ? source : baseline,name,c);
  function checkpoint(label) {
    trace.push([label,copy({state:c.state,gen:c.gen,phase:c.migrationPhase,data:c.workspaceData,
      commit:c.migrationCommit,attempts:c.migrationAttempts,station:c.currentStation,
      error:c.layoutError,baseline:c.previewBaseline,clients:c.clients})]);
  }
  function drain() { let count=0; while (jobs.length) { assert.ok(++count<100); jobs.shift()(); } }
  function ack() { trace.push(['ack',c.migrationPhase]); c.migrationSaved(); }
  return {c,trace,writes,jobs,checkpoint,drain,ack};
}

test('workspace owner is the sole journal writer with finite ports and compatible root forwarding', () => {
  assert.doesNotMatch(service,/id: workspaceFile|id: migrationRetry/);
  assert.doesNotMatch(service,/(?:root\.)?topologyDirty\s*=/);
  assert.doesNotMatch(source,/property var (station|service|shell)\b|root\.persisted\b|IpcHandler|execDetached/);
  assert.match(source,/readonly property var snapshot: detached\(workspaceData\)/);
  assert.match(service,/readonly property var workspaceData: workspace.snapshot/);
  assert.match(service,/pending: root.workspaceData.pending/);
  assert.match(service,/workspace.clearTopologyDirty\(\)/);
  assert.equal((service.match(/workspace.markTopologyDirty\(\)/g)||[]).length,3);
  for (const name of names) {
    const calls = [];
    const fn = functionFrom(service,name,{workspace:{[name](...args) { calls.push(args); return 'forwarded'; }}});
    const args = name === 'migrationFailed' ? ['disk full'] : [];
    assert.equal(fn(...args),'forwarded'); assert.deepEqual(calls,[args]);
  }
});

const scenarios = {
  ordinary(h) { h.c.reconcile(); h.drain(); h.checkpoint('journal delayed'); h.ack(); h.drain();
    h.checkpoint('commit delayed'); h.ack(); h.drain(); },
  journalFailure(h) { h.c.reconcile(); h.drain(); h.c.migrationFailed('disk full'); h.checkpoint('failed');
    h.c.reconcile(); h.drain(); h.ack(); h.drain(); h.ack(); h.drain(); },
  commitFailure(h) { h.c.reconcile(); h.drain(); h.ack(); h.drain(); h.c.migrationFailed('commit failed');
    h.checkpoint('failed commit'); h.c.reconcile(); h.drain(); h.ack(); h.drain(); h.ack(); h.drain(); },
  rejectedRules(h) { h.c.reconcile(); h.drain(); h.c.reject=true; h.ack(); h.drain(); },
  verifiedFalseMoves(h) { h.c.falseMoves=true; scenarios.ordinary(h); },
  nestedPreview(h) { h.c.state='previewing'; h.c.gen=42;
    h.c.previewBaseline=Grid.plan(h.c.workspaceMap,h.c.workspaceMap,h.c.clients,3); scenarios.ordinary(h); },
  retryExhaustion(h) { h.c.state='previewing'; h.c.gen=42;
    for(let i=0;i<4;i++) { h.c.reconcile(); h.drain(); h.c.migrationFailed('disk full'); } },
  supersedingTopology(h) { h.c.reconcile(); h.drain(); h.ack();
    h.c.target={outputs:['B']}; h.c.topologyDirty=true; h.drain(); h.checkpoint('replan barrier');
    h.ack(); h.drain(); h.ack(); h.drain(); },
  refreshedTarget(h) { h.c.reconcile(); h.c.target={outputs:['B']}; h.drain();
    h.ack(); h.drain(); h.ack(); h.drain(); },
  lateRuleReply(h) { h.c.state='previewing'; h.c.gen=42;
    h.c.previewBaseline=Grid.plan(h.c.workspaceMap,h.c.workspaceMap,h.c.clients,3);
    h.c.reconcile(); h.drain(); h.ack();
    // A config reload has abandoned the enclosing preview while an effect runs.
    // Preserve the existing callback policy; do not invent a second generation.
    h.c.gen++; h.c.state='migrating'; h.checkpoint('changed operation');
    h.drain(); h.ack(); h.drain(); },
};
for (const [name, run] of Object.entries(scenarios)) test('pre-M5 and owner traces/serialized bytes match: '+name, () => {
  const old = harness('old'), next = harness('owner');
  run(old); run(next); old.checkpoint('final'); next.checkpoint('final');
  assert.deepEqual(next.writes,old.writes);
  assert.deepEqual(next.trace,old.trace);
});

for (const [producer,consumer] of [['old','owner'],['owner','old']]) {
  test(`partial-move journal compatibility: ${producer} -> ${consumer}`, () => {
    const original = harness(producer);
    original.c.state='previewing'; original.c.gen=42;
    original.c.previewBaseline=Grid.plan(original.c.workspaceMap,original.c.workspaceMap,original.c.clients,3);
    original.c.reconcile(); original.drain();
    const directory=mkdtempSync(join(tmpdir(),'station-m5-rollback-'));
    try {
      const path=join(directory,'workspace-map.json');
      writeFileSync(path,original.writes[0]);
      const journal=readFileSync(path,'utf8');
      const restarted=harness(consumer);
      const c=restarted.c;
      c.workspaceData={mapping:null,pending:null}; c.mappingLoaded=false;
      c.parseJson=(raw,fallback) => { try { return JSON.parse(raw); } catch { return fallback; } };
      c.parseJournal=raw => c.parseJson(raw,null);
      c.ready=c.maybeStart=() => { c.readyCount=(c.readyCount||0)+1; };
      c.text=() => journal;
      // Execute the consumer's actual FileView load handler. Real signal/disk
      // behavior is checked independently by check-workspace-fileview.py.
      const body=(consumer === 'owner' ? source : baseline).match(/onLoaded: \{([^]*?)\n    \}/)[1];
      runInNewContext('(function() {'+body+'\n})',c)();
      assert.equal(c.mappingLoaded,true); assert.equal(c.readyCount,1);
      assert.deepEqual(copy(c.previewBaseline),copy(original.c.previewBaseline));
      c.clients[1].workspace={id:3,name:'3'};
      c.reconcile(); restarted.drain(); restarted.ack(); restarted.drain();
      assert.deepEqual(copy(c.workspaceMap.outputs),['A']);
      restarted.ack(); restarted.drain();
      assert.deepEqual(copy(c.workspaceMap.outputs),['A','B']);
      assert.deepEqual(c.clients.map(c => c.workspace.id),[1,3,5,7]);
      assert.equal(c.workspaceData.pending,null); assert.equal(c.previewBaseline,null);
      assert.ok(JSON.parse(restarted.writes[0]).revision>JSON.parse(journal).revision);
      writeFileSync(path,restarted.writes.at(-1));
      assert.deepEqual(JSON.parse(readFileSync(path,'utf8')),copy(c.workspaceData));
    } finally { rmSync(directory,{recursive:true,force:true}); }
  });
}

test('pending identities keep OpenApps membership stable while IDs have partly moved', () => {
  const h=harness('owner'); h.c.reconcile(); h.drain(); h.c.clients[1].workspace={id:3,name:'3'};
  const rows=OpenApps.rows(h.c.workspaceMap,h.c.clients,'',h.c.workspaceData.pending,1,3);
  assert.equal(rows[2][0].address,'0x2');
  assert.equal(rows[3][0].address,'0x3');
  assert.deepEqual(h.c.workspaceMap.outputs,['A']);
});

test('journal snapshot and preview serialization cannot mutate original identities', () => {
  const h=harness('owner');
  h.c.previewBaseline=Grid.plan(h.c.workspaceMap,h.c.workspaceMap,h.c.clients,3);
  const original=copy(h.c.previewBaseline);
  h.c.state='previewing'; h.c.reconcile(); h.drain();
  h.c.workspaceData.preview.windows[0].station=9;
  assert.deepEqual(h.c.previewBaseline,original);
  const detached=functionFrom(source,'detached',{})(h.c.workspaceData);
  detached.mapping.outputs.push('C'); detached.pending.windows[0].station=10;
  assert.deepEqual(h.c.workspaceMap.outputs,['A']);
  assert.equal(h.c.workspaceData.pending.windows[0].station,1);
});

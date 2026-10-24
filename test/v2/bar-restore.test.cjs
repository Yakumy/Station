const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { runInNewContext } = require('node:vm');
const R = require('../../lib/Recovery.js');

const service = readFileSync(join(__dirname, '..', '..', 'Service.qml'), 'utf8');

function restoreBody() {
  const match = service.match(/function restoreStockLease\(forceShow\) \{([\s\S]*?)\n {2}\}/);
  assert.ok(match, 'restoreStockLease is defined');
  return match[1];
}

function restoreDisplayBody() {
  const match = service.match(/function restoreDisplayLease\(forceShow\) \{([\s\S]*?)\n {2}\}/);
  assert.ok(match, 'restoreDisplayLease is defined');
  return match[1];
}

function serviceFunction(name, context) {
  const start = service.indexOf('  function ' + name + '(');
  assert.notEqual(start, -1, name + ' exists');
  const end = service.indexOf('\n  }', start) + '\n  }'.length;
  assert.ok(end > start, name + ' has an end');
  return runInNewContext('(' + service.slice(start, end).trim() + '\n)', context);
}

test('workspace indicator comes back after the Station widget, not before it', () => {
  const body = restoreBody();

  // Re-enabling lands it in the centre and the lease records the pre-lease
  // spot: between the Omarchy menu mark and our widget. Park it behind us.
  assert.match(body, /"--after",\s*"yakumy\.station"/);
  // The captured section/index stays as the fallback for a bar that has
  // since dropped the Station widget, and it only runs if --after failed.
  assert.match(body, /"--section", place\.section/);
  assert.match(body, /"--index", String\(place\.index\)/);
  const after = body.indexOf('"--after"');
  const fallback = body.indexOf('"--section"');
  assert.ok(after !== -1 && after < fallback, '--after is tried first');
});

test('explicit Show enables a previously hidden workspace indicator without a lease', () => {
  const commands = [];
  const context = {
    config: { hideNative: false },
    persisted: { stockLease: null },
    stockDisable: { running: false },
    workspaceShowPending: false,
    leaseVerify: { restart() {} },
    enqueue(command, done) { commands.push(command); done(0); },
    acquireStockLeases() {},
    saveState() {},
  };
  context.root = context;
  const restore = serviceFunction('restoreStockLease', context);
  restore();
  assert.equal(commands.length, 0, 'startup does not enable an unleased widget');
  restore(true);
  assert.deepEqual(JSON.parse(JSON.stringify(commands)), [
    ['omarchy', 'plugin', 'enable', 'omarchy.workspaces'],
    ['omarchy', 'bar', 'move', 'omarchy.workspaces', '--after', 'yakumy.station'],
  ]);
  assert.equal(context.workspaceShowPending, false);
});

test('unload cleanup returns the indicator to its recorded spot', () => {
  // Station's own widget is already gone on that path, so --after
  // yakumy.station could never resolve there.
  assert.match(R.cleanup,
    /omarchy bar move omarchy\.workspaces --section "\$section" --index "\$index"/);
});

test('Display widget returns only through its recorded lease', () => {
  const body = restoreDisplayBody();
  assert.match(body, /"enable", "omarchy\.monitor"/);
  assert.match(body, /"move", "omarchy\.monitor", "--section", place\.section/);
  assert.match(body, /"--index", String\(place\.index\)/);
  assert.match(body, /if \(moveCode === 0 && lease\)/);
  assert.match(R.cleanup,
    /omarchy bar move omarchy\.monitor --section "\$display_section" --index "\$display_index"/);
});

test('explicit Show enables a previously hidden Display without creating a removal lease', () => {
  const commands = [];
  let stateSaves = 0;
  const context = {
    config: { hideDisplay: false },
    persisted: { displayLease: null },
    displayDisable: { running: false },
    displayShowPending: false,
    leaseVerify: { restart() {} },
    enqueue(command, done) { commands.push(command); done(0); },
    saveState() { stateSaves++; },
  };
  context.root = context;
  const restore = serviceFunction('restoreDisplayLease', context);
  restore();
  assert.equal(commands.length, 0, 'startup does not enable an unleased widget');
  restore(true);
  assert.deepEqual(JSON.parse(JSON.stringify(commands)), [
    ['omarchy', 'plugin', 'enable', 'omarchy.monitor'],
    ['omarchy', 'bar', 'move', 'omarchy.monitor', '--section', 'right', '--index', '5'],
  ]);
  assert.equal(context.persisted.displayLease, null);
  assert.equal(stateSaves, 0, 'explicit Show creates no removal lease');
});

test('explicit Show overrides a disabled-before-Station Display lease', () => {
  const commands = [];
  const lease = { wasEnabled: false, disabledByStation: false, section: 'left', index: 2 };
  const context = {
    config: { hideDisplay: false },
    persisted: { displayLease: lease },
    displayDisable: { running: false },
    displayShowPending: false,
    leaseVerify: { restart() {} },
    enqueue(command, done) { commands.push(command); done(0); },
    saveState() {},
  };
  context.root = context;
  serviceFunction('restoreDisplayLease', context)(true);
  assert.deepEqual(JSON.parse(JSON.stringify(commands[1])),
    ['omarchy', 'bar', 'move', 'omarchy.monitor', '--section', 'left', '--index', '2']);
  assert.equal(context.persisted.displayLease, null);
});

test('explicit Show waits for an in-flight Display disable', () => {
  const commands = [];
  const context = {
    config: { hideDisplay: false },
    persisted: { displayLease: null },
    displayDisable: { running: true },
    displayShowPending: false,
    leaseVerify: { restart() {} },
    enqueue(command, done) { commands.push(command); done(0); },
    saveState() {},
  };
  context.root = context;
  const restore = serviceFunction('restoreDisplayLease', context);
  restore(true);
  assert.equal(context.displayShowPending, true);
  assert.equal(commands.length, 0);
  context.displayDisable.running = false;
  restore(true);
  assert.equal(commands.length, 2);
  assert.equal(context.displayShowPending, false);
});

test('workspace and Display leases preserve ownership and serialize bar rebuilds', () => {
  let saves = 0;
  const context = {
    config: { hideNative: true, hideDisplay: true },
    persisted: { stockLease: null, displayLease: null },
    parseJson: JSON.parse,
    barPlacement(id) {
      return id === 'omarchy.workspaces'
        ? { section: 'left', index: 1 }
        : { section: 'right', index: 5 };
    },
    stockDisable: { running: false },
    displayDisable: { running: false },
    stockDisableAttempts: 0,
    displayDisableAttempts: 0,
    displayWidgetEnabled: null,
    workspaceWidgetEnabled: null,
    saveState() { saves++; },
  };
  const handle = serviceFunction('handleStockPlugins', context);
  handle(JSON.stringify([
    { id: 'omarchy.workspaces', enabled: true },
    { id: 'omarchy.monitor', enabled: true },
  ]));
  assert.deepEqual(JSON.parse(JSON.stringify(context.persisted.stockLease)),
    { wasEnabled: true, section: 'left', index: 1, disabledByStation: true });
  assert.deepEqual(JSON.parse(JSON.stringify(context.persisted.displayLease)),
    { wasEnabled: true, section: 'right', index: 5, disabledByStation: true });
  assert.equal(context.stockDisable.running, true);
  assert.equal(context.displayDisable.running, false, 'bar config writes are serialized');
  assert.equal(context.workspaceWidgetEnabled, true);
  assert.equal(saves, 1);

  context.stockDisable.running = false;
  handle(JSON.stringify([
    { id: 'omarchy.workspaces', enabled: false },
    { id: 'omarchy.monitor', enabled: true },
  ]));
  assert.equal(context.displayDisable.running, true);
  assert.equal(context.displayDisableAttempts, 1);
});

test('Display presence is observed even when Station is not hiding it', () => {
  const context = {
    config: { hideNative: false, hideDisplay: false },
    persisted: { stockLease: null, displayLease: null },
    parseJson: JSON.parse,
    displayWidgetEnabled: null,
    saveState() { throw new Error('no lease should be saved'); },
  };
  serviceFunction('handleStockPlugins', context)(JSON.stringify([
    { id: 'omarchy.monitor', enabled: false },
  ]));
  assert.equal(context.displayWidgetEnabled, false);
  assert.equal(context.persisted.displayLease, null);
});

test('workspace presence is observed even when Station is not hiding it', () => {
  const context = {
    config: { hideNative: false, hideDisplay: false },
    persisted: { stockLease: null, displayLease: null },
    parseJson: JSON.parse,
    workspaceWidgetEnabled: null,
    saveState() { throw new Error('no lease should be saved'); },
  };
  serviceFunction('handleStockPlugins', context)(JSON.stringify([
    { id: 'omarchy.workspaces', enabled: false },
  ]));
  assert.equal(context.workspaceWidgetEnabled, false);
  assert.equal(context.persisted.stockLease, null);
});

test('Settings can refresh Display presence only after Station starts', () => {
  const context = {
    started: false,
    pluginList: { running: false },
  };
  const refresh = serviceFunction('acquireStockLeases', context);
  refresh();
  assert.equal(context.pluginList.running, false);
  context.started = true;
  refresh();
  assert.equal(context.pluginList.running, true);
});

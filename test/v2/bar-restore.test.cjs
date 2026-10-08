const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { runInNewContext } = require('node:vm');
const R = require('../../lib/Recovery.js');

const service = readFileSync(join(__dirname, '..', '..', 'Service.qml'), 'utf8');

function restoreBody() {
  const match = service.match(/function restoreStockLease\(\) \{([\s\S]*?)\n {2}\}/);
  assert.ok(match, 'restoreStockLease is defined');
  return match[1];
}

function restoreDisplayBody() {
  const match = service.match(/function restoreDisplayLease\(\) \{([\s\S]*?)\n {2}\}/);
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
  assert.match(body, /"--section", lease\.section/);
  assert.match(body, /"--index", String\(lease\.index\)/);
  const after = body.indexOf('"--after"');
  const fallback = body.indexOf('"--section"');
  assert.ok(after !== -1 && after < fallback, '--after is tried first');
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
  assert.match(body, /"move", "omarchy\.monitor", "--section", lease\.section/);
  assert.match(body, /"--index", String\(lease\.index\)/);
  assert.match(body, /if \(moveCode !== 0\) return/);
  assert.ok(body.indexOf('moveCode !== 0') < body.indexOf('displayLease = null'),
    'the lease remains available when placement restoration fails');
  assert.match(R.cleanup,
    /omarchy bar move omarchy\.monitor --section "\$display_section" --index "\$display_index"/);
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
  assert.equal(saves, 1);

  context.stockDisable.running = false;
  handle(JSON.stringify([
    { id: 'omarchy.workspaces', enabled: false },
    { id: 'omarchy.monitor', enabled: true },
  ]));
  assert.equal(context.displayDisable.running, true);
  assert.equal(context.displayDisableAttempts, 1);
});

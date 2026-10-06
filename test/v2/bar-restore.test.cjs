const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const R = require('../../lib/Recovery.js');

const service = readFileSync(join(__dirname, '..', '..', 'Service.qml'), 'utf8');

function restoreBody() {
  const match = service.match(/function restoreStockLease\(\) \{([\s\S]*?)\n {2}\}/);
  assert.ok(match, 'restoreStockLease is defined');
  return match[1];
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

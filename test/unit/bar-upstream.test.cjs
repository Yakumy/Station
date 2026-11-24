// Station's bar is Omarchy's bar plus the differences listed in
// test/fixtures/omarchy-bar/differences.json. See docs/omarchy-bar.md.
const test = require('node:test');
const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { qmlUnits } = require('../helpers/qml-units.cjs');

const root = join(__dirname, '../..');
const read = path => readFileSync(join(root, path), 'utf8');
const fixture = name => read('test/fixtures/omarchy-bar/' + name);
const pin = JSON.parse(fixture('pin.json'));
const differences = JSON.parse(fixture('differences.json'));
const listed = Object.values(differences).flat();
// A listed parent covers everything inside it.
const covers = (entry, unit) => unit === entry || unit.startsWith(entry + '/');

test('the pinned snapshot is the Omarchy revision pin.json names', () => {
  assert.match(pin.commit, /^[0-9a-f]{40}$/);
  for (const [name, hash] of Object.entries(pin.files))
    assert.equal(createHash('sha256').update(fixture(name)).digest('hex'), hash, name);
});

test('every difference from Omarchy\'s bar is listed with its reason, and no more', () => {
  const upstream = qmlUnits(fixture('Bar.qml'));
  const ours = qmlUnits(read('lib/bars/omarchy/MonitorBar.qml'));
  assert.ok(upstream.size > 900, 'the snapshot parses: ' + upstream.size);
  const different = [...upstream].filter(([name, text]) => ours.get(name) !== text).map(([name]) => name);
  const unlisted = different.filter(name => !listed.some(entry => covers(entry, name)));
  assert.deepEqual(unlisted, [], 'Omarchy has these and Station\'s bar differs. Port them, or list the reason.');
  const stale = listed.filter(entry => !different.some(name => covers(entry, name)));
  assert.deepEqual(stale, [], 'These no longer differ. Take them off the list.');
  assert.equal(new Set(listed).size, listed.length, 'no difference is listed twice');
});

test('BarModel keeps Omarchy\'s policy untouched and only adds to it', () => {
  const marker = 'if (typeof module !== "undefined")';
  const upstream = fixture('BarModel.js');
  const ours = read('lib/bars/omarchy/BarModel.js');
  assert.equal(ours.startsWith(upstream.slice(0, upstream.indexOf(marker))), true);
  const exported = Object.keys(require(join(root, 'lib/bars/omarchy/BarModel.js')));
  for (const name of Object.keys(require(join(root, 'test/fixtures/omarchy-bar/BarModel.js'))))
    assert.ok(exported.includes(name), name);
});

test('the parity check sees a changed, a missing and an unchanged member', () => {
  const a = 'Item {\n  id: root\n  property int size: 1\n  function go() {\n    return 1\n  }\n  component Part: Item {\n    width: 1\n  }\n}\n';
  const b = a.replace('return 1', 'return 2').replace('    width: 1\n', '');
  const before = qmlUnits(a), after = qmlUnits(b);
  assert.deepEqual([...before].filter(([name, text]) => after.get(name) !== text).map(([name]) => name), ['go()', 'Part/width']);
});

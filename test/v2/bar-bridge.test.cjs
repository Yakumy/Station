const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { runInNewContext } = require('node:vm');

function bridge() {
  const source = readFileSync(join(__dirname, '../../lib/BarBridge.js'), 'utf8');
  const context = {};
  runInNewContext(source.replace(/^\.pragma library\s*/, ''), context);
  return context;
}

test('the frozen bridge exposes only snapshot and closed, synchronous actions', () => {
  const b = bridge();
  const service = { count: 0 };
  const calls = [];
  const api = b.publish(() => ({ count: service.count }), {
    setSetting(name, value) { calls.push([name, value]); return 'ok'; },
    notAnAction: service,
  });
  assert.deepEqual(Object.keys(api), ['snapshot', 'call']);
  assert.equal(Object.isFrozen(api), true);
  assert.ok(Object.values(api).every(value => value !== service));
  assert.equal(b.current(), api);
  assert.equal(api.snapshot().count, 0);
  service.count = 3;
  assert.equal(api.snapshot().count, 3, 'read fresh data on every snapshot');
  assert.notEqual(api.snapshot(), api.snapshot());
  assert.equal(api.call('setSetting', ['x', 1]), 'ok');
  for (const key of ['unknown', 'constructor', '__proto__', 'toString', 'notAnAction'])
    assert.equal(api.call(key, ['x', 2]), undefined);
  assert.deepEqual(calls, [['x', 1]]);
});

test('clear and replacement retire snapshots and actions without clearing a newer service', () => {
  const b = bridge();
  let calls = 0;
  const old = b.publish(() => ({}), { act() { calls++; } });
  const next = b.publish(() => ({ generation: 2 }), { act() { calls++; } });
  b.clear(old);
  assert.equal(b.current(), next);
  assert.equal(old.snapshot(), null);
  assert.equal(old.call('act'), undefined);
  assert.equal(calls, 0);
  assert.equal(next.snapshot().generation, 2);
  next.call('act', 'not an array');
  assert.equal(calls, 1);
  b.clear(next);
  assert.equal(b.current(), null);
  assert.equal(next.snapshot(), null);
  next.call('act', []);
  assert.equal(calls, 1);
});

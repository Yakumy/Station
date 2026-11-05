import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';

const shellPath = '/usr/share/omarchy/shell/shell.qml';
const registryPath = '/usr/share/omarchy/shell/services/PluginRegistry.qml';
const installed = existsSync(shellPath) && existsSync(registryPath);
// Run the installed host's actual JS functions with controlled host objects.
// This proves routing/index semantics, not QML loading or desktop behaviour.
function extract(path, name) {
  const source = readFileSync(path, 'utf8');
  const start = source.indexOf(`  function ${name}(`);
  assert.notEqual(start, -1, `missing ${name}`);
  const end = source.indexOf('\n  }', start);
  assert.notEqual(end, -1);
  return source.slice(start, end + 4);
}

test('M0: shell call targets a loaded panel, not an own service', { skip: !installed }, () => {
  let calls = 0;
  const service = { switchStation: arg => { calls++; return arg; } };
  const host = {
    shell: { pluginRegistry: { resolveEnabledId: id => id }, serviceFor: () => service },
    panelLoaders: {}, console,
  };
  const call = runInNewContext(`(${extract(shellPath, 'callIfLoaded')})`, host);
  assert.equal(call('yakumy.station', 'switchStation', '2'), 'unknown');
  assert.equal(calls, 0);
  host.panelLoaders['yakumy.station'] = { item: { switchStation: arg => service.switchStation(arg) } };
  assert.equal(call('yakumy.station', 'switchStation', '2'), '2');
  assert.equal(calls, 1);
  delete host.panelLoaders['yakumy.station'];
  assert.equal(call('yakumy.station', 'switchStation', '2'), 'unknown');
});

test('M0: explicit bar indexes are zero-based and clamped', { skip: !installed }, () => {
  const target = runInNewContext(`(${extract(registryPath, 'barTarget')})`, {});
  const config = { bar: { layout: { left: [{ id: 'omarchy.menu' }, { id: 'omarchy.workspaces' }] } } };
  assert.equal(target(config, { section: 'left', index: 1 }, 'center').index, 1);
  assert.equal(target(config, { section: 'left', index: -4 }, 'center').index, 0);
  assert.equal(target(config, { section: 'left', index: 99 }, 'center').index, 2);
});

test('M0: bar put never relocates an already-present widget', { skip: !installed }, () => {
  let enabled = false;
  const put = runInNewContext(`(${extract(registryPath, 'putBarWidget')})`, {
    inBar: () => true,
    setEnabled: () => { enabled = true; },
  });
  assert.equal(put('omarchy.workspaces', { section: 'right', index: 1 }), '');
  assert.equal(enabled, false);
});

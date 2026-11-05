import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, readFileSync, readdirSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';

const compiler = resolve('test/lint/compile-qml.py');
function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'station-discovery-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const write = (name, text = 'import QtQuick\nItem {}\n') => {
    mkdirSync(join(root, name, '..'), { recursive: true });
    writeFileSync(join(root, name), text);
  };
  const manifest = { id: 'yakumy.station', kinds: ['service', 'bar-widget', 'bar'],
    entryPoints: { service: 'Service.qml', barWidget: 'Panel.qml', bar: 'Bar.qml' } };
  write('manifest.json', JSON.stringify(manifest));
  for (const name of Object.values(manifest.entryPoints)) write(name);
  return { root, write, manifest };
}
function list(root) {
  const result = spawnSync('python3', [compiler, root, '--list'], {
    encoding: 'utf8', env: { ...process.env, WAYLAND_DISPLAY: '', XDG_RUNTIME_DIR: '' }, timeout: 10000,
  });
  return { ...result, files: result.status === 0 ? JSON.parse(result.stdout) : [] };
}
function requireFiles(actual, required) {
  for (const name of required) assert.ok(actual.includes(name), 'omitted QML: ' + name);
}

test('QML discovery includes manifest entries, all root QML and recursive runtime subtrees without Wayland', t => {
  const { root, write, manifest } = fixture(t);
  for (const name of ['Extra.qml', 'lib/Card.qml', 'lib/feature/deep/Control.qml',
    'feature/Entry.qml', 'feature/internal/Helper.qml', 'tools/Unsafe.qml', 'docs/Example.qml']) write(name);
  manifest.entryPoints.overlay = 'feature/Entry.qml';
  write('manifest.json', JSON.stringify(manifest));
  const result = list(root);
  assert.equal(result.status, 0, result.stderr);
  const expected = ['Bar.qml', 'Extra.qml', 'Panel.qml', 'Service.qml', 'feature/Entry.qml',
    'feature/internal/Helper.qml', 'lib/Card.qml', 'lib/feature/deep/Control.qml'];
  assert.deepEqual(result.files, expected);
  requireFiles(result.files, expected);
  // Verify the completeness assertion itself rejects both historical failure modes.
  for (const omitted of ['Bar.qml', 'Extra.qml', 'lib/feature/deep/Control.qml'])
    assert.throws(() => requireFiles(result.files.filter(name => name !== omitted), expected), /omitted QML/);
});

test('the current repository compile list covers every manifest entry and recursively inventoried library QML', () => {
  const result = list(resolve('.'));
  assert.equal(result.status, 0, result.stderr);
  const expected = new Set(Object.values(JSON.parse(readFileSync('manifest.json', 'utf8')).entryPoints));
  for (const name of readdirSync('.')) if (name.endsWith('.qml')) expected.add(name);
  const walk = directory => {
    for (const item of readdirSync(directory, { withFileTypes: true })) {
      const path = directory + '/' + item.name;
      if (item.isDirectory()) walk(path);
      else if (item.name.endsWith('.qml')) expected.add(path);
    }
  };
  walk('lib');
  assert.deepEqual(result.files, [...expected].sort());
  requireFiles(result.files, ['Service.qml', 'Panel.qml', 'Bar.qml']);
});

test('discovery fails closed for missing declared entry points and unsafe manifest paths', t => {
  const { root, write, manifest } = fixture(t);
  rmSync(join(root, 'Bar.qml'));
  assert.match(list(root).stderr, /Missing or non-QML entry point: Bar.qml/);
  write('Bar.qml');
  for (const entry of ['../outside.qml', '/outside.qml', 'lib/../Bar.qml', 'lib\\Bar.qml', 'lib//Bar.qml']) {
    manifest.entryPoints.bar = entry;
    write('manifest.json', JSON.stringify(manifest));
    const result = list(root);
    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /Unsafe QML entry point/);
  }
  delete manifest.entryPoints.bar;
  write('manifest.json', JSON.stringify(manifest));
  assert.match(list(root).stderr, /Missing declared entry point: bar/);
});

test('discovery rejects symlinked files and directories rather than following or silently omitting them', t => {
  const { root, write } = fixture(t);
  write('external/Hidden.qml');
  mkdirSync(join(root, 'lib'));
  symlinkSync(join(root, 'external'), join(root, 'lib/linked'));
  assert.match(list(root).stderr, /Refusing symlink/);
  rmSync(join(root, 'lib/linked'));
  symlinkSync(join(root, 'external/Hidden.qml'), join(root, 'lib/Hidden.qml'));
  assert.match(list(root).stderr, /Refusing symlink/);
});

test('compilation harness uses the complete discovered list and fails on compile errors or missing readiness', t => {
  const { root, write } = fixture(t);
  write('lib/nested/Control.qml');
  // Import the production tool, replace only session/process boundaries. No Qt,
  // compositor, production QML object or real Wayland socket is created here.
  const program = `
import importlib.util, json, re
from pathlib import Path
from unittest.mock import patch
spec = importlib.util.spec_from_file_location('qml_check', ${JSON.stringify(compiler)})
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
root = Path(${JSON.stringify(root)})
names = m.discover_components(root)
def unreadable_walk(*args, **kwargs):
    kwargs['onerror'](PermissionError('unreadable runtime subtree'))
    return iter(())
with patch.object(m.os, 'walk', unreadable_walk):
    try: m.discover_components(root)
    except PermissionError: pass
    else: raise AssertionError('unreadable subtree silently omitted')
outputs = ['STATION_COMPONENTS_READY', 'STATION_COMPONENTS_READY\\nSTATION_COMPILE_FAILED broken', 'no readiness']
seen = []
class Process:
    def __init__(self, argv, **kwargs):
        harness = (Path(argv[-1]) / 'shell.qml').read_text()
        targets = json.loads(re.search(r'for \\(var name of (.+)\\)', harness).group(1))
        assert targets == names
        assert 'Bar.qml' in targets and 'lib/nested/Control.qml' in targets
        assert 'Qt.createComponent(' in harness
        assert 'createObject(' not in harness
        assert kwargs['env']['QT_QPA_PLATFORM'] == 'wayland'
        seen.append(targets)
    def communicate(self, **kwargs): return (outputs.pop(0), None)
    def poll(self): return 0
with patch.object(m.socket, 'socket'), patch.object(m.subprocess, 'Popen', Process), patch.dict(m.os.environ, {'WAYLAND_DISPLAY': '/fake/socket'}):
    m.compile_components(root, names)
    for _ in range(2):
        try: m.compile_components(root, names)
        except SystemExit as error: assert error.code == 1
        else: raise AssertionError('compile failure incorrectly passed')
assert len(seen) == 3
`;
  const result = spawnSync('python3', ['-c', program], { encoding: 'utf8', timeout: 10000 });
  assert.equal(result.status, 0, result.stdout + result.stderr);
});

test('compile CLI refuses inaccessible Wayland before launching Quickshell', t => {
  const { root } = fixture(t);
  const result = spawnSync('python3', [compiler, root], { encoding: 'utf8', timeout: 10000,
    env: { ...process.env, WAYLAND_DISPLAY: 'missing-socket', XDG_RUNTIME_DIR: root } });
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /QML check needs access to the Wayland socket/);
  assert.doesNotMatch(result.stdout + result.stderr, /Launching config|quickshell has crashed/i);
});

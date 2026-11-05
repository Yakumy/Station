import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, mkdirSync, writeFileSync, rmSync, symlinkSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { spawnSync } from 'node:child_process';
const scanner = resolve('test/lint/theme-tokens.mjs');

function fixture(t) {
  const root = mkdtempSync(join(tmpdir(), 'station-runtime-theme-'));
  t.after(() => rmSync(root, { recursive: true, force: true }));
  const write = (name, text) => {
    mkdirSync(join(root, name, '..'), { recursive: true });
    writeFileSync(join(root, name), text);
  };
  write('manifest.json', JSON.stringify({ entryPoints: {
    service: 'Service.qml', barWidget: 'Panel.qml', bar: 'Bar.qml', overlay: 'feature/Entry.qml',
  } }));
  const run = explicit => spawnSync(process.execPath, [scanner, ...(explicit ? [root] : [])], {
    cwd: root, encoding: 'utf8', timeout: 10000,
  });
  return { root, write, run };
}
const good = 'Rectangle { color: Color.popups.background; radius: Style.cornerRadius }';
const bad = 'Rectangle { color: "#abc123" }';

test('repository theme scan catches violations in every runtime root, nested library and non-branding asset', t => {
  const { write, run } = fixture(t);
  const runtime = ['Service.qml', 'Panel.qml', 'Bar.qml', 'Future.qml', 'Generated.js',
    'lib/nested/deep/Card.qml', 'lib/nested/Policy.js', 'feature/Entry.qml',
    'feature/internal/Helper.qml', 'assets/new-icon.svg'];
  for (const name of runtime) write(name, good);
  // Docs, test fixtures and developer media may legitimately contain palettes.
  for (const name of ['docs/Example.qml', 'test/Fixture.qml', 'tools/Fixture.qml', 'videos/intro/Art.svg']) write(name, bad);
  assert.equal(run().status, 0);
  for (const name of runtime) {
    write(name, bad);
    const result = run();
    assert.equal(result.status, 1, name + ': ' + result.stdout + result.stderr);
    assert.ok(result.stderr.includes(name), name + ': ' + JSON.stringify(result));
    write(name, good);
  }
});

test('only exact approved branding SVGs are excluded in repository mode; explicit-root mode stays strict', t => {
  const { write, run } = fixture(t);
  write('Bar.qml', good);
  write('assets/station-main-logo.svg', '<svg fill="#A6B465"/>');
  write('assets/station-main-logo-mask.svg', '<svg fill="white"/>');
  assert.equal(run().status, 0, 'approved Station artwork is not a runtime UI palette');
  assert.equal(run(true).status, 1, 'whole-tree fixture mode retains hex checks');
  write('assets/nested/station-main-logo.svg', '<svg fill="#A6B465"/>');
  assert.equal(run().status, 1, 'same basename in a different location is not exempt');
});

test('theme scan refuses runtime symlinks, including exempt artwork and the manifest', t => {
  const { root, write, run } = fixture(t);
  write('lib/Good.qml', good);
  symlinkSync(join(root, 'lib/Good.qml'), join(root, 'lib/Linked.qml'));
  const result = run();
  assert.match(result.stderr, /Refusing symlink/, JSON.stringify(result));
  rmSync(join(root, 'lib/Linked.qml'));
  mkdirSync(join(root, 'assets'));
  symlinkSync(join(root, 'lib/Good.qml'), join(root, 'assets/station-main-logo.svg'));
  assert.match(run().stderr, /Refusing symlink/);
  rmSync(join(root, 'assets/station-main-logo.svg'));
  write('manifest-copy.json', '{"entryPoints":{"bar":"Bar.qml"}}');
  rmSync(join(root, 'manifest.json'));
  symlinkSync(join(root, 'manifest-copy.json'), join(root, 'manifest.json'));
  assert.match(run().stderr, /Refusing symlink/);
});

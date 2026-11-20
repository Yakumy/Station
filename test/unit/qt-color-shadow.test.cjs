// GitHub issue #24: Qt 6.12 adds a QtQuick `Color` singleton. Every QML file imports
// QtQuick, so a bare `Color.` can resolve to Qt's type instead of Omarchy's theme
// colors. Station reaches the theme only through `Commons.Color`.
const test = require('node:test');
const assert = require('node:assert/strict');
const { readdirSync, readFileSync, statSync } = require('node:fs');
const { join, relative } = require('node:path');

const root = join(__dirname, '../..');
function qmlFiles(dir) {
  return readdirSync(dir).flatMap(name => {
    const path = join(dir, name);
    if (statSync(path).isDirectory()) return qmlFiles(path);
    return name.endsWith('.qml') ? [path] : [];
  });
}

test('theme colors are always reached through the Commons namespace', () => {
  const files = [...qmlFiles(join(root, 'lib')),
    ...readdirSync(root).filter(name => name.endsWith('.qml')).map(name => join(root, name))];
  assert.ok(files.length > 50);
  const bare = [];
  for (const file of files) {
    const text = readFileSync(file, 'utf8');
    text.split('\n').forEach((line, index) => {
      const code = line.replace(/\/\/.*$/, '');
      if (/(?<![A-Za-z0-9_."])Color\./.test(code)) bare.push(`${relative(root, file)}:${index + 1}`);
    });
    if (/(?<![A-Za-z0-9_."])Commons\.Color\./.test(text))
      assert.match(text, /^import qs\.Commons as Commons$/m, relative(root, file));
  }
  assert.deepEqual(bare, []);
});

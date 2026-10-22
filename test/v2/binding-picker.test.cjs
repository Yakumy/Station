const test = require('node:test');
const assert = require('node:assert/strict');
const { readFileSync, readdirSync } = require('node:fs');

test('Station runtime has no native editable input or clipboard API, including hidden controls', () => {
  const files = ['Panel.qml', 'Service.qml', ...readdirSync('lib')
    .filter(name => /\.(qml|js)$/.test(name)).map(name => 'lib/' + name)];
  for (const file of files) {
    const source = readFileSync(file, 'utf8').replace(/\/\/[^\n]*|\/\*[\s\S]*?\*\//g, '');
    assert.doesNotMatch(source, /\b(?:TextField|TextInput|TextEdit|TextArea|Clipboard)\b/, file);
  }
});

test('the conflict picker updates only the draft and is gated by the open Keybindings tab', () => {
  const source = readFileSync('lib/KeybindingsTab.qml', 'utf8');
  assert.match(source, /available: .*\.opened && .*\.selectedTab === 3/);
  assert.match(source, /onPicked: function\(key\) \{ .*\.editingKey = key \}/);
  assert.match(source, /text: "Cancel"[\s\S]*?editingBindingId = ""/);
});

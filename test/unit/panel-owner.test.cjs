const test = require('node:test');
const { runtimeSource, libPath } = require('../helpers/runtime-source.cjs');
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { runInNewContext } = require('node:vm');
const read = name => readFileSync(name, 'utf8');
const panel = read('lib/panel/StationPanel.qml');
const session = read('lib/panel/PanelSession.qml');
const controls = read('lib/displays/DisplayControls.qml');
const keys = read('lib/keybindings/KeybindingsTab.qml');
const Tabs = require('../../lib/panel/Tabs.js');
const Binds = require('../../lib/keybindings/Binds.js');
const copy = value => JSON.parse(JSON.stringify(value));
test('panel session and local editors stay widget-local', () => {
  assert.match(panel, /PanelUi\.PanelSession/); assert.match(panel, /Displays\.DisplayControls/);
  assert.doesNotMatch(runtimeSource(), /PanelSession|DisplayControls/);
  assert.doesNotMatch(panel, /function (?:tryRestorePanel|setBrightness|beginBindingEdit)\(/);
  for (const name of ['DisplaysTab','BarTab','WindowsTab','WallpaperTab','KeybindingsTab','SettingsTab',
    'DisplayLayout','BarLayout','WindowsLayout']) assert.doesNotMatch(read(libPath(name+'.qml')), /panelRoot/);
  const tokens = panel.match(/QtObject \{\n    id: panelTokens[\s\S]*?\n  \}/)[0];
  assert.doesNotMatch(tokens, /service|session|function|\bbar\b/);
  assert.doesNotMatch(session+controls, /import .*BarBridge|execDetached|hyprctl|Transactions/);
  for (const [port, consumers] of [
    ['displaysTabPort', ['DisplaysTab', 'DisplayLayout']], ['barTabPort', ['BarTab', 'BarLayout']],
    ['windowsTabPort', ['WindowsTab', 'WindowsLayout']], ['keybindingsTabPort', ['KeybindingsTab']],
    ['settingsTabPort', ['SettingsTab']], ['panelIntent', ['PanelSession']],
  ]) {
    const source = consumers.map(name => read(libPath(name+'.qml'))).join('\n');
    const consumed = new Set([...source.matchAll(/\bservice\.(\w+)/g)].map(m => m[1]));
    if (port === 'panelIntent') consumed.add('acknowledgePanelEvacuation');
    // Use literal block boundaries so the check is independent of QML naming conventions.
    const start = panel.indexOf('    id: '+port+'\n');
    const block = panel.slice(start, panel.indexOf('\n  }', start));
    const exposed = new Set([...block.matchAll(/(?:property \w+|function) (\w+)/g)].map(m => m[1]));
    assert.deepEqual([...exposed].sort(), [...consumed].sort(), port+' covers precisely its consumers');
  }
});
test('all finite tab ports preserve arguments and synchronous results on direct and bridge paths', () => {
  const blocks = [...panel.matchAll(/  QtObject \{\n    id: (panelIntent|\w+TabPort)\n([\s\S]*?)\n  \}/g)];
  assert.equal(blocks.length,6);
  let calls=0;
  for (const [,id,source] of blocks) for (const [,name,args,code] of source.matchAll(/function (\w+)\(([^)]*)\) \{([^\n]*)\}/g)) {
    for (const bridge of [false,true]) {
      const values=args ? args.split(',').map((_,i)=>i+'-value') : [];
      const target={ [name](...actual){assert.deepEqual(actual,values);calls++;return 'result';} };
      const context={root:{service:bridge ? new Proxy({}, {get:(_,member)=>(...a)=>target[member](...a)}) : target}};
      const fn=runInNewContext('(function('+args+'){'+code+'})',context);
      assert.equal(fn(...values),'result',id+'.'+name);
      context.root.service=null;assert.equal(fn(...values),undefined);
    }
  }
  assert.ok(calls>=60);
});

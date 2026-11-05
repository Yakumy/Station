// Runs Omarchy's real per-monitor workspace module under a fake compositor. It shows
// what its reconcile does to Station's numbering, and that the authority line stops it.
const test = require('node:test');
const assert = require('node:assert/strict');
const { existsSync, mkdtempSync, rmSync, writeFileSync } = require('node:fs');
const { spawnSync } = require('node:child_process');
const { tmpdir } = require('node:os');
const { join } = require('node:path');
const Hypr = require('../../lib/platform/Hypr.js');

const omarchy = process.env.OMARCHY_PATH || '/usr/share/omarchy';
const module_ = join(omarchy, 'default/hypr/monitor-workspaces.lua');
const lua = spawnSync('lua5.4', ['-v']).status === 0;

const fake = String.raw`
local script, state = arg[1], arg[2]
local log = {}
local monitors = {
  { id = 0, name = "eDP-1", description = "panel", focused = false },
  { id = 1, name = "HDMI-A-2", description = "lenovo", focused = true },
}
local byName = { ["eDP-1"] = monitors[1], ["HDMI-A-2"] = monitors[2] }
local spaces = {}
local function space(id, monitor, windows)
  spaces[id] = { id = id, name = tostring(id), special = false, windows = windows, monitor = byName[monitor] }
end
-- Station's two-output map: HDMI owns odd workspaces, eDP even ones.
space(1, "HDMI-A-2", 2); space(2, "eDP-1", 1); space(5, "HDMI-A-2", 1)
monitors[1].active_workspace = spaces[2]
monitors[2].active_workspace = spaces[1]
monitors[1].set_workspace = function() end
monitors[2].set_workspace = function() end
local handlers = {}
hl = {
  get_monitors = function() return monitors end,
  get_monitor = function(name) return byName[name] end,
  get_active_monitor = function() return monitors[2] end,
  get_active_window = function() return nil end,
  get_active_workspace = function() return monitors[2].active_workspace end,
  get_window = function() return nil end,
  get_workspace = function(id) return spaces[tonumber(id)] end,
  get_workspaces = function()
    local out = {}
    for _, value in pairs(spaces) do out[#out + 1] = value end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
  end,
  on = function(name, fn) handlers[name] = fn end,
  timer = function() end,
  dispatch = function(action) if type(action) == "function" then action() end end,
  dsp = {
    focus = function() return function() end end,
    workspace = {
      move = function() return function() end end,
      change_id = function(args) return function()
        local old, id = tonumber(args.workspace), args.id
        log[#log + 1] = old .. "->" .. id
        spaces[id] = spaces[old]; spaces[id].id = id; spaces[id].name = tostring(id); spaces[old] = nil
      end end,
    },
  },
}
o = { bind_expressions = {}, shell_quote = function(value) return "'" .. value .. "'" end }
package.preload["default.hypr.paths"] = function() return { state_home = state } end
dofile(script)
if arg[3] ~= "" then load(arg[3])() end
handlers["config.reloaded"]()
print(table.concat(log, ","))
`;

function reconcile(authority) {
  const dir = mkdtempSync(join(tmpdir(), 'station-authority-'));
  try {
    const harness = join(dir, 'harness.lua');
    writeFileSync(harness, fake);
    const run = spawnSync('lua5.4', [harness, module_, dir, authority], { encoding: 'utf8' });
    assert.equal(run.status, 0, run.stderr);
    return run.stdout.trim();
  } finally { rmSync(dir, { recursive: true, force: true }); }
}

test('a reload renumbers a station workspace on the second monitor into station 6', { skip: !lua || !existsSync(module_) }, () => {
  const moves = reconcile('').split(',');
  assert.ok(moves.includes('1->11'), moves.join());
  assert.ok(moves.includes('5->15'), moves.join());
});

test('the authority line leaves station workspaces alone', { skip: !lua || !existsSync(module_) }, () => {
  assert.equal(reconcile(Hypr.workspaceAuthority()), '');
});

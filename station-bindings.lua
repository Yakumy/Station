-- Station v1.0.0
--
-- Quattro / Hyprland 0.56.x integration layer.
-- The CLI owns state and migration logic. This Lua file is deliberately small:
--   1) it reapplies workspace->monitor rules after every Hyprland reload;
--   2) it registers Station bindings only while Station is enabled;
--   3) it observes monitor topology and asks the CLI to reconcile it.

local HOME = os.getenv("HOME")
local STATION = HOME .. "/.local/bin/station"
local STATE = HOME .. "/.local/state/station/state.json"

local function exec(command)
  hl.dispatch(hl.dsp.exec_cmd(STATION .. " " .. command))
end

local function read_text(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local text = file:read("*a")
  file:close()
  return text
end

local function json_string(text, key)
  if not text then return nil end
  return text:match('"' .. key .. '"%s*:%s*"([^"]*)"')
end

local function json_bool(text, key)
  if not text then return false end
  return text:match('"' .. key .. '"%s*:%s*true') ~= nil
end

local function json_number(text, key, default)
  if not text then return default end
  return tonumber(text:match('"' .. key .. '"%s*:%s*(-?%d+)')) or default
end

local function station_state()
  local text = read_text(STATE)
  if not text or not json_bool(text, "enabled") then return nil end
  return {
    mode = json_string(text, "mode") or "dual",
    singleRole = json_string(text, "singleRole"),
    primary = json_string(text, "primary"),
    secondary = json_string(text, "secondary"),
    stations = json_number(text, "stations", 5),
  }
end

local function apply_workspace_rules(state)
  if not state or not state.primary or not state.secondary then return end

  if state.mode == "single" then
    local monitor = state.singleRole == "secondary" and state.secondary or state.primary
    for station = 1, state.stations do
      hl.workspace_rule({
        workspace = tostring(station),
        monitor = monitor,
        persistent = true,
      })
    end
    return
  end

  for station = 1, state.stations do
    hl.workspace_rule({
      workspace = tostring(station * 2 - 1),
      monitor = state.primary,
      persistent = true,
    })
    hl.workspace_rule({
      workspace = tostring(station * 2),
      monitor = state.secondary,
      persistent = true,
    })
  end
end

local function bind(key, command, description)
  hl.bind(
    key,
    hl.dsp.exec_cmd(STATION .. " " .. command),
    {
      description = description,
    }
  )
end

local state = station_state()
apply_workspace_rules(state)

bind(
  "CTRL + SUPER + RIGHT",
  "switch right",
  "Station next/previous (direction-aware)"
)

bind(
  "CTRL + SUPER + LEFT",
  "switch left",
  "Station previous/next (direction-aware)"
)


  for station = 1, 5 do
    bind("CTRL + SUPER + F" .. station, "switch " .. station, "Switch to Station " .. station)
    bind("SHIFT + CTRL + SUPER + F" .. station, "move " .. station, "Move window to Station " .. station)
    bind("SHIFT + SUPER + ALT + F" .. station, "move-silent " .. station, "Move window silently to Station " .. station)
  end

  for _, direction in ipairs({ "LEFT", "RIGHT", "UP", "DOWN" }) do
    bind("SHIFT + CTRL + SUPER + " .. direction,
      "move-dir " .. string.lower(direction),
      "Station directional window move")
  end


-- Hotplug hooks. The CLI no-ops when Station is disabled or not initialized.
hl.on("monitor.removed", function(_)
  exec("hotplug removed")
end)

hl.on("monitor.added", function(_)
  exec("hotplug added")
end)

hl.on("hyprland.start", function()
  exec("reconcile")
end)

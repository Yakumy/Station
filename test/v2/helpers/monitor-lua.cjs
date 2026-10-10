const { execFileSync } = require('node:child_process');

// Execute the generated configuration in real Lua, with no compositor access.
// A regex over source would incorrectly apply both sides of an if/else.
function monitorRules(source, discovery = 'function() return {{name="eDP-1"}, {name="HDMI-A-2"}} end') {
  const script = `
hl = {
  env = function() end,
  get_monitors = ${discovery},
  monitor = function(rule)
    local fields = {}
    for _, key in ipairs({"output", "mode", "position", "scale", "transform", "disabled", "mirror"}) do
      local value = rule[key]
      if value ~= nil then
        fields[#fields + 1] = key .. " = " .. (type(value) == "string" and string.format("%q", value) or tostring(value))
      end
    end
    print("hl.monitor({ " .. table.concat(fields, ", ") .. " })")
  end
}
${source}
`;
  return execFileSync('lua', ['-'], { input: script, encoding: 'utf8', timeout: 5000 })
    .trim().split('\n').filter(Boolean);
}

module.exports = { monitorRules };

var START = "-- >>> station (managed; edited by the Station panel) >>>"
var END = "-- <<< station <<<"
var CONNECTOR = /^[A-Za-z0-9_.:-]{1,64}$/
var SCALES = [1, 1.25, 1.6, 2, 3, 4]

function connector(value) {
  value = String(value || "")
  if (!CONNECTOR.test(value)) throw new Error("invalid connector")
  return value
}

function luaString(value) {
  return '"' + String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')
    .replace(/\n/g, "\\n").replace(/\r/g, "\\r") + '"'
}

function integer(value, minimum, maximum, label) {
  var number = Number(value)
  if (!Number.isInteger(number) || number < minimum || number > maximum) throw new Error("invalid " + label)
  return number
}

function validateDisplay(display) {
  var name = connector(display.name)
  var available = Array.isArray(display.availableModes) ? display.availableModes.map(String) : []
  var mode = String(display.mode || "")
  if (available.indexOf(mode) === -1) throw new Error("mode is not available on " + name)
  var scale = Number(display.scale)
  if (SCALES.indexOf(scale) === -1) throw new Error("invalid scale")
  return {
    name: name, mode: mode,
    x: integer(display.x, -100000, 100000, "x"),
    y: integer(display.y, -100000, 100000, "y"),
    scale: scale,
    transform: integer(display.transform || 0, 0, 7, "transform"),
    enabled: display.enabled !== false,
    lane: integer(display.lane, 1, 3, "lane")
  }
}

function monitorRule(display, extras) {
  var fields = ["output = " + luaString(display.name)]
  if (!extras || extras.geometry !== false) {
    fields.push("mode = " + luaString(display.mode))
    fields.push("position = " + luaString(display.x + "x" + display.y))
    fields.push("scale = " + display.scale)
    fields.push("transform = " + display.transform)
  }
  if (extras && extras.disabled !== undefined) fields.push("disabled = " + (extras.disabled ? "true" : "false"))
  if (extras && extras.mirror !== undefined) fields.push("mirror = " + luaString(extras.mirror))
  return "hl.monitor({ " + fields.join(", ") + " })"
}

function geometryLines(displays) {
  return displays.map(function(display) { return monitorRule(display) })
}

function runtimeLines(displays, options) {
  var mode = options.mode || "extend"
  var enabledNames = Array.isArray(options.enabled) ? options.enabled : displays.map(function(d) { return d.name })
  var enabled = displays.filter(function(display) { return enabledNames.indexOf(display.name) !== -1 })
  if (!enabled.length) enabled = displays.slice()
  var lines = []
  if (mode === "single") {
    var target = connector(options.singleTarget)
    if (!displays.some(function(display) { return display.name === target })) throw new Error("single target is not connected")
    lines.push("if up[" + luaString(target) + "] then")
    // Bring the destination up before removing the current sole output.
    lines.push("  " + monitorRule(displays.find(function(display) { return display.name === target }),
      { geometry: false, disabled: false, mirror: "" }))
    displays.forEach(function(display) {
      if (display.name !== target) lines.push("  if up[" + luaString(display.name) + "] and up_count > 1 then "
        + monitorRule(display, { geometry: false, disabled: true, mirror: "" }) + " end")
    })
    lines.push("end")
    return lines
  }
  if (mode === "mirror") {
    enabled.sort(function(a, b) { return a.lane - b.lane })
    var source = enabled[0]
    lines.push("if up[" + luaString(source.name) + "] then")
    lines.push("  " + monitorRule(source, { geometry: false, disabled: false, mirror: "" }))
    displays.forEach(function(display) {
      if (enabledNames.indexOf(display.name) === -1) {
        lines.push("  if up[" + luaString(display.name) + "] and up_count > 1 then "
          + monitorRule(display, { geometry: false, disabled: true, mirror: "" }) + " end")
      } else if (display.name !== source.name) {
        lines.push("  " + monitorRule(display, { geometry: false, disabled: false,
          mirror: source.name }))
      }
    })
    lines.push("end")
    return lines
  }
  displays.filter(function(display) { return enabledNames.indexOf(display.name) !== -1 }).forEach(function(display) {
    lines.push(monitorRule(display, { geometry: false, disabled: false, mirror: "" }))
  })
  displays.filter(function(display) { return enabledNames.indexOf(display.name) === -1 }).forEach(function(display) {
    lines.push("if up[" + luaString(display.name) + "] and up_count > 1 then "
      + monitorRule(display, { geometry: false, disabled: true, mirror: "" }) + " end")
  })
  return lines
}

function runtimeModeStates(displaysInput, options) {
  var displays = (displaysInput || []).map(function(display) {
    return { name: connector(display.name), lane: integer(display.lane, 1, 3, "lane") }
  })
  if (!displays.length) return []
  var enabledNames = Array.isArray(options.enabled) ? options.enabled.filter(function(name) {
    connector(name)
    return displays.some(function(display) { return display.name === name })
  }) : displays.map(function(display) { return display.name })
  if (!enabledNames.length) enabledNames = displays.map(function(display) { return display.name })
  var mode = options.mode || "extend"
  if (["extend", "mirror", "single"].indexOf(mode) === -1) throw new Error("invalid mode")
  var target = mode === "single" && enabledNames.indexOf(options.singleTarget) !== -1
    ? options.singleTarget : enabledNames.slice().sort(function(a, b) {
      return displays.find(function(d) { return d.name === a }).lane - displays.find(function(d) { return d.name === b }).lane
    })[0]
  var source = ""
  if (mode === "mirror") {
    var enabledDisplays = displays.filter(function(display) { return enabledNames.indexOf(display.name) !== -1 })
      .sort(function(a, b) { return a.lane - b.lane })
    source = enabledDisplays[0].name
  }
  return displays.map(function(display) {
    var isEnabled = mode === "single" ? display.name === target : enabledNames.indexOf(display.name) !== -1
    var mirror = mode === "mirror" && isEnabled && display.name !== source ? source : ""
    return { name: display.name, disabled: !isEnabled, mirror: mirror }
  })
}

function runtimeModeRules(displaysInput, options) {
  // Never disable the old sole output before enabling the next source.
  var states = runtimeModeStates(displaysInput, options)
  var active = states.filter(function(display) { return !display.disabled })
  var inactive = states.filter(function(display) { return display.disabled })
  if (options.mode === "mirror") active.sort(function(a, b) {
    return (a.mirror ? 1 : 0) - (b.mirror ? 1 : 0)
  })
  return active.concat(inactive).map(function(display) {
    return monitorRule(display, { geometry: false, disabled: display.disabled, mirror: display.mirror })
  })
}

// A mode-only preview needs no geometry rules. Reissuing them can tear down
// Wayland outputs even when their position, resolution and scale did not move.
function changedModeNames(displays, beforeOptions, afterOptions) {
  var previous = runtimeModeStates(displays, beforeOptions)
  return runtimeModeStates(displays, afterOptions).filter(function(state) {
    var old = previous.find(function(item) { return item.name === state.name })
    return !old || old.disabled !== state.disabled || old.mirror !== state.mirror
  }).map(function(state) { return state.name })
}

function modeOnlyRules(before, after, beforeOptions, options) {
  if (!before || before.length !== after.length) return null
  for (var i = 0; i < after.length; i++) {
    var old = before.find(function(display) { return display.name === after[i].name })
    if (!old || String(old.mode) !== String(after[i].mode) || Number(old.x) !== Number(after[i].x)
        || Number(old.y) !== Number(after[i].y) || Number(old.scale) !== Number(after[i].scale)
        || Number(old.transform || 0) !== Number(after[i].transform || 0)) return null
  }
  var changed = changedModeNames(after, beforeOptions, options)
  return runtimeModeRules(after, options).filter(function(rule) {
    return changed.some(function(name) { return rule.indexOf("output = " + luaString(name) + ",") !== -1 })
  })
}

function changedOutputs(displays, options, monitors, includeGeometry) {
  return runtimeModeStates(displays, options).filter(function(target) {
    var before = monitors.find(function(monitor) { return monitor.name === target.name })
    if (!before || (before.disabled === true) !== target.disabled
        || (before.mirrorOf === "none" ? "" : String(before.mirrorOf || "")) !== target.mirror) return true
    if (!includeGeometry) return false
    var display = displays.find(function(item) { return item.name === target.name })
    var match = String(display.mode).match(/^(\d+)x(\d+)@(\d+(?:\.\d+)?)Hz$/)
    return Number(before.x) !== display.x || Number(before.y) !== display.y
      || Number(before.scale) !== display.scale || Number(before.transform) !== display.transform
      || !match || Number(before.width) !== Number(match[1]) || Number(before.height) !== Number(match[2])
      || Math.abs(Number(before.refreshRate) - Number(match[3])) > 0.01
  }).map(function(display) { return display.name })
}

// Return only the monitor rules needed for a position-only Extend edit. A
// null result means mode, enablement, or other geometry changed and the full
// guarded transaction must run instead.
function positionOnlyRules(before, after, beforeMode, afterMode) {
  if (beforeMode !== "extend" || afterMode !== "extend" || before.length !== after.length) return null
  var lines = []
  for (var i = 0; i < after.length; i++) {
    var display = after[i]
    var old = before.find(function(item) { return item.name === display.name })
    if (!old || String(old.mode) !== String(display.mode)
        || Number(old.scale) !== Number(display.scale)
        || Number(old.transform || 0) !== Number(display.transform || 0)
        || (old.enabled !== false) !== (display.enabled !== false)) return null
    if (Number(old.x) !== Number(display.x) || Number(old.y) !== Number(display.y))
      lines.push(monitorRule(display))
  }
  return lines
}

function generate(displaysInput, options) {
  if (!Array.isArray(displaysInput) || displaysInput.length === 0) throw new Error("at least one display is required")
  var displays = displaysInput.map(validateDisplay)
  var names = {}
  displays.forEach(function(display) {
    if (names[display.name]) throw new Error("duplicate connector")
    names[display.name] = true
  })
  var guard = [
    "local up = {}", "local up_count = 0",
    "if type(hl.get_monitors) == \"function\" then",
    "  local ok, list = pcall(hl.get_monitors)",
    "  if ok and type(list) == \"table\" then",
    "    for _, m in ipairs(list) do",
    "      local ok2, name = pcall(function() return m.name end)",
    "      if ok2 and type(name) == \"string\" then up[name] = true; up_count = up_count + 1 end",
    "    end", "  end", "end"
  ]
  var geometry = geometryLines(displays)
  var interior = guard.concat(geometry, runtimeLines(displays, options || {})).join("\n")
  return {
    block: START + "\n" + interior + "\n" + END,
    plain: geometry.join("\n") + "\n",
    displays: displays
  }
}

function markerInfo(source) {
  var lines = String(source || "").split(/\r?\n/)
  var starts = [], ends = []
  lines.forEach(function(line, index) {
    if (line === START) starts.push(index)
    if (line === END) ends.push(index)
  })
  return { lines: lines, starts: starts, ends: ends }
}

function replaceManagedBlock(source, block) {
  var info = markerInfo(source)
  if (info.starts.length !== info.ends.length || info.starts.length > 1
      || (info.starts.length === 1 && info.starts[0] >= info.ends[0])) throw new Error("invalid Station markers")
  var kept
  if (info.starts.length === 1) kept = info.lines.slice(0, info.starts[0]).concat(info.lines.slice(info.ends[0] + 1))
  else kept = info.lines
  while (kept.length && kept[kept.length - 1].trim() === "") kept.pop()
  return kept.concat(kept.length ? [""] : [], String(block).split("\n"), [""]).join("\n")
}

function removeManagedBlock(source) {
  var info = markerInfo(source)
  if (!info.starts.length && !info.ends.length) return String(source || "")
  if (info.starts.length !== 1 || info.ends.length !== 1 || info.starts[0] >= info.ends[0])
    throw new Error("invalid Station markers")
  var kept = info.lines.slice(0, info.starts[0]).concat(info.lines.slice(info.ends[0] + 1))
  while (kept.length > 1 && kept[kept.length - 1].trim() === "" && kept[kept.length - 2].trim() === "") kept.pop()
  return kept.join("\n")
}

function externalRuleConflicts(source, outputs) {
  var info = markerInfo(source)
  var outside = info.lines.filter(function(line, index) {
    return !info.starts.length || index < info.starts[0] || index > info.ends[0]
  }).join("\n")
  return (outputs || []).filter(function(output) {
    connector(output)
    return outside.indexOf(luaString(output)) !== -1 && /hl\.monitor\s*\(\s*\{/.test(outside)
  })
}

if (typeof module !== "undefined") module.exports = {
  START: START, END: END, SCALES: SCALES, connector: connector, luaString: luaString,
  validateDisplay: validateDisplay, monitorRule: monitorRule, generate: generate,
  runtimeModeRules: runtimeModeRules, modeOnlyRules: modeOnlyRules, changedModeNames: changedModeNames,
  runtimeModeStates: runtimeModeStates, changedOutputs: changedOutputs,
  positionOnlyRules: positionOnlyRules,
  markerInfo: markerInfo, replaceManagedBlock: replaceManagedBlock,
  removeManagedBlock: removeManagedBlock,
  externalRuleConflicts: externalRuleConflicts
}

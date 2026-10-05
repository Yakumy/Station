var MOD_ORDER = ["SUPER", "CTRL", "ALT", "SHIFT"]
var MOD_ALIASES = { CONTROL: "CTRL", MOD4: "SUPER", WIN: "SUPER" }

function keyName(value) {
  var key = String(value || "").trim().toUpperCase()
  return ({ "←": "LEFT", "→": "RIGHT", "↑": "UP", "↓": "DOWN" })[key] || key
}

function normalize(combo) {
  var parts = String(combo || "").split(/[+\s]+/).filter(Boolean).map(keyName)
  var mods = {}
  var key = ""
  for (var i = 0; i < parts.length; i++) {
    var part = MOD_ALIASES[parts[i]] || parts[i]
    if (MOD_ORDER.indexOf(part) !== -1) mods[part] = true
    else key = part.replace(/^CODE:/, "CODE:")
  }
  var ordered = MOD_ORDER.filter(function(mod) { return mods[mod] })
  if (key) ordered.push(key)
  return ordered.join("+")
}

function parseMenu(text) {
  var rows = []
  String(text || "").split(/\r?\n/).forEach(function(line) {
    var split = line.split(/\s+(?:→|->)\s+/)
    if (split.length < 2) return
    var combo = normalize(split.shift())
    var description = split.join(" → ").trim()
    if (combo) rows.push({ combo: combo, description: description, source: "menu" })
  })
  return rows
}

function intentional(combo) {
  var value = normalize(combo)
  if (/^SUPER\+(?:[0-9]|CODE:1[0-9])$/.test(value)) return true
  if (/^SUPER\+ALT\+SHIFT\+(?:[0-9]|CODE:1[0-9])$/.test(value)) return true
  if (/^SUPER\+SHIFT\+(?:[0-9]|CODE:1[0-9])$/.test(value)) return true
  return ["SUPER+CTRL+LEFT", "SUPER+CTRL+RIGHT",
    "SUPER+ALT+SHIFT+LEFT", "SUPER+ALT+SHIFT+RIGHT"].indexOf(value) !== -1
}

function classify(combo, menuResult, fallbackConflicts) {
  var value = normalize(combo)
  var rows = menuResult && menuResult.ok ? parseMenu(menuResult.text) : []
  var owners = rows.filter(function(row) {
    return row.combo === value && row.description.indexOf("Station:") !== 0
  }).map(function(row) { return row.description })
  if (intentional(value)) return { status: "replacement", owners: owners }
  var fallback = (fallbackConflicts || []).filter(function(row) {
    return normalize(row.combo) === value && String(row.description || "").indexOf("Station:") !== 0
  })
  owners = owners.concat(fallback.map(function(row) { return row.description || "Personal binding" }))
  if (owners.length) return { status: "conflict", owners: owners }
  if (!menuResult || !menuResult.ok || !String(menuResult.text || "").trim()) return { status: "unverified", owners: [] }
  return { status: "free", owners: [] }
}

function definitions() {
  var out = []
  for (var n = 1; n <= 10; n++) {
    var key = n === 10 ? "0" : String(n)
    var code = n === 10 ? 19 : n + 9
    out.push({ id: "switch-" + n, combo: "SUPER + code:" + code, label: "Switch to station " + key,
      method: "switchStation", argument: String(n), replacement: true })
    out.push({ id: "send-" + n, combo: "SUPER + SHIFT + code:" + code, label: "Move window to station " + key,
      method: "sendToStation", argument: String(n), replacement: true })
    out.push({ id: "silent-" + n, combo: "SUPER + SHIFT + ALT + code:" + code, label: "Move window silently to station " + key,
      method: "sendSilent", argument: String(n), replacement: true })
  }
  ;["LEFT", "RIGHT"].forEach(function(key) {
    out.push({ id: "go-" + key.toLowerCase(), combo: "SUPER + CTRL + " + key, label: "Station " + key.toLowerCase(),
      method: "goDirection", argument: key.toLowerCase(), replacement: true })
  })
  ;["LEFT", "RIGHT", "UP", "DOWN"].forEach(function(key) {
    out.push({ id: "shift-" + key.toLowerCase(), combo: "SHIFT + CTRL + SUPER + " + key, label: "Move window " + key.toLowerCase(),
      method: "shiftWindow", argument: key.toLowerCase(), replacement: false })
  })
  return out
}

function effectiveDefinitions(custom) {
  custom = custom && typeof custom === "object" ? custom : {}
  return definitions().map(function(definition) {
    var copy = Object.assign({}, definition)
    if (custom[copy.id]) copy.combo = String(custom[copy.id])
    copy.defaultCombo = definitions().find(function(item) { return item.id === copy.id }).combo
    copy.replacement = normalize(copy.combo) === normalize(copy.defaultCombo) && copy.replacement
    return copy
  })
}

function parseHypr(raw) {
  var parsed
  try { parsed = JSON.parse(String(raw || "")) } catch (error) { return [] }
  if (!Array.isArray(parsed)) return []
  var masks = [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"]]
  return parsed.filter(function(item) { return item && item.key && !item.keycode }).map(function(item) {
    var parts = []
    var mask = Number(item.modmask) || 0
    masks.forEach(function(pair) { if ((mask & pair[0]) !== 0) parts.push(pair[1]) })
    parts.push(String(item.key))
    return { combo: normalize(parts.join("+")), description: String(item.description || "Hyprland binding"), source: "hyprctl" }
  })
}

function parseLua(raw) {
  var rows = []
  var pattern = /(?:o\.bind|hl\.bind|hl\.unbind)\s*\(\s*["']([^"']+)["']/g
  var match
  var source = String(raw || "").split(/\r?\n/).map(function(line) {
    return line.replace(/--.*$/, "")
  }).join("\n")
  while ((match = pattern.exec(source)) !== null)
    rows.push({ combo: normalize(match[1]), description: "Personal bindings.lua", source: "lua" })
  return rows
}

function validCombo(combo) {
  var normalized = normalize(combo)
  var parts = normalized.split("+")
  if (parts.length < 2) return false
  var key = parts[parts.length - 1]
  return /^[A-Z0-9_.:-]+$/.test(key) && MOD_ORDER.some(function(mod) { return parts.indexOf(mod) !== -1 })
}

function luaString(value) {
  return '"' + String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"') + '"'
}

function applyLua(definitionsToApply, previouslyApplied) {
  var previous = Array.isArray(previouslyApplied) ? previouslyApplied : []
  var statements = []
  var removed = {}
  for (var p = 0; p < previous.length; p++) {
    var oldCombo = String(previous[p] || "")
    if (!oldCombo || removed[oldCombo]) continue
    statements.push("hl.unbind(" + luaString(oldCombo) + ")")
    removed[oldCombo] = true
  }
  for (var i = 0; i < definitionsToApply.length; i++) {
    var definition = definitionsToApply[i]
    if (definition.replacement && !removed[definition.combo])
      statements.push("hl.unbind(" + luaString(definition.combo) + ")")
    var command = "omarchy-shell yakumy.station " + definition.method
      + (definition.argument ? " " + definition.argument : "")
    // Match v1's direct dispatcher binding, with the plugin IPC replacing its CLI.
    statements.push("hl.bind(" + luaString(definition.combo) + ", hl.dsp.exec_cmd("
      + luaString(command) + "), { description = " + luaString("Station: " + definition.label) + " })")
  }
  // These defaults move whole workspaces and break fixed lane meaning.
  statements.push('hl.unbind("SUPER + SHIFT + ALT + LEFT")')
  statements.push('hl.unbind("SUPER + SHIFT + ALT + RIGHT")')
  return statements.join("; ")
}

if (typeof module !== "undefined") module.exports = {
  normalize: normalize, parseMenu: parseMenu, intentional: intentional,
  classify: classify, definitions: definitions, effectiveDefinitions: effectiveDefinitions,
  parseHypr: parseHypr, parseLua: parseLua, validCombo: validCombo, applyLua: applyLua
}

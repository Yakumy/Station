// Values are logical pixels; innerGap is the full visible inter-window gap.
var limits = { innerGap: [0, 160, 10], outerGap: [0, 160, 10], split: [25, 75, 50], rounding: [0, 20, 0], speed: [0, 2, 1] }
var speeds = [0, 0.25, 0.5, 0.75, 1, 1.24, 1.5, 1.75, 2]
function speedIndex(value) {
  var best = 4
  if (typeof value !== "number" || !isFinite(value)) return best
  speeds.forEach(function(speed, index) {
    if (Math.abs(speed - value) < Math.abs(speeds[best] - value)) best = index
  })
  return best
}
function clean(source) {
  var out = {}
  Object.keys(limits).forEach(function(key) {
    var n = source && source[key]
    var range = limits[key]
    out[key] = key === "speed" ? speeds[speedIndex(n)] : typeof n === "number" && isFinite(n) ? Math.max(range[0], Math.min(range[1], Math.round(n))) : range[2]
  })
  return out
}
// A Solid or Blur bar keeps the outer gap beside it. A Transparent bar, Omarchy
// default or Pill, floats over the wallpaper, so windows sit flush against it.
function gaps(source, bar) {
  var value = clean(source).outerGap
  var out = { top: value, right: value, bottom: value, left: value }
  if (bar && bar.enabled !== false && bar.background === "transparent"
      && Object.prototype.hasOwnProperty.call(out, bar.position)) out[bar.position] = 0
  return out
}
// One runtime rule per monitor. `only` limits it to the named monitors.
function gapRules(source, bars, only) {
  return Object.keys(bars || {}).filter(function(name) {
    return !only || only.indexOf(name) !== -1
  }).map(function(name) {
    if (!/^[A-Za-z0-9_.:-]{1,64}$/.test(name)) throw new Error("invalid connector")
    var g = gaps(source, bars[name])
    return 'hl.workspace_rule({workspace="m[' + name + ']",gaps_out={top=' + g.top + ',right=' + g.right
      + ',bottom=' + g.bottom + ',left=' + g.left + '}})'
  }).join('; ')
}
// Each edit changes one setting; observing values never emits Lua.
function settingLua(key, value) {
  if (!Object.prototype.hasOwnProperty.call(limits, key) || typeof value !== "number" || !isFinite(value)) throw new Error("Invalid window setting")
  var input = {}; input[key] = value
  var v = clean(input)[key]
  if (key === "innerGap") return 'hl.config({general={gaps_in=' + v / 2 + '}})'
  if (key === "outerGap") return 'hl.config({general={gaps_out=' + v + '}})'
  if (key === "split") return 'hl.config({dwindle={default_split_ratio=' + (100 - v) / 50 + '}})'
  if (key === "rounding") return 'hl.config({decoration={rounding=' + v + '}})'
  var result = 'hl.config({animations={enabled=' + (v > 0 ? 'true' : 'false') + '}})'
  if (v > 0) ['windows', 'windowsIn', 'windowsOut', 'windowsMove'].forEach(function(leaf) {
    result += '; hl.animation({leaf="' + leaf + '",enabled=true,speed=' + 4 / v + ',bezier="default"})'
  })
  return result
}
function observed(raw) {
  // hyprctl batch returns concatenated JSON documents, not a JSON array.
  var source = String(raw).trim(), values = [], start = 0, depth = 0, quoted = false, escaped = false
  for (var i = 0; i < source.length; i++) {
    var ch = source[i]
    if (quoted) { if (escaped) escaped = false; else if (ch === "\\") escaped = true; else if (ch === '"') quoted = false; continue }
    if (ch === '"') quoted = true
    else if (ch === '{' || ch === '[') { if (depth++ === 0) start = i }
    else if (ch === '}' || ch === ']') { if (--depth === 0) values.push(JSON.parse(source.slice(start, i + 1))) }
  }
  if (depth || values.length !== 6) throw new Error("Incomplete compositor settings")
  function gap(index) {
    var parts = String(values[index].css || "").trim().split(/\s+/).map(Number)
    if (!parts.length || parts.some(function(n) { return !isFinite(n) || n < 0 })) throw new Error("Invalid gap response")
    return parts[0]
  }
  var animations = values[5][0] || []
  var windowAnimation = animations.find(function(row) { return row.name === "windows" })
  var ratio = values[2].float, rounding = values[3].int
  if (typeof ratio !== "number" || typeof rounding !== "number" || typeof values[4].bool !== "boolean" || !windowAnimation) throw new Error("Invalid compositor response")
  return { innerGap: gap(0) * 2, outerGap: gap(1), split: 100 - ratio * 50, rounding: rounding,
    speed: !values[4].bool || !windowAnimation.enabled ? 0 : windowAnimation.speed > 0 ? Math.round(400 / windowAnimation.speed) / 100 : 1 }
}
if (typeof module !== 'undefined') { module.exports.settingLua = settingLua; module.exports.observed = observed }

function displayValues(source) {
  var out = clean(null)
  Object.keys(out).forEach(function(key) {
    if (source && typeof source[key] === "number" && isFinite(source[key])) out[key] = source[key]
  })
  return out
}
if (typeof module !== 'undefined') Object.assign(module.exports, {limits:limits, speeds:speeds, speedIndex:speedIndex, clean:clean, gaps:gaps, gapRules:gapRules, displayValues:displayValues})

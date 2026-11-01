// Values are logical pixels; innerGap is the full visible inter-window gap.
var limits = { innerGap: [0, 160, 10], outerGap: [0, 160, 10], split: [25, 75, 50], rounding: [0, 40, 0], speed: [0, 2, 1] }
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
function gaps(source, bar) {
  var value = clean(source).outerGap
  var out = { top: value, right: value, bottom: value, left: value }
  if (bar && bar.enabled !== false && Object.prototype.hasOwnProperty.call(out, bar.position)) out[bar.position] = 0
  return out
}
function gapRules(source, bars) {
  return Object.keys(bars || {}).map(function(name) {
    if (!/^[A-Za-z0-9_.:-]{1,64}$/.test(name)) throw new Error("invalid connector")
    var g = gaps(source, bars[name])
    return 'hl.workspace_rule({workspace="m[' + name + ']",gaps_out={top=' + g.top + ',right=' + g.right + ',bottom=' + g.bottom + ',left=' + g.left + '}})'
  }).join('; ')
}
function lua(source) {
  var v = clean(source)
  var result = 'hl.config({general={gaps_in=' + v.innerGap / 2 + ',gaps_out=' + v.outerGap + '},dwindle={default_split_ratio=' + (100 - v.split) / 50 + '},decoration={rounding=' + v.rounding + '},animations={enabled=' + (v.speed > 0 ? 'true' : 'false') + '}})'
  if (v.speed > 0) ['windows', 'windowsIn', 'windowsOut', 'windowsMove'].forEach(function(leaf) {
    result += '; hl.animation({leaf="' + leaf + '",enabled=true,speed=' + (4 / v.speed) + ',bezier="default"})'
  })
  return result
}
if (typeof module !== 'undefined') module.exports = { limits: limits, speeds: speeds, speedIndex: speedIndex, clean: clean, lua: lua, gaps: gaps, gapRules: gapRules }

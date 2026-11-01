// Values are logical pixels; innerGap is the full visible inter-window gap.
var limits = { innerGap: [0, 160, 10], outerGap: [0, 160, 10], split: [25, 75, 50], rounding: [0, 40, 0], speed: [0, 10, 1] }
function clean(source) {
  var out = {}
  Object.keys(limits).forEach(function(key) {
    var n = source && source[key]
    var range = limits[key]
    out[key] = typeof n === "number" && isFinite(n) ? Math.max(range[0], Math.min(range[1], Math.round(n))) : range[2]
  })
  return out
}
function lua(source) {
  var v = clean(source)
  var result = 'hl.config({general={gaps_in=' + v.innerGap / 2 + ',gaps_out=' + v.outerGap + '},dwindle={default_split_ratio=' + v.split / 50 + '},decoration={rounding=' + v.rounding + '},animations={enabled=' + (v.speed > 0 ? 'true' : 'false') + '}})'
  if (v.speed > 0) ['windows', 'windowsIn', 'windowsOut', 'windowsMove'].forEach(function(leaf) {
    result += '; hl.animation({leaf="' + leaf + '",enabled=true,speed=' + (4 / v.speed) + ',bezier="default"})'
  })
  return result
}
if (typeof module !== 'undefined') module.exports = { limits: limits, clean: clean, lua: lua }

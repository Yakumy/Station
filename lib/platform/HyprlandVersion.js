// Whether this Hyprland leaves a mapped layer surface at its old global position
// when its monitor moves. Fixed in 0.57. Anything unreadable counts as fixed: a
// needless remap can crash the shell, a missed one only misplaces a surface.
function strandsLayers(text) {
  var info
  try { info = JSON.parse(String(text || "")) } catch (error) { return false }
  var found = /^v?(\d+)\.(\d+)(?:\D|$)/.exec(String(info && (info.version || info.tag) || ""))
  if (!found) return false
  return Number(found[1]) === 0 && Number(found[2]) < 57
}

if (typeof module !== "undefined") module.exports = { strandsLayers: strandsLayers }

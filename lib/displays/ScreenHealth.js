// Detect a shell process whose Qt screen list did not recover after Hyprland
// removed and re-added an output during a Station topology change.
function activeMonitorNames(monitors) {
  var names = []
  ;(monitors || []).forEach(function(monitor) {
    var mirror = String(monitor && monitor.mirrorOf || "")
    if (!monitor || monitor.disabled === true || monitor.enabled === false
        || (mirror && mirror !== "none") || !(monitor.width > 0 && monitor.height > 0)) return
    if (typeof monitor.name === "string" && names.indexOf(monitor.name) < 0) names.push(monitor.name)
  })
  return names
}

function shellScreenNames(screens) {
  var names = []
  for (var i = 0; screens && i < screens.length; i++) {
    var name = screens[i] && screens[i].name
    if (typeof name === "string" && names.indexOf(name) < 0) names.push(name)
  }
  return names
}

function missingScreens(monitors, screens) {
  var available = shellScreenNames(screens)
  return activeMonitorNames(monitors).filter(function(name) { return available.indexOf(name) < 0 })
}

function recoveryTarget(monitors, screens) {
  var active = activeMonitorNames(monitors)
  var available = shellScreenNames(screens)
  return missingScreens(monitors, screens).find(function(name) {
    return active.some(function(other) { return other !== name && available.indexOf(other) >= 0 })
  }) || ""
}

if (typeof module !== "undefined") module.exports = {
  activeMonitorNames: activeMonitorNames,
  shellScreenNames: shellScreenNames,
  missingScreens: missingScreens,
  recoveryTarget: recoveryTarget
}

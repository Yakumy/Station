// Actual compositor placement, never decoded workspace IDs: this remains valid
// while the migration journal and committed mapping deliberately disagree.
function rows(monitors, clients, active) {
  var result = {}
  ;(monitors || []).forEach(function(monitor) {
    var name = String(monitor.name || "")
    if (!name || monitor.disabled || (monitor.mirrorOf && monitor.mirrorOf !== "none")) return
    var workspace = Number(monitor.activeWorkspace && monitor.activeWorkspace.id)
    var special = Number(monitor.specialWorkspace && monitor.specialWorkspace.id)
    result[name] = (clients || []).filter(function(client) {
      if (client.mapped === false || client.hidden === true) return false
      if (client.monitor !== monitor.id && client.monitor !== name) return false
      var id = Number(client.workspace && client.workspace.id)
      return client.pinned === true || id === workspace || (special !== 0 && id === special)
    }).map(function(client) {
      return { address: String(client.address || ""),
        appId: String(client.class || client.initialClass || ""),
        initialAppId: String(client.initialClass || ""),
        title: String(client.title || client.class || "Application"),
        focused: !!active && !!active.address && client.address === active.address }
    }).sort(function(a, b) { return a.address.localeCompare(b.address) })
  })
  return result
}

if (typeof module !== "undefined") module.exports = { rows: rows }

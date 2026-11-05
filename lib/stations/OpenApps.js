// Logical station membership uses the saved map. During a migration the
// identity journal wins over partly migrated workspace IDs.
function rows(map, clients, active, pending, minimum, current) {
  var result = {}
  for (var s = 1; s <= Math.min(10, Math.max(1, minimum || 1)); s++) result[s] = []
  result[current || 1] = []
  if (!map || !map.outputs || !map.outputs.length) return result
  ;(clients || []).forEach(function(client) {
    if (client.mapped === false || client.hidden === true) return
    var id = Number(client.workspace && client.workspace.id)
    // Scratchpads have no station. Pinned windows retain their home station.
    if (id < 1 || !Number.isInteger(id)) return
    var saved = pending && (pending.windows || []).find(function(row) {
      return row.address === client.address
        && (row.pid == null || row.pid === client.pid)
        && (row.initialClass == null || row.initialClass === client.initialClass)
    })
    var station = saved ? saved.station : Math.floor((id - 1) / map.outputs.length) + 1
    if (station < 1 || station > 10) return
    if (!result[station]) result[station] = []
    result[station].push({ address: String(client.address || ""),
      appId: String(client.class || client.initialClass || ""),
      initialAppId: String(client.initialClass || ""),
      title: String(client.title || client.class || "Application"),
      focused: !!active && !!active.address && client.address === active.address })
  })
  Object.keys(result).forEach(function(key) {
    result[key].sort(function(a, b) { return a.address.localeCompare(b.address) })
  })
  return result
}

if (typeof module !== "undefined") module.exports = { rows: rows }

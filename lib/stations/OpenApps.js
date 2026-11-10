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

// Repetitive and Non-repetitive group apps per output: { output: { number: [apps] } }.
// Repetitive maps keep Station's IDs, so the number is the per-output workspace;
// Non-repetitive IDs are the numbers, and each output owns a consecutive block.
function outputRows(map, clients, active, pending) {
  var result = {}
  if (!map || !Array.isArray(map.outputs) || !map.outputs.length || !Array.isArray(map.counts)) return result
  var global = map.mode === "nonrepetitive"
  var n = map.outputs.length
  map.outputs.forEach(function(name) { result[name] = {} })
  function owner(id) {
    var next = 1
    for (var i = 0; i < n; i++) { next += map.counts[i]; if (id < next) return i }
    return n - 1
  }
  ;(clients || []).forEach(function(client) {
    if (client.mapped === false || client.hidden === true) return
    var id = Number(client.workspace && client.workspace.id)
    if (id < 1 || !Number.isInteger(id) || id > (global ? 20 : 10 * n)) return
    var saved = pending && (pending.windows || []).find(function(row) {
      return row.address === client.address
        && (row.pid == null || row.pid === client.pid)
        && (row.initialClass == null || row.initialClass === client.initialClass)
    })
    var output = saved ? saved.output : map.outputs[global ? owner(id) : (id - 1) % n]
    var number = saved ? saved.station : (global ? id : Math.floor((id - 1) / n) + 1)
    if (!result[output] || number < 1 || number > (global ? 20 : 10)) return
    if (!result[output][number]) result[output][number] = []
    result[output][number].push({ address: String(client.address || ""),
      appId: String(client.class || client.initialClass || ""),
      initialAppId: String(client.initialClass || ""),
      title: String(client.title || client.class || "Application"),
      focused: !!active && !!active.address && client.address === active.address })
  })
  Object.keys(result).forEach(function(output) {
    Object.keys(result[output]).forEach(function(key) {
      result[output][key].sort(function(a, b) { return a.address.localeCompare(b.address) })
    })
  })
  return result
}

if (typeof module !== "undefined") module.exports = { rows: rows, outputRows: outputRows }

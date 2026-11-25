// A mapped window on a numbered workspace. Scratchpads have no station. Pinned
// windows retain their home station.
function listed(client) {
  var id = Number(client.workspace && client.workspace.id)
  return client.mapped !== false && client.hidden !== true && Number.isInteger(id) && id >= 1
}

// The window's journal row while a migration is moving it, otherwise nothing.
function journaled(pending, client) {
  return pending && (pending.windows || []).find(function(row) {
    return row.address === client.address
      && (row.pid == null || row.pid === client.pid)
      && (row.initialClass == null || row.initialClass === client.initialClass)
  })
}

function add(groups, number, client, active) {
  if (!groups[number]) groups[number] = []
  groups[number].push({ address: String(client.address || ""),
    appId: String(client.class || client.initialClass || ""),
    initialAppId: String(client.initialClass || ""),
    title: String(client.title || client.class || "Application"),
    focused: !!active && !!active.address && client.address === active.address })
}

function sortGroups(groups) {
  Object.keys(groups).forEach(function(number) {
    groups[number].sort(function(a, b) { return a.address.localeCompare(b.address) })
  })
}

// Logical station membership uses the saved map. During a migration the
// identity journal wins over partly migrated workspace IDs.
function rows(map, clients, active, pending, minimum, current) {
  var result = {}
  for (var s = 1; s <= Math.min(10, Math.max(1, minimum || 1)); s++) result[s] = []
  result[current || 1] = []
  if (!map || !map.outputs || !map.outputs.length) return result
  ;(clients || []).filter(listed).forEach(function(client) {
    var saved = journaled(pending, client)
    var station = saved ? saved.station : Math.floor((Number(client.workspace.id) - 1) / map.outputs.length) + 1
    if (station >= 1 && station <= 10) add(result, station, client, active)
  })
  sortGroups(result)
  return result
}

// The output that owns a Non-repetitive ID, as Grid.owner. A map saved before
// `owned` existed gave each output a consecutive block. IDs past the total belong
// to the last output.
function owner(id, map) {
  var last = map.outputs.length - 1
  if (Array.isArray(map.owned)) {
    for (var i = 0; i < last; i++) if (map.owned[i].indexOf(id) !== -1) return i
    return last
  }
  var next = 1
  for (var j = 0; j < last; j++) { next += map.counts[j]; if (id < next) return j }
  return last
}

// The output and the number on it that a workspace ID stands for, or null.
// Non-repetitive IDs are the numbers. Repetitive maps with blocks use Omarchy's
// numbering, ten IDs per block; without them they keep Station's IDs.
function locate(id, map) {
  var n = map.outputs.length
  if (map.mode === "nonrepetitive")
    return id <= 20 ? { output: map.outputs[owner(id, map)], number: id } : null
  if (map.mode === "repetitive" && Array.isArray(map.blocks)) {
    var index = map.blocks.indexOf(Math.floor((id - 1) / 10))
    return id <= 100 && index !== -1 ? { output: map.outputs[index], number: (id - 1) % 10 + 1 } : null
  }
  return id <= 10 * n ? { output: map.outputs[(id - 1) % n], number: Math.floor((id - 1) / n) + 1 } : null
}

// Repetitive and Non-repetitive group apps per output: { output: { number: [apps] } }.
function outputRows(map, clients, active, pending) {
  var result = {}
  if (!map || !Array.isArray(map.outputs) || !map.outputs.length || !Array.isArray(map.counts)) return result
  var highest = map.mode === "nonrepetitive" ? 20 : 10
  map.outputs.forEach(function(name) { result[name] = {} })
  ;(clients || []).filter(listed).forEach(function(client) {
    var home = locate(Number(client.workspace.id), map)
    if (!home) return
    var saved = journaled(pending, client)
    if (saved) home = { output: saved.output, number: saved.station }
    if (result[home.output] && home.number >= 1 && home.number <= highest)
      add(result[home.output], home.number, client, active)
  })
  map.outputs.forEach(function(name) { sortGroups(result[name]) })
  return result
}

if (typeof module !== "undefined") module.exports = { rows: rows, outputRows: outputRows }

// Compact workspace numbering. Monitor preferences are separate from active slots.
var MAX_STATIONS = 10
var MAX_OUTPUTS = 3

function valid(map) {
  return map && Array.isArray(map.outputs) && map.outputs.length >= 1
    && map.outputs.length <= MAX_OUTPUTS
    && map.outputs.every(function(name) { return typeof name === "string" && /^[A-Za-z0-9_.:-]{1,64}$/.test(name) })
    && map.outputs.every(function(name, index) { return map.outputs.indexOf(name) === index })
}

function width(map) { return map && map.outputs ? map.outputs.length : 0 }
function contains(id, map) { return Number.isInteger(id) && id >= 1 && id <= MAX_STATIONS * width(map) }
function station(id, map) { return contains(id, map) ? Math.floor((id - 1) / width(map)) + 1 : null }
function slot(id, map) { return contains(id, map) ? (id - 1) % width(map) : -1 }
function workspace(s, output, map) {
  var index = map ? map.outputs.indexOf(output) : -1
  return Number.isInteger(s) && s >= 1 && s <= MAX_STATIONS && index >= 0 ? (s - 1) * width(map) + index + 1 : null
}
function equal(a, b) { return !!a && !!b && JSON.stringify(a.outputs) === JSON.stringify(b.outputs) }

function mapping(monitors, lanes, options) {
  options = options || {}
  var connected = (monitors || []).filter(function(m) { return lanes[m.name] && !m.disabled })
  var enabled = options.enabled || []
  var selected = connected.filter(function(m) { return !enabled.length || enabled.indexOf(m.name) !== -1 })
  if (!selected.length) selected = connected
  selected.sort(function(a, b) { return lanes[a.name] - lanes[b.name] })
  if (options.mode === "single") {
    var target = selected.find(function(m) { return m.name === options.singleTarget })
    selected = target ? [target] : selected.slice(0, 1)
  } else if (options.mode === "mirror") selected = selected.slice(0, 1)
  return { outputs: selected.map(function(m) { return m.name }) }
}

// Only used when upgrading an existing fixed-three-slot v2 installation.
function legacy(lanes) {
  var outputs = [null, null, null]
  Object.keys(lanes).forEach(function(name) {
    if (lanes[name] >= 1 && lanes[name] <= 3) outputs[lanes[name] - 1] = name
  })
  return { outputs: outputs, legacy: true }
}

function host(output, oldMap, newMap) {
  if (newMap.outputs.indexOf(output) !== -1) return output
  var index = oldMap.outputs.indexOf(output)
  // Merge into the next surviving old display, otherwise the previous one.
  for (var i = index + 1; i < oldMap.outputs.length; i++)
    if (newMap.outputs.indexOf(oldMap.outputs[i]) !== -1) return oldMap.outputs[i]
  for (var j = index - 1; j >= 0; j--)
    if (newMap.outputs.indexOf(oldMap.outputs[j]) !== -1) return oldMap.outputs[j]
  return newMap.outputs[0]
}

function eligible(client, map) {
  var id = Number(client.workspace && client.workspace.id)
  var name = client.workspace && client.workspace.name
  return !client.pinned && contains(id, map)
    && (name === undefined || name === String(id))
}

function identity(client) {
  return { address: client.address, pid: client.pid === undefined ? null : client.pid,
    initialClass: client.initialClass === undefined ? null : client.initialClass }
}
function sameClient(row, client) {
  return row.address === client.address
    && (row.pid === null || row.pid === client.pid)
    && (row.initialClass === null || row.initialClass === client.initialClass)
}

function plan(oldMap, newMap, clients, activeStation) {
  if (!valid(newMap) || !width(oldMap)) throw new Error("Invalid workspace mapping")
  var rows = []
  ;(clients || []).forEach(function(client) {
    if (!eligible(client, oldMap)) return
    // The compositor can already have moved removed-display clients to a survivor.
    // Decode their old slot rather than inferring ownership from that new monitor.
    if (oldMap.outputs.indexOf(client.monitor) === -1 && newMap.outputs.indexOf(client.monitor) === -1) return
    var id = Number(client.workspace.id)
    var output = oldMap.outputs[slot(id, oldMap)]
    var s = station(id, oldMap)
    var target = host(output, oldMap, newMap)
    // The old v2 service did not reliably place existing workspaces. During
    // the one-time upgrade, its raw slot may disagree with the physical display.
    if (oldMap.legacy && newMap.outputs.indexOf(client.monitor) !== -1) target = client.monitor
    rows.push(Object.assign(identity(client), { station: s, output: target, to: workspace(s, target, newMap) }))
  })
  return { version: 1, from: oldMap, to: newMap, station: activeStation, windows: rows }
}

function resume(pending, newMap, clients) {
  if (!valid(newMap)) throw new Error("No active workspace mapping")
  var rows = []
  pending.windows.forEach(function(row) {
    var client = clients.find(function(c) { return sameClient(row, c) })
    if (!client || client.pinned || Number(client.workspace.id) < 1) return
    var output = host(row.output, pending.to, newMap)
    rows.push(Object.assign({}, row, { output: output, to: workspace(row.station, output, newMap) }))
  })
  return { version: 1, from: pending.from, to: newMap, station: pending.station, windows: rows }
}

function existing(clients, monitors, minimum, map) {
  var set = {}
  for (var s = 1; s <= Math.max(1, Math.min(10, minimum)); s++) set[s] = true
  ;(clients || []).forEach(function(c) {
    if (map.outputs.indexOf(c.monitor) !== -1 && eligible(c, map)) set[station(Number(c.workspace.id), map)] = true
  })
  ;(monitors || []).forEach(function(m) {
    var s = station(Number(m.activeWorkspace && m.activeWorkspace.id), map)
    if (map.outputs.indexOf(m.name) !== -1 && s !== null) set[s] = true
  })
  return Object.keys(set).map(Number).sort(function(a, b) { return a - b })
}

if (typeof module !== "undefined") module.exports = {
  MAX_STATIONS: MAX_STATIONS, valid: valid, width: width, contains: contains, station: station,
  slot: slot, workspace: workspace, equal: equal, mapping: mapping, legacy: legacy, host: host,
  eligible: eligible, identity: identity, sameClient: sameClient, plan: plan, resume: resume, existing: existing
}

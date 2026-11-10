// Compact workspace numbering. Monitor preferences are separate from active slots.
//
// A map is `{ outputs }` in Station mode, the original numbering. Repetitive and
// Non-repetitive maps add `mode` and `counts`, the number of workspaces each output
// shows. Repetitive also has `blocks`: Omarchy's own numbering, where each monitor
// owns IDs block·10+1 to block·10+10, so Omarchy's indicator and renumbering work
// unchanged; `station(id)` is the per-output workspace number. A Repetitive map
// saved without `blocks` used Station's IDs and is still read that way.
// Non-repetitive numbers workspaces 1 to 20 globally, and each output owns one
// consecutive block of them.
// MAX_STATIONS is the most workspaces one output holds in a per-output map.
var MAX_STATIONS = 10
var MAX_STATION_COUNT = 5
var MAX_GLOBAL = 20
var MAX_OUTPUTS = 3
var MODES = ["station", "repetitive", "nonrepetitive"]

function mode(map) { return map && MODES.indexOf(map.mode) !== -1 ? map.mode : "station" }
function perOutput(map) { return mode(map) !== "nonrepetitive" }
function blocked(map) { return mode(map) === "repetitive" && !!map && Array.isArray(map.blocks) }
function blockIndex(id, map) { return map.blocks.indexOf(Math.floor((id - 1) / MAX_STATIONS)) }
function internal(name) { return /^(eDP|LVDS|DSI)/.test(String(name)) }
// Omarchy's block for each output: the one its state file records for the
// connector, otherwise the lowest one nobody holds, internal panels first, as
// Omarchy assigns them.
function blocksFor(outputs, known) {
  known = known || {}
  var byConnector = known.byConnector || {}
  var taken = (known.taken || []).slice()
  var result = outputs.map(function(name) {
    var block = byConnector[name]
    return Number.isInteger(block) && block >= 0 && block < MAX_STATIONS ? block : null
  })
  result.forEach(function(block) { if (block !== null) taken.push(block) })
  var order = outputs.map(function(name, index) { return index })
  order.sort(function(a, b) { return (internal(outputs[b]) ? 1 : 0) - (internal(outputs[a]) ? 1 : 0) || a - b })
  order.forEach(function(index) {
    if (result[index] !== null && result.indexOf(result[index]) === index) return
    var block = 0
    while (taken.indexOf(block) !== -1) block++
    result[index] = block
    taken.push(block)
  })
  return result
}
// The highest number a map reaches: a station or per-output workspace, or a
// Non-repetitive workspace.
function ceiling(map) { return perOutput(map) ? MAX_STATIONS : MAX_GLOBAL }

// Count limits per mode for n outputs. Station counts stations, up to five; the
// others count all workspaces, at least one per output. Repetitive allows ten per
// output, and Non-repetitive twenty in all, still at most ten per output.
function limits(value, n) {
  n = Math.max(1, Math.min(MAX_OUTPUTS, Number(n) || 1))
  if (value === "repetitive") return { min: n, max: MAX_STATIONS * n, fallback: 5 * n }
  if (value === "nonrepetitive") {
    var most = Math.min(MAX_GLOBAL, MAX_STATIONS * n)
    return { min: n, max: most, fallback: Math.min(10, most) }
  }
  return { min: 1, max: MAX_STATION_COUNT, fallback: 3 }
}

function total(value, n, requested) {
  var range = limits(value, n)
  var number = Number(requested)
  if (requested === null || requested === undefined || requested === "" || !isFinite(number)) number = range.fallback
  return Math.max(range.min, Math.min(range.max, Math.round(number)))
}

// Each output gets an equal share; the remainder goes to the last output. No output
// exceeds ten, so an overflow moves back toward the first output.
function split(value, n, requested) {
  n = Math.max(1, Math.min(MAX_OUTPUTS, Number(n) || 1))
  var sum = total(value, n, requested)
  var base = Math.floor(sum / n)
  var out = []
  for (var i = 0; i < n; i++) out.push(base)
  out[n - 1] += sum - base * n
  for (var j = n - 1; j > 0; j--) if (out[j] > MAX_STATIONS) {
    out[j - 1] += out[j] - MAX_STATIONS
    out[j] = MAX_STATIONS
  }
  return out
}

// The numbers each output shows, in output order, for the panel and the bar.
// Station mode lists workspace IDs, the other modes the numbers the keys reach.
function assigned(value, n, requested) {
  n = Math.max(1, Math.min(MAX_OUTPUTS, Number(n) || 1))
  var result = []
  var i, s
  if (value === "repetitive" || value === "nonrepetitive") {
    var counts = split(value, n, requested)
    var next = 1
    for (i = 0; i < n; i++) {
      var row = []
      for (s = 1; s <= counts[i]; s++) row.push(value === "repetitive" ? s : next++)
      result.push(row)
    }
    return result
  }
  var stations = total("station", n, requested)
  for (i = 0; i < n; i++) {
    var ids = []
    for (s = 1; s <= stations; s++) ids.push((s - 1) * n + i + 1)
    result.push(ids)
  }
  return result
}

function validCounts(map) {
  var value = mode(map)
  if (value === "station") return true
  var counts = map.counts
  if (!Array.isArray(counts) || counts.length !== map.outputs.length) return false
  if (!counts.every(function(count) { return Number.isInteger(count) && count >= 1 && count <= MAX_STATIONS })) return false
  if (map.blocks !== undefined && (value !== "repetitive" || !Array.isArray(map.blocks)
      || map.blocks.length !== map.outputs.length
      || !map.blocks.every(function(block, index) { return Number.isInteger(block) && block >= 0
        && block < MAX_STATIONS && map.blocks.indexOf(block) === index }))) return false
  var sum = counts.reduce(function(a, b) { return a + b }, 0)
  return value === "repetitive" || sum <= MAX_GLOBAL
}

function valid(map) {
  return map && Array.isArray(map.outputs) && map.outputs.length >= 1
    && map.outputs.length <= MAX_OUTPUTS
    && map.outputs.every(function(name) { return typeof name === "string" && /^[A-Za-z0-9_.:-]{1,64}$/.test(name) })
    && map.outputs.every(function(name, index) { return map.outputs.indexOf(name) === index })
    && (map.mode === undefined || MODES.indexOf(map.mode) !== -1) && validCounts(map)
}

// The first Non-repetitive workspace an output owns. IDs past the last block
// belong to the last output.
function start(index, map) {
  var first = 1
  for (var i = 0; i < index; i++) first += map.counts[i]
  return first
}
function owner(id, map) {
  var next = 1
  for (var i = 0; i < map.outputs.length; i++) {
    next += map.counts[i]
    if (id < next) return i
  }
  return map.outputs.length - 1
}

// The numbers an output of a Repetitive or Non-repetitive map shows.
function numbers(map, index) {
  if (perOutput(map) && mode(map) !== "repetitive") return []
  if (!map || !Array.isArray(map.counts) || index < 0 || index >= map.counts.length) return []
  var first = mode(map) === "repetitive" ? 1 : start(index, map)
  var out = []
  for (var i = 0; i < map.counts[index]; i++) out.push(first + i)
  return out
}

function width(map) { return map && map.outputs ? map.outputs.length : 0 }
function contains(id, map) {
  if (blocked(map)) return Number.isInteger(id) && id >= 1 && blockIndex(id, map) !== -1
  return Number.isInteger(id) && id >= 1 && id <= (perOutput(map) ? MAX_STATIONS * width(map) : (width(map) ? MAX_GLOBAL : 0))
}
function station(id, map) {
  if (!contains(id, map)) return null
  if (blocked(map)) return (id - 1) % MAX_STATIONS + 1
  return perOutput(map) ? Math.floor((id - 1) / width(map)) + 1 : id
}
function slot(id, map) {
  if (!contains(id, map)) return -1
  if (blocked(map)) return blockIndex(id, map)
  return perOutput(map) ? (id - 1) % width(map) : owner(id, map)
}
function workspace(s, output, map) {
  var index = map ? map.outputs.indexOf(output) : -1
  if (!Number.isInteger(s) || s < 1 || s > ceiling(map) || index < 0) return null
  if (!perOutput(map)) return owner(s, map) === index ? s : null
  if (blocked(map)) return map.blocks[index] * MAX_STATIONS + s
  return (s - 1) * width(map) + index + 1
}
// Where a workspace number lives: its owner in Non-repetitive, otherwise the
// output asked for.
function home(s, output, map) {
  if (perOutput(map)) return map.outputs.indexOf(output) !== -1 ? output : null
  return Number.isInteger(s) && s >= 1 && s <= MAX_GLOBAL ? map.outputs[owner(s, map)] : null
}
// Every workspace rule for a map: [id, output] pairs.
function assignments(map) {
  var rows = []
  if (!valid(map)) return rows
  for (var s = 1; s <= ceiling(map); s++) {
    if (perOutput(map)) map.outputs.forEach(function(output, index) {
      rows.push([workspace(s, output, map), output])
    })
    else rows.push([s, map.outputs[owner(s, map)]])
  }
  return rows
}
function equal(a, b) {
  return !!a && !!b && JSON.stringify(a.outputs) === JSON.stringify(b.outputs) && mode(a) === mode(b)
    && (mode(a) === "station" || JSON.stringify(a.counts) === JSON.stringify(b.counts))
    && JSON.stringify(a.blocks) === JSON.stringify(b.blocks)
}

// `workspaces` is `{ mode, counts, blocks }`: the mode and the requested total for
// each non-Station mode from the preferences, and Omarchy's recorded blocks as
// `{ byConnector, taken }`.
function mapping(monitors, lanes, options, workspaces) {
  options = options || {}
  var connected = (monitors || []).filter(function(m) { return lanes[m.name] && !m.disabled
    && (m.mirrorOf === undefined || m.mirrorOf === null || m.mirrorOf === "" || m.mirrorOf === "none" || String(m.mirrorOf) === "-1") })
  var enabled = options.enabled || []
  var selected = connected.filter(function(m) { return !enabled.length || enabled.indexOf(m.name) !== -1 })
  if (!selected.length) selected = connected
  selected.sort(function(a, b) { return lanes[a.name] - lanes[b.name] })
  if (options.mode === "single") {
    var target = selected.find(function(m) { return m.name === options.singleTarget })
    selected = target ? [target] : selected.slice(0, 1)
  } else if (options.mode === "mirror") selected = selected.slice(0, 1)
  var result = { outputs: selected.map(function(m) { return m.name }) }
  var chosen = workspaces && MODES.indexOf(workspaces.mode) !== -1 ? workspaces.mode : "station"
  if (chosen !== "station" && result.outputs.length) {
    var requested = workspaces.counts && typeof workspaces.counts === "object" ? workspaces.counts[chosen] : null
    result.mode = chosen
    result.counts = split(chosen, result.outputs.length, requested)
    if (chosen === "repetitive") result.blocks = blocksFor(result.outputs, workspaces.blocks)
  }
  return result
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

// Decode a workspace through a map: its number (station, per-output workspace or
// global workspace), its output, and its rank inside that output's own list.
function decode(id, map) {
  var output = map.outputs[slot(id, map)]
  var number = station(id, map)
  return { number: number, output: output, rank: perOutput(map) ? number : rank(number, output, map) }
}
function rank(number, output, map) {
  if (perOutput(map)) return number
  var index = map.outputs.indexOf(output)
  return index === -1 ? number : number - start(index, map) + 1
}

// Place a decoded workspace in another map. Same-kind maps keep the number: a
// station or per-output workspace keeps its output, a global workspace moves to
// its new owner. Across kinds a workspace keeps its output and its rank there.
function place(position, from, to) {
  var output = host(position.output, from, to)
  var number
  if (perOutput(to)) number = perOutput(from) ? position.number : position.rank
  else if (!perOutput(from)) {
    number = position.number
    output = to.outputs[owner(number, to)]
  } else {
    var index = to.outputs.indexOf(output)
    number = start(index, to) + Math.min(position.rank, to.counts[index]) - 1
  }
  number = Math.max(1, Math.min(ceiling(to), number))
  return { station: number, output: output, to: workspace(number, output, to) }
}

function plan(oldMap, newMap, clients, activeStation) {
  if (!valid(newMap) || !width(oldMap)) throw new Error("Invalid workspace mapping")
  var rows = []
  // Between Repetitive maps Omarchy owns the windows: its reconcile moves and
  // returns them on hotplug, so Station moves nothing.
  if (blocked(oldMap) && blocked(newMap)) return { version: 1, from: oldMap, to: newMap, station: activeStation, windows: rows }
  ;(clients || []).forEach(function(client) {
    if (!eligible(client, oldMap)) return
    // The compositor can already have moved removed-display clients to a survivor.
    // Decode their old slot rather than inferring ownership from that new monitor.
    if (oldMap.outputs.indexOf(client.monitor) === -1 && newMap.outputs.indexOf(client.monitor) === -1) return
    var position = decode(Number(client.workspace.id), oldMap)
    // The old v2 service did not reliably place existing workspaces. During
    // the one-time upgrade, its raw slot may disagree with the physical display.
    if (oldMap.legacy && newMap.outputs.indexOf(client.monitor) !== -1) position.output = client.monitor
    var target = place(position, oldMap, newMap)
    rows.push(Object.assign(identity(client), target))
  })
  return { version: 1, from: oldMap, to: newMap, station: activeStation, windows: rows }
}

function resume(pending, newMap, clients) {
  if (!valid(newMap)) throw new Error("No active workspace mapping")
  var rows = []
  pending.windows.forEach(function(row) {
    var client = clients.find(function(c) { return sameClient(row, c) })
    if (!client || client.pinned || Number(client.workspace.id) < 1) return
    var position = { number: row.station, output: row.output, rank: rank(row.station, row.output, pending.to) }
    rows.push(Object.assign({}, row, place(position, pending.to, newMap)))
  })
  return { version: 1, from: pending.from, to: newMap, station: pending.station, windows: rows }
}

// Restore original station/output ownership on Revert, including after a
// shell restart. Windows opened during the preview follow the normal plan.
function restorePreview(baseline, fallback, clients) {
  var original = resume(baseline, fallback.to, clients)
  var extra = fallback.windows.filter(function(row) {
    return !original.windows.some(function(old) { return sameClient(old, row) })
  })
  return Object.assign({}, fallback, { station: baseline.station, windows: original.windows.concat(extra) })
}

// The numbers navigation steps through. Station mode is global. Repetitive is
// per output: pass the output. Non-repetitive is global over workspace IDs.
function existing(clients, monitors, minimum, map, output) {
  var set = {}
  var value = mode(map)
  var index = map.outputs.indexOf(output)
  var s
  if (value === "repetitive") {
    if (index === -1) return []
    for (s = 1; s <= map.counts[index]; s++) set[s] = true
  } else if (value === "nonrepetitive") {
    var sum = map.counts.reduce(function(a, b) { return a + b }, 0)
    for (s = 1; s <= sum; s++) set[s] = true
  } else for (s = 1; s <= Math.max(1, Math.min(MAX_STATION_COUNT, minimum)); s++) set[s] = true
  var include = function(name) { return map.outputs.indexOf(name) !== -1 && (value !== "repetitive" || name === output) }
  ;(clients || []).forEach(function(c) {
    if (include(c.monitor) && eligible(c, map)) set[station(Number(c.workspace.id), map)] = true
  })
  ;(monitors || []).forEach(function(m) {
    var number = station(Number(m.activeWorkspace && m.activeWorkspace.id), map)
    if (include(m.name) && number !== null) set[number] = true
  })
  return Object.keys(set).map(Number).sort(function(a, b) { return a - b })
}

if (typeof module !== "undefined") module.exports = {
  MAX_STATIONS: MAX_STATIONS, MAX_STATION_COUNT: MAX_STATION_COUNT, MAX_GLOBAL: MAX_GLOBAL,
  MODES: MODES, mode: mode, perOutput: perOutput, ceiling: ceiling, blocked: blocked, blocksFor: blocksFor, limits: limits, total: total,
  split: split, assigned: assigned, numbers: numbers, owner: owner, start: start, home: home, assignments: assignments,
  decode: decode, place: place, valid: valid, width: width, contains: contains, station: station,
  slot: slot, workspace: workspace, equal: equal, mapping: mapping, legacy: legacy, host: host,
  eligible: eligible, identity: identity, sameClient: sameClient, plan: plan, resume: resume,
  restorePreview: restorePreview, existing: existing
}

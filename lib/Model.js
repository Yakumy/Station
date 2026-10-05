var SLOTS = 3
var MAX_STATION = 10

function ws(station, lane) {
  return (station - 1) * SLOTS + lane
}

function stationOf(workspace) {
  return Math.floor((workspace - 1) / SLOTS) + 1
}

function slotOf(workspace) {
  return ((workspace - 1) % SLOTS) + 1
}

function inGrid(workspace) {
  return Number.isInteger(workspace) && workspace >= 1 && workspace <= MAX_STATION * SLOTS
}

function host(lane, present) {
  if (!Array.isArray(present) || present.length === 0) return null
  var sorted = present.slice().sort(function(a, b) { return a - b })
  if (sorted.indexOf(lane) !== -1) return lane
  for (var i = 0; i < sorted.length; i++) if (sorted[i] > lane) return sorted[i]
  for (var j = sorted.length - 1; j >= 0; j--) if (sorted[j] < lane) return sorted[j]
  return null
}

function clientWorkspace(client) {
  return client && client.workspace ? Number(client.workspace.id) : NaN
}

function planReconcile(clients, present, laneOfMonitor) {
  var moves = []
  if (!Array.isArray(present) || present.length === 0) return moves
  for (var i = 0; i < (clients || []).length; i++) {
    var client = clients[i]
    var workspace = clientWorkspace(client)
    if (!inGrid(workspace) || client.pinned) continue
    if (!laneOfMonitor || !Object.prototype.hasOwnProperty.call(laneOfMonitor, client.monitor)) continue
    var targetLane = host(slotOf(workspace), present)
    var target = ws(stationOf(workspace), targetLane)
    if (target !== workspace) moves.push({ address: client.address, to: target })
  }
  return moves
}

function planRoleChange(clients, oldLane, newLane) {
  var moves = []
  for (var i = 0; i < (clients || []).length; i++) {
    var client = clients[i]
    var workspace = clientWorkspace(client)
    var monitor = client.monitor
    if (!inGrid(workspace) || client.pinned || !newLane
        || !Object.prototype.hasOwnProperty.call(newLane, monitor)
        || oldLane[monitor] === newLane[monitor]) continue
    var target = ws(stationOf(workspace), newLane[monitor])
    if (target !== workspace) moves.push({ address: client.address, to: target })
  }
  return moves
}

function connectedIdentity(monitor) {
  if (!monitor) return ""
  var connector = String(monitor.name || "")
  var description = String(monitor.description || "").trim()
  var serial = String(monitor.serial || "").trim()
  var model = String(monitor.model || "").trim()
  if (serial) return description || [monitor.make, model, serial].filter(Boolean).join(" ")
  return (model || description || "display") + "@" + connector
}

function identities(monitors) {
  var base = []
  var counts = {}
  for (var i = 0; i < (monitors || []).length; i++) {
    var value = connectedIdentity(monitors[i])
    base.push(value)
    counts[value] = (counts[value] || 0) + 1
  }
  return base.map(function(value, index) {
    return counts[value] > 1 ? value + "@" + String(monitors[index].name || "") : value
  })
}

function assignLanes(monitors, preferences, effective) {
  var ids = identities(monitors)
  var used = {}
  var lanes = {}
  var unmanaged = []
  var nextPreferences = Object.assign({}, preferences || {})
  var i
  // A still-present monitor keeps its effective lane.
  for (i = 0; i < monitors.length; i++) {
    var connector = monitors[i].name
    var old = effective && Number(effective[connector])
    if (old >= 1 && old <= SLOTS && !used[old]) {
      lanes[connector] = old
      used[old] = true
    }
  }
  for (i = 0; i < monitors.length; i++) {
    var name = monitors[i].name
    if (lanes[name]) continue
    var preferred = Number(nextPreferences[ids[i]])
    var lane = preferred >= 1 && preferred <= SLOTS && !used[preferred] ? preferred : 0
    if (!lane) for (var candidate = 1; candidate <= SLOTS; candidate++) {
      if (!used[candidate]) { lane = candidate; break }
    }
    if (!lane) { unmanaged.push(name); continue }
    lanes[name] = lane
    used[lane] = true
    nextPreferences[ids[i]] = lane
  }
  return { lanes: lanes, preferences: nextPreferences, identities: ids, unmanaged: unmanaged }
}

function enabledNames(monitors, enabled) {
  var wanted = Array.isArray(enabled) ? enabled : []
  var connected = (monitors || []).map(function(m) { return m.name })
  var out = wanted.filter(function(name) { return connected.indexOf(name) !== -1 })
  return out.length ? out : connected
}

function presentForMode(monitors, lanes, mode, enabled, singleTarget) {
  var names = enabledNames(monitors, enabled)
  if (mode === "single") {
    if (names.indexOf(singleTarget) !== -1 && lanes[singleTarget]) return [lanes[singleTarget]]
  } else if (mode === "mirror") {
    var mirrorLanes = names.map(function(name) { return lanes[name] }).filter(Boolean).sort(function(a, b) { return a - b })
    return mirrorLanes.length ? [mirrorLanes[0]] : []
  }
  return names.map(function(name) { return lanes[name] }).filter(Boolean).sort(function(a, b) { return a - b })
}

function existingStations(clients, monitors, minStations, managedNames) {
  var set = {}
  var minimum = Math.max(1, Math.min(MAX_STATION, Number(minStations) || 3))
  for (var station = 1; station <= minimum; station++) set[station] = true
  for (var i = 0; i < (clients || []).length; i++) {
    if (Array.isArray(managedNames) && managedNames.indexOf(clients[i].monitor) === -1) continue
    var workspace = clientWorkspace(clients[i])
    if (inGrid(workspace)) set[stationOf(workspace)] = true
  }
  for (var j = 0; j < (monitors || []).length; j++) {
    if (Array.isArray(managedNames) && managedNames.indexOf(monitors[j].name) === -1) continue
    var active = Number(monitors[j].activeWorkspace && monitors[j].activeWorkspace.id)
    if (inGrid(active)) set[stationOf(active)] = true
  }
  return Object.keys(set).map(Number).sort(function(a, b) { return a - b })
}

var AXIS = {
  ltr: { axis: "x", next: 1 }, rtl: { axis: "x", next: -1 },
  ttb: { axis: "y", next: 1 }, btt: { axis: "y", next: -1 }
}

function step(directionKey, direction) {
  var axis = AXIS[direction]
  if (!axis) return null
  var value = axis.axis === "x"
    ? { left: -1, right: 1 }[directionKey]
    : { up: -1, down: 1 }[directionKey]
  return value === undefined ? null : value * axis.next
}

function nextExisting(current, delta, existing) {
  if (delta !== 1 && delta !== -1) return null
  var sorted = (existing || []).slice().sort(function(a, b) { return a - b })
  if (delta > 0) for (var i = 0; i < sorted.length; i++) if (sorted[i] > current) return sorted[i]
  if (delta < 0) for (var j = sorted.length - 1; j >= 0; j--) if (sorted[j] < current) return sorted[j]
  return null
}

function logicalSize(monitor) {
  var scale = Number(monitor.scale) || 1
  var width = Number(monitor.width) / scale
  var height = Number(monitor.height) / scale
  if ([1, 3, 5, 7].indexOf(Number(monitor.transform)) !== -1) {
    var swap = width; width = height; height = swap
  }
  return { width: width, height: height }
}

function rectanglesOverlap(a, b) {
  return a.x < b.x + b.width && a.x + a.width > b.x
    && a.y < b.y + b.height && a.y + a.height > b.y
}

function layoutOverlaps(monitors) {
  var rects = (monitors || []).map(function(m) {
    var size = logicalSize(m)
    return { name: m.name, x: Number(m.x) || 0, y: Number(m.y) || 0, width: size.width, height: size.height }
  })
  var pairs = []
  for (var i = 0; i < rects.length; i++) for (var j = i + 1; j < rects.length; j++) {
    if (rectanglesOverlap(rects[i], rects[j])) pairs.push([rects[i].name, rects[j].name])
  }
  return pairs
}

function nearestSnap(value, candidates, threshold) {
  var best = value, distance = Number(threshold)
  for (var i = 0; i < candidates.length; i++) {
    var nextDistance = Math.abs(value - candidates[i])
    if (nextDistance <= distance) { distance = nextDistance; best = candidates[i] }
  }
  return best
}

function snapPosition(display, x, y, displays) {
  var size = logicalSize(display)
  var xCandidates = [], yCandidates = []
  for (var i = 0; i < (displays || []).length; i++) {
    var other = displays[i]
    if (other.name === display.name) continue
    var otherSize = logicalSize(other)
    var ox = Number(other.x) || 0, oy = Number(other.y) || 0
    xCandidates.push(ox, ox + otherSize.width, ox - size.width)
    yCandidates.push(oy, oy + otherSize.height, oy - size.height)
  }
  var gridX = Math.round(Number(x) / 10) * 10
  var gridY = Math.round(Number(y) / 10) * 10
  return { x: nearestSnap(gridX, xCandidates, 20), y: nearestSnap(gridY, yCandidates, 20) }
}

function monitorCenter(monitor) {
  var size = logicalSize(monitor)
  return { x: Number(monitor.x) + size.width / 2, y: Number(monitor.y) + size.height / 2 }
}

function neighborMonitor(currentName, direction, monitors, managedNames) {
  var allowed = managedNames || (monitors || []).map(function(m) { return m.name })
  var current = (monitors || []).find(function(m) { return m.name === currentName })
  if (!current) return null
  var origin = monitorCenter(current)
  var best = null
  var bestScore = Infinity
  for (var i = 0; i < monitors.length; i++) {
    var candidate = monitors[i]
    if (candidate.name === currentName || allowed.indexOf(candidate.name) === -1) continue
    var center = monitorCenter(candidate)
    var dx = center.x - origin.x
    var dy = center.y - origin.y
    var forward = direction === "left" ? -dx : direction === "right" ? dx
      : direction === "up" ? -dy : dy
    if (forward <= 0) continue
    var cross = direction === "left" || direction === "right" ? Math.abs(dy) : Math.abs(dx)
    var score = forward + cross * 2
    if (score < bestScore) { bestScore = score; best = candidate.name }
  }
  return best
}

function edgeMonitor(direction, monitors, managedNames) {
  var allowed = managedNames || (monitors || []).map(function(m) { return m.name })
  var candidates = (monitors || []).filter(function(m) { return allowed.indexOf(m.name) !== -1 })
  if (!candidates.length) return null
  var axis = direction === "left" || direction === "right" ? "x" : "y"
  var ascending = direction === "left" || direction === "up"
  candidates.sort(function(a, b) {
    var av = monitorCenter(a)[axis], bv = monitorCenter(b)[axis]
    return ascending ? av - bv : bv - av
  })
  return candidates[0].name
}

function parseMode(mode) {
  var match = String(mode || "").match(/^(\d+)x(\d+)@(\d+(?:\.\d+)?)Hz$/)
  return match ? { width: Number(match[1]), height: Number(match[2]), refresh: Number(match[3]), exact: String(mode) } : null
}

function currentMode(monitor) {
  var modes = (monitor.availableModes || []).map(parseMode).filter(Boolean)
  var best = null, distance = Infinity
  for (var i = 0; i < modes.length; i++) {
    var mode = modes[i]
    if (mode.width !== Number(monitor.width) || mode.height !== Number(monitor.height)) continue
    var candidateDistance = Math.abs(mode.refresh - Number(monitor.refreshRate))
    if (candidateDistance < distance) { distance = candidateDistance; best = mode.exact }
  }
  return best || String((monitor.availableModes || [])[0] || "")
}

function modeChoices(availableModes) {
  var seen = {}, choices = []
  for (var i = 0; i < (availableModes || []).length; i++) {
    var parsed = parseMode(availableModes[i])
    if (!parsed) continue
    var label = parsed.width + "x" + parsed.height + " · " + parsed.refresh + " Hz"
    if (seen[label]) continue
    seen[label] = true
    choices.push({ label: label, exact: parsed.exact, width: parsed.width,
      height: parsed.height, refresh: parsed.refresh })
  }
  return choices
}

function resolutionChoices(availableModes) {
  var seen = {}, out = []
  modeChoices(availableModes).forEach(function(mode) {
    var value = mode.width + "x" + mode.height
    if (!seen[value]) { seen[value] = true; out.push({ value: value, label: value }) }
  })
  return out
}

function refreshChoices(availableModes, resolution) {
  var seen = {}, out = []
  modeChoices(availableModes).forEach(function(mode) {
    if (mode.width + "x" + mode.height !== resolution) return
    var label = mode.refresh + " Hz"
    if (!seen[mode.exact]) { seen[mode.exact] = true; out.push({ value: mode.exact, label: label }) }
  })
  return out
}

function modeForResolution(availableModes, resolution, currentModeValue) {
  var current = parseMode(currentModeValue)
  var choices = refreshChoices(availableModes, resolution)
  if (!choices.length) return ""
  if (!current) return choices[0].value
  choices.sort(function(a, b) {
    return Math.abs(parseMode(a.value).refresh - current.refresh) - Math.abs(parseMode(b.value).refresh - current.refresh)
  })
  return choices[0].value
}

if (typeof module !== "undefined") module.exports = {
  SLOTS: SLOTS, MAX_STATION: MAX_STATION, ws: ws, stationOf: stationOf,
  slotOf: slotOf, inGrid: inGrid, host: host, planReconcile: planReconcile,
  planRoleChange: planRoleChange, connectedIdentity: connectedIdentity,
  identities: identities, assignLanes: assignLanes, enabledNames: enabledNames,
  presentForMode: presentForMode, existingStations: existingStations, step: step,
  nextExisting: nextExisting, logicalSize: logicalSize,
  rectanglesOverlap: rectanglesOverlap, layoutOverlaps: layoutOverlaps,
  snapPosition: snapPosition,
  neighborMonitor: neighborMonitor, edgeMonitor: edgeMonitor,
  parseMode: parseMode, currentMode: currentMode, modeChoices: modeChoices,
  resolutionChoices: resolutionChoices, refreshChoices: refreshChoices,
  modeForResolution: modeForResolution
}

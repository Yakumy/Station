var MAX_MONITORS = 3
var MAX_STATION = 10

function normalizeClients(clients, monitors) {
  return (clients || []).map(function(client) {
    var copy = Object.assign({}, client)
    if (typeof client.monitor === "number") {
      var monitor = (monitors || []).find(function(m) { return m.id === client.monitor })
      copy.monitor = monitor ? monitor.name : ""
    }
    return copy
  })
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
    if (old >= 1 && old <= MAX_MONITORS && !used[old]) {
      lanes[connector] = old
      used[old] = true
    }
  }
  for (i = 0; i < monitors.length; i++) {
    var name = monitors[i].name
    if (lanes[name]) continue
    var preferred = Number(nextPreferences[ids[i]])
    var lane = preferred >= 1 && preferred <= MAX_MONITORS && !used[preferred] ? preferred : 0
    if (!lane) for (var candidate = 1; candidate <= MAX_MONITORS; candidate++) {
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
  var mode = parseMode(monitor.mode)
  var width = (mode ? mode.width : Number(monitor.width)) / scale
  var height = (mode ? mode.height : Number(monitor.height)) / scale
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

function resizedPosition(before, after, monitors) {
  var oldSize = logicalSize(before), nextSize = logicalSize(after)
  var old = { x: Number(before.x) || 0, y: Number(before.y) || 0,
    width: oldSize.width, height: oldSize.height }
  var next = { x: old.x, y: old.y, width: nextSize.width, height: nextSize.height }
  var xAnchors = [], yAnchors = [], contacts = [], epsilon = 0.01
  var others = (monitors || []).filter(function(monitor) { return monitor.name !== before.name })
  others.forEach(function(monitor) {
    var size = logicalSize(monitor)
    var other = { x: Number(monitor.x) || 0, y: Number(monitor.y) || 0,
      width: size.width, height: size.height }
    var verticalSpan = Math.min(old.y + old.height, other.y + other.height) - Math.max(old.y, other.y)
    var horizontalSpan = Math.min(old.x + old.width, other.x + other.width) - Math.max(old.x, other.x)
    if (verticalSpan > 0) {
      if (Math.abs(old.x + old.width - other.x) <= epsilon) {
        xAnchors.push({ value: other.x - next.width, span: verticalSpan })
        contacts.push({ side: "left", other: other })
      }
      if (Math.abs(old.x - other.x - other.width) <= epsilon) {
        xAnchors.push({ value: other.x + other.width, span: verticalSpan })
        contacts.push({ side: "right", other: other })
      }
    }
    if (horizontalSpan > 0) {
      if (Math.abs(old.y + old.height - other.y) <= epsilon) {
        yAnchors.push({ value: other.y - next.height, span: horizontalSpan })
        contacts.push({ side: "above", other: other })
      }
      if (Math.abs(old.y - other.y - other.height) <= epsilon) {
        yAnchors.push({ value: other.y + other.height, span: horizontalSpan })
        contacts.push({ side: "below", other: other })
      }
    }
  })
  function strongest(anchors, current) {
    anchors.sort(function(a, b) { return b.span - a.span || Math.abs(a.value - current) - Math.abs(b.value - current) })
    return anchors.length ? anchors[0].value : current
  }
  next.x = strongest(xAnchors, next.x)
  next.y = strongest(yAnchors, next.y)

  var rects = others.map(function(monitor) {
    var size = logicalSize(monitor)
    return { x: Number(monitor.x) || 0, y: Number(monitor.y) || 0,
      width: size.width, height: size.height }
  })
  function integerPosition(candidate) {
    var xs = [Math.floor(candidate.x) - 1, Math.floor(candidate.x), Math.ceil(candidate.x), Math.ceil(candidate.x) + 1]
    var ys = [Math.floor(candidate.y) - 1, Math.floor(candidate.y), Math.ceil(candidate.y), Math.ceil(candidate.y) + 1]
    var best = null, score = Infinity
    xs.forEach(function(x) { ys.forEach(function(y) {
      var integer = { x: x, y: y, width: candidate.width, height: candidate.height }
      if (rects.some(function(other) { return rectanglesOverlap(integer, other) })) return
      var distance = Math.pow(x - candidate.x, 2) + Math.pow(y - candidate.y, 2)
      if (distance < score) { score = distance; best = integer }
    }) })
    return best ? { x: best.x, y: best.y }
      : { x: Math.round(candidate.x), y: Math.round(candidate.y) }
  }
  if (!rects.some(function(other) { return rectanglesOverlap(next, other) }))
    return integerPosition(next)

  // A display can be enclosed by two neighbors, so resolving one collision at
  // a time may oscillate. Search the bounded set of neighbor edges instead and
  // prefer a collision-free placement that retains the most old attachments.
  var xs = [old.x, next.x], ys = [old.y, next.y]
  rects.forEach(function(other) {
    xs.push(other.x - next.width, other.x, other.x + other.width - next.width, other.x + other.width)
    ys.push(other.y - next.height, other.y, other.y + other.height - next.height, other.y + other.height)
  })
  function unique(values) {
    return values.filter(function(value, index) { return values.indexOf(value) === index })
  }
  function span(a1, a2, b1, b2) { return Math.min(a2, b2) - Math.max(a1, b1) }
  function touches(candidate, other) {
    return ((Math.abs(candidate.x + candidate.width - other.x) <= epsilon
          || Math.abs(candidate.x - other.x - other.width) <= epsilon)
        && span(candidate.y, candidate.y + candidate.height, other.y, other.y + other.height) > 0)
      || ((Math.abs(candidate.y + candidate.height - other.y) <= epsilon
          || Math.abs(candidate.y - other.y - other.height) <= epsilon)
        && span(candidate.x, candidate.x + candidate.width, other.x, other.x + other.width) > 0)
  }
  function touchesAxis(candidate, other, axis) {
    if (axis === "x")
      return (Math.abs(candidate.x + candidate.width - other.x) <= epsilon
          || Math.abs(candidate.x - other.x - other.width) <= epsilon)
        && span(candidate.y, candidate.y + candidate.height, other.y, other.y + other.height) > 0
    return (Math.abs(candidate.y + candidate.height - other.y) <= epsilon
        || Math.abs(candidate.y - other.y - other.height) <= epsilon)
      && span(candidate.x, candidate.x + candidate.width, other.x, other.x + other.width) > 0
  }
  function preserves(candidate, contact) {
    var other = contact.other
    if (contact.side === "left")
      return Math.abs(candidate.x + candidate.width - other.x) <= epsilon
        && span(candidate.y, candidate.y + candidate.height, other.y, other.y + other.height) > 0
    if (contact.side === "right")
      return Math.abs(candidate.x - other.x - other.width) <= epsilon
        && span(candidate.y, candidate.y + candidate.height, other.y, other.y + other.height) > 0
    if (contact.side === "above")
      return Math.abs(candidate.y + candidate.height - other.y) <= epsilon
        && span(candidate.x, candidate.x + candidate.width, other.x, other.x + other.width) > 0
    return Math.abs(candidate.y - other.y - other.height) <= epsilon
      && span(candidate.x, candidate.x + candidate.width, other.x, other.x + other.width) > 0
  }
  var best = null, bestScore = Infinity
  unique(xs).forEach(function(x) { unique(ys).forEach(function(y) {
    var candidate = { x: x, y: y, width: next.width, height: next.height }
    if (rects.some(function(other) { return rectanglesOverlap(candidate, other) })) return
    var retained = contacts.filter(function(contact) { return preserves(candidate, contact) }).length
    var attached = rects.some(function(other) { return touches(candidate, other) })
    var wantsX = contacts.some(function(contact) { return contact.side === "left" || contact.side === "right" })
    var wantsY = contacts.some(function(contact) { return contact.side === "above" || contact.side === "below" })
    var sameAxis = (!wantsX || rects.some(function(other) { return touchesAxis(candidate, other, "x") }))
      && (!wantsY || rects.some(function(other) { return touchesAxis(candidate, other, "y") }))
    var score = (contacts.length - retained) * 1000000000 + (attached ? 0 : 100000000)
      + (sameAxis ? 0 : 50000000)
      + Math.pow(x - old.x, 2) + Math.pow(y - old.y, 2)
    if (score < bestScore) { bestScore = score; best = candidate }
  }) })
  if (best) {
    next.x = best.x
    next.y = best.y
  }
  return integerPosition(next)
}

function nearestSnap(value, candidates, threshold) {
  var best = value, distance = Number(threshold)
  for (var i = 0; i < candidates.length; i++) {
    var nextDistance = Math.abs(value - candidates[i])
    if (nextDistance <= distance) { distance = nextDistance; best = candidates[i] }
  }
  return best
}

function snapPosition(display, x, y, displays, threshold) {
  var size = logicalSize(display)
  var xCandidates = [], yCandidates = []
  for (var i = 0; i < (displays || []).length; i++) {
    var other = displays[i]
    if (other.name === display.name) continue
    var otherSize = logicalSize(other)
    var ox = Number(other.x) || 0, oy = Number(other.y) || 0
    xCandidates.push(ox, ox + otherSize.width, ox - size.width, ox + otherSize.width - size.width)
    yCandidates.push(oy, oy + otherSize.height, oy - size.height, oy + otherSize.height - size.height)
  }
  var gridX = Math.round(Number(x) / 10) * 10
  var gridY = Math.round(Number(y) / 10) * 10
  var distance = threshold === undefined ? 20 : threshold
  return { x: nearestSnap(gridX, xCandidates, distance), y: nearestSnap(gridY, yCandidates, distance) }
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

// v1: preserve the physical display when crossing stations perpendicular to
// the display arrangement; wrap to the opposite edge when moving along it.
function boundaryMonitor(currentName, direction, monitors, managedNames) {
  var centers = monitors.filter(function(m) { return managedNames.indexOf(m.name) !== -1 }).map(monitorCenter)
  if (centers.length < 2) return currentName
  var xs = centers.map(function(c) { return c.x })
  var ys = centers.map(function(c) { return c.y })
  var horizontal = Math.max.apply(null, xs) - Math.min.apply(null, xs)
    > Math.max.apply(null, ys) - Math.min.apply(null, ys)
  var movingHorizontally = direction === "left" || direction === "right"
  if (horizontal !== movingHorizontally) return currentName
  return edgeMonitor({ left: "right", right: "left", up: "down", down: "up" }[direction], monitors, managedNames)
}

function windowChanged(before, after) {
  if (!before || !after) return false
  if (Number(before.workspace.id) !== Number(after.workspace.id) || before.monitor !== after.monitor) return true
  return ["at", "size"].some(function(key) {
    return Array.isArray(before[key]) && Array.isArray(after[key])
      && (before[key][0] !== after[key][0] || before[key][1] !== after[key][1])
  })
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
  MAX_MONITORS: MAX_MONITORS, MAX_STATION: MAX_STATION, normalizeClients: normalizeClients,
  connectedIdentity: connectedIdentity,
  identities: identities, assignLanes: assignLanes, enabledNames: enabledNames,
  step: step,
  nextExisting: nextExisting, logicalSize: logicalSize,
  rectanglesOverlap: rectanglesOverlap, layoutOverlaps: layoutOverlaps,
  resizedPosition: resizedPosition, snapPosition: snapPosition,
  neighborMonitor: neighborMonitor, edgeMonitor: edgeMonitor,
  boundaryMonitor: boundaryMonitor, windowChanged: windowChanged,
  parseMode: parseMode, currentMode: currentMode, modeChoices: modeChoices,
  resolutionChoices: resolutionChoices, refreshChoices: refreshChoices,
  modeForResolution: modeForResolution
}

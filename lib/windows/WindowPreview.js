// Stable window identities and one shared interpolation clock for the preview.
function tiles(area, count, split, gap) {
  if (count === 1) return [area]
  var available = Math.max(0, area.width - gap)
  var left = available * (100 - split) / 100
  var right = {x:area.x + left + gap, y:area.y, width:available - left, height:area.height}
  var first = {x:area.x, y:area.y, width:left, height:area.height}
  if (count === 2) return [first, right]
  var height = Math.max(0, area.height - gap) / 2
  return [first, {x:right.x, y:right.y, width:right.width, height:height},
    {x:right.x, y:right.y + height + gap, width:right.width, height:height}]
}
function frame(areas, participants, rotation, stage, split, gap) {
  var occupants = areas.map(function(_, i) { return [i * 2 + 1, i * 2] })
  var count = participants.length
  if (count === 1) {
    var monitor = participants[0]
    if (stage === 1) occupants[monitor].reverse()
  } else if (count > 1) {
    // Stable WINDOW identities rotate through every enabled output. NEXT WINDOW
    // stays on its output and reflows when an outgoing/arriving window moves.
    var windows = participants.map(function(_, i) {
      return participants[(i - Number(rotation) % count + count) % count] * 2 + 1
    })
    participants.forEach(function(monitor, i) { occupants[monitor] = [windows[i], monitor * 2] })
    for (var move = 0; move < Math.min(stage, count); move++) {
      var from = participants[move], to = participants[(move + 1) % count]
      occupants[from].splice(occupants[from].indexOf(windows[move]), 1)
      occupants[to].splice(occupants[to].length - 1, 0, windows[move])
    }
  }
  var result = []
  occupants.forEach(function(ids, monitor) {
    var slots = tiles(areas[monitor], ids.length, split, gap)
    ids.forEach(function(id, slot) { result[id] = slots[slot] })
  })
  return result
}
function rect(index, areas, participants, rotation, progress, split, gap) {
  var steps = Math.max(2, participants.length)
  var stage = Math.max(0, Math.min(steps - 1, Math.floor(progress)))
  var fraction = Math.max(0, Math.min(1, progress - stage))
  var from = frame(areas, participants, rotation, stage, split, gap)[index]
  var to = frame(areas, participants, rotation, stage + 1, split, gap)[index]
  if (fraction === 0) return from
  if (fraction === 1) return to
  var result = {}
  ;['x', 'y', 'width', 'height'].forEach(function(key) {
    result[key] = from[key] + (to[key] - from[key]) * fraction
  })
  return result
}
if (typeof module !== 'undefined') module.exports = {tiles:tiles, frame:frame, rect:rect}

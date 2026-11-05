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
function frame(areas, pair, swapped, stage, split, gap) {
  var occupants = areas.map(function(_, i) { return [i * 2 + 1, i * 2] })
  if (pair.length === 2) {
    var a = pair[0], b = pair[1]
    var outgoing = (swapped ? b : a) * 2 + 1
    var returning = (swapped ? a : b) * 2 + 1
    occupants[a] = stage === 1 ? [a * 2] : [stage === 0 ? outgoing : returning, a * 2]
    occupants[b] = stage === 1 ? [returning, outgoing, b * 2]
      : [stage === 0 ? returning : outgoing, b * 2]
  }
  var result = []
  occupants.forEach(function(ids, monitor) {
    var slots = tiles(areas[monitor], ids.length, split, gap)
    ids.forEach(function(id, slot) { result[id] = slots[slot] })
  })
  return result
}
function rect(index, areas, pair, swapped, progress, split, gap) {
  var stage = progress < 1 ? 0 : 1
  var fraction = Math.max(0, Math.min(1, progress - stage))
  var from = frame(areas, pair, swapped, stage, split, gap)[index]
  var to = frame(areas, pair, swapped, stage + 1, split, gap)[index]
  var result = {}
  ;['x', 'y', 'width', 'height'].forEach(function(key) {
    result[key] = from[key] + (to[key] - from[key]) * fraction
  })
  return result
}
if (typeof module !== 'undefined') module.exports = {tiles:tiles, frame:frame, rect:rect}

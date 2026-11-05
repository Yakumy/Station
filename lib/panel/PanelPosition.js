// KeyboardPanel centers along the bar with centerOnBar. Its gap controls the
// other axis, so choose the gap that puts the card at the screen midpoint.
function centerGap(barPosition, screenWidth, screenHeight, barWidth, barHeight,
    desiredWidth, desiredHeight, margin, defaultGap) {
  var horizontalBar = barPosition === "top" || barPosition === "bottom"
  var screenSize = horizontalBar ? Number(screenHeight) : Number(screenWidth)
  var barSize = horizontalBar ? Number(barHeight) : Number(barWidth)
  var desiredSize = horizontalBar ? Number(desiredHeight) : Number(desiredWidth)
  if (!isFinite(screenSize) || screenSize <= 0 || !isFinite(barSize)
      || !isFinite(desiredSize) || desiredSize <= 0) return defaultGap
  var fittedSize = Math.min(desiredSize, Math.max(0, screenSize - 2 * margin))
  // Keep the card beyond the bar when the monitor is too small to center it
  // without covering that bar.
  return Math.max(defaultGap, Math.round((screenSize - fittedSize) / 2 - barSize))
}

function verticalBarPosition(position) {
  return position === "left" || position === "right"
}

// A layer-shell window changes its logical edge before its backing geometry
// necessarily swaps axes. Keep the previous edge until width/height agree with
// the requested orientation so consumers never combine new-edge math with an
// old full-axis dimension.
function stableBarPosition(previous, requested, barWidth, barHeight, expectedThickness) {
  if (verticalBarPosition(previous) === verticalBarPosition(requested)) return requested
  var width = Number(barWidth), height = Number(barHeight)
  if (!isFinite(width) || !isFinite(height) || width <= 0 || height <= 0) return previous
  var geometryIsVertical = height > width
  if (geometryIsVertical !== verticalBarPosition(requested)) return previous
  var thickness = geometryIsVertical ? width : height
  var expected = Number(expectedThickness)
  if (isFinite(expected) && expected > 0 && thickness > expected + 2) return previous
  return requested
}

if (typeof module !== "undefined") module.exports = {
  centerGap: centerGap,
  stableBarPosition: stableBarPosition,
  verticalBarPosition: verticalBarPosition
}

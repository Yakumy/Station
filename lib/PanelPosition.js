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

if (typeof module !== "undefined") module.exports = { centerGap: centerGap }

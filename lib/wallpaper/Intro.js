// The video and its matching still use one normalized source rectangle.
function request(status, scene, layout, imageWidth, imageHeight, crop) {
  if (!status || status.source_rects !== 1 || !status.intro || !status.ready || status.error
      || !Number.isSafeInteger(status.media_id) || !scene.followTheme
      || imageWidth <= 0 || imageHeight <= 0) return null
  var slash = scene.source.lastIndexOf("/")
  var stem = scene.source.slice(slash + 1).replace(/\.[^.]+$/, "")
  var prefix = scene.source.slice(0, slash) + "/intros/" + stem + "."
  if (typeof status.intro_path !== "string" || status.intro_path.indexOf(prefix) !== 0
      || !/^(mp4|m4v|mov|webm|mkv|avi)$/.test(status.intro_path.slice(prefix.length))) return null
  var outputs = layout.displays.map(function(display) {
    var c = crop(scene, layout, display, imageWidth, imageHeight)
    return {name: display.name, x: c.x / imageWidth, y: c.y / imageHeight,
      width: c.width / imageWidth, height: c.height / imageHeight}
  })
  return outputs.length ? {cmd: "source-rects", hold: true, handoff: status.composition_handoff === 1, media_id: status.media_id, outputs: outputs} : null
}
if (typeof module !== "undefined") module.exports = {request: request}

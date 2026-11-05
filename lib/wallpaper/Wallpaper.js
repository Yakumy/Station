// Pure geometry and preference validation, shared by preview and desktop surfaces.
function object(value) { return value && typeof value === "object" && !Array.isArray(value) }
function bounded(value, low, high, fallback) {
  var n = Number(value)
  return isFinite(n) ? Math.max(low, Math.min(high, n)) : fallback
}
function path(value) {
  return typeof value === "string" && value[0] === "/" && !/[\x00-\x1f\x7f]/.test(value) ? value : ""
}
function framing(value) {
  value = object(value) ? value : {}
  return { zoom: bounded(value.zoom === undefined ? 1 : value.zoom, 1, 8, 1),
    x: bounded(value.x === undefined ? 0.5 : value.x, 0, 1, 0.5),
    y: bounded(value.y === undefined ? 0.5 : value.y, 0, 1, 0.5) }
}
// One frame per monitor and mode. A centered, unzoomed frame is no frame at all, so
// resetting a monitor hands it back to Omarchy's stock surface where that applies.
function frameMap(value) {
  var map = {}
  if (object(value)) Object.keys(value).slice(0, 64).forEach(function(key) {
    if (key === "__proto__" || !object(value[key])) return
    var f = framing(value[key])
    if (f.zoom !== 1 || Math.abs(f.x - 0.5) > 0.0001 || Math.abs(f.y - 0.5) > 0.0001) map[key] = f
  })
  return map
}
function frames(value) {
  value = object(value) ? value : {}
  return { same: frameMap(value.same), individual: frameMap(value.individual) }
}
function profile(value) {
  value = object(value) ? value : {}
  var perDisplay = {}
  if (object(value.perDisplay)) Object.keys(value.perDisplay).slice(0, 64).forEach(function(key) {
    if (key !== "__proto__" && path(value.perDisplay[key])) perDisplay[key] = path(value.perDisplay[key])
  })
  return { source: path(value.source), perDisplay: perDisplay, framing: framing(value.framing),
    frames: frames(value.frames), safe: value.safe === true }
}
function settings(value) {
  value = object(value) ? value : {}
  var profiles = {}
  if (object(value.profiles)) Object.keys(value.profiles).slice(-64).forEach(function(key) {
    if (key !== "__proto__") profiles[key] = profile(value.profiles[key])
  })
  return { mode: ["same", "individual", "span"].indexOf(value.mode) >= 0 ? value.mode : "same",
    followTheme: value.followTheme !== false, pinned: profile(value.pinned), profiles: profiles }
}
function resolve(value, themeKey, themePath, themeRevision) {
  var s = settings(value)
  var p = s.followTheme ? profile(s.profiles[themeKey]) : s.pinned
  if (s.followTheme || !p.source) p.source = path(themePath)
  return { mode: s.mode, followTheme: s.followTheme, source: p.source,
    perDisplay: s.followTheme ? {} : p.perDisplay, framing: p.framing, frames: p.frames,
    safe: s.followTheme || p.safe,
    revision: s.followTheme ? String(themeRevision || "") : "" }
}
function topology(monitors, identities) {
  var displays = []
  ;(monitors || []).forEach(function(m, index) {
    if (m.disabled || m.enabled === false || (m.mirrorOf && m.mirrorOf !== "none")
        || !(m.width > 0 && m.height > 0)) return
    var rotated = [1, 3, 5, 7].indexOf(Number(m.transform)) >= 0
    var scale = bounded(m.scale || 1, 0.25, 8, 1)
    displays.push({ name: m.name, identity: identities[index], x: Number(m.x) || 0, y: Number(m.y) || 0,
      width: (rotated ? m.height : m.width) / scale,
      height: (rotated ? m.width : m.height) / scale, scale: scale })
  })
  var minX = displays.length ? Math.min.apply(null, displays.map(function(d) { return d.x })) : 0
  var minY = displays.length ? Math.min.apply(null, displays.map(function(d) { return d.y })) : 0
  var width = Math.max.apply(null, [1].concat(displays.map(function(d) { return d.x + d.width - minX })))
  var height = Math.max.apply(null, [1].concat(displays.map(function(d) { return d.y + d.height - minY })))
  displays.forEach(function(d) { d.x -= minX; d.y -= minY })
  return { displays: displays, width: width, height: height,
    density: Math.max.apply(null, [1].concat(displays.map(function(d) { return d.scale }))) }
}
function composition(layout, imageWidth, imageHeight, frame) {
  var f = framing(frame)
  var unit = Math.min(imageWidth / layout.width, imageHeight / layout.height) / f.zoom
  unit = isFinite(unit) && unit > 0 ? unit : 1
  return { unit: unit, x: Math.max(0, imageWidth - layout.width * unit) * f.x,
    y: Math.max(0, imageHeight - layout.height * unit) * f.y,
    width: layout.width * unit, height: layout.height * unit }
}
function hasFrame(scene, display) {
  var map = scene.frames && scene.frames[scene.mode]
  return !!map && !!display && Object.prototype.hasOwnProperty.call(map, display.identity)
}
function frameFor(scene, display) {
  return framing(hasFrame(scene, display) ? scene.frames[scene.mode][display.identity] : null)
}
function withFrame(scene, identity, value) {
  if (scene.mode !== "same" && scene.mode !== "individual") return scene
  var next = frames(scene.frames)
  next[scene.mode][identity] = framing(value)
  return Object.assign({}, scene, { frames: frames(next) })
}
// A frame belongs to the image it framed. Identity names one monitor's own image,
// otherwise the shared image changed, along with every monitor that shows it.
function framesWithoutImage(scene, identity) {
  var next = frames(scene.frames)
  if (identity) { delete next.individual[identity]; return next }
  next.same = {}
  Object.keys(next.individual).forEach(function(key) {
    if (!scene.perDisplay || !scene.perDisplay[key]) delete next.individual[key]
  })
  return next
}
// The source rectangle one monitor shows: its place in the group under Span, otherwise
// its own frame, where zoom 1 is the largest crop that still fills the monitor.
function crop(scene, layout, display, imageWidth, imageHeight) {
  if (scene.mode !== "span") return composition(display, imageWidth, imageHeight, frameFor(scene, display))
  var c = composition(layout, imageWidth, imageHeight, scene.framing)
  return { unit: c.unit, x: c.x + display.x * c.unit, y: c.y + display.y * c.unit,
    width: display.width * c.unit, height: display.height * c.unit }
}
// Move the image with the pointer. dx and dy are logical monitor pixels.
function panned(display, imageWidth, imageHeight, frame, dx, dy) {
  var f = framing(frame)
  if (!(imageWidth > 0 && imageHeight > 0)) return f
  var c = composition(display, imageWidth, imageHeight, f)
  var slackX = (imageWidth - c.width) / c.unit
  var slackY = (imageHeight - c.height) / c.unit
  return framing({ zoom: f.zoom, x: slackX > 0.000001 ? f.x - dx / slackX : 0.5,
    y: slackY > 0.000001 ? f.y - dy / slackY : 0.5 })
}
// Zoom around a monitor point, which keeps the same part of the image under it.
function zoomed(display, imageWidth, imageHeight, frame, factor, pointX, pointY) {
  var f = framing(frame)
  if (!(imageWidth > 0 && imageHeight > 0)) return f
  var zoom = bounded(f.zoom * factor, 1, 8, 1)
  if (Math.abs(zoom - 1) < 0.001) zoom = 1
  var before = composition(display, imageWidth, imageHeight, f)
  var after = composition(display, imageWidth, imageHeight, { zoom: zoom })
  var slackX = imageWidth - after.width
  var slackY = imageHeight - after.height
  return framing({ zoom: zoom,
    x: slackX > 0.000001 ? (before.x + pointX * before.unit - pointX * after.unit) / slackX : 0.5,
    y: slackY > 0.000001 ? (before.y + pointY * before.unit - pointY * after.unit) / slackY : 0.5 })
}
function recommendation(layout, frame) {
  var density = layout.density * framing(frame).zoom
  return { width: Math.ceil(layout.width * density), height: Math.ceil(layout.height * density) }
}
function sourceFor(scene, display) {
  return scene.mode === "individual" && Object.prototype.hasOwnProperty.call(scene.perDisplay, display.identity)
      && scene.perDisplay[display.identity]
    ? scene.perDisplay[display.identity] : scene.source
}
function directory(value) {
  var p = path(value)
  return p ? p.slice(0, p.lastIndexOf("/")) || "/" : ""
}
// Every create, rename, delete and finished write in the state directory and in the
// image's directory. Paths travel as separate arguments.
function watchCommand(stateDir, imageDir) {
  var command = ["inotifywait", "-m", "-e", "create,moved_to,moved_from,delete,close_write", "--format", "%w%f", "--", stateDir]
  return imageDir && imageDir !== stateDir ? command.concat([imageDir]) : command
}
// The image's directory can be a busy one, so only the image itself counts there.
function watchRelevant(changed, stateDir, image) {
  return changed === image || String(changed).indexOf(stateDir + "/") === 0
}
if (typeof module !== "undefined") module.exports = {
  path: path, directory: directory, watchCommand: watchCommand, watchRelevant: watchRelevant, framing: framing, profile: profile, settings: settings, resolve: resolve,
  topology: topology, composition: composition, recommendation: recommendation, sourceFor: sourceFor,
  frames: frames, hasFrame: hasFrame, frameFor: frameFor, withFrame: withFrame, framesWithoutImage: framesWithoutImage,
  crop: crop, panned: panned, zoomed: zoomed
}

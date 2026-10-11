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
function profile(value) {
  value = object(value) ? value : {}
  var perDisplay = {}
  if (object(value.perDisplay)) Object.keys(value.perDisplay).slice(0, 64).forEach(function(key) {
    if (key !== "__proto__" && path(value.perDisplay[key])) perDisplay[key] = path(value.perDisplay[key])
  })
  return { source: path(value.source), perDisplay: perDisplay, framing: framing(value.framing) }
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
function resolve(value, themeKey, themePath) {
  var s = settings(value)
  var p = s.followTheme ? profile(s.profiles[themeKey]) : s.pinned
  if (!p.source) p.source = path(themePath)
  return { mode: s.mode, followTheme: s.followTheme, source: p.source,
    perDisplay: p.perDisplay, framing: p.framing }
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
function recommendation(layout, frame) {
  var density = layout.density * framing(frame).zoom
  return { width: Math.ceil(layout.width * density), height: Math.ceil(layout.height * density) }
}
function sourceFor(scene, display) {
  return scene.mode === "individual" && Object.prototype.hasOwnProperty.call(scene.perDisplay, display.identity)
      && scene.perDisplay[display.identity]
    ? scene.perDisplay[display.identity] : scene.source
}
if (typeof module !== "undefined") module.exports = {
  path: path, framing: framing, profile: profile, settings: settings, resolve: resolve,
  topology: topology, composition: composition, recommendation: recommendation, sourceFor: sourceFor
}

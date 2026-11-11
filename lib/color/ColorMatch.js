// Color Match policy. Each monitor's settings become one ICC v4 matrix/TRC
// display profile. Hyprland turns it into a 3D LUT with lcms2, so white balance,
// brightness and saturation live in the colorant matrix and gamma in the shared
// tone curve. VCGT ramps are not used: they never reached the CRTC on the
// maintainer's i915 output (see platform findings).

var limits = {
  temperature: [4000, 9000, 6500],
  tint: [-100, 100, 0],
  brightness: [50, 100, 100],
  gamma: [70, 140, 100],
  saturation: [0, 150, 100]
}
var KEYS = ["temperature", "tint", "brightness", "gamma", "saturation"]
var CONNECTOR = /^[A-Za-z0-9_.:-]{1,64}$/
var PROFILE = /^[A-Za-z0-9_.:-]{1,64}-[0-9a-f]{8}\.icc$/
// The strongest green/magenta shift, as a fraction of the channel's light.
var TINT_RANGE = 0.3
// Saturation 0 has no inverse, so the matrix keeps this much color. It is far below
// what the eye sees, and keeps the s15Fixed16 colorants exact enough for lcms.
var SATURATION_FLOOR = 0.002

function step(key) { return key === "temperature" ? 100 : 1 }

function clean(source) {
  var out = {}
  KEYS.forEach(function(key) {
    var range = limits[key], n = source && source[key]
    out[key] = typeof n === "number" && isFinite(n)
      ? Math.max(range[0], Math.min(range[1], Math.round(n / step(key)) * step(key))) : range[2]
  })
  return out
}

function isNeutral(source) {
  var value = clean(source)
  return KEYS.every(function(key) { return value[key] === limits[key][2] })
}

// Planckian locus chromaticity (Kim et al. cubic spline, 1667 K to 25000 K).
function planckXY(kelvin) {
  var t = kelvin, x
  if (t <= 4000) x = -0.2661239e9 / (t * t * t) - 0.2343589e6 / (t * t) + 0.8776956e3 / t + 0.179910
  else x = -3.0258469e9 / (t * t * t) + 2.1070379e6 / (t * t) + 0.2226347e3 / t + 0.240390
  var y
  if (t <= 2222) y = -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683
  else if (t <= 4000) y = -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867
  else y = 3.0817580 * x * x * x - 5.87338670 * x * x + 3.75112997 * x - 0.37001483
  return [x, y]
}

// Linear sRGB (D65) of a Planckian white with luminance 1.
function planckRGB(kelvin) {
  var xy = planckXY(kelvin)
  var X = xy[0] / xy[1], Y = 1, Z = (1 - xy[0] - xy[1]) / xy[1]
  return [
    3.2404542 * X - 1.5371385 * Y - 0.4985314 * Z,
    -0.9692660 * X + 1.8760108 * Y + 0.0415560 * Z,
    0.0556434 * X - 0.2040259 * Y + 1.0572252 * Z
  ]
}

// Linear per-channel gains of the corrected white. The default is exactly 1, 1, 1.
// The brightest channel stays at 1 so no channel clips, then brightness scales all.
function gains(source) {
  var value = clean(source)
  var warm = planckRGB(value.temperature), base = planckRGB(limits.temperature[2])
  var rgb = [warm[0] / base[0], warm[1] / base[1], warm[2] / base[2]]
  var tint = value.tint / 100 * TINT_RANGE
  // Positive tint is magenta (less green), negative is green (less red and blue).
  if (tint > 0) rgb[1] *= 1 - tint
  else { rgb[0] *= 1 + tint; rgb[2] *= 1 + tint }
  var peak = Math.max(rgb[0], rgb[1], rgb[2])
  var scale = value.brightness / 100 / peak
  return rgb.map(function(channel) { return channel * scale })
}

// Luminance-preserving saturation matrix in linear sRGB (Rec. 709 weights).
function saturationMatrix(amount) {
  var s = amount, w = [0.2126, 0.7152, 0.0722], m = []
  for (var row = 0; row < 3; row++) for (var col = 0; col < 3; col++)
    m.push((1 - s) * w[col] + (row === col ? s : 0))
  return m
}

function invert3(m) {
  var a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7], i = m[8]
  var A = e * i - f * h, B = -(d * i - f * g), C = d * h - e * g
  var det = a * A + b * B + c * C
  if (!isFinite(det) || Math.abs(det) < 1e-9) throw new Error("singular color matrix")
  return [A / det, -(b * i - c * h) / det, (b * f - c * e) / det,
    B / det, (a * i - c * g) / det, -(a * f - c * d) / det,
    C / det, -(a * h - b * g) / det, (a * e - b * d) / det]
}

function multiply3(p, q) {
  var out = []
  for (var row = 0; row < 3; row++) for (var col = 0; col < 3; col++)
    out.push(p[row * 3] * q[col] + p[row * 3 + 1] * q[3 + col] + p[row * 3 + 2] * q[6 + col])
  return out
}

// sRGB to XYZ, adapted to the D50 profile connection space (columns are rXYZ, gXYZ, bXYZ).
var SRGB_D50 = [0.4360747, 0.3850649, 0.1430804, 0.2225045, 0.7168786, 0.0606169, 0.0139322, 0.0971045, 0.7141733]

// The display is described as if it showed `gains * saturation * content`.
// lcms inverts that description, so the screen receives the corrected signal.
function colorants(source) {
  var value = clean(source), g = gains(value)
  var correction = multiply3([g[0], 0, 0, 0, g[1], 0, 0, 0, g[2]], saturationMatrix(Math.max(SATURATION_FLOOR, value.saturation / 100)))
  return multiply3(SRGB_D50, invert3(correction))
}

function srgbDecode(v) { return v <= 0.04045 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4) }

// Tone curve samples: the sRGB curve raised to 100 / gamma. A higher gamma value
// darkens the midtones. Black and white stay fixed.
function toneCurve(source, size) {
  var value = clean(source), power = 100 / value.gamma, out = []
  for (var i = 0; i < size; i++) out.push(Math.pow(srgbDecode(i / (size - 1)), power))
  return out
}

function u8(out, n) { out.push(n & 255) }
function u16(out, n) { out.push((n >>> 8) & 255, n & 255) }
function u32(out, n) { out.push((n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255) }
function s15(out, v) { u32(out, Math.round(v * 65536) | 0) }
function ascii(out, text) { for (var i = 0; i < text.length; i++) u8(out, text.charCodeAt(i)) }

function xyzTag(x, y, z) { var out = []; ascii(out, "XYZ "); u32(out, 0); s15(out, x); s15(out, y); s15(out, z); return out }
function mlucTag(text) {
  var out = []
  ascii(out, "mluc"); u32(out, 0); u32(out, 1); u32(out, 12); ascii(out, "enUS")
  u32(out, text.length * 2); u32(out, 28)
  for (var i = 0; i < text.length; i++) u16(out, text.charCodeAt(i))
  return out
}
function curvTag(samples) {
  var out = []
  ascii(out, "curv"); u32(out, 0); u32(out, samples.length)
  samples.forEach(function(v) { u16(out, Math.max(0, Math.min(65535, Math.round(v * 65535)))) })
  return out
}
function sf32Tag(values) { var out = []; ascii(out, "sf32"); u32(out, 0); values.forEach(function(v) { s15(out, v) }); return out }

var D50 = [0.9642, 1.0, 0.8249]
var BRADFORD_D65_D50 = [1.0478112, 0.0228866, -0.0501270, 0.0295424, 0.9904844, -0.0170491, -0.0092345, 0.0150436, 0.7521316]

// Byte array of the ICC v4 display profile for `source`.
function profileBytes(source) {
  var m = colorants(source), trc = curvTag(toneCurve(source, 1024))
  var tags = [
    ["desc", mlucTag("Station Color Match")],
    ["cprt", mlucTag("No copyright, use freely")],
    ["wtpt", xyzTag(D50[0], D50[1], D50[2])],
    ["rXYZ", xyzTag(m[0], m[3], m[6])],
    ["gXYZ", xyzTag(m[1], m[4], m[7])],
    ["bXYZ", xyzTag(m[2], m[5], m[8])],
    ["rTRC", trc], ["gTRC", trc], ["bTRC", trc],
    ["chad", sf32Tag(BRADFORD_D65_D50)]
  ]
  var offset = 128 + 4 + 12 * tags.length, table = [], data = [], shared = null
  tags.forEach(function(tag) {
    var body = tag[1]
    if (body === trc && shared !== null) { table.push([tag[0], shared, body.length]); return }
    while (offset % 4) { data.push(0); offset++ }
    if (body === trc) shared = offset
    table.push([tag[0], offset, body.length])
    data = data.concat(body)
    offset += body.length
  })
  while (offset % 4) { data.push(0); offset++ }
  var out = []
  u32(out, offset); u32(out, 0); u32(out, 0x04300000)
  ascii(out, "mntrRGB XYZ ")
  ;[2026, 1, 1, 0, 0, 0].forEach(function(n) { u16(out, n) })
  // Platform, flags, manufacturer, model, attributes (8 bytes), perceptual intent.
  ascii(out, "acsp"); for (var h = 0; h < 7; h++) u32(out, 0)
  s15(out, D50[0]); s15(out, D50[1]); s15(out, D50[2])
  u32(out, 0)
  for (var i = 0; i < 44; i++) u8(out, 0)
  u32(out, tags.length)
  table.forEach(function(row) { ascii(out, row[0]); u32(out, row[1]); u32(out, row[2]) })
  return out.concat(data)
}

var B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
function base64(bytes) {
  var out = ""
  for (var i = 0; i < bytes.length; i += 3) {
    var n = (bytes[i] << 16) | ((bytes[i + 1] || 0) << 8) | (bytes[i + 2] || 0)
    out += B64[(n >> 18) & 63] + B64[(n >> 12) & 63]
      + (i + 1 < bytes.length ? B64[(n >> 6) & 63] : "=") + (i + 2 < bytes.length ? B64[n & 63] : "=")
  }
  return out
}

// FNV-1a over the bytes: a short content name, so Hyprland never reuses a stale file.
function hash(bytes) {
  var h = 0x811c9dc5
  for (var i = 0; i < bytes.length; i++) { h ^= bytes[i]; h = Math.imul(h, 0x01000193) >>> 0 }
  return ("00000000" + h.toString(16)).slice(-8)
}

function connector(value) {
  value = String(value || "")
  if (!CONNECTOR.test(value)) throw new Error("invalid connector")
  return value
}

function luaString(value) {
  return '"' + String(value).replace(/\\/g, "\\\\").replace(/"/g, '\\"')
    .replace(/\n/g, "\\n").replace(/\r/g, "\\r") + '"'
}

// Profile file name and payload for one connector. Null means no profile.
function profile(name, source) {
  name = connector(name)
  if (isNeutral(source)) return null
  var bytes = profileBytes(source)
  return { name: name, file: name + "-" + hash(bytes) + ".icc", base64: base64(bytes) }
}

function profilePath(directory, file) {
  if (!PROFILE.test(String(file))) throw new Error("invalid profile name")
  directory = String(directory)
  if (/[\u0000-\u001f"\\]/.test(directory) || directory.charAt(0) !== "/") throw new Error("invalid profile directory")
  return directory + "/" + file
}

// The live apply. Errors surface through hyprctl's reply.
function rule(name, directory, file) {
  return "hl.monitor({ output = " + luaString(connector(name)) + ", icc = " + luaString(profilePath(directory, file)) + " })"
}

var HEADER = "-- Managed by the Station plugin (Color Match); removed with it."
// A missing or rejected profile must never become a configuration error at login.
var HELPER = [
  "local function station_icc(output, path)",
  "  if type(io) == \"table\" and type(io.open) == \"function\" then",
  "    local file = io.open(path, \"rb\")",
  "    if not file then return end",
  "    file:close()",
  "  end",
  "  pcall(hl.monitor, { output = output, icc = path })",
  "end"
]
var LINE = /^station_icc\("([A-Za-z0-9_.:-]{1,64})", "((?:[^"\\]|\\.)*)"\)$/

// The toggle file Omarchy loads after monitors.lua. Each row is { name, file }.
// No rows means no file.
function source(directory, rows) {
  if (!rows || !rows.length) return ""
  var lines = [HEADER].concat(HELPER)
  rows.slice().sort(function(a, b) { return a.name < b.name ? -1 : a.name > b.name ? 1 : 0 })
    .forEach(function(row) {
      lines.push("station_icc(" + luaString(connector(row.name)) + ", " + luaString(profilePath(directory, row.file)) + ")")
    })
  return lines.join("\n") + "\n"
}

// Rows of a file this module wrote. Anything else is ignored.
function rows(text) {
  var out = []
  String(text || "").split("\n").forEach(function(line) {
    var match = line.match(LINE)
    if (!match) return
    var file = match[2].slice(match[2].lastIndexOf("/") + 1)
    if (PROFILE.test(file)) out.push({ name: match[1], file: file })
  })
  return out
}

// What a change from `before` rows to `after` rows needs. Only connected monitors
// are applied live; a connected monitor that loses its profile needs a reload.
function change(before, after, connected) {
  function find(list, name) { return list.find(function(row) { return row.name === name }) || null }
  var live = connected || []
  var removed = before.some(function(row) { return live.indexOf(row.name) !== -1 && !find(after, row.name) })
  if (removed) return { action: "reload", rows: [] }
  var changed = after.filter(function(row) {
    var old = find(before, row.name)
    return live.indexOf(row.name) !== -1 && (!old || old.file !== row.file)
  })
  return { action: changed.length ? "eval" : "none", rows: changed }
}

// Settings are stored by display identity, so they follow a monitor across ports.
// `displays` rows are { name, identity, hdr }. An HDR output gets no profile,
// because an ICC overrides its HDR preset. Returns the profile rows to apply.
function plan(settings, displays) {
  var out = []
  ;(displays || []).forEach(function(display) {
    var key = String(display.identity || "")
    if (display.hdr || !key || !settings || !Object.prototype.hasOwnProperty.call(settings, key)) return
    var row = profile(display.name, settings[key])
    if (row) out.push(row)
  })
  return out
}

// The rows the file should hold: connected monitors from their settings, and an
// absent connector keeps its row, so unplugging never costs a reload.
function desired(settings, displays, before) {
  var names = (displays || []).map(function(display) { return display.name })
  return plan(settings, displays).concat((before || []).filter(function(row) {
    return names.indexOf(row.name) === -1
  }))
}

function cleanAll(settings) {
  var out = {}
  Object.keys(settings && typeof settings === "object" ? settings : {}).slice(0, 32).forEach(function(key) {
    if (typeof key !== "string" || !key || key.length > 512) return
    var value = clean(settings[key])
    if (!isNeutral(value)) out[key] = value
  })
  return out
}

if (typeof module !== "undefined") module.exports = {
  limits: limits, KEYS: KEYS, clean: clean, isNeutral: isNeutral, gains: gains, colorants: colorants,
  toneCurve: toneCurve, profileBytes: profileBytes, base64: base64, hash: hash, profile: profile,
  rule: rule, source: source, rows: rows, change: change, plan: plan, desired: desired, cleanAll: cleanAll, step: step,
  HEADER: HEADER, profilePath: profilePath
}

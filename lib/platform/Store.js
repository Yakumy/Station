var CONFIG_VERSION = 11
var STATE_VERSION = 4

function configDefaults() {
  return { version: CONFIG_VERSION, lanes: {}, mode: "extend", enabled: [], singleTarget: "",
    direction: "ltr", followFocus: true, graceMs: 0,
    keybindings: {}, approvedReplacements: [], hideNative: true, hideDisplay: true,
    compactMode: "hover", showOpenApps: true,
    panelPosition: "bar-landscape", bars: {}, wallpaper: { mode: "same", followTheme: true },
    workspaceMode: "station", stationCount: 3, workspaceLayout: { repetitive: {}, nonrepetitive: {} },
    indicatorStyle: "prefixed", colorMatch: {} }
}

function stateDefaults() {
  return { version: STATE_VERSION, lastStation: 1, appliedBinds: [], stockLease: null, displayLease: null,
    barBlurLease: null, pendingTransaction: null, activeNoticeShown: false, legacyWorkspaceGrid: false }
}

function validObject(value) { return value && typeof value === "object" && !Array.isArray(value) }

// Per connector: a Repetitive count of 1 to 10, and the Non-repetitive numbers the
// monitor owns. Grid checks that the lists fit together for the monitors present.
function workspaceLayout(value) {
  var source = validObject(value) ? value : {}
  var out = { repetitive: {}, nonrepetitive: {} }
  var name = /^[A-Za-z0-9_.:-]{1,64}$/
  var repetitive = validObject(source.repetitive) ? source.repetitive : {}
  Object.keys(repetitive).forEach(function(key) {
    var count = repetitive[key]
    if (name.test(key) && Number.isInteger(count) && count >= 1 && count <= 10) out.repetitive[key] = count
  })
  var owned = validObject(source.nonrepetitive) ? source.nonrepetitive : {}
  Object.keys(owned).forEach(function(key) {
    var row = owned[key]
    if (!name.test(key) || !Array.isArray(row) || row.length < 1 || row.length > 10) return
    if (!row.every(function(n, i) { return Number.isInteger(n) && n >= 1 && n <= 20 && row.indexOf(n) === i })) return
    out.nonrepetitive[key] = row.slice().sort(function(a, b) { return a - b })
  })
  return out
}

function choice(value, allowed, fallback) { return allowed.indexOf(value) !== -1 ? value : fallback }

function rounded(value, minimum, maximum, fallback) {
  var number = Number(value)
  return isFinite(number) ? Math.max(minimum, Math.min(maximum, Math.round(number))) : fallback
}

function barRow(value) {
  var row = validObject(value) ? value : {}
  return { enabled: row.enabled !== false,
    position: choice(row.position, ["top", "bottom", "left", "right"], "top"),
    width: rounded(row.width, 1, 100, 100), height: rounded(row.height, 0, 1000, 0),
    background: choice(row.background, ["solid", "transparent", "blur"], "solid"),
    style: choice(row.style, ["default", "pill"], "default"),
    contentSize: rounded(row.contentSize, 0, 1000, 0) }
}

// Color Match values by display identity. Their owner clamps each value.
function colorRows(value) {
  var colors = validObject(value) ? value : {}
  var out = {}
  Object.keys(colors).slice(0, 32).forEach(function(key) {
    if (key.length <= 512 && validObject(colors[key])) out[key] = colors[key]
  })
  return out
}

function loadConfig(value) {
  var source = validObject(value) ? value : {}
  var out = Object.assign(configDefaults(), source)
  out.mode = choice(out.mode, ["extend", "mirror", "single"], "extend")
  out.direction = choice(out.direction, ["ltr", "rtl", "ttb", "btt"], "ltr")
  var grace = Number(out.graceMs)
  out.graceMs = isFinite(grace) ? Math.max(0, Math.min(30000, grace)) : 0
  out.workspaceMode = choice(out.workspaceMode, ["station", "repetitive", "nonrepetitive"], "station")
  var stations = Number(out.stationCount)
  out.stationCount = Number.isInteger(stations) && stations >= 1 && stations <= 10 ? stations : 3
  out.workspaceLayout = workspaceLayout(out.workspaceLayout)
  // Sync's old count and totals are gone; Station mode has its own 1-to-10 count,
  // and each monitor starts with five workspaces in the per-monitor modes.
  delete out.minStations
  delete out.workspaceCounts
  out.indicatorStyle = choice(out.indicatorStyle, ["prefixed", "number", "roman", "kanji"], "prefixed")
  out.lanes = validObject(out.lanes) ? out.lanes : {}
  out.keybindings = validObject(out.keybindings) ? out.keybindings : {}
  out.enabled = Array.isArray(out.enabled) ? out.enabled : []
  out.approvedReplacements = Array.isArray(out.approvedReplacements) ? out.approvedReplacements : []
  out.bars = validObject(out.bars) ? out.bars : {}
  out.colorMatch = colorRows(out.colorMatch)
  var bars = {}
  Object.keys(out.bars).forEach(function(name) { bars[name] = barRow(out.bars[name]) })
  out.bars = bars
  // `stationAppsMode` was one setting for both: Always on is compact Off, Off is
  // compact On without apps.
  var legacyApps = source.stationAppsMode
  out.compactMode = choice(source.compactMode, ["off", "hover", "on"],
    legacyApps === "always" ? "off" : legacyApps === "hide" ? "on" : "hover")
  out.showOpenApps = typeof source.showOpenApps === "boolean" ? source.showOpenApps : legacyApps !== "hide"
  delete out.stationAppsMode
  out.hideNative = out.hideNative !== false
  out.hideDisplay = out.hideDisplay !== false
  // Migrate earlier style names without changing the user's placement: the
  // first "center", then "bar-wide", "bar-tall" and "center-wide".
  var legacyPosition = { center: "center-landscape", "bar-wide": "bar-landscape",
    "bar-tall": "bar-portrait", "center-wide": "center-landscape" }[out.panelPosition]
  if (legacyPosition) out.panelPosition = legacyPosition
  out.panelPosition = choice(out.panelPosition, ["bar-landscape", "bar-portrait", "center-landscape"], "bar-landscape")
  // Follow focus is a Station invariant now; the former preference is retained
  // only as a migration input and cannot leave the feature disabled.
  out.followFocus = true
  out.version = CONFIG_VERSION
  return out
}

function loadState(value) {
  var source = validObject(value) ? value : {}
  var out = Object.assign(stateDefaults(), source)
  out.lastStation = Math.max(1, Math.min(10, Number(out.lastStation) || 1))
  out.appliedBinds = Array.isArray(out.appliedBinds) ? out.appliedBinds : []
  out.barBlurLease = validObject(out.barBlurLease)
      && typeof out.barBlurLease.originalEnabled === "boolean"
      && typeof out.barBlurLease.changed === "boolean"
    ? { originalEnabled: out.barBlurLease.originalEnabled, changed: out.barBlurLease.changed,
        originalSize: Number.isInteger(out.barBlurLease.originalSize) ? out.barBlurLease.originalSize : null,
        originalPasses: Number.isInteger(out.barBlurLease.originalPasses) ? out.barBlurLease.originalPasses : null }
    : null
  out.legacyWorkspaceGrid = source.version === 1 || source.legacyWorkspaceGrid === true
  out.version = STATE_VERSION
  return out
}

if (typeof module !== "undefined") module.exports = {
  CONFIG_VERSION: CONFIG_VERSION, STATE_VERSION: STATE_VERSION,
  configDefaults: configDefaults, stateDefaults: stateDefaults,
  loadConfig: loadConfig, loadState: loadState, workspaceLayout: workspaceLayout
}

var CONFIG_VERSION = 11
var STATE_VERSION = 4

function configDefaults() {
  return { version: CONFIG_VERSION, lanes: {}, mode: "extend", enabled: [], singleTarget: "",
    direction: "ltr", followFocus: true, graceMs: 5000,
    keybindings: {}, approvedReplacements: [], hideNative: true, hideDisplay: true,
    compactMode: "hover", showOpenApps: true,
    panelPosition: "left", bars: {}, wallpaper: { mode: "same", followTheme: true },
    workspaceMode: "station", workspaceLayout: { repetitive: {}, nonrepetitive: {} },
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

function loadConfig(value) {
  var source = validObject(value) ? value : {}
  var out = Object.assign(configDefaults(), source)
  if (["extend", "mirror", "single"].indexOf(out.mode) === -1) out.mode = "extend"
  if (["ltr", "rtl", "ttb", "btt"].indexOf(out.direction) === -1) out.direction = "ltr"
  var grace = Number(out.graceMs)
  out.graceMs = isFinite(grace) ? Math.max(0, Math.min(30000, grace)) : 5000
  if (["station", "repetitive", "nonrepetitive"].indexOf(out.workspaceMode) === -1) out.workspaceMode = "station"
  out.workspaceLayout = workspaceLayout(out.workspaceLayout)
  // Sync's count and the old totals are gone: Sync offers three stations, and each
  // monitor starts with five workspaces.
  delete out.minStations
  delete out.workspaceCounts
  if (["prefixed", "number", "roman"].indexOf(out.indicatorStyle) === -1) out.indicatorStyle = "prefixed"
  out.lanes = validObject(out.lanes) ? out.lanes : {}
  out.keybindings = validObject(out.keybindings) ? out.keybindings : {}
  out.enabled = Array.isArray(out.enabled) ? out.enabled : []
  out.approvedReplacements = Array.isArray(out.approvedReplacements) ? out.approvedReplacements : []
  out.bars = validObject(out.bars) ? out.bars : {}
  // Color Match values by display identity. Their owner clamps each value.
  var colors = validObject(out.colorMatch) ? out.colorMatch : {}
  out.colorMatch = {}
  Object.keys(colors).slice(0, 32).forEach(function(key) {
    if (key.length <= 512 && validObject(colors[key])) out.colorMatch[key] = colors[key]
  })
  var cleanBars = {}
  Object.keys(out.bars).forEach(function(name) {
    var row = validObject(out.bars[name]) ? out.bars[name] : {}
    var position = ["top", "bottom", "left", "right"].indexOf(row.position) !== -1
      ? row.position : "top"
    var width = Number(row.width)
    width = isFinite(width) ? Math.max(1, Math.min(100, Math.round(width))) : 100
    var height = Number(row.height)
    height = isFinite(height) ? Math.max(0, Math.min(1000, Math.round(height))) : 0
    var background = ["solid", "transparent", "blur"].indexOf(row.background) !== -1
      ? row.background : "solid"
    var style = ["default", "pill"].indexOf(row.style) !== -1 ? row.style : "default"
    var contentSize = Number(row.contentSize)
    contentSize = isFinite(contentSize) ? Math.max(0, Math.min(1000, Math.round(contentSize))) : 0
    cleanBars[name] = { enabled: row.enabled !== false, position: position, width: width,
      height: height, background: background, style: style, contentSize: contentSize }
  })
  out.bars = cleanBars
  // `stationAppsMode` was one setting for both: Always on is compact Off, Off is
  // compact On without apps.
  var legacyApps = source.stationAppsMode
  if (["off", "hover", "on"].indexOf(source.compactMode) === -1)
    out.compactMode = legacyApps === "always" ? "off" : legacyApps === "hide" ? "on" : "hover"
  out.showOpenApps = typeof source.showOpenApps === "boolean" ? source.showOpenApps : legacyApps !== "hide"
  delete out.stationAppsMode
  out.hideNative = out.hideNative !== false
  out.hideDisplay = out.hideDisplay !== false
  if (["left", "center"].indexOf(out.panelPosition) === -1) out.panelPosition = "left"
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

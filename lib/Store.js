var CONFIG_VERSION = 2
var STATE_VERSION = 3

function configDefaults() {
  return { version: CONFIG_VERSION, lanes: {}, mode: "extend", enabled: [], singleTarget: "",
    direction: "ltr", followFocus: true, graceMs: 5000, minStations: 3,
    keybindings: {}, approvedReplacements: [], hideNative: true, hideDisplay: false,
    panelPosition: "left" }
}

function stateDefaults() {
  return { version: STATE_VERSION, lastStation: 1, appliedBinds: [], stockLease: null, displayLease: null,
    pendingTransaction: null, activeNoticeShown: false, legacyWorkspaceGrid: false }
}

function validObject(value) { return value && typeof value === "object" && !Array.isArray(value) }

function loadConfig(value) {
  var source = validObject(value) ? value : {}
  var out = Object.assign(configDefaults(), source)
  if (["extend", "mirror", "single"].indexOf(out.mode) === -1) out.mode = "extend"
  if (["ltr", "rtl", "ttb", "btt"].indexOf(out.direction) === -1) out.direction = "ltr"
  var grace = Number(out.graceMs)
  out.graceMs = isFinite(grace) ? Math.max(0, Math.min(30000, grace)) : 5000
  out.minStations = Math.max(1, Math.min(10, Number(out.minStations) || 3))
  out.lanes = validObject(out.lanes) ? out.lanes : {}
  out.keybindings = validObject(out.keybindings) ? out.keybindings : {}
  out.enabled = Array.isArray(out.enabled) ? out.enabled : []
  out.approvedReplacements = Array.isArray(out.approvedReplacements) ? out.approvedReplacements : []
  out.hideNative = out.hideNative !== false
  out.hideDisplay = out.hideDisplay === true
  if (["left", "center"].indexOf(out.panelPosition) === -1) out.panelPosition = "left"
  out.version = CONFIG_VERSION
  return out
}

function loadState(value) {
  var source = validObject(value) ? value : {}
  var out = Object.assign(stateDefaults(), source)
  out.lastStation = Math.max(1, Math.min(10, Number(out.lastStation) || 1))
  out.appliedBinds = Array.isArray(out.appliedBinds) ? out.appliedBinds : []
  out.legacyWorkspaceGrid = source.version === 1 || source.legacyWorkspaceGrid === true
  out.version = STATE_VERSION
  return out
}

if (typeof module !== "undefined") module.exports = {
  CONFIG_VERSION: CONFIG_VERSION, STATE_VERSION: STATE_VERSION,
  configDefaults: configDefaults, stateDefaults: stateDefaults,
  loadConfig: loadConfig, loadState: loadState
}

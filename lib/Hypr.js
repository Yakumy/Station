var CONNECTOR = /^[A-Za-z0-9_.:-]{1,64}$/
var ADDRESS = /^0x[0-9a-fA-F]+$/

function connector(value) {
  value = String(value || "")
  if (!CONNECTOR.test(value)) throw new Error("invalid connector")
  return value
}

function luaString(value) {
  value = String(value)
  return '"' + value.replace(/\\/g, "\\\\").replace(/"/g, '\\"')
    .replace(/\n/g, "\\n").replace(/\r/g, "\\r") + '"'
}

function workspace(value) {
  var n = Number(value)
  if (!Number.isInteger(n) || n < 1 || n > 30) throw new Error("invalid workspace")
  return n
}

function address(value) {
  value = String(value || "")
  if (!ADDRESS.test(value)) throw new Error("invalid window address")
  return value
}

function workspaceRules(station, lanes, present, hostFn) {
  var statements = []
  for (var lane = 1; lane <= 3; lane++) {
    var targetLane = present.indexOf(lane) !== -1 ? lane : hostFn(lane, present)
    if (!targetLane) continue
    var output = Object.keys(lanes).find(function(name) { return lanes[name] === targetLane })
    if (!output) continue
    statements.push("hl.workspace_rule({ workspace = " + luaString(String(workspace((station - 1) * 3 + lane)))
      + ", monitor = " + luaString(connector(output)) + " })")
  }
  return statements
}

function focusWorkspace(value) {
  return "hl.dispatch(hl.dsp.focus({ workspace = " + luaString(String(workspace(value))) + " }))"
}

function focusMonitor(value) {
  return "hl.dispatch(hl.dsp.focus({ monitor = " + luaString(connector(value)) + " }))"
}

function moveWindow(value, target, follow) {
  return "hl.dispatch(hl.dsp.window.move({ window = " + luaString("address:" + address(value))
    + ", workspace = " + workspace(target) + ", follow = " + (follow ? "true" : "false") + " }))"
}

function batch(statements) {
  if (!Array.isArray(statements)) throw new Error("invalid statements")
  return statements.filter(Boolean).join("; ")
}

if (typeof module !== "undefined") module.exports = {
  connector: connector, luaString: luaString, workspace: workspace, address: address,
  workspaceRules: workspaceRules, focusWorkspace: focusWorkspace,
  focusMonitor: focusMonitor, moveWindow: moveWindow, batch: batch
}

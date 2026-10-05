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

function focusWorkspace(value) {
  return "hl.dispatch(hl.dsp.focus({ workspace = " + luaString(String(workspace(value))) + " }))"
}

function focusMonitor(value) {
  return "hl.dispatch(hl.dsp.focus({ monitor = " + luaString(connector(value)) + " }))"
}

function compactRules(outputs) {
  var statements = []
  for (var station = 1; station <= 10; station++) {
    outputs.forEach(function(output, index) {
      var id = (station - 1) * outputs.length + index + 1
      statements.push("hl.workspace_rule({ workspace = " + luaString(String(workspace(id)))
        + ", monitor = " + luaString(connector(output)) + " })")
    })
  }
  return statements
}

function moveWorkspace(id, output) {
  return "hl.dispatch(hl.dsp.workspace.move({ workspace = " + workspace(id)
    + ", monitor = " + luaString(connector(output)) + " }))"
}

function moveWindow(value, target, follow) {
  return "hl.dispatch(hl.dsp.window.move({ window = " + luaString("address:" + address(value))
    + ", workspace = " + workspace(target) + ", follow = " + (follow ? "true" : "false") + " }))"
}

function nativeMove(value, direction) {
  if (["left", "right", "up", "down"].indexOf(direction) === -1) throw new Error("invalid direction")
  return "hl.dispatch(hl.dsp.window.move({ window = " + luaString("address:" + address(value))
    + ", direction = " + luaString(direction) + " }))"
}

function focusWindow(value) {
  return "hl.dispatch(hl.dsp.focus({ window = " + luaString("address:" + address(value)) + " }))"
}

function batch(statements) {
  if (!Array.isArray(statements)) throw new Error("invalid statements")
  return statements.filter(Boolean).join("; ")
}

if (typeof module !== "undefined") module.exports = {
  connector: connector, luaString: luaString, workspace: workspace, address: address,
  focusWorkspace: focusWorkspace,
  focusMonitor: focusMonitor, moveWindow: moveWindow, batch: batch,
  compactRules: compactRules, moveWorkspace: moveWorkspace,
  nativeMove: nativeMove, focusWindow: focusWindow
}

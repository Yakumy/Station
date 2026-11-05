function outputName(event) {
  var name = String(event && event.name || "").toLowerCase()
  var data = String(event && event.data || "")
  if (/^monitor(?:added|removed)/.test(name)) {
    return /v2$/.test(name) ? String(data.split(",")[1] || "").trim() : data.trim()
  }
  if (/^focusedmon/.test(name)) return data.split(",")[0].trim()
  return ""
}

function expected(event, expectation, now, output) {
  if (now > Number(expectation.until || 0)) return false
  var name = String(event && event.name || "").toLowerCase()
  if (!(expectation.kinds || []).some(function(kind) { return name.indexOf(kind) === 0 })) return false
  var connector = outputName(event) || output || ""
  return connector !== "" && (expectation.outputs || []).indexOf(connector) !== -1
}

if (typeof module !== "undefined") module.exports = { outputName: outputName, expected: expected }

// Only Station's bounded marker section is interpreted. Personal Lua stays opaque.
var START = "-- >>> station windows >>>"
var END = "-- <<< station windows <<<"
function setWindow(source, key, lua) {
  source = String(source || "")
  if (source.length > 65536 || source.indexOf("\u0000") !== -1) throw new Error("Configuration is too large or contains NUL")
  if (["innerGap", "outerGap", "split", "rounding", "speed"].indexOf(key) < 0) throw new Error("Invalid window setting")
  var lines = source.split("\n"), starts = [], ends = []
  lines.forEach(function(line, i) { if (line === START) starts.push(i); if (line === END) ends.push(i) })
  if (starts.length !== ends.length || starts.length > 1 || (starts.length && starts[0] >= ends[0])) throw new Error("Invalid Station window markers")
  var body = starts.length ? lines.slice(starts[0] + 1, ends[0]) : []
  var prefix = "-- setting: " + key
  var index = body.indexOf(prefix)
  if (index >= 0) body.splice(index, 2, prefix, lua)
  else body.push(prefix, lua)
  var outside = starts.length ? lines.slice(0, starts[0]).concat(lines.slice(ends[0] + 1)) : lines
  while (outside.length && outside[0] === "") outside.shift()
  return [START].concat(body, [END, ""], outside).join("\n")
}
if (typeof module !== "undefined") module.exports = { START: START, END: END, setWindow: setWindow }

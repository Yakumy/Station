// Numeric indices remain the service/IPC compatibility surface. Feature code
// names tabs here so inserting a tab cannot retarget picker or restore actions.
var TABS = [
  { id: "displays", label: "Displays" },
  { id: "bar", label: "Bar" },
  { id: "windows", label: "Windows" },
  { id: "wallpaper", label: "Wallpaper" },
  { id: "keybindings", label: "Keybindings" },
  { id: "settings", label: "Settings" }
]
function index(id) {
  for (var i = 0; i < TABS.length; i++) if (TABS[i].id === id) return i
  return -1
}
function labels() { return TABS.map(function(tab) { return tab.label }) }
function validIndex(value) { return Number.isInteger(value) && value >= 0 && value < TABS.length }
function next(value, direction) {
  return validIndex(value) ? (value + (direction > 0 ? 1 : TABS.length - 1)) % TABS.length : index("displays")
}
if (typeof module !== "undefined") module.exports = { index: index, labels: labels, validIndex: validIndex, next: next }

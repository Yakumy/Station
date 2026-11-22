.pragma library

// The scroll hints already played in this shell session, keyed by ScrollThumb.hintKey.
// A library keeps one copy per engine, so the record outlives the panel and its
// popups and resets only when the shell restarts. Import it only from ScrollThumb.qml
// so every thumb shares the same copy.
var played = {}

// True the first time a key is claimed, false afterwards and for an empty key.
function claim(key) {
  if (!key || played[key]) return false
  played[key] = true
  return true
}

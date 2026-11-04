import QtQuick
import Quickshell
import Quickshell.Io
import "Windows.js" as Windows
import "SharedConfig.js" as SharedConfig
import "Transactions.js" as Transactions
import "Hypr.js" as Hypr

// Persistent owner of the explicit window-save/readback protocol. Service owns
// the queue, configuration generation and observed config projection. These
// finite ports never grant access to monitor policy or the whole Service.
Item {
  id: root
  property var appliedSettings: ({})
  property string operationState: "idle"
  property int configGeneration: 0
  property var enqueue: null
  property var publishObserved: null
  property var reportError: null
  property var refreshStyle: null

  property bool windowSettingsBusy: false
  property string appearanceSource: ""
  property bool appearanceLoaded: false
  property string appearancePath: Quickshell.env("HOME") + "/.config/hypr/looknfeel.lua"

  function setWindowSetting(key, value) {
    if (windowSettingsBusy) return "busy"
    if (!Object.prototype.hasOwnProperty.call(Windows.limits, key)
        || typeof value !== "number" || !isFinite(value)) return "invalid"
    if (operationState !== "idle" || !appearanceLoaded) return "busy"
    var next = Windows.clean(appliedSettings)
    next[key] = value
    next = Windows.clean(next)
    var source
    var lua = Windows.settingLua(key, next[key])
    try { source = SharedConfig.setWindow(appearanceSource, key, lua) }
    catch (error) { reportError(String(error)); return "invalid" }
    windowSettingsBusy = true
    enqueue(["sh", "-c", Transactions.windowSetting, "sh", appearancePath, appearanceSource, source,
      "assert(loadfile(" + Hypr.luaString(appearancePath) + ")); " + lua], function(code, output) {
      appearanceFile.reload()
      if (code === 0) refreshStyle()
      if (code === 0) reportError("")
      if (code !== 0) reportError(code === 4 ? "Configuration changed while saving; try again." : "Could not save window setting: " + output)
      root.refreshWindowSettings(function(observed) {
        root.windowSettingsBusy = false
        if (code === 0 && observed && Math.abs(Number(root.appliedSettings[key]) - next[key]) > 0.02)
          reportError("A personal Hyprland rule overrides this setting. Station shows the applied value.")
      }, true)
    }, configGeneration)
    return "ok"
  }

  function refreshWindowSettings(done, completingEdit) {
    if (windowSettingsBusy && !completingEdit) return
    var generation = configGeneration
    enqueue(["hyprctl", "-j", "--batch", "getoption general:gaps_in; getoption general:gaps_out; getoption dwindle:default_split_ratio; getoption decoration:rounding; getoption animations:enabled; animations"], function(code, output) {
      if (code !== 0 || generation !== root.configGeneration || (root.windowSettingsBusy && !completingEdit)) {
        if (done) done(false)
        return
      }
      try {
        var observed = Windows.observed(output)
        if (JSON.stringify(observed) !== JSON.stringify(root.appliedSettings))
          publishObserved(observed)
      } catch (error) {
        console.warn("Station settings read:", error)
        if (done) done(false)
        return
      }
      if (done) done(true)
    })
  }

  FileView {
    id: appearanceFile
    path: root.appearancePath
    watchChanges: true
    printErrors: false
    onLoaded: { root.appearanceSource = text(); root.appearanceLoaded = true }
    onLoadFailed: { root.appearanceSource = ""; root.appearanceLoaded = true }
    onFileChanged: reload()
  }
}

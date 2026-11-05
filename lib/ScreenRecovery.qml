import QtQuick
import Quickshell
import "Model.js" as Model
import "MonitorsLua.js" as MonitorsLua
import "ScreenHealth.js" as ScreenHealth

// After a committed or reverted topology change, compare Hyprland's active
// outputs with the shell's screen list. Cycle one stale output once, restoring
// its validated exact rule. Never cycles the only visible output.
Item {
  id: root
  property string operationState: "idle"
  property var monitors: []
  property var lanes: ({})
  property var setOperationState: null
  property var recordExpectedEvents: null
  property var evalLua: null
  property var refresh: null
  property var reconcile: null
  property var reportError: null

  property bool screenRecoveryActive: false
  property int screenRecoveryAttempts: 0
  property string screenRecoveryTarget: ""
  property string screenRecoveryRule: ""

  function armScreenHealthCheck() {
    if (screenRecoveryActive) return
    screenRecoveryAttempts = 0
    screenHealthCheck.restart()
  }

  function verifyScreenHealth() {
    if (screenRecoveryActive || screenRecoveryAttempts > 0) return
    if (operationState !== "idle") { screenHealthCheck.restart(); return }
    var target = ScreenHealth.recoveryTarget(monitors, Quickshell.screens)
    if (!target) return
    try {
      var monitor = monitors.find(function(item) { return item.name === target })
      var display = MonitorsLua.validateDisplay({ name: target, mode: Model.currentMode(monitor),
        availableModes: monitor.availableModes, x: Math.round(Number(monitor.x) || 0),
        y: Math.round(Number(monitor.y) || 0), scale: Number(monitor.scale),
        transform: Number(monitor.transform), enabled: true, lane: lanes[target] || 1 })
      screenRecoveryRule = MonitorsLua.monitorRule(display, { disabled: false, mirror: "" })
      screenRecoveryTarget = target
      screenRecoveryActive = true
      screenRecoveryAttempts += 1
      setOperationState("recoveringScreen")
      recordExpectedEvents({ kinds: ["monitor", "workspace"], outputs: [target], until: Date.now() + 3000 })
      console.warn("Station: cycling stale Wayland output " + target)
      evalLua(MonitorsLua.monitorRule(display, { geometry: false, disabled: true, mirror: "" }),
        function(code, output) {
          if (code !== 0 || (output && output.trim() !== "ok")) {
            root.screenRecoveryActive = false
            root.screenRecoveryTarget = ""
            root.screenRecoveryRule = ""
            root.setOperationState("idle")
            root.reportError("Could not recover the display surface for " + target + ".")
            return
          }
          screenRecoveryEnable.restart()
        })
    } catch (error) {
      screenRecoveryActive = false
      screenRecoveryTarget = ""
      screenRecoveryRule = ""
      setOperationState("idle")
      reportError("Could not safely recover the display surface.")
      console.warn("Station screen recovery:", error)
    }
  }

  function finishScreenRecovery() {
    var rule = screenRecoveryRule
    var target = screenRecoveryTarget
    recordExpectedEvents({ kinds: ["monitor", "workspace"], outputs: [target], until: Date.now() + 3000 })
    evalLua(rule, function(code, output) {
      root.screenRecoveryActive = false
      root.screenRecoveryTarget = ""
      root.screenRecoveryRule = ""
      root.setOperationState("idle")
      if (code !== 0 || (output && output.trim() !== "ok")) {
        root.reportError("Could not restore the display after surface recovery. Reload Hyprland.")
        return
      }
      root.refresh(true, function() { if (root.operationState === "idle") root.reconcile() })
    })
  }

  Timer { id: screenHealthCheck; interval: 2500; onTriggered: root.verifyScreenHealth() }
  Timer { id: screenRecoveryEnable; interval: 250; onTriggered: root.finishScreenRecovery() }
}

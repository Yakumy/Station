import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import "Templates.js" as Templates

Item {
  id: root
  property var shell: null
  property var manifest: null
  property int calls: 0
  property string lastSwitch: ""
  property var panelState: ({ opened: false })
  property var config: ({ armed: false })
  property string lastResult: ""
  property int completed: 0
  property int generation: 0
  property string timingStartMs: ""
  property var timingsMs: []
  readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/omarchy/station-m0"

  function log(event) {
    Quickshell.execDetached(["sh", "-c", 'printf "%s %s\\n" "$(date +%s.%N)" "$2" >> "$1"',
      "sh", stateDir + "/lifecycle.log", event])
  }
  Component.onCompleted: log("created")
  Component.onDestruction: {
    log("destroyed")
    var lease = config.lease || { section: "left", index: 0, restore: false }
    if (!["left", "center", "right"].includes(lease.section)
        || !Number.isInteger(lease.index) || lease.index < 0) return
    Quickshell.execDetached(["sh", "-c", Templates.cleanup, "sh", stateDir,
      Quickshell.env("HOME") + "/.config/hypr/monitors.lua",
      lease.section, String(lease.index), lease.restore === true ? "1" : "0"])
  }

  function applyProbeBinds() {
    if (!config.armed || action.running) return
    run('hl.unbind("SUPER + code:10"); o.bind("SUPER + code:10", "Station: M0 number", "omarchy-shell yakumy.station-m0 switchProbe 1"); '
      + 'hl.unbind("CTRL + SUPER + LEFT"); o.bind("CTRL + SUPER + LEFT", "Station: M0 left", "sh \\"$HOME/.config/omarchy/plugins/yakumy.station-m0/timed-call.sh\\" 1"); '
      + 'hl.unbind("CTRL + SUPER + RIGHT"); o.bind("CTRL + SUPER + RIGHT", "Station: M0 right", "sh \\"$HOME/.config/omarchy/plugins/yakumy.station-m0/timed-call.sh\\" 2")')
  }
  function run(lua) {
    if (action.running) return "busy"
    lastResult = "pending"
    action.command = ["hyprctl", "eval", lua]
    action.running = true
    return "started"
  }
  function switchProbe(value) {
    if (!/^[12]$/.test(value) || !config.armed || !Array.isArray(config.outputs)) return "invalid"
    if (action.running) return "busy"
    var lua = [], targets = []
    for (var i = 0; i < config.outputs.length; i++) {
      var output = config.outputs[i]
      if (!/^[A-Za-z0-9_.:-]{1,64}$/.test(output.name) || ![1,2,3].includes(output.lane)) return "invalid"
      var workspace = (Number(value) + 7) * 3 + output.lane
      lua.push('hl.workspace_rule({ workspace = "' + workspace + '", monitor = "' + output.name + '" })')
      targets.push('hl.dispatch(hl.dsp.focus({ workspace = "' + workspace + '" }))')
    }
    if (!/^[A-Za-z0-9_.:-]{1,64}$/.test(config.focus || "")) return "invalid"
    lua = lua.concat(targets)
    lua.push('hl.dispatch(hl.dsp.focus({ monitor = "' + config.focus + '" }))')
    calls += 1
    lastSwitch = value
    return run(lua.join("; "))
  }
  function switchTimed(value, pressedMs) {
    if (!/^\d{13}$/.test(pressedMs)) return "invalid"
    timingStartMs = pressedMs
    var result = switchProbe(value)
    if (result !== "started") timingStartMs = ""
    return result
  }
  function watchdog() {
    Quickshell.execDetached(["sh", "-c", 'sleep "$1"; [ -e "$2" ] && { rm -f "$2"; hyprctl reload; }',
      "sh", "20", stateDir + "/preview.token"])
    return "armed"
  }
  FileView {
    path: root.stateDir + "/probe.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      try { root.config = JSON.parse(text()); root.applyProbeBinds() }
      catch (e) { root.lastResult = "invalid config" }
    }
  }
  Process {
    id: action
    stdout: StdioCollector { onStreamFinished: root.lastResult = text.trim() }
    onExited: function(code) {
      root.completed += 1
      if (root.timingStartMs !== "") {
        var elapsed = Date.now() - Number(root.timingStartMs)
        if (isFinite(elapsed) && elapsed >= 0 && elapsed < 10000) {
          root.timingsMs = root.timingsMs.concat([elapsed])
          if (root.timingsMs.length === 20
              && Number.isInteger(root.config.returnWorkspace)
              && root.config.returnWorkspace >= 1 && root.config.returnWorkspace <= 30) {
            var back = root.config.returnWorkspace
            Qt.callLater(function() {
              root.run('hl.dispatch(hl.dsp.focus({ workspace = "' + back + '" }))')
            })
          }
        }
        root.timingStartMs = ""
      }
      if (code !== 0) root.lastResult = "exit:" + code
    }
  }
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (event.name === "configreloaded") { root.generation += 1; reapply.restart() }
    }
  }
  Timer { id: reapply; interval: 300; onTriggered: root.applyProbeBinds() }

  function probe(value) {
    if (!/^(?:[1-9]|10)$/.test(value)) return "invalid"
    calls += 1
    return "service:" + value + ":" + calls
  }

  function togglePanel() {
    return shell ? String(shell.toggle("yakumy.station-m0", "{}")) : "no-shell"
  }

  IpcHandler {
    target: "yakumy.station-m0"
    function probe(value: string): string { return root.probe(value) }
    function togglePanel(): string { return root.togglePanel() }
    function status(): string { return JSON.stringify({ calls: root.calls, lastSwitch: root.lastSwitch, panel: root.panelState,
      completed: root.completed, result: root.lastResult, generation: root.generation, busy: action.running,
      timingsMs: root.timingsMs, config: root.config }) }
    function switchProbe(value: string): string { return root.switchProbe(value) }
    function switchTimed(value: string, pressedMs: string): string { return root.switchTimed(value, pressedMs) }
    function resetTimings(): string { root.timingsMs = []; return "ok" }
    function watchdog(): string { return root.watchdog() }
  }
}

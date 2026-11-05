import QtQuick
import Quickshell.Io
import "Wallpaper.js" as Wallpaper
import "Intro.js" as Intro

// Observe a bounded theme-change window. Keep Station's still in front until
// OWE has actually swapped the same crop on every output, including at EOF.
Item {
  id: root
  property bool enabled: false
  property var scene: ({})
  property var layout: ({displays: []})
  property string themeToken: ""
  property int imageWidth: 0
  property int imageHeight: 0
  property bool exposed: false
  property double deadline: 0
  property string expectedRequest: ""
  property double compositionId: -1
  property bool releaseSent: false
  property bool returning: false
  property bool returnReady: false
  property bool finishSent: false
  property double returnMediaId: -1
  onReturnReadyChanged: finishIfReady()
  function finishIfReady() {
    if (!returning || !returnReady || finishSent || finish.running) return
    finishSent = true
    finish.token = framingToken
    finish.request = JSON.stringify({cmd:"source-rects-finish", media_id:returnMediaId, composition_id:compositionId})
    finish.running = true
  }
  readonly property string framingToken: JSON.stringify([themeToken, scene, layout])
  onFramingTokenChanged: arm()
  onEnabledChanged: arm()
  function arm() {
    exposed = false; expectedRequest = ""; compositionId = -1; releaseSent = false
    returning = false; finishSent = false; returnMediaId = -1
    deadline = enabled ? Date.now() + 10000 : 0
    if (enabled) introPoll.restart(); else introPoll.stop()
  }
  Component.onCompleted: arm()
  Timer {
    id: introPoll
    interval: 100
    repeat: true
    onTriggered: {
      // Date.now() is not observable; stop explicitly when the window closes.
      if (Date.now() >= root.deadline) { root.exposed = false; stop(); return }
      if (!statusRead.running) statusRead.running = true
    }
  }
  Process {
    id: statusRead
    command: ["timeout", "1", "owe", "render-status"]
    property string token: ""
    onStarted: token = root.framingToken
    stdout: StdioCollector { id: statusOut }
    onExited: function(code) {
      if (token !== root.framingToken || !root.enabled) return
      var status = null
      try { if (code === 0) status = JSON.parse(statusOut.text) } catch (e) {}
      var request = Intro.request(status, root.scene, root.layout, root.imageWidth, root.imageHeight, Wallpaper.crop)
      if (!request) {
        root.exposed = false
        if (root.compositionId >= 0 && (!status || !status.intro || status.error)) introPoll.stop()
        return
      }
      var key = JSON.stringify(request)
      if (key !== root.expectedRequest) {
        root.exposed = false
        if (!compose.running) {
          root.expectedRequest = key; root.compositionId = -1; root.releaseSent = false
          compose.request = key; compose.token = token
          compose.running = true
        }
        return
      }
      if (status.composition_handoff_pending && status.composition_id === root.compositionId) {
        root.returning = true
        root.exposed = false
        root.returnMediaId = status.media_id
        root.finishIfReady()
        return
      }
      // The restored surface stays up while OWE enables the stock layer below it.
      if (root.returning) { root.exposed = false; return }
      root.exposed = root.compositionId >= 0 && status.composition_id === root.compositionId
        && status.composition_ready === true
      if (root.exposed && status.composition_held && !root.releaseSent && !release.running) {
        root.releaseSent = true
        release.token = token
        release.request = JSON.stringify({cmd:"source-rects-release", media_id:status.media_id,
          composition_id:root.compositionId})
        Qt.callLater(function() { if (root.enabled && release.token === root.framingToken) release.running = true })
      }
    }
  }
  Process {
    id: compose
    property string request: ""
    property string token: ""
    command: ["timeout", "1", "owe", "render", request]
    stdout: StdioCollector { id: composeOut }
    onExited: function(code) {
      if (token !== root.framingToken || !root.enabled || request !== root.expectedRequest) return
      try {
        var result = JSON.parse(composeOut.text)
        if (code === 0 && result.status === "ok" && Number.isSafeInteger(result.composition_id)) {
          root.compositionId = result.composition_id
          // The daemon bounds intros to 30 seconds; allow its EOF handoff too.
          root.deadline = Date.now() + 35000
        }
      } catch (e) {}
    }
  }
  Process {
    id: release
    property string request: ""
    property string token: ""
    command: ["timeout", "1", "owe", "render", request]
    onExited: function(code) {
      if (code !== 0 && token === root.framingToken) root.exposed = false
    }
  }

  Process {
    id: finish
    property string request: ""
    property string token: ""
    command: ["timeout", "1", "owe", "render", request]
    onExited: function(code) {
      if (code !== 0 && token === root.framingToken) root.finishSent = false
    }
  }

}

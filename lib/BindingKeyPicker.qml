import QtQuick
import qs.Ui as Ui
import qs.Commons
import "." as Station

// Deliberately contains no editable text control: Qt text inputs can retrieve
// clipboard payloads on dataChanged even when hidden and never pasted into.
FocusScope {
  id: root
  property string value: ""
  property bool available: true
  property bool capturing: false
  property string notice: ""
  signal picked(string key)
  implicitWidth: controls.implicitWidth
  implicitHeight: controls.implicitHeight

  function keyName(key) {
    if (key >= Qt.Key_A && key <= Qt.Key_Z) return String.fromCharCode(key)
    if (key >= Qt.Key_0 && key <= Qt.Key_9) return String.fromCharCode(key)
    if (key >= Qt.Key_F1 && key <= Qt.Key_F35) return "F" + (key - Qt.Key_F1 + 1)
    var names = [[Qt.Key_Left, "LEFT"], [Qt.Key_Right, "RIGHT"],
      [Qt.Key_Up, "UP"], [Qt.Key_Down, "DOWN"], [Qt.Key_Space, "SPACE"],
      [Qt.Key_Return, "RETURN"], [Qt.Key_Enter, "KP_ENTER"],
      [Qt.Key_Backspace, "BACKSPACE"], [Qt.Key_Delete, "DELETE"],
      [Qt.Key_Insert, "INSERT"], [Qt.Key_Home, "HOME"], [Qt.Key_End, "END"],
      [Qt.Key_PageUp, "PRIOR"], [Qt.Key_PageDown, "NEXT"],
      [Qt.Key_Minus, "MINUS"], [Qt.Key_Equal, "EQUAL"],
      [Qt.Key_Comma, "COMMA"], [Qt.Key_Period, "PERIOD"],
      [Qt.Key_Slash, "SLASH"], [Qt.Key_Backslash, "BACKSLASH"],
      [Qt.Key_Semicolon, "SEMICOLON"], [Qt.Key_Apostrophe, "APOSTROPHE"],
      [Qt.Key_BracketLeft, "BRACKETLEFT"], [Qt.Key_BracketRight, "BRACKETRIGHT"],
      [Qt.Key_QuoteLeft, "GRAVE"]]
    for (var i = 0; i < names.length; i++) if (names[i][0] === key) return names[i][1]
    return ""
  }
  function startCapture() {
    if (!available || !visible) return
    notice = ""
    capturing = true
    capture.forceActiveFocus()
  }
  function stopCapture() { capturing = false; notice = "" }
  onAvailableChanged: if (!available) stopCapture()
  onVisibleChanged: if (!visible) stopCapture()

  Row {
    id: controls
    spacing: Style.spacing.controlGap
    Ui.Button {
      id: trigger
      objectName: "captureKey"
      text: root.capturing ? "Press a key…" : (root.value || "Choose key")
      tooltipText: root.notice || "Press the key alone; choose modifiers with the chips. Escape cancels."
      foreground: Color.popups.text
      bordered: true
      focusable: true
      enabled: root.available
      onClicked: root.startCapture()
    }
    Station.InlineDropdown {
      objectName: "specialKey"
      prefix: "Special key"
      enabled: root.available
      options: ["ESCAPE", "TAB", "RETURN", "SPACE", "BACKSPACE", "DELETE",
        "INSERT", "HOME", "END", "PRIOR", "NEXT", "LEFT", "RIGHT", "UP", "DOWN"]
      onChanged: function(value) { root.stopCapture(); root.picked(value) }
    }
  }
  Item {
    id: capture
    onActiveFocusChanged: if (!activeFocus) root.stopCapture()
    Keys.priority: Keys.BeforeItem
    Keys.onPressed: function(event) {
      if (!root.capturing || !root.available || !root.visible) return
      event.accepted = true
      if (event.isAutoRepeat) return
      if (event.key === Qt.Key_Escape) { root.stopCapture(); trigger.forceActiveFocus(); return }
      // Keep Tab available for navigation. It can be selected from the menu.
      if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
        root.stopCapture(); event.accepted = false; return
      }
      if ([Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta,
           Qt.Key_AltGr].indexOf(event.key) !== -1) return
      if (event.modifiers !== Qt.NoModifier) {
        root.notice = "Release modifiers and press the key alone."
        return
      }
      var key = root.keyName(event.key)
      if (!key) { root.notice = "Unsupported key; choose another key or use Special key."; return }
      root.stopCapture()
      // Keep focus here until release so Return/Space cannot activate Apply.
      root.picked(key)
    }
    Keys.onReleased: function(event) { event.accepted = true }
  }
}

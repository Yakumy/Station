import QtQuick
import qs.Commons
import qs.Commons as Commons
import "." as PanelUi

// The display preview's countdown for the tabs that do not carry their own. A preview
// reverts when it runs out, which can turn a monitor off, so it must never be hidden.
PanelUi.ActionDrawer {
  id: root
  required property var service
  wideHeight: Style.space(66)
  wideMessageSize: Style.font.body
  messageColor: tokens.textPrimary
  message: root.service.previewBusy ? "Applying layout and moving windows…"
    : "Display change: keep it? Reverting in " + root.service.previewSeconds + " s"
  PanelUi.ActionButton {
    widthFactor: 0.6
    objectName: "previewRevert"
    text: "Revert"
    enabled: !root.service.previewBusy
    bordered: true
    foreground: Commons.Color.popups.text
    onClicked: root.service.revertPreview("")
  }
  PanelUi.ActionButton {
    widthFactor: 0.6
    objectName: "previewKeep"
    text: "Keep"
    enabled: !root.service.previewBusy
    accent: Commons.Color.accent
    background: Commons.Color.accent
    foreground: Commons.Color.popups.background
    onClicked: root.service.keepPreview()
  }
}

import QtQuick
import qs.Ui as Ui
import "." as PanelUi
import qs.Commons

// The display preview's countdown for the tabs that do not carry their own. A preview
// reverts when it runs out, which can turn a monitor off, so it must never be hidden.
Item {
  id: root
  required property var tokens
  required property var service
  height: Style.space(66)

  Ui.PanelSeparator { width: parent.width; foreground: root.tokens.textPrimary }
  Text {
    anchors.left: parent.left
    anchors.leftMargin: root.tokens.regionPadH
    anchors.right: revertButton.left
    anchors.rightMargin: root.tokens.space3
    anchors.verticalCenter: parent.verticalCenter
    elide: Text.ElideRight
    text: root.service.previewBusy ? "Applying layout and moving windows…"
      : "Display change: keep it? Reverting in " + root.service.previewSeconds + " s"
    color: root.tokens.textPrimary
    font.family: Style.font.family
    font.pixelSize: Style.font.body
  }
  PanelUi.ActionButton {
    widthFactor: 0.6
    id: keepButton
    anchors.right: parent.right
    anchors.rightMargin: root.tokens.regionPadH
    anchors.verticalCenter: parent.verticalCenter
    text: "Keep"
    enabled: !root.service.previewBusy
    accent: Color.accent
    background: Color.accent
    foreground: Color.popups.background
    onClicked: root.service.keepPreview()
  }
  PanelUi.ActionButton {
    widthFactor: 0.6
    id: revertButton
    anchors.right: keepButton.left
    anchors.rightMargin: root.tokens.space3
    anchors.verticalCenter: parent.verticalCenter
    text: "Revert"
    enabled: !root.service.previewBusy
    bordered: true
    foreground: Color.popups.text
    onClicked: root.service.revertPreview("")
  }
}

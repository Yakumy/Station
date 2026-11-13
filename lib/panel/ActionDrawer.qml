import QtQuick
import qs.Ui as Ui
import qs.Commons
import "." as PanelUi

// The confirmation strip under a feature tab: Keep/Revert or Cancel/Apply.
// Landscape: the message sits on the left and the buttons on the right. Portrait: the
// buttons are centered and the message sits under them in caption type, and
// the strip collapses while it has nothing to confirm.
//
// Position children with x/y only. Switching anchors between the two modes at
// runtime can briefly combine a vertical-center and bottom anchor, which
// resizes the buttons and left Keep unpainted in a live portrait preview.
Item {
  id: root
  required property var tokens
  property bool narrow: false
  // Portrait only: whether the strip takes height. Landscape always shows it.
  property bool open: true
  // Whether the buttons are shown, for tabs that hide them until there is
  // something to confirm. The objectName lets a tab's tests find the row.
  property bool showButtons: true
  property string buttonsName: "actionDrawerButtons"
  property string message: ""
  property color messageColor: tokens.textDim
  property real wideMessageSize: Style.font.caption
  property real wideHeight: Style.space(64)
  default property alias buttons: actions.data
  readonly property real pad: tokens.regionPadH
  readonly property real gap: tokens.space1
  readonly property bool hasMessage: message.length > 0

  PanelUi.FeatureGeometry { id: geometry }
  height: narrow ? (open ? geometry.actionHeight : 0) : wideHeight
  clip: true

  Ui.PanelSeparator { width: parent.width; foreground: root.tokens.textPrimary }

  Row {
    id: actions
    objectName: root.buttonsName
    visible: root.showButtons
    spacing: root.tokens.space2
    x: root.narrow ? Math.round((root.width - width) / 2) : root.width - width - root.pad
    y: root.narrow
      ? Math.round((root.height - height - (root.hasMessage ? root.gap + messageText.height : 0)) / 2)
      : Math.round((root.height - height) / 2)
  }

  Text {
    id: messageText
    objectName: "actionDrawerMessage"
    visible: root.hasMessage
    text: root.message
    textFormat: Text.PlainText
    x: root.pad
    width: root.narrow ? root.width - root.pad * 2
      : Math.max(0, root.width - actions.width - root.pad * 3)
    y: root.narrow ? actions.y + actions.height + root.gap : Math.round((root.height - height) / 2)
    horizontalAlignment: root.narrow ? Text.AlignHCenter : Text.AlignLeft
    wrapMode: Text.WordWrap
    maximumLineCount: 2
    elide: Text.ElideRight
    color: root.messageColor
    font.family: Style.font.family
    font.pixelSize: root.narrow ? Style.font.caption : root.wideMessageSize
  }
}

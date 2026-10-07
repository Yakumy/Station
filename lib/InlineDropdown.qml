import QtQuick
import QtQuick.Controls
import qs.Commons

// Compact, borderless trigger for the layout card and top toolbar. The menu
// itself uses the host's popup/selection tokens, like Ui.Dropdown.
Item {
  id: root
  property string prefix: ""
  property string value: ""
  property var options: []
  property color foreground: Color.popups.text
  property int fontSize: Style.font.body
  property real popupMinWidth: Style.space(100)
  property bool popupAlignRight: false
  signal changed(string value)

  function optionValue(option) { return String(option && typeof option === "object" ? option.value : option) }
  function optionLabel(option) { return String(option && typeof option === "object" ? option.label : option) }
  function currentLabel() {
    for (var i = 0; i < options.length; i++)
      if (optionValue(options[i]) === value) return optionLabel(options[i])
    return value
  }

  implicitWidth: label.implicitWidth + arrow.implicitWidth + Style.spacing.md
  implicitHeight: Math.max(label.implicitHeight, arrow.implicitHeight) + Style.spacing.sm

  Row {
    anchors.centerIn: parent
    spacing: Style.spacing.md
    Text {
      id: label
      text: root.prefix + root.currentLabel()
      color: root.foreground
      font.family: Style.font.family
      font.pixelSize: root.fontSize
      elide: Text.ElideRight
    }
    Text {
      id: arrow
      text: "󰅀"
      color: Qt.darker(root.foreground, 1.4)
      font.family: Style.font.family
      font.pixelSize: root.fontSize
    }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: menu.opened ? menu.close() : menu.open()
  }

  Popup {
    id: menu
    x: root.popupAlignRight ? root.width - width : 0
    y: root.height + Style.spacing.xxs
    width: Math.max(root.width, root.popupMinWidth)
    implicitHeight: Math.min(root.options.length, 8) * Style.spacing.popupRowHeight
      + Style.spacing.hairline * 2
    padding: Style.spacing.hairline
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
    background: Rectangle {
      color: Color.menu.background
      border.color: Color.menu.border
      border.width: Style.normalBorderWidth
      radius: Style.cornerRadius
    }
    contentItem: ListView {
      id: choices
      clip: true
      boundsBehavior: Flickable.StopAtBounds
      model: root.options
      currentIndex: -1
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Down) { currentIndex = Math.min(count - 1, currentIndex + 1); event.accepted = true }
        else if (event.key === Qt.Key_Up) { currentIndex = Math.max(0, currentIndex - 1); event.accepted = true }
        else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
          if (currentIndex >= 0) choose(currentIndex)
          event.accepted = true
        }
      }
      function choose(index) {
        var next = root.optionValue(root.options[index])
        menu.close()
        if (next !== root.value) root.changed(next)
      }
      delegate: Rectangle {
        required property var modelData
        required property int index
        width: choices.width
        height: Style.spacing.popupRowHeight
        color: index === choices.currentIndex ? Color.menu.selectedBackground : Color.menu.background
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.controlPaddingX
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.controlPaddingX
          anchors.verticalCenter: parent.verticalCenter
          text: root.optionLabel(modelData)
          color: index === choices.currentIndex ? Color.menu.selectedText : Color.menu.text
          font.family: Style.font.family
          font.pixelSize: root.fontSize
          elide: Text.ElideRight
        }
        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: choices.currentIndex = index
          onClicked: choices.choose(index)
        }
      }
    }
    onOpened: {
      for (var i = 0; i < root.options.length; i++)
        if (root.optionValue(root.options[i]) === root.value) { choices.currentIndex = i; break }
      choices.forceActiveFocus()
    }
  }
}

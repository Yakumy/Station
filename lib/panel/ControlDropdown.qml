import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Commons as Commons
import qs.Ui as Ui
import "." as PanelUi

// Station's control-sized dropdown. It mirrors Omarchy's Ui.Dropdown, but the
// popup list carries a thin accent scroll thumb that appears on hover: the
// 1-to-10 workspace-number menu overflows the panel in Bar portrait, and the
// host menu gives no sign that more options are reachable by scrolling.
Item {
  id: root
  property string label: ""
  property string value: ""
  property var options: []

  property color foreground: Commons.Color.popups.text
  property color background: Commons.Color.popups.background
  property color popupBorder: Commons.Color.popups.border
  property color accent: Commons.Color.accent
  readonly property var popupBorderSpec: Border.localOrSurfaceSpec("popups", "border", popupBorder, Commons.Color.popups.border, Style.normalBorderWidth)
  property string fontFamily: Style.font.family
  property int rowHeight: Style.spacing.controlHeight
  property int popupRowHeight: Style.spacing.popupRowHeight
  property bool showLabel: true
  property bool hasCursor: false

  readonly property bool popupOpen: popup.opened
  function open() { popup.open() }
  function close() { popup.close() }
  function toggle() { popup.opened ? popup.close() : popup.open() }

  signal changed(string value)
  signal hovered(bool isHovered)

  function optionValue(o) {
    return (o && typeof o === "object") ? String(o.value) : String(o)
  }
  function optionLabel(o) {
    return (o && typeof o === "object") ? String(o.label) : String(o)
  }
  function currentLabel() {
    for (var i = 0; i < options.length; i++)
      if (optionValue(options[i]) === value) return optionLabel(options[i])
    return value
  }

  // The shared row inset; see ControlSlider.qml.
  readonly property real rowInset: Style.space(8) + Math.ceil((parent.width - Style.space(8) * 2) * 0.005)
  x: rowInset
  width: parent.width - rowInset * 2
  anchors.verticalCenter: parent.verticalCenter
  implicitWidth: Style.spacing.dropdownWidth
  implicitHeight: showLabel && label !== "" ? rowHeight + Style.spacing.huge : rowHeight

  Column {
    anchors.fill: parent
    spacing: Style.spacing.labelGap

    Text {
      textFormat: Text.PlainText
      visible: root.showLabel && root.label !== ""
      text: root.label
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
    }

    Ui.BorderSurface {
      id: trigger
      width: parent.width
      height: root.rowHeight
      radius: Style.cornerRadius

      readonly property bool _focused: trigger.activeFocus
      readonly property bool _hot: triggerHover.hovered || root.hasCursor
      readonly property var _borderSpec: Border.controlSpec(trigger._focused ? "focus" : (trigger._hot ? "hover-cursor" : "normal"), root.foreground, root.accent)

      color: Style.controlFill(trigger._focused, trigger._hot, root.foreground, root.accent)
      borderSpec: _borderSpec
      activeFocusOnTab: true

      HoverHandler {
        id: triggerHover
        onHoveredChanged: root.hovered(hovered)
      }

      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter
            || event.key === Qt.Key_Space || event.key === Qt.Key_Down || event.text === "j") {
          popup.opened ? popup.close() : popup.open()
          event.accepted = true
        } else if (event.key === Qt.Key_Escape && popup.opened) {
          popup.close(); event.accepted = true
        }
      }

      Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.right: chevron.left
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: trigger.borderLeft + Style.spacing.controlPaddingX
        anchors.rightMargin: trigger.borderRight + Style.spacing.md
        text: root.currentLabel()
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }

      Text {
        id: chevron
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.rightMargin: trigger.borderRight + Style.spacing.controlGap
        text: "󰅀"
        color: Qt.darker(root.foreground, 1.4)
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: {
          trigger.forceActiveFocus()
          popup.opened ? popup.close() : popup.open()
        }
      }

      Popup {
        id: popup
        x: 0
        y: trigger.height + Style.spacing.xxs
        closePolicy: Popup.CloseOnPressOutsideParent | Popup.CloseOnEscape
        width: trigger.width
        implicitHeight: Math.min(root.options.length * root.popupRowHeight + Math.max(0, root.options.length - 1) * Style.spacing.labelGap,
                                 root.popupRowHeight * 8 + 7 * Style.spacing.labelGap)
                        + topPadding + bottomPadding
        padding: Style.spacing.hairline
        leftPadding: Border.left(root.popupBorderSpec) + Style.spacing.hairline
        rightPadding: Border.right(root.popupBorderSpec) + Style.spacing.hairline
        topPadding: Border.top(root.popupBorderSpec) + Style.spacing.hairline
        bottomPadding: Border.bottom(root.popupBorderSpec) + Style.spacing.hairline
        focus: true

        background: Ui.BorderSurface {
          color: root.background
          borderSpec: root.popupBorderSpec
          radius: Style.cornerRadius
        }

        onOpened: {
          optionList.currentIndex = Math.max(0, optionList.indexOfValue(root.value))
          optionList.forceActiveFocus()
        }

        contentItem: Item {
          ListView {
            id: optionList
            anchors.fill: parent
            spacing: Style.spacing.labelGap
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            model: root.options
            currentIndex: -1

            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function(event) {
              if (event.key === Qt.Key_Escape) { popup.close(); event.accepted = true }
              else if (event.key === Qt.Key_Down || event.text === "j") {
                optionList.currentIndex = Math.min(root.options.length - 1, optionList.currentIndex + 1)
                event.accepted = true
              } else if (event.key === Qt.Key_Up || event.text === "k") {
                optionList.currentIndex = Math.max(0, optionList.currentIndex - 1)
                event.accepted = true
              } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                optionList.selectCurrent(); event.accepted = true
              }
            }

            function indexOfValue(v) {
              for (var i = 0; i < root.options.length; i++)
                if (root.optionValue(root.options[i]) === v) return i
              return -1
            }

            function selectCurrent() {
              if (currentIndex < 0 || currentIndex >= root.options.length) return
              var v = root.optionValue(root.options[currentIndex])
              root.value = v
              root.changed(v)
              popup.close()
            }

            delegate: Rectangle {
              required property var modelData
              required property int index
              width: optionList.width
              height: root.popupRowHeight
              color: index === optionList.currentIndex
                ? Style.hoverFillFor(root.foreground, root.accent)
                : "transparent"

              Text {
                textFormat: Text.PlainText
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Style.spacing.controlPaddingX
                anchors.rightMargin: Style.spacing.controlPaddingX
                text: root.optionLabel(modelData)
                color: index === optionList.currentIndex ? Style.hoverStateColor(root.foreground, root.accent) : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onPositionChanged: optionList.currentIndex = parent.index
                onClicked: optionList.selectCurrent()
              }
            }
          }

          // Thin accent thumb inside the popup, shown and grabbed on the thumb itself.
          PanelUi.ScrollThumb {
            objectName: "dropdownScrollThumb"
            flickable: optionList
            hintKey: "dropdown"
            color: root.accent
          }
        }
      }
    }
  }
}

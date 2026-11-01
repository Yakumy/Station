import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "Windows.js" as Windows

Column {
  id: root
  required property var panelRoot
  property var values: Windows.clean(panelRoot.service ? panelRoot.service.config.windows : null)
  readonly property var savedValues: panelRoot.service ? panelRoot.service.config.windows : null
  onSavedValuesChanged: values = Windows.clean(savedValues)
  property bool swapped: false
  readonly property var barSettings: panelRoot.selectedDisplay && panelRoot.service ? panelRoot.service.monitorBar(panelRoot.selectedDisplay.name) : ({})
  readonly property real thickness: Number(barSettings.height) || (barSettings.position === "left" || barSettings.position === "right" ? Style.bar.sizeVertical : Style.bar.sizeHorizontal)
  function preview(key, value) { var next = Object.assign({}, values); next[key] = value; values = next }
  component Caption: Text {
    color: root.panelRoot.textPrimary
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  Timer { interval: 2200; repeat: true; running: root.visible && root.panelRoot.opened; onTriggered: root.swapped = !root.swapped }
  Row {
    width: parent.width
    height: Style.space(428)
    Column {
      width: parent.width * 0.576
      Item {
        width: parent.width; height: Style.space(28)
        Ui.PanelSectionHeader { anchors.left: parent.left; anchors.leftMargin: root.panelRoot.regionPadH; text: "LAYOUT"; foreground: root.panelRoot.textPrimary }
      }
      Item {
        width: parent.width; height: Style.space(370)
        Rectangle {
          id: screen
          anchors.centerIn: parent
          width: parent.width - root.panelRoot.regionPadH * 2
          height: width * 0.625
          color: Commons.Color.popups.background
          border.color: Commons.Color.popups.text
          border.width: Style.normalBorderWidth
          radius: Style.cornerRadius
          readonly property real factor: width / 1000
          readonly property real gap: root.values.innerGap * factor
          readonly property real outer: root.values.outerGap * factor + border.width
          Item {
            id: area
            anchors.fill: parent
            anchors.margins: screen.outer
            Repeater {
              model: 2
              Rectangle {
                required property int index
                readonly property bool onRight: (index === 1) !== root.swapped
                width: (area.width - screen.gap) * (index === 0 ? root.values.split / 100 : 1 - root.values.split / 100)
                height: area.height
                x: onRight ? area.width - width : 0
                color: Commons.Color.menu.selectedBackground
                border.color: index === 0 ? Commons.Color.accent : Commons.Color.popups.text
                border.width: Style.normalBorderWidth
                radius: root.values.rounding * screen.factor
                Behavior on x { NumberAnimation { duration: root.values.speed === 0 ? 0 : 400 / root.values.speed; easing.type: Easing.OutCubic } }
                Caption { anchors.centerIn: parent; text: index === 0 ? "NEXT WINDOW" : "WINDOW" }
              }
            }
          }
        }
      }
    }
    Rectangle { width: Math.max(1, Style.normalBorderWidth); height: parent.height; color: Commons.Color.popups.text; opacity: 0.12 }
    Column {
      width: parent.width * 0.424 - Math.max(1, Style.normalBorderWidth)
      Item { width: parent.width; height: Style.space(28); Caption { anchors.centerIn: parent; text: "All monitors · Dwindle split" } }
      Ui.BorderSurface {
        width: parent.width - Style.space(56); height: Style.space(370)
        anchors.horizontalCenter: parent.horizontalCenter
        color: Commons.Color.popups.background
        borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
        radius: Style.cornerRadius
        Column {
          anchors.fill: parent
          Repeater {
            model: [{key:"innerGap",label:"INNER GAP"},{key:"outerGap",label:"OUTER GAP"},{key:"split",label:"NEXT WINDOW SIZE"},{key:"rounding",label:"BORDER ROUNDNESS"},{key:"speed",label:"ANIMATION SPEED"}]
            Item {
              id: row
              required property var modelData
              required property int index
              width: parent.width; height: Style.space(74)
              Caption { anchors.left: parent.left; anchors.leftMargin: root.panelRoot.space3; anchors.top: parent.top; anchors.topMargin: root.panelRoot.space2; text: row.modelData.label }
              Caption { anchors.right: parent.right; anchors.rightMargin: root.panelRoot.space3; anchors.top: parent.top; anchors.topMargin: root.panelRoot.space2; text: root.values[row.modelData.key] + (row.index === 2 ? "%" : row.index === 4 ? "×" : " px") }
              Ui.PanelSlider {
                id: slider
                width: parent.width - root.panelRoot.space3 * 2
                anchors.centerIn: parent
                bar: root.panelRoot.bar
                minimum: Windows.limits[row.modelData.key][0]
                maximum: Windows.limits[row.modelData.key][1]
                enabled: root.panelRoot.service && !root.panelRoot.service.windowSettingsBusy
                integer: true
                value: root.values[row.modelData.key]
                onMoved: function(value) { root.preview(row.modelData.key, value) }
                onReleased: function(value) { root.panelRoot.service.setWindowSetting(row.modelData.key, value) }
                Rectangle {
                  visible: row.index < 2
                  x: Math.min(1, root.thickness / slider.maximum) * parent.width - width / 2
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.max(1, Style.normalBorderWidth); height: slider.trackHeight + Style.space(6)
                  color: Commons.Color.accent
                  MouseArea { anchors.fill: parent; anchors.margins: -Style.space(5); hoverEnabled: true; onEntered: { if (root.panelRoot.bar) root.panelRoot.bar.showTooltip(parent, "Bar thickness: " + root.thickness + " px") } onExited: { if (root.panelRoot.bar) root.panelRoot.bar.hideTooltip(parent) } }
                }
              }
              Ui.PanelSeparator { visible: row.index < 4; anchors.bottom: parent.bottom; width: parent.width; foreground: Commons.Color.popups.text }
            }
          }
        }
      }
    }
  }
  Ui.PanelSeparator { width: parent.width; foreground: Commons.Color.popups.text }
  Item { width: parent.width; height: Style.space(64); Caption { anchors.centerIn: parent; text: "Preview swaps automatically · 0 disables animations" } }
}

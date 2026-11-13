import QtQuick
import "../panel" as PanelUi
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "Windows.js" as Windows
import "." as WindowsUi

Column {
  id: root
  required property var tokens
  required property var selectedDisplay
  required property var bar
  required property var service
  property bool narrow: false
  property var values: Windows.displayValues(service ? service.config.windows : null)
  readonly property var savedValues: service ? service.config.windows : null
  property bool editing: false
  readonly property bool saving: service ? service.windowSettingsBusy : false
  function syncValues() {
    if (!editing && !saving) values = Windows.displayValues(savedValues)
  }
  onSavedValuesChanged: syncValues()
  onSavingChanged: syncValues()
  readonly property var barSettings: selectedDisplay && service ? service.monitorBar(selectedDisplay.name) : ({})
  readonly property real thickness: Number(barSettings.height) || (barSettings.position === "left" || barSettings.position === "right" ? Style.bar.sizeVertical : Style.bar.sizeHorizontal)
  function preview(key, value) { var next = Object.assign({}, values); next[key] = value; values = next }
  component Caption: Text {
    color: root.tokens.textDim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }
  PanelUi.FeatureGeometry { id: geometry }

  Item {
    id: windowColumns
    width: parent.width
    height: root.narrow ? geometry.stackedHeight : Style.space(428)
    Column {
      id: leftColumn
      width: root.narrow ? windowColumns.width : windowColumns.width * 0.576
      Item {
        width: parent.width; height: geometry.headingHeight
        Ui.PanelSectionHeader { anchors.left: parent.left; anchors.leftMargin: root.tokens.regionPadH; anchors.verticalCenter: parent.verticalCenter; text: "LAYOUT"; foreground: root.tokens.textPrimary }
      }
      WindowsUi.WindowsLayout {
        objectName: "windowsLayout"
        width: parent.width - root.tokens.regionPadH * 2
        height: geometry.frameHeight
        anchors.horizontalCenter: parent.horizontalCenter
        tokens: root.tokens; service: root.service
        values: root.values
        id: layout
      }
    }
    Item {
      x: root.narrow ? 0 : leftColumn.width
      y: root.narrow ? geometry.headingHeight + geometry.frameHeight : 0
      width: root.narrow ? windowColumns.width : Math.max(1, Style.normalBorderWidth)
      height: root.narrow ? geometry.separatorSlot : Style.space(428)
      Rectangle {
        objectName: "featureDivider"
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.narrow ? geometry.halfGap - height / 2 : 0
        width: root.narrow ? parent.width : Math.max(1, Style.normalBorderWidth)
        height: root.narrow ? Math.max(1, Style.normalBorderWidth) : parent.height
        color: Commons.Color.popups.text; opacity: 0.12
      }
    }
    Column {
      x: root.narrow ? 0 : leftColumn.width + Math.max(1, Style.normalBorderWidth)
      y: root.narrow ? geometry.headingHeight + geometry.frameHeight + geometry.separatorSlot : 0
      width: root.narrow ? windowColumns.width
        : windowColumns.width - leftColumn.width - Math.max(1, Style.normalBorderWidth)
      Item { width: parent.width; height: geometry.headingHeight }
      PanelUi.ControlFrame {
        objectName: "featureControlFrame"
        narrow: root.narrow
        height: geometry.frameHeight
        Column {
          anchors.fill: parent
          Repeater {
            model: [{key:"innerGap",label:"INNER GAP"},{key:"outerGap",label:"OUTER GAP"},{key:"split",label:"NEXT WINDOW SIZE"},{key:"rounding",label:"BORDER ROUNDNESS"},{key:"speed",label:"ANIMATION SPEED"}]
            Item {
              id: row
              required property var modelData
              required property int index
              width: parent.width; height: Style.space(74)
              PanelUi.ControlLabel { text: row.modelData.label }
              Caption { anchors.right: parent.right; anchors.rightMargin: root.tokens.space2; anchors.top: parent.top; anchors.topMargin: root.tokens.space2; text: root.values[row.modelData.key] + (row.index === 2 ? "%" : row.index === 4 ? "×" : " px") }
              PanelUi.ControlSlider {
                id: slider
                anchors.centerIn: parent
                bar: root.bar
                minimum: row.index === 4 ? 0 : Windows.limits[row.modelData.key][0]
                maximum: row.index === 4 ? Windows.speeds.length - 1 : Windows.limits[row.modelData.key][1]
                enabled: root.service && !root.service.windowSettingsBusy
                integer: true
                value: row.index === 4 ? Windows.speedIndex(root.values.speed) : root.values[row.modelData.key]
                onMoved: function(value) {
                  root.editing = true
                  root.preview(row.modelData.key, row.index === 4 ? Windows.speeds[value] : value)
                }
                onReleased: function(value) {
                  if (row.index === 4) value = Windows.speeds[value]
                  if (row.modelData.key === "speed" && value !== Windows.displayValues(root.savedValues).speed) layout.previewExchange(value)
                  var result = root.service.setWindowSetting(row.modelData.key, value)
                  root.editing = false
                  if (result !== "ok") root.syncValues()
                }
                Rectangle {
                  visible: row.index < 2
                  x: slider.trackX(Math.min(1, root.thickness / slider.maximum)) - width / 2
                  anchors.verticalCenter: parent.verticalCenter
                  width: Math.max(1, Style.normalBorderWidth); height: slider.trackHeight + Style.space(6)
                  color: Commons.Color.accent
                  MouseArea { anchors.fill: parent; anchors.margins: -Style.space(5); hoverEnabled: true; onEntered: { if (root.bar) root.bar.showTooltip(parent, "Bar thickness: " + root.thickness + " px") } onExited: { if (root.bar) root.bar.hideTooltip(parent) } }
                }
              }
              Text {
                visible: row.index === 4
                anchors.left: parent.left
                anchors.leftMargin: root.tokens.space2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.tokens.space1
                width: parent.width - root.tokens.space2 * 2
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
                text: "Change animation speed to preview · 0 disables animations"
                color: root.tokens.textDim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }
              Ui.PanelSeparator { visible: row.index < 4; anchors.bottom: parent.bottom; width: parent.width; foreground: Commons.Color.popups.text }
            }
          }
        }
      }
    }
  }
  Ui.PanelSeparator { width: parent.width; foreground: Commons.Color.popups.text }
}

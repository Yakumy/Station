import QtQuick
import "../panel" as PanelUi
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons
import "ColorMatch.js" as ColorMatch
import "." as ColorUi

// Color Match: pick a monitor on the left, adjust its white balance, brightness,
// gamma and saturation on the right. Each release applies one ICC profile live.
Column {
  id: root
  required property var tokens
  required property var bar
  required property var selectDisplay
  required property var service
  required property var selectedDisplay
  property bool narrow: false
  readonly property string selectedName: selectedDisplay ? selectedDisplay.name : ""
  readonly property var colorMatch: service && service.colorMatch
    ? service.colorMatch : ({ busy: false, error: "", values: {}, hdr: [] })
  readonly property var savedValues: ColorMatch.clean((colorMatch.values || {})[selectedName])
  readonly property bool hdr: (colorMatch.hdr || []).indexOf(selectedName) !== -1
  readonly property bool busy: colorMatch.busy === true
  readonly property bool usable: selectedDisplay !== null && !hdr && !busy
  // The control being dragged shows its live value; everything else shows saved values.
  property string editingKey: ""
  property real editingValue: 0
  property string notice: ""
  // The row whose slider was pushed past what its setting can reach.
  property string cappedKey: ""
  readonly property var values: {
    var out = Object.assign({}, savedValues)
    if (editingKey) {
      var change = {}
      change[editingKey] = editingValue
      out[editingKey] = ColorMatch.clean(Object.assign({}, savedValues, change))[editingKey]
    }
    return out
  }
  readonly property var rows: [
    { key: "temperature", label: "TEMPERATURE", hint: "Lower is warmer, higher is cooler" },
    { key: "tint", label: "TINT", hint: "Left adds green, right adds magenta" },
    { key: "brightness", label: "BRIGHTNESS", hint: "Dims this monitor to match a darker one",
      cap: "100% is the maximum brightness" },
    { key: "gamma", label: "GAMMA", hint: "Higher darkens the midtones" },
    { key: "saturation", label: "SATURATION", hint: "0% is black and white" }
  ]
  readonly property real pad: tokens.regionPadH
  spacing: 0
  onSelectedNameChanged: { editingKey = ""; notice = ""; cappedKey = "" }

  function format(key, value) {
    if (key === "temperature") return value + " K"
    if (key === "tint") return value > 0 ? "+" + value : String(value)
    if (key === "gamma") return (value / 100).toFixed(2)
    return value + "%"
  }

  function report(result) {
    notice = result === "ok" || result === undefined ? ""
      : result === "busy" ? "Station is busy; try again in a moment."
      : result === "hdr" ? "Color Match is off while this monitor uses HDR."
      : "Could not apply that value."
  }

  component Caption: Text {
    color: root.tokens.textDim
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  PanelUi.FeatureGeometry { id: geometry }

  Item {
    id: colorColumns
    width: parent.width
    height: root.narrow ? geometry.stackedHeight : Style.space(428)

    Column {
      id: leftColumn
      width: root.narrow ? colorColumns.width : colorColumns.width * 0.576
      spacing: 0
      Item {
        width: parent.width
        height: geometry.headingHeight
        Ui.PanelSectionHeader {
          anchors.left: parent.left
          anchors.leftMargin: root.pad
          anchors.verticalCenter: parent.verticalCenter
          text: "LAYOUT"
          foreground: root.tokens.textPrimary
        }
        Text {
          anchors.right: parent.right
          anchors.rightMargin: root.pad
          anchors.verticalCenter: parent.verticalCenter
          text: "SELECT A MONITOR"
          color: root.tokens.textDim
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
      ColorUi.ColorLayout {
        objectName: "featureLayoutFrame"
        width: parent.width - root.pad * 2
        height: geometry.frameHeight
        anchors.horizontalCenter: parent.horizontalCenter
        tokens: root.tokens
        service: root.service
        selectedDisplayName: root.selectedName
        onDisplaySelected: function(name) { root.selectDisplay(name) }
      }
    }

    Item {
      x: root.narrow ? 0 : leftColumn.width
      y: root.narrow ? geometry.headingHeight + geometry.frameHeight : 0
      width: root.narrow ? colorColumns.width : Math.max(1, Style.normalBorderWidth)
      height: root.narrow ? geometry.separatorSlot : Style.space(428)
      Rectangle {
        objectName: "featureDivider"
        anchors.horizontalCenter: parent.horizontalCenter
        y: root.narrow ? geometry.halfGap - height / 2 : 0
        width: root.narrow ? parent.width : Math.max(1, Style.normalBorderWidth)
        height: root.narrow ? Math.max(1, Style.normalBorderWidth) : parent.height
        color: Commons.Color.popups.text
        opacity: 0.12
      }
    }

    Column {
      x: root.narrow ? 0 : leftColumn.width + Math.max(1, Style.normalBorderWidth)
      y: root.narrow ? geometry.headingHeight + geometry.frameHeight + geometry.separatorSlot : 0
      width: root.narrow ? colorColumns.width
        : colorColumns.width - leftColumn.width - Math.max(1, Style.normalBorderWidth)
      spacing: 0
      Item {
        width: parent.width
        height: geometry.headingHeight
        Text {
          anchors.left: parent.left
          anchors.leftMargin: geometry.headingHeight
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(56)
          text: root.selectedDisplay ? "Selected: " + root.selectedName : "No monitor selected"
          color: root.tokens.textPrimary
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
      PanelUi.ControlFrame {
        objectName: "featureControlFrame"
        narrow: root.narrow
        id: controlFrame
        height: geometry.frameHeight
        readonly property real rowHeight: height / root.rows.length

        Column {
          anchors.fill: parent
          spacing: 0
          Repeater {
            model: root.rows
            Item {
              id: row
              required property var modelData
              required property int index
              width: parent.width
              height: controlFrame.rowHeight
              PanelUi.ControlLabel { text: row.modelData.label }
              Caption {
                objectName: "colorValue-" + row.modelData.key
                anchors.right: parent.right
                anchors.rightMargin: root.tokens.space2
                anchors.top: parent.top
                anchors.topMargin: root.tokens.space2
                text: root.format(row.modelData.key, root.values[row.modelData.key])
              }
              PanelUi.ControlSlider {
                objectName: "colorSlider-" + row.modelData.key
                bar: root.bar
                minimum: ColorMatch.sliderRange(row.modelData.key)[0]
                maximum: ColorMatch.sliderRange(row.modelData.key)[1]
                integer: true
                step: ColorMatch.step(row.modelData.key)
                value: root.savedValues[row.modelData.key]
                enabled: root.usable
                opacity: enabled ? 1 : root.tokens.disabledOpacity
                onMoved: function(value) {
                  root.editingValue = value
                  root.editingKey = row.modelData.key
                  root.cappedKey = ColorMatch.capped(row.modelData.key, value) ? row.modelData.key : ""
                }
                onReleased: function(value) {
                  var key = row.modelData.key
                  var change = {}
                  change[key] = value
                  var next = ColorMatch.clean(Object.assign({}, root.savedValues, change))[key]
                  root.editingKey = ""
                  if (next !== root.savedValues[key]) root.report(root.service.setColorValue(root.selectedName, key, next))
                  // A knob pushed past the cap returns to the value that applies.
                  else liveValue = next
                }
              }
              Text {
                anchors.left: parent.left
                anchors.leftMargin: root.tokens.space2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.tokens.space1
                width: parent.width - root.tokens.space2 * 2
                objectName: "colorHint-" + row.modelData.key
                text: root.hdr ? "Color Match is off while this monitor uses HDR."
                  : root.notice || root.colorMatch.error || (root.busy ? "Applying…"
                    : root.cappedKey === row.modelData.key ? row.modelData.cap : row.modelData.hint)
                color: root.notice || root.colorMatch.error ? Commons.Color.urgent
                  : root.cappedKey === row.modelData.key ? root.tokens.textPrimary : root.tokens.textDim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
              Ui.PanelSeparator { visible: row.index < root.rows.length - 1; anchors.bottom: parent.bottom; width: parent.width; foreground: Commons.Color.popups.text }
            }
          }
        }
      }
    }
  }
  Ui.PanelSeparator { width: parent.width; foreground: Commons.Color.popups.text }
}

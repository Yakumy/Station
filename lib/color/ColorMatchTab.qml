import QtQuick
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
    color: root.tokens.textPrimary
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Row {
    width: parent.width
    height: Style.space(428)

    Column {
      id: leftColumn
      width: parent.width * 0.576
      spacing: 0
      Item {
        width: parent.width
        height: Style.space(28)
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
        width: parent.width - root.pad * 2
        height: Style.space(370)
        anchors.horizontalCenter: parent.horizontalCenter
        tokens: root.tokens
        service: root.service
        selectedDisplayName: root.selectedName
        onDisplaySelected: function(name) { root.selectDisplay(name) }
      }
    }

    Rectangle {
      width: Math.max(1, Style.normalBorderWidth)
      height: parent.height
      color: Commons.Color.popups.text
      opacity: 0.12
    }

    Column {
      width: parent.width - leftColumn.width - Math.max(1, Style.normalBorderWidth)
      spacing: 0
      Item {
        width: parent.width
        height: Style.space(28)
        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.space(28)
          anchors.verticalCenter: parent.verticalCenter
          width: parent.width - Style.space(56)
          text: root.selectedDisplay ? "Selected: " + root.selectedName : "No monitor selected"
          color: root.tokens.textPrimary
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }
      Ui.BorderSurface {
        id: controlFrame
        width: parent.width - Style.space(28) * 2
        height: Style.space(370)
        anchors.horizontalCenter: parent.horizontalCenter
        color: Commons.Color.popups.background
        borderSpec: Border.controlSpec("normal", Commons.Color.popups.text, Commons.Color.accent)
        radius: Style.cornerRadius
        readonly property real rowHeight: height * 0.165

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
              Caption {
                anchors.left: parent.left
                anchors.leftMargin: root.tokens.space3
                anchors.top: parent.top
                anchors.topMargin: root.tokens.space2
                text: row.modelData.label
              }
              Caption {
                objectName: "colorValue-" + row.modelData.key
                anchors.right: parent.right
                anchors.rightMargin: root.tokens.space3
                anchors.top: parent.top
                anchors.topMargin: root.tokens.space2
                text: root.format(row.modelData.key, root.values[row.modelData.key])
              }
              Ui.PanelSlider {
                objectName: "colorSlider-" + row.modelData.key
                width: parent.width - root.tokens.space3 * 2
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: Style.space(2)
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
                anchors.leftMargin: root.tokens.space3
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.tokens.space1
                width: parent.width - root.tokens.space3 * 2
                objectName: "colorHint-" + row.modelData.key
                text: root.cappedKey === row.modelData.key ? row.modelData.cap : row.modelData.hint
                color: root.cappedKey === row.modelData.key ? root.tokens.textPrimary : root.tokens.textDim
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
              Ui.PanelSeparator { anchors.bottom: parent.bottom; width: parent.width; foreground: Commons.Color.popups.text }
            }
          }
          Item {
            width: parent.width
            height: controlFrame.height - controlFrame.rowHeight * root.rows.length
            Text {
              objectName: "colorNotice"
              anchors.left: parent.left
              anchors.leftMargin: root.tokens.space3
              anchors.right: resetButton.left
              anchors.rightMargin: root.tokens.space2
              anchors.verticalCenter: parent.verticalCenter
              text: root.hdr ? "Color Match is off while this monitor uses HDR."
                : root.notice || root.colorMatch.error || (root.busy ? "Applying…" : "Changes apply when you release a slider.")
              color: root.colorMatch.error || root.notice ? Commons.Color.urgent : root.tokens.textDim
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              maximumLineCount: 2
              elide: Text.ElideRight
            }
            Ui.Button {
              id: resetButton
              objectName: "colorReset"
              anchors.right: parent.right
              anchors.rightMargin: root.tokens.space3
              anchors.verticalCenter: parent.verticalCenter
              height: root.tokens.controlHeight
              radius: Style.cornerRadius
              text: "Reset"
              enabled: root.usable && !ColorMatch.isNeutral(root.savedValues)
              bordered: true
              foreground: Commons.Color.popups.text
              onClicked: { root.cappedKey = ""; root.report(root.service.resetColor(root.selectedName)) }
            }
          }
        }
      }
    }
  }
  Ui.PanelSeparator { width: parent.width; foreground: Commons.Color.popups.text }
}

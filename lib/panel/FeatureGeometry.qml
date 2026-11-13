import QtQuick
import qs.Commons

// Shared visible frame sizes and spacing for the six feature tabs.
QtObject {
  readonly property real frameHeight: Style.space(370)
  readonly property real headingHeight: Style.space(28)
  readonly property real halfGap: Style.space(36)
  readonly property real separatorSlot: halfGap * 2 - headingHeight
  readonly property real stackedHeight: headingHeight + frameHeight * 2 + halfGap * 3
}

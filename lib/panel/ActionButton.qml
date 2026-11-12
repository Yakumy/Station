import QtQuick
import qs.Ui as Ui
import qs.Commons
import qs.Commons as Commons

Ui.Button {
  width: Style.space(180) * 1.2 * 0.96
  height: Style.spacing.controlHeight
  radius: Style.cornerRadius
  bordered: true
  foreground: Commons.Color.popups.text
}

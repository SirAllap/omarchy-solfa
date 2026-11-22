import QtQuick
import qs.Commons
import "../lib/Calm.js" as Calm

// A key and what it does, for the hint line.
Row {
  id: hint

  property string keys: ""
  property string label: ""
  property QtObject bar: null
  readonly property color fg: Calm.fg
  readonly property string family: Calm.font

  spacing: Style.space(5)

  Rectangle {
    anchors.verticalCenter: parent.verticalCenter
    width: keyText.implicitWidth + Style.space(8)
    height: keyText.implicitHeight + Style.space(2)
    radius: Style.space(4)
    color: Util.alpha(hint.fg, 0.08)
    border.width: 1
    border.color: Util.alpha(hint.fg, 0.2)
    Text {
      id: keyText
      anchors.centerIn: parent
      text: hint.keys
      textFormat: Text.PlainText
      color: Util.alpha(hint.fg, 0.85)
      font.family: hint.family
      font.pixelSize: Style.font.caption
    }
  }

  Text {
    anchors.verticalCenter: parent.verticalCenter
    text: hint.label
    textFormat: Text.PlainText
    color: Util.alpha(hint.fg, 0.62)
    font.family: hint.family
    font.pixelSize: Style.font.caption
  }
}

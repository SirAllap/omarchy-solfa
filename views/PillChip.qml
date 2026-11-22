import QtQuick
import qs.Commons
import "../lib/Calm.js" as Calm

// One filter chip of the calm mockup (Chip.qml): a 32 px pill, a hairline,
// and the open one tinted with the accent.
Rectangle {
  id: chip

  property string text: ""
  property bool on: false
  property string family: Calm.font
  signal clicked()

  width: label.implicitWidth + Style.space(24)
  height: Style.space(32)
  radius: height / 2
  color: on ? Calm.a(Calm.accent, 0.2) : ma.containsMouse ? Calm.a(Calm.fg, 0.1) : Calm.wash
  border.width: 1
  border.color: on ? Calm.a(Calm.accent, 0.55) : Calm.hair
  Behavior on color { enabled: !Style.reduceMotion; ColorAnimation { duration: 160 } }

  Text {
    id: label
    anchors.centerIn: parent
    text: chip.text
    textFormat: Text.PlainText
    color: chip.on ? Calm.fg : Calm.a(Calm.fg, 0.64)
    font.family: chip.family
    font.pixelSize: Style.space(13)
    font.weight: chip.on ? Font.DemiBold : Font.Normal
  }

  MouseArea {
    id: ma
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: chip.clicked()
  }
}

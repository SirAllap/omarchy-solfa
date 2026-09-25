import QtQuick
import qs.Ui
import qs.Commons

// Solfa is off (the engine closed on purpose, or after it kept crashing):
// nothing below would work, so under the header ("Solfa is off") the panel
// shows only the way back on.
Column {
  id: card

  property var svc: null
  property QtObject bar: null
  readonly property color fg: bar ? bar.foreground : Color.foreground
  readonly property string family: bar ? bar.fontFamily : Style.font.family

  spacing: Style.space(10)

  Button {
    objectName: "offTurnOn"
    anchors.horizontalCenter: parent.horizontalCenter
    text: "Turn on"
    fontFamily: card.family
    foreground: Color.accent
    bordered: true
    onClicked: if (card.svc) card.svc.startEngine()
  }

  Text {
    width: parent.width
    text: "or press Enter"
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignHCenter
    color: Util.alpha(card.fg, 0.5)
    font.family: card.family
    font.pixelSize: Style.font.caption
  }
}

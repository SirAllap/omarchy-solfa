import QtQuick
import qs.Ui
import qs.Commons
import "../lib/Icons.js" as Icons

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

  // A round power tile, quiet: an accent ring on a faint fill.
  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    width: Style.space(64)
    height: width
    radius: width / 2
    color: Util.alpha(card.fg, 0.06)
    border.width: 1
    border.color: Util.alpha(card.fg, 0.18)
    Text {
      anchors.centerIn: parent
      text: Icons.power
      textFormat: Text.PlainText
      color: Color.accent
      font.family: card.family
      font.pixelSize: Style.font.iconLarge
    }
  }

  Text {
    width: parent.width
    text: "Turn Solfa on"
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignHCenter
    color: card.fg
    font.family: card.family
    font.pixelSize: Style.font.title
    font.bold: true
  }

  Text {
    width: parent.width
    text: "It starts YouTube Music in the background. Nothing plays until you do."
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    horizontalAlignment: Text.AlignHCenter
    color: Util.alpha(card.fg, 0.6)
    font.family: card.family
    font.pixelSize: Style.font.body
  }

  HitButton {
    objectName: "offTurnOn"
    anchors.horizontalCenter: parent.horizontalCenter
    text: "Turn on"
    iconText: Icons.power
    fontFamily: card.family
    foreground: Color.background
    background: Color.accent
    radius: height / 2
    onClicked: if (card.svc) card.svc.startEngine()
  }

  KeyHint {
    anchors.horizontalCenter: parent.horizontalCenter
    keys: "↵"
    label: "or press Enter"
    bar: card.bar
  }
}

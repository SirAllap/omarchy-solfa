import QtQuick
import "../lib/Calm.js" as Calm
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
  readonly property color fg: bar ? bar.foreground : Calm.fg
  readonly property string family: Calm.font

  spacing: 12

  // A round power tile, quiet: an accent ring on a faint fill.
  Rectangle {
    anchors.horizontalCenter: parent.horizontalCenter
    width: 70
    height: width
    radius: width / 2
    color: Calm.wash
    border.width: 1
    border.color: Calm.a(Calm.accent, 0.5)
    Text {
      anchors.centerIn: parent
      text: Icons.power
      textFormat: Text.PlainText
      color: Calm.accent
      font.family: card.family
      font.pixelSize: 28
    }
  }

  Text {
    width: parent.width
    text: "Turn Solfa on"
    textFormat: Text.PlainText
    horizontalAlignment: Text.AlignHCenter
    color: card.fg
    font.family: card.family
    font.pixelSize: 18
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
    font.pixelSize: 13
  }

  HitButton {
    objectName: "offTurnOn"
    anchors.horizontalCenter: parent.horizontalCenter
    text: "Turn on"
    iconText: Icons.power
    fontFamily: card.family
    foreground: Calm.bg
    background: Calm.accent
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

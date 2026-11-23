import QtQuick
import "../lib"
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
  readonly property color fg: Calm.fg
  readonly property string family: Calm.font

  spacing: 12

  // The round power circle IS the Turn on button: click, Enter (the panel's key
  // handler) or Space turns Solfa on. Hover and press change the fill; Tab shows a ring.
  Rectangle {
    id: power
    objectName: "offPower"
    anchors.horizontalCenter: parent.horizontalCenter
    width: 70
    height: width
    radius: width / 2
    activeFocusOnTab: true
    color: powerMouse.pressed ? Calm.a(Calm.accent, 0.32) : powerMouse.containsMouse ? Calm.a(Calm.accent, 0.18) : Calm.wash
    border.width: 1
    border.color: Calm.a(Calm.accent, powerMouse.containsMouse || power.activeFocus ? 0.9 : 0.5)
    scale: powerMouse.pressed ? 0.95 : 1
    Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }
    Behavior on color { ColorAnimation { duration: 120 } }
    Accessible.role: Accessible.Button
    Accessible.name: "Turn Solfa on"
    Accessible.onPressAction: power.turnOn()
    function turnOn() { if (card.svc) card.svc.startEngine() }
    Keys.onReturnPressed: turnOn()
    Keys.onEnterPressed: turnOn()
    Keys.onSpacePressed: turnOn()
    // Keyboard focus ring, outside the circle.
    Rectangle {
      objectName: "offPowerFocus"
      anchors.centerIn: parent
      width: parent.width + 8
      height: width
      radius: width / 2
      color: "transparent"
      border.width: 2
      border.color: Calm.accent
      visible: power.activeFocus
    }
    Text {
      anchors.centerIn: parent
      text: Icons.power
      textFormat: Text.PlainText
      color: Calm.accent
      font.family: card.family
      font.pixelSize: 28
    }
    MouseArea {
      id: powerMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { power.forceActiveFocus(); power.turnOn() }
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
    color: Calm.muted
    font.family: card.family
    font.pixelSize: 13
  }

  KeyHint {
    anchors.horizontalCenter: parent.horizontalCenter
    keys: "↵"
    label: "or press Enter"
    bar: card.bar
  }
}

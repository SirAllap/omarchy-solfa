import QtQuick

// What the panel shows while the engine is off.
Item {
  id: o
  property bool active: true
  Glow { anchors.centerIn: parent; width: 380; height: 300; color: Theme.accent2; strength: 0.14 }
  Column { anchors.centerIn: parent; spacing: 12; width: 300
    Item { width: 86; height: 86; anchors.horizontalCenter: parent.horizontalCenter
      Rectangle { id: ring; anchors.centerIn: parent; width: 70; height: 70; radius: 35; color: Theme.wash; border.width: 1.5; border.color: Theme.a(Theme.accent2, 0.5)
        SequentialAnimation on scale { running: o.active && !Motion.reduce; loops: Animation.Infinite; NumberAnimation { to: 1.08; duration: 1600; easing.type: Easing.InOutSine } NumberAnimation { to: 1; duration: 1600; easing.type: Easing.InOutSine } }
        Icon { anchors.centerIn: parent; name: "power"; size: 28; color: Theme.accent2 } } }
    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; text: "Turn Solfa on"; color: Theme.fg; font.family: Theme.font; font.pixelSize: 18; font.weight: Font.Bold }
    Text { width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; text: "It starts YouTube Music in the background. Nothing plays until you do."; color: Theme.dim; font.family: Theme.font; font.pixelSize: 13 }
    Btn { anchors.horizontalCenter: parent.horizontalCenter; kind: "primary"; icon: "power"; text: "Turn on" }
    KeyCap { anchors.horizontalCenter: parent.horizontalCenter; keys: "↵"; label: "or press Enter" } }
}

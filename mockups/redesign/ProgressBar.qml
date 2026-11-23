import QtQuick

// A seek bar with a glowing fill. The light follows the head and breathes
// while the song plays.
Item {
  id: p
  property real value: 0.38
  property bool playing: true
  property bool hot: false
  property bool dim: false
  property real breath: 0
  implicitHeight: 22
  SequentialAnimation on breath { running: p.playing && Motion.live; loops: Animation.Infinite
    NumberAnimation { to: 1; duration: 1400; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0; duration: 1400; easing.type: Easing.InOutSine } }
  readonly property real fillW: Math.max(6, value * width)
  Behavior on value { enabled: !Motion.reduce; NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
  opacity: dim ? 0.35 : 1

  Rectangle { id: track; anchors.verticalCenter: parent.verticalCenter; width: parent.width; height: p.hot || ma.containsMouse ? 8 : 5; radius: height / 2; color: Qt.rgba(1, 1, 1, 0.1)
    Behavior on height { enabled: !Motion.reduce; SpringAnimation { spring: 6; damping: 0.5; epsilon: 0.2 } } }
  // light under the fill
  Rectangle { x: 0; width: p.fillW; height: 16; anchors.verticalCenter: track.verticalCenter; radius: 8
    opacity: 0.18 + 0.14 * p.breath
    gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: Theme.accent2 } } }
  Rectangle { id: fill; anchors.verticalCenter: track.verticalCenter; width: p.fillW; height: track.height; radius: height / 2
    gradient: Gradient { orientation: Gradient.Horizontal; GradientStop { position: 0; color: Theme.accent } GradientStop { position: 1; color: Theme.accent2 } } }
  Glow { x: p.fillW - width / 2; anchors.verticalCenter: track.verticalCenter; width: 46 + 14 * p.breath; height: width; color: Theme.accent2; strength: 0.55 }
  Rectangle { id: head; x: p.fillW - width / 2; anchors.verticalCenter: track.verticalCenter; width: 12; height: 12; radius: 6; color: "#fff"
    scale: p.hot || ma.containsMouse || ma.pressed ? 1.35 : 1
    Behavior on scale { enabled: !Motion.reduce; SpringAnimation { spring: 6; damping: 0.4; epsilon: 0.001 } } }
  MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onPressed: p.value = Math.max(0, Math.min(1, mouseX / width)); onPositionChanged: if (pressed) p.value = Math.max(0, Math.min(1, mouseX / width)) }
}

import QtQuick

// Procedural album art (no image files). When "breathe" is on and the song
// plays, it swells and relaxes with a soft light behind it; paused, it
// settles back with a spring.
Item {
  id: r
  property int seed: 0
  property bool playing: false
  property bool breathe: false
  property bool lit: false
  property real radius: 14
  property bool round: false
  property real pulse: 0
  // where the cover is looking: a spring (critically damped), so a new look never jumps
  property real gx: 0
  property real gy: 0
  Behavior on gx { enabled: !Motion.reduce; SpringAnimation { spring: 4.5; damping: 1; epsilon: 0.01 } }
  Behavior on gy { enabled: !Motion.reduce; SpringAnimation { spring: 4.5; damping: 1; epsilon: 0.01 } }
  property real rest: (breathe && !playing) ? 0.94 : 1
  Behavior on rest { enabled: !Motion.reduce; SpringAnimation { spring: 3.2; damping: 0.22; epsilon: 0.002 } }
  SequentialAnimation on pulse {
    running: r.breathe && r.playing && Motion.live
    loops: Animation.Infinite
    NumberAnimation { to: 1; duration: 2100; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0; duration: 2100; easing.type: Easing.InOutSine }
  }

  Rectangle {
    id: art
    anchors.fill: parent
    radius: r.round ? width / 2 : r.radius
    scale: r.rest * (1 + 0.035 * r.pulse)
    rotation: r.gx * 0.7
    transform: Translate { x: r.gx; y: r.gy }
    gradient: Gradient {
      GradientStop { position: 0; color: Theme.hue(r.seed, 0.46) }
      GradientStop { position: 1; color: Theme.hue(r.seed + 4, 0.2) }
    }
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.12)
    Rectangle { anchors.centerIn: parent; width: parent.width * 0.62; height: width; radius: width / 2; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.16) }
    Rectangle { anchors.centerIn: parent; width: parent.width * 0.34; height: width; radius: width / 2; color: "transparent"; border.width: 1; border.color: Qt.rgba(1, 1, 1, 0.2) }
    Rectangle { anchors.centerIn: parent; width: parent.width * 0.09; height: width; radius: width / 2; color: Qt.rgba(1, 1, 1, 0.55) }
    Rectangle {
      anchors.fill: parent; radius: parent.radius; color: "#000"
      opacity: (r.breathe && !r.playing) ? 0.3 : 0
      Behavior on opacity { enabled: !Motion.reduce; NumberAnimation { duration: 300 } }
    }
  }
}

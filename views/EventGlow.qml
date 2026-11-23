import QtQuick
import QtQuick.Shapes
import qs.Commons
import "../lib/Motion.js" as Motion

// A soft glow and a ring that start on an event and die away smoothly
// (exp(-t/520 ms)); the colour says what happened: like is the accent,
// an error is the warning colour. Nothing runs when it is not fired, and
// nothing at all under the system's reduce-motion setting.
Item {
  id: root
  property real size: 120
  property color color: Color.accent
  property real age: 99999
  width: 1; height: 1
  readonly property real glow: Motion.decay(age, Motion.glowTau)
  readonly property real flash: Motion.decay(age, Motion.flashTau)

  function fire(kind) {
    if (Style.reduceMotion) return
    color = kind === "error" ? Color.urgent : Color.accent
    anim.stop(); age = 0; anim.start()
  }
  NumberAnimation { id: anim; target: root; property: "age"; from: 0; to: 3200; duration: 3200 }

  Shape {
    visible: root.age < 3000
    x: -root.size / 2; y: -root.size / 2; width: root.size; height: root.size
    ShapePath {
      strokeColor: "transparent"
      fillGradient: RadialGradient {
        centerX: root.size / 2; centerY: root.size / 2
        centerRadius: root.size / 2; focalX: centerX; focalY: centerY
        GradientStop { position: 0; color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.3 * root.glow) }
        GradientStop { position: 0.55; color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.1 * root.glow) }
        GradientStop { position: 1; color: Qt.rgba(root.color.r, root.color.g, root.color.b, 0) }
      }
      startX: 0; startY: 0
      PathLine { x: root.size; y: 0 }
      PathLine { x: root.size; y: root.size }
      PathLine { x: 0; y: root.size }
      PathLine { x: 0; y: 0 }
    }
  }
  Rectangle {
    visible: root.age < 2000
    x: -width / 2; y: -height / 2
    width: 24 + root.age * 0.12; height: width; radius: width / 2
    color: "transparent"
    border.width: 2; border.color: root.color
    opacity: 0.45 * root.flash
  }
}

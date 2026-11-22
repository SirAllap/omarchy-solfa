import QtQuick
import qs.Commons

// Song progress as a ring of dots around the bar's cover: the dots up to
// the playhead are lit, the playhead is a little bigger, the rest are
// faint. It moves once a second while a song plays and not at all otherwise.
// (Same properties as the thin arc it replaces.)
Item {
  id: root

  property real progress: 0
  property color color: "white"
  property color trackColor: "transparent"
  property real thickness: 2
  property int dots: Math.max(24, Math.min(56, Math.round(Math.min(width, height) * 1.4)))

  readonly property real r: Math.max(1, Math.min(width, height) / 2 - thickness / 2)
  readonly property real dot: Math.max(1.5, thickness * 0.9)
  readonly property real head: Math.max(0.01, Math.min(1, progress)) * dots

  Repeater {
    model: root.dots
    Rectangle {
      required property int index
      readonly property bool lit: index < root.head
      readonly property bool isHead: lit && index === Math.ceil(root.head) - 1
      readonly property real a: index / root.dots * 2 * Math.PI - Math.PI / 2
      width: isHead ? root.dot * 1.6 : root.dot; height: width; radius: width / 2
      x: root.width / 2 + root.r * Math.cos(a) - width / 2
      y: root.height / 2 + root.r * Math.sin(a) - height / 2
      color: lit ? root.color : root.trackColor
      opacity: lit ? 0.6 + 0.4 * index / Math.max(1, root.dots) : 1
    }
  }
}

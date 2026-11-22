import QtQuick
import QtQuick.Shapes

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
  // a multiple of four, so the ring is symmetric about both axes
  property int dots: 4 * Math.round(Math.max(24, Math.min(56, Math.min(width, height) * 1.4)) / 4)

  // (centring tests need this radius; a dot-sized inset shifted the ring's centre)
  readonly property real r: Math.max(1, Math.min(width, height) / 2 - thickness / 2)
  readonly property real dot: Math.max(2, thickness * 1.5)
  readonly property real head: Math.max(0.01, Math.min(1, progress)) * dots

  // Circles as SVG path text: "M x y" then two half-turns of radius dr.
  function circles(from, to) {
    var s = "", dr = dot / 2
    for (var i = from; i < to; i++) {
      var a = i / dots * 2 * Math.PI - Math.PI / 2
      var cx = width / 2 + r * Math.cos(a), cy = height / 2 + r * Math.sin(a)
      s += "M" + (cx - dr) + " " + cy + "a" + dr + " " + dr + " 0 1 0 " + (2 * dr) + " 0a" + dr + " " + dr + " 0 1 0 " + (-2 * dr) + " 0z"
    }
    return s
  }
  readonly property int litCount: Math.min(dots, Math.ceil(head))

  // One vector Shape, like the arc it replaces, so the dots share the cover's
  // sub-pixel grid and the ring stays centred at any scale.
  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      strokeWidth: -1; strokeColor: "transparent"
      fillColor: root.trackColor
      PathSvg { path: root.circles(root.litCount, root.dots) }
    }
    ShapePath {
      strokeWidth: -1; strokeColor: "transparent"
      fillColor: Qt.rgba(root.color.r, root.color.g, root.color.b, root.color.a * 0.65)
      PathSvg { path: root.circles(0, Math.max(0, root.litCount - 1)) }
    }
    ShapePath {
      strokeWidth: -1; strokeColor: "transparent"
      fillColor: root.color
      PathSvg { path: root.circles(Math.max(0, root.litCount - 1), root.litCount) }
    }
  }
}

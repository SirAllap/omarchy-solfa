import QtQuick
import QtQuick.Shapes

// Song progress as a thin continuous arc around the bar's cover: a faint full
// circle (the track) and, over it, the part up to the playhead, starting at
// twelve o'clock and running clockwise. One anti-aliased vector Shape, so it
// shares the cover's sub-pixel grid and the ring stays centred at any scale.
// It moves once a second while a song plays and not at all otherwise.
Item {
  id: root

  property real progress: 0
  property color color: "white"
  property color trackColor: "transparent"
  property real thickness: 2
  // Thin on purpose: a wide stroke next to the pill's own outline read as a second line.
  readonly property real stroke: Math.min(2, thickness)

  // (centring tests need this radius: the stroke is centred on it)
  readonly property real r: Math.max(1, Math.min(width, height) / 2 - stroke / 2)
  readonly property real sweep: Math.max(0.01, Math.min(1, progress)) * 360

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    layer.enabled: true
    layer.samples: 8
    ShapePath {
      strokeWidth: root.stroke
      strokeColor: root.trackColor
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.r; radiusY: root.r; startAngle: -90; sweepAngle: 359.99 }
    }
    ShapePath {
      strokeWidth: root.stroke
      strokeColor: root.color
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.r; radiusY: root.r; startAngle: -90; sweepAngle: root.sweep }
    }
  }
}

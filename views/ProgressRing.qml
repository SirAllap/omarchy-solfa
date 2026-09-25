import QtQuick
import QtQuick.Shapes

// A thin ring for song progress, drawn around the bar's cover. It moves
// once a second while a song plays and not at all otherwise.
Item {
  id: root

  property real progress: 0
  property color color: "white"
  property color trackColor: "transparent"
  property real thickness: 2

  readonly property real r: Math.max(1, Math.min(width, height) / 2 - thickness / 2)

  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer

    ShapePath {
      strokeColor: root.trackColor
      strokeWidth: root.thickness
      fillColor: "transparent"
      capStyle: ShapePath.FlatCap
      PathAngleArc { centerX: root.width / 2; centerY: root.height / 2; radiusX: root.r; radiusY: root.r; startAngle: 0; sweepAngle: 360 }
    }

    ShapePath {
      strokeColor: root.color
      strokeWidth: root.thickness
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      PathAngleArc {
        centerX: root.width / 2; centerY: root.height / 2; radiusX: root.r; radiusY: root.r
        startAngle: -90
        sweepAngle: Math.max(0.01, Math.min(1, root.progress)) * 360
      }
    }
  }
}

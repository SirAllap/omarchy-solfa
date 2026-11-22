import QtQuick
import QtQuick.Shapes

Item {
  id: s
  property real size: 22
  property color color: Theme.accent
  width: size; height: size
  Shape {
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    ShapePath { strokeColor: Theme.a(s.color, 0.2); strokeWidth: 2.2; fillColor: "transparent"
      PathAngleArc { centerX: s.size / 2; centerY: s.size / 2; radiusX: s.size / 2 - 2; radiusY: s.size / 2 - 2; startAngle: 0; sweepAngle: 360 } }
    ShapePath { strokeColor: s.color; strokeWidth: 2.2; fillColor: "transparent"; capStyle: ShapePath.RoundCap
      PathAngleArc { centerX: s.size / 2; centerY: s.size / 2; radiusX: s.size / 2 - 2; radiusY: s.size / 2 - 2; startAngle: -90; sweepAngle: 100 } }
    RotationAnimation on rotation { from: 0; to: 360; duration: 900; loops: Animation.Infinite; running: s.visible }
  }
}

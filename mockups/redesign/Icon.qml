import QtQuick
import QtQuick.Shapes

// One 24x24 vector icon, drawn from Theme.icons.
Item {
  id: r
  property string name: "play"
  property color color: Theme.fg
  property bool filled: false
  property real size: 20
  property real stroke: 1.9
  width: size
  height: size
  Shape {
    width: 24
    height: 24
    scale: r.size / 24
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: r.filled ? r.color : "transparent"
      strokeColor: r.filled ? "transparent" : r.color
      strokeWidth: r.stroke
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: Theme.icons[r.name] || "" }
    }
  }
}

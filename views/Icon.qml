import QtQuick
import QtQuick.Shapes
import "../lib/IconPaths.js" as IconPaths

// One 24x24 outline icon from lib/IconPaths.js: a thin, round-capped stroke
// (not a filled font glyph), so it matches the mockup at any size.
Item {
  id: r
  property string name: "play"
  property color color: "white"
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
      PathSvg { path: IconPaths.paths[r.name] || "" }
    }
  }
}

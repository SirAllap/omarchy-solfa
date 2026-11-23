import QtQuick
import QtQuick.Shapes
import QtQuick.Window
import "Pixel.js" as Pixel

// The liquid join between the bar pill and the card: two concave quarter-circle
// "necks", one per side. Every number comes in from outside and is snapped to whole
// DEVICE pixels here, from the same values on both sides; the right side is the left
// side's path mirrored about the snapped centre line. Each side is ONE fill path and
// ONE outline path (vertical run + arc as a single stroke, no shapes meeting at the
// inflection), so there is no seam where the pill-side arc turns into the card side.
Item {
  id: bridge
  property real dpr: Screen.devicePixelRatio
  property real pillLeft: 0      // the pill's left edge (parent coordinates)
  property real pillWidth: 0     // the pill's full width, end to end
  property real pillTop: 0
  property real pillBottom: 0
  property real cardTop: 0
  property real rDesign: 16      // the neck's radius (the caller caps it so it never climbs above the pill's top corner)
  property real progress: 1      // 0..1: the neck grows from the card up
  property real ov: 1            // overlap into the pill and into the card: no seam
  property color fillColor: "white"
  property color lineColor: "black"
  property int rendererType: Shape.CurveRenderer   // analytic anti-aliasing; tests flip it to prove they can tell

  function sn(v) { return Pixel.snap(v, dpr) }
  readonly property real pillW: sn(pillWidth)
  readonly property real snapLeft: sn(pillLeft)
  readonly property real pb: sn(pillBottom)
  readonly property real ct: sn(cardTop)
  readonly property real r: sn(Math.max(0, rDesign))
  readonly property real rr: sn(r * Math.max(0, Math.min(1, progress)))
  readonly property real rx: r + pillW
  readonly property real yC: ct - y
  readonly property real yP: pb - ov - y
  readonly property real m: width / 2

  x: snapLeft - r
  y: Math.min(pb - ov, ct - r)
  width: pillW + 2 * r
  height: yC + ov

  Component {
    id: halfComp
    Shape {
      width: bridge.width; height: bridge.height
      preferredRendererType: bridge.rendererType
      ShapePath {
        fillColor: bridge.fillColor
        strokeWidth: -1
        startX: bridge.m - 1; startY: bridge.yP
        PathLine { x: bridge.rx - 1; y: bridge.yP }
        PathLine { x: bridge.rx - 1; y: bridge.yC - bridge.rr }
        PathLine { x: bridge.rx; y: bridge.yC - bridge.rr }
        PathArc { x: bridge.rx + bridge.rr; y: bridge.yC
          radiusX: Math.max(0.01, bridge.rr); radiusY: Math.max(0.01, bridge.rr); direction: PathArc.Counterclockwise }
        PathLine { x: bridge.rx + bridge.rr; y: bridge.yC + bridge.ov }
        PathLine { x: bridge.m - 1; y: bridge.yC + bridge.ov }
      }
      // The outline: down the pill's side, then the arc, as one stroke.
      ShapePath {
        fillColor: "transparent"
        strokeColor: bridge.lineColor
        strokeWidth: 1
        capStyle: ShapePath.FlatCap
        startX: bridge.rx - 0.5; startY: Math.max(0, Math.min(bridge.yP, bridge.yC - bridge.rr))
        PathLine { x: bridge.rx - 0.5; y: bridge.yC - bridge.rr }
        PathArc { x: bridge.rx + bridge.rr; y: bridge.yC + 0.5
          radiusX: bridge.rr + 0.5; radiusY: bridge.rr + 0.5; direction: PathArc.Counterclockwise }
      }
    }
  }
  Loader { anchors.fill: parent; sourceComponent: halfComp }
  Loader {
    anchors.fill: parent
    sourceComponent: halfComp
    transform: Scale { xScale: -1; origin.x: bridge.m }
  }
}

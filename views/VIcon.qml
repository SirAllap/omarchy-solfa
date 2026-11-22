import QtQuick
import QtQuick.Shapes

// One thin 24x24 vector icon (the calm mockup's set): outline strokes with
// round caps, or filled for the transport glyphs. It sits in the middle of
// its box, so it is centred by the box, not by the glyph's font metrics.
Item {
  id: root
  property string name: "play"
  property color color: "white"
  property bool filled: false
  property real size: 20
  property real stroke: 1.9
  width: size
  height: size
  readonly property var paths: ({
    play: "M6.5 5v14l11-7z",
    pause: "M6.5 5h3.5v14H6.5zM14 5h3.5v14H14z",
    next: "M6 5l10 7-10 7zM17.5 5H20v14h-2.5z",
    prev: "M18 5L8 12l10 7zM6.5 5H4v14h2.5z",
    heart: "M12 20.5S3.5 15.4 3.5 9.4A4.6 4.6 0 0 1 12 7a4.6 4.6 0 0 1 8.5 2.4c0 6-8.5 11.1-8.5 11.1z",
    shuffle: "M3 7h3.5c3.5 0 4.5 10 8 10H20M3 17h3.5c1.5 0 2.5-2 3.3-3.5M13.5 9c.8-1 1.6-2 3-2H20M17.5 4l3 3-3 3M17.5 14l3 3-3 3",
    repeat: "M4 11V9.5A2.5 2.5 0 0 1 6.5 7H19M16 4l3 3-3 3M20 13v1.5a2.5 2.5 0 0 1-2.5 2.5H5M8 14l-3 3 3 3",
    repeatOnce: "M4 11V9.5A2.5 2.5 0 0 1 6.5 7H19M16 4l3 3-3 3M20 13v1.5a2.5 2.5 0 0 1-2.5 2.5H5M8 14l-3 3 3 3M11 10.5l1.2-.8V14",
    queue: "M4 6h16M4 12h16M4 18h9M17 16v4M15 18h4",
    volume: "M4 9.5v5h3.5L12.5 19V5L7.5 9.5zM16 9a4.5 4.5 0 0 1 0 6M18.5 6.5a8 8 0 0 1 0 11",
    mute: "M4 9.5v5h3.5L12.5 19V5L7.5 9.5zM16.5 9.5l5 5M21.5 9.5l-5 5",
    moon: "M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z",
    radio: "M5 8.5a9 9 0 0 0 0 7M19 8.5a9 9 0 0 1 0 7M8.5 10.5a4.5 4.5 0 0 0 0 3M15.5 10.5a4.5 4.5 0 0 1 0 3M12 11a1 1 0 1 0 0 2 1 1 0 0 0 0-2z"
  })
  Shape {
    width: 24
    height: 24
    scale: root.size / 24
    transformOrigin: Item.TopLeft
    preferredRendererType: Shape.CurveRenderer
    ShapePath {
      fillColor: root.filled ? root.color : "transparent"
      strokeColor: root.filled && root.name !== "heart" ? "transparent" : root.color
      strokeWidth: root.filled && root.name !== "heart" ? 0 : root.stroke
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin
      PathSvg { path: root.paths[root.name] || "" }
    }
  }
}

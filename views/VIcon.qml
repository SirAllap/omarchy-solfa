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
    gear: "M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 0 1 0 2.83 2 2 0 0 1-2.83 0l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-2 2 2 2 0 0 1-2-2v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 0 1-2.83 0 2 2 0 0 1 0-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1-2-2 2 2 0 0 1 2-2h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 0 1 0-2.83 2 2 0 0 1 2.83 0l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 2-2 2 2 0 0 1 2 2v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 0 1 2.83 0 2 2 0 0 1 0 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 2 2 2 2 0 0 1-2 2h-.09a1.65 1.65 0 0 0-1.51 1z",
    sun: "M12 8.5a3.5 3.5 0 1 0 0 7 3.5 3.5 0 0 0 0-7zM12 2.5v3M12 18.5v3M2.5 12h3M18.5 12h3M5.3 5.3l2.1 2.1M16.6 16.6l2.1 2.1M5.3 18.7l2.1-2.1M16.6 7.4l2.1-2.1",
    power: "M12 3v8M7 6.5a7.5 7.5 0 1 0 10 0",
    search: "M10.5 4a6.5 6.5 0 1 0 0 13 6.5 6.5 0 0 0 0-13zM15.5 15.5L20 20",
    library: "M5 4v16M10 4v16M14.5 5.5l4.5 14",
    lyrics: "M4 6h16M4 11h12M4 16h16M4 21h8",
    history: "M3.5 12a8.5 8.5 0 1 0 2.6-6.1M3.5 4v4.5H8M12 8v4.5l3 1.5",
    close: "M6 6l12 12M18 6L6 18",
    plus: "M12 5v14M5 12h14",
    queue: "M4 6h16M4 12h16M4 18h9M17 16v4M15 18h4",
    playlistRemove: "M4 6h16M4 12h16M4 18h9M15 16l4 4M19 16l-4 4",
    share: "M12 15V4M7.5 8.5L12 4l4.5 4.5M5 12v6.5A1.5 1.5 0 0 0 6.5 20h11a1.5 1.5 0 0 0 1.5-1.5V12",
    volume: "M4 9.5v5h3.5L12.5 19V5L7.5 9.5zM16 9a4.5 4.5 0 0 1 0 6M18.5 6.5a8 8 0 0 1 0 11",
    mute: "M4 9.5v5h3.5L12.5 19V5L7.5 9.5zM16.5 9.5l5 5M21.5 9.5l-5 5",
    moon: "M20 14.5A8 8 0 0 1 9.5 4a8 8 0 1 0 10.5 10.5z",
    user: "M12 11.500a4 4 0 1 0 0-8 4 4 0 0 0 0 8zM4.500 20.500c0-3.800 3.400-5.500 7.500-5.500s7.500 1.700 7.500 5.500",
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

import QtQuick

// The bar's round cover inside its progress ring. The gap between ring and
// cover is a whole pixel count, the same on every side: an odd total gap
// put the cover half a pixel off centre, and Qt rounds a centred item to a
// whole pixel, so the cover sat up and to the left in its ring.
Item {
  id: root

  property int barSize: 26
  property bool hasTrack: false
  property real progress: 0
  property color ringColor: "white"
  property color trackColor: "transparent"
  property url source: ""
  property color foreground: "white"
  property color fill: "transparent"
  property string fontFamily: ""
  property bool dim: false

  readonly property int gap: Math.max(2, Math.round(barSize * 0.1))

  width: Math.round(barSize * 0.78)
  height: width

  ProgressRing {
    anchors.fill: parent
    visible: root.hasTrack
    progress: root.progress
    thickness: Math.max(1.5, Math.round(root.barSize * 0.07))
    color: root.ringColor
    trackColor: root.trackColor
  }

  RoundCover {
    x: root.hasTrack ? root.gap : 0
    y: x
    width: root.width - 2 * x
    height: width
    source: root.source
    foreground: root.foreground
    fill: root.fill
    fontFamily: root.fontFamily
    dim: root.dim
  }
}

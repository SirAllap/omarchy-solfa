import QtQuick
import QtQuick.Shapes
import "../lib"
import qs.Ui
import qs.Commons

// Loading state on a cover: a bright beam runs around the cover's rounded edge, over a soft
// dark veil, so "loading" reads at a glance and stays inside the cover's own corners.
// Reduce motion: the beam stands still.
Item {
  id: root
  property real radius: 0
  property color color: Calm.accent
  property bool running: visible
  anchors.fill: parent

  Rectangle {
    anchors.fill: parent
    radius: root.radius
    color: Qt.rgba(0, 0, 0, 0.45)
  }

  Shape {
    id: shape
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    readonly property real w: 5
    // Perimeter of the rounded rectangle the stroke runs on, in pixels.
    readonly property real r: Math.max(0, root.radius - w / 2)
    readonly property real per: 2 * (width - w - 2 * r) + 2 * (height - w - 2 * r) + 2 * Math.PI * r
    property real phase: 0
    // The track: a faint full ring.
    ShapePath {
      strokeWidth: shape.w
      strokeColor: Qt.rgba(root.color.r, root.color.g, root.color.b, 0.22)
      fillColor: "transparent"
      PathRectangle { x: shape.w / 2; y: shape.w / 2; width: shape.width - shape.w; height: shape.height - shape.w; radius: shape.r }
    }
    // The beam: one dash, a quarter of the way round, running along it.
    ShapePath {
      strokeWidth: shape.w
      strokeColor: root.color
      fillColor: "transparent"
      capStyle: ShapePath.RoundCap
      strokeStyle: ShapePath.DashLine
      dashPattern: [shape.per * 0.3 / shape.w, shape.per * 0.7 / shape.w]
      dashOffset: -shape.phase / shape.w
      PathRectangle { x: shape.w / 2; y: shape.w / 2; width: shape.width - shape.w; height: shape.height - shape.w; radius: shape.r }
    }
    NumberAnimation on phase {
      running: root.running && !Style.reduceMotion
      from: 0
      to: shape.per
      duration: 1300
      loops: Animation.Infinite
    }
  }

  // Centre: equaliser bars bouncing in a frosted disc, readable on a light or a dark cover.
  Rectangle {
    anchors.centerIn: parent
    width: Math.round(Math.min(root.width, root.height) * 0.44)
    height: width
    radius: width / 2
    color: Qt.rgba(0.06, 0.06, 0.09, 0.62)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.14)
    Row {
      anchors.centerIn: parent
      spacing: Math.max(2, Math.round(parent.width * 0.07))
      Repeater {
        model: 4
        Rectangle {
          required property int index
          readonly property real full: root.height * 0.24
          width: Math.max(3, Math.round(root.width * 0.035))
          radius: width / 2
          anchors.verticalCenter: parent.verticalCenter
          color: "white"
          height: full * 0.3
          SequentialAnimation on height {
            running: root.running && !Style.reduceMotion
            loops: Animation.Infinite
            PauseAnimation { duration: index * 110 }
            NumberAnimation { to: full; duration: 260; easing.type: Easing.OutQuad }
            NumberAnimation { to: full * 0.3; duration: 260; easing.type: Easing.InQuad }
            PauseAnimation { duration: (3 - index) * 110 }
          }
        }
      }
    }
  }
}

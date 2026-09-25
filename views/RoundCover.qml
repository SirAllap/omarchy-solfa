import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Window
import "../lib/Icons.js" as Icons

// A cover cut to a circle (the record motif of Solfa), with a glyph while
// there is no picture. `dim` greys it out, for a paused song.
Item {
  id: root

  property url source: ""
  property color foreground: "white"
  property color fill: "transparent"
  property string glyph: Icons.note
  property string fontFamily: ""
  property bool dim: false

  implicitWidth: 32
  implicitHeight: 32

  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: root.fill
    visible: img.status !== Image.Ready

    Text {
      anchors.centerIn: parent
      text: root.glyph
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Math.max(8, Math.round(root.width * 0.45))
    }
  }

  Image {
    id: img
    anchors.fill: parent
    source: root.source
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
    smooth: true
    mipmap: true
    // Decode at the size it is drawn (HiDPI included), not at 544 px.
    sourceSize.width: Math.ceil(root.width * 2)
    sourceSize.height: Math.ceil(root.height * 2)
    visible: false
  }

  // Cut to a circle by the same vector renderer as the bar's ring, so the
  // two share one centre at any scale (a masked texture lands on the pixel
  // grid and sat up to a pixel off at 125 % and 150 %).
  Shape {
    anchors.fill: parent
    visible: img.status === Image.Ready
    preferredRendererType: Shape.CurveRenderer
    opacity: root.dim ? 0.75 : 1
    layer.enabled: root.dim
    layer.effect: MultiEffect { saturation: -0.8 }

    ShapePath {
      strokeWidth: -1
      strokeColor: "transparent"
      fillItem: img
      // The picture comes in at its own size in screen pixels: scale it to
      // cover the circle and centre it ("object-fit: cover" on the web).
      fillTransform: {
        // (Window.devicePixelRatio is Qt 6.11; the screen's ratio before that.)
        var win = root.Window.window
        var dpr = (win && win.devicePixelRatio) || root.Screen.devicePixelRatio || 1
        var iw = Math.max(1, img.implicitWidth) / dpr, ih = Math.max(1, img.implicitHeight) / dpr
        var k = Math.max(root.width / iw, root.height / ih)
        return PlanarTransform.fromAffineMatrix(k, 0, 0, k, (root.width - iw * k) / 2, (root.height - ih * k) / 2)
      }
      PathAngleArc {
        centerX: root.width / 2; centerY: root.height / 2
        radiusX: root.width / 2; radiusY: root.height / 2
        startAngle: 0; sweepAngle: 360
      }
    }
  }
}

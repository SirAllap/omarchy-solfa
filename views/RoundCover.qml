import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import QtQuick.Window
import qs.Commons
import "../lib/Icons.js" as Icons
import "../lib/Motion.js" as Motion

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
  // Asleep (the bar's last song while Solfa is off): fully grey and half faded.
  property bool asleep: false
  // The calm vinyl motif (rings and a label dot) in place of the glyph.
  property bool motif: false
  // Corner radius; below zero is a full circle (the bar's record cover).
  property real cornerRadius: -1
  readonly property real cr: cornerRadius >= 0 ? Math.min(cornerRadius, Math.min(width, height) / 2) : Math.min(width, height) / 2
  // Life: while the panel is open and a song plays the cover breathes, and
  // it can look toward a control (a critically damped spring, so a new look
  // never jumps). All of it stops with the system's reduce-motion setting.
  property bool breathe: false
  property bool live: false
  property bool reduceMotion: false   // the owner of the cover passes Style.reduceMotion
  readonly property bool moving: !reduceMotion
  property real gx: 0
  property real gy: 0
  property real pulse: 0
  Behavior on gx { enabled: root.moving; SpringAnimation { spring: 4.5; damping: 1; epsilon: 0.01 } }
  Behavior on gy { enabled: root.moving; SpringAnimation { spring: 4.5; damping: 1; epsilon: 0.01 } }
  // Only a cover that breathes gets a transform: a plain one stays on the pixel grid.
  scale: breathe ? 1 + 0.03 * pulse : 1
  transform: breathe ? [moveBy] : []
  Translate { id: moveBy; x: root.gx; y: root.gy }
  SequentialAnimation on pulse {
    running: root.breathe && root.live && root.moving
    loops: Animation.Infinite
    NumberAnimation { to: 1; duration: 2100; easing.type: Easing.InOutSine }
    NumberAnimation { to: 0; duration: 2100; easing.type: Easing.InOutSine }
  }
  Timer { id: back; interval: 520; onTriggered: { root.gx = 0; root.gy = 0 } }
  // Look toward `item` (any item in the same window), then settle back.
  function lookAt(item) {
    if (!root.moving || !root.live || !item) return
    var p = item.mapToItem(root, item.width / 2, item.height / 2)
    var g = Motion.gaze(p.x - width / 2, p.y - height / 2, Math.max(2, width * 0.09))
    root.gx = g.x; root.gy = g.y
    back.restart()
  }
  // After a quiet spell it glances elsewhere (a seeded direction), then rests.
  property int glances: 0
  Timer {
    interval: Motion.idleMs; running: root.breathe && root.live && root.moving; repeat: true
    onTriggered: {
      root.glances += 1
      var a = Motion.rand(root.glances + 40) * 6.283
      root.gx = Math.cos(a) * root.width * 0.08; root.gy = Math.sin(a) * root.width * 0.08
      back.restart()
    }
  }

  implicitWidth: 32
  implicitHeight: 32

  Rectangle {
    anchors.fill: parent
    radius: root.cr
    color: root.fill
    visible: img.status !== Image.Ready && !root.heldShown

    Rectangle { visible: root.motif; anchors.centerIn: parent; width: parent.width * 0.62; height: width; radius: width / 2; color: "transparent"; border.width: 1; border.color: Util.alpha(root.foreground, 0.16) }
    Rectangle { visible: root.motif; anchors.centerIn: parent; width: parent.width * 0.34; height: width; radius: width / 2; color: "transparent"; border.width: 1; border.color: Util.alpha(root.foreground, 0.2) }
    Rectangle { visible: root.motif; anchors.centerIn: parent; width: parent.width * 0.09; height: width; radius: width / 2; color: Util.alpha(root.foreground, 0.55) }
    Text {
      visible: !root.motif
      anchors.centerIn: parent
      text: root.glyph
      textFormat: Text.PlainText
      color: root.foreground
      opacity: 0.7
      font.family: root.fontFamily
      font.pixelSize: Math.max(8, Math.round(root.width * 0.45))
    }
  }

  // hold: keep the last picture that was ready on screen while the source changes
  // (the tile's image, then the page's own): a new picture fades in over it, the
  // source never shows a gap. For a cover that stays the same item (page header,
  // grid tile); not for recycled list rows.
  property bool hold: false
  readonly property bool heldShown: hold && held.status === Image.Ready

  Image {
    id: img
    anchors.fill: parent
    source: root.source
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
    cache: true
    smooth: true
    mipmap: true
    // Two decode sizes, so a tile and the page header opened from it ask the pixmap
    // cache for the same image (no second fetch): small covers (rows, bar) 128 px,
    // larger ones (tiles, page covers) 512 px.
    sourceSize.width: root.width * 2 <= 128 ? 128 : 512
    sourceSize.height: root.width * 2 <= 128 ? 128 : 512
    visible: false
    onStatusChanged: if (status === Image.Ready && root.hold) held.source = source
  }

  // The last ready picture: from the pixmap cache, so it is there at once.
  Image {
    id: held
    anchors.fill: parent
    fillMode: Image.PreserveAspectCrop
    asynchronous: false
    cache: true
    smooth: true
    mipmap: true
    sourceSize: img.sourceSize
    visible: false
  }

  // Cut to a circle by the same vector renderer as the bar's ring, so the
  // two share one centre at any scale (a masked texture lands on the pixel
  // grid and sat up to a pixel off at 125 % and 150 %).
  component CoverShape: Shape {
    id: cs
    property Item pic: null
    anchors.fill: parent
    preferredRendererType: Shape.CurveRenderer
    layer.enabled: root.dim || root.asleep
    layer.effect: MultiEffect { saturation: root.asleep ? -1 : -0.8 }

    ShapePath {
      strokeWidth: -1
      strokeColor: "transparent"
      fillItem: cs.pic
      // The picture comes in at its own size in screen pixels: scale it to
      // cover the circle and centre it ("object-fit: cover" on the web).
      fillTransform: {
        // (Window.devicePixelRatio is Qt 6.11; the screen's ratio before that.)
        var win = root.Window.window
        var dpr = (win && win.devicePixelRatio) || root.Screen.devicePixelRatio || 1
        var iw = Math.max(1, cs.pic.implicitWidth) / dpr, ih = Math.max(1, cs.pic.implicitHeight) / dpr
        var k = Math.max(root.width / iw, root.height / ih) * 1.03   // a hair over, so the edge never samples past the crop
        return PlanarTransform.fromAffineMatrix(k, 0, 0, k, (root.width - iw * k) / 2, (root.height - ih * k) / 2)
      }
      PathSvg {
        path: {
          var w = root.width, h = root.height, r = root.cr
          return "M" + r + " 0H" + (w - r) + "A" + r + " " + r + " 0 0 1 " + w + " " + r + "V" + (h - r)
            + "A" + r + " " + r + " 0 0 1 " + (w - r) + " " + h + "H" + r + "A" + r + " " + r + " 0 0 1 0 " + (h - r)
            + "V" + r + "A" + r + " " + r + " 0 0 1 " + r + " 0Z"
        }
      }
    }
  }

  CoverShape {
    pic: held
    visible: root.heldShown
    opacity: root.asleep ? 0.5 : root.dim ? 0.75 : 1
  }
  CoverShape {
    pic: img
    visible: opacity > 0
    opacity: (img.status === Image.Ready ? 1 : 0) * (root.asleep ? 0.5 : root.dim ? 0.75 : 1)
    // fades in over a held picture; with none, it is simply there
    Behavior on opacity { enabled: root.heldShown && !root.reduceMotion; NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
  }
}

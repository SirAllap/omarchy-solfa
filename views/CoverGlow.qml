import QtQuick
import QtQuick.Effects

// A soft blurred glow of a cover, to sit behind a card or a hero. Independent of any view:
// give it a source, size it and place it behind (z: -1); it paints only itself.
//   source   the cover's url (empty: nothing is drawn)
//   active   false: grey (no colour); true: the cover's own colour
//   opacity  the Item's own opacity, the glow's strength (keep it low, about 0.3 to 0.4)
// The cover is read at a small size (the blur hides the detail), so a change of cover costs
// one small decode and one blur pass, not a frame-by-frame cost.
Item {
  id: root

  property url source: ""
  property bool active: true
  // Colour pulled out when active, and how fast active/rest cross-fade.
  property real saturation: 0.35
  property int fadeMs: 400
  property bool reduceMotion: false

  opacity: 0.35
  visible: source.toString() !== ""

  // The blur runs on a small copy, padded by blurMax on every side, then scaled up to this
  // item: so the glow fades to nothing at the edge (no square border), at the cost of a tiny pass.
  readonly property int core: 96
  readonly property int pad: 64

  Image {
    id: img
    visible: false
    width: root.core
    height: root.core
    source: root.source
    sourceSize.width: root.core
    sourceSize.height: root.core
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
  }
  MultiEffect {
    anchors.centerIn: parent
    width: root.core
    height: root.core
    source: img
    autoPaddingEnabled: true
    blurEnabled: true
    blurMax: root.pad
    blur: 1
    transform: Scale {
      origin.x: root.core / 2
      origin.y: root.core / 2
      xScale: root.width / (root.core + 2 * root.pad)
      yScale: root.height / (root.core + 2 * root.pad)
    }
    saturation: root.active ? root.saturation : -1
    Behavior on saturation { enabled: !root.reduceMotion; NumberAnimation { duration: root.fadeMs } }
  }
}

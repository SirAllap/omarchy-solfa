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

  Image {
    id: img
    visible: false
    anchors.fill: parent
    source: root.source
    sourceSize.width: 96
    sourceSize.height: 96
    fillMode: Image.PreserveAspectCrop
    asynchronous: true
  }
  MultiEffect {
    anchors.fill: parent
    source: img
    blurEnabled: true
    blurMax: 64
    blur: 1
    saturation: root.active ? root.saturation : -1
    Behavior on saturation { enabled: !root.reduceMotion; NumberAnimation { duration: root.fadeMs } }
  }
}

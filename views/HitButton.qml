import QtQuick
import qs.Ui
import qs.Commons

// The kit's button with a hit box that does not depend on its glyph: at
// least `minSize` on each side (a square for an icon), and a small press
// that follows the pointer. Hover, pressed and keyboard-cursor fills come
// from the kit, so every theme still decides the colours.
Button {
  id: root

  // Smallest side of the box; the glyph sits in its middle.
  property real minSize: Style.space(32)
  // A square box for an icon-only button, grown to fit a label otherwise.
  readonly property bool iconOnly: text === ""

  width: iconOnly ? minSize : Math.max(minSize, implicitWidth)
  height: Math.max(minSize, implicitHeight)
  horizontalPadding: iconOnly ? 0 : Math.max(Style.spacing.controlPaddingX, Style.space(12))
  verticalPadding: 0

  // Pressed: shrink a little, straight away, and let go just as fast.
  // Only a pointer press moves it; a key never does.
  scale: press.active ? 0.94 : 1
  Behavior on scale { NumberAnimation { duration: 110; easing.type: Easing.OutCubic } }

  // Above the kit's MouseArea: watches the press without taking it.
  Item {
    anchors.fill: parent
    PointHandler { id: press; acceptedButtons: Qt.LeftButton; enabled: root.enabled }
  }
}

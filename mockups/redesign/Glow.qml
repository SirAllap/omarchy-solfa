import QtQuick
import QtQuick.Shapes

// A soft round light: a radial fade from colour to nothing. Cheap, no blur.
Shape {
  id: g
  property color color: Theme.accent
  property real strength: 0.6
  property bool keep: false   // only event glows are kept; decorative glows draw nothing
  visible: keep
  ShapePath {
    strokeColor: "transparent"
    fillGradient: RadialGradient {
      centerX: g.width / 2; centerY: g.height / 2
      centerRadius: Math.min(g.width, g.height) / 2
      focalX: centerX; focalY: centerY
      GradientStop { position: 0; color: Theme.a(g.color, g.keep ? g.strength : 0) }
      GradientStop { position: 0.55; color: Theme.a(g.color, g.keep ? g.strength * 0.35 : 0) }
      GradientStop { position: 1; color: Theme.a(g.color, 0) }
    }
    startX: 0; startY: 0
    PathLine { x: g.width; y: 0 }
    PathLine { x: g.width; y: g.height }
    PathLine { x: 0; y: g.height }
    PathLine { x: 0; y: 0 }
  }
}

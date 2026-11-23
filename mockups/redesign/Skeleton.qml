import QtQuick

// A loading placeholder with a light that sweeps across it.
Rectangle {
  id: sk
  color: Theme.wash
  radius: 8
  clip: true
  Rectangle {
    id: sweep
    width: sk.width * 0.5
    height: sk.height
    rotation: 0
    gradient: Gradient {
      orientation: Gradient.Horizontal
      GradientStop { position: 0; color: "transparent" }
      GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.07) }
      GradientStop { position: 1; color: "transparent" }
    }
    NumberAnimation on x { from: -sk.width * 0.5; to: sk.width; duration: 1300; loops: Animation.Infinite; easing.type: Easing.InOutSine }
  }
}

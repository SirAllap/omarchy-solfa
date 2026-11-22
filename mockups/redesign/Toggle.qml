import QtQuick

// A switch whose knob springs across and stretches while it moves.
Item {
  id: t
  property bool checked: false
  property bool hot: false
  signal toggled()
  width: 44; height: 26
  Glow { visible: t.checked; anchors.centerIn: parent; width: 90; height: 60; color: Theme.accent; strength: 0.22 }
  Rectangle {
    anchors.fill: parent; radius: 13
    color: t.checked ? "transparent" : Qt.rgba(1, 1, 1, 0.1)
    border.width: 1; border.color: t.checked ? "transparent" : Theme.hair
    gradient: t.checked ? onFill : null
  }
  Gradient { id: onFill; orientation: Gradient.Horizontal; GradientStop { position: 0; color: Theme.accent } GradientStop { position: 1; color: Theme.accent2 } }
  Rectangle {
    id: knob
    y: 3; height: 20
    width: ma.pressed || t.hot ? 26 : 20
    radius: 10
    x: t.checked ? t.width - width - 3 : 3
    color: t.checked ? "#fff" : Theme.dim
    Behavior on x { enabled: !Motion.reduce; SpringAnimation { spring: 5.5; damping: 0.38; epsilon: 0.25 } }
    Behavior on width { enabled: !Motion.reduce; NumberAnimation { duration: 120 } }
  }
  MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: { t.checked = !t.checked; t.toggled() } }
}

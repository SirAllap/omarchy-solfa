import QtQuick

// A round icon button with a spring on hover and press. "hot" forces the
// hover look, so a still picture can show it.
Item {
  id: b
  property string icon: "play"
  property real size: 38
  property real glyph: 18
  property bool primary: false
  property bool active: false
  property bool filled: false
  property bool hot: false
  property bool enabled2: true
  property string tip: ""
  signal clicked()
  readonly property bool over: hot || (ma.containsMouse && enabled2)
  width: size
  height: size
  opacity: enabled2 ? 1 : 0.35
  property real s: ma.pressed ? 0.9 : (over ? 1.08 : 1)
  Behavior on s { enabled: !Motion.reduce; SpringAnimation { spring: 6; damping: 0.4; epsilon: 0.001 } }
  scale: s

  Glow {
    visible: b.primary
    anchors.centerIn: parent
    width: b.size * 2.2
    height: width
    color: Theme.accent2
    strength: b.over ? 0.5 : 0.3
    Behavior on strength { enabled: !Motion.reduce; NumberAnimation { duration: 220 } }
  }
  Rectangle {
    anchors.fill: parent
    radius: width / 2
    color: b.primary ? "transparent" : (b.active ? Theme.a(Theme.accent, 0.2) : (b.over ? Qt.rgba(1, 1, 1, 0.1) : "transparent"))
    Behavior on color { enabled: !Motion.reduce; ColorAnimation { duration: 160 } }
    gradient: b.primary ? primaryFill : null
  }
  Gradient {
    id: primaryFill
    orientation: Gradient.Horizontal
    GradientStop { position: 0; color: Theme.accent }
    GradientStop { position: 1; color: Theme.accent2 }
  }
  Icon {
    anchors.centerIn: parent
    name: b.icon
    size: b.glyph
    filled: b.filled || b.icon === "play" || b.icon === "pause" || b.icon === "next" || b.icon === "prev"
    color: b.primary ? "#14101f" : (b.active ? Theme.accent : (b.over ? Theme.fg : Theme.dim))
    Behavior on color { enabled: !Motion.reduce; ColorAnimation { duration: 160 } }
  }
  Rectangle {
    visible: b.tip !== "" && b.over
    y: -height - 8
    anchors.horizontalCenter: parent.horizontalCenter
    width: tipText.width + 16
    height: 24
    radius: 8
    color: Theme.raised
    border.color: Theme.hair
    Text { id: tipText; anchors.centerIn: parent; text: b.tip; color: Theme.fg; font.family: Theme.font; font.pixelSize: 11 }
  }
  MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
}

import QtQuick

// A text button. kind: primary | quiet | danger | ghost.
Item {
  id: b
  property string text: "Button"
  property string icon: ""
  property string kind: "quiet"
  property bool hot: false
  property bool busy: false
  property bool compact: false
  signal clicked()
  readonly property bool over: hot || ma.containsMouse
  implicitWidth: row.width + (compact ? 22 : 30)
  implicitHeight: compact ? 28 : 36
  width: implicitWidth
  height: implicitHeight
  property real s: ma.pressed ? 0.95 : (over ? 1.03 : 1)
  Behavior on s { enabled: !Motion.reduce; SpringAnimation { spring: 6; damping: 0.42; epsilon: 0.001 } }
  scale: s
  Glow {
    visible: b.kind === "primary"
    anchors.centerIn: parent
    width: parent.width * 1.5; height: parent.height * 3
    color: Theme.accent2
    strength: b.over ? 0.34 : 0.18
  }
  Rectangle {
    anchors.fill: parent
    radius: height / 2
    color: b.kind === "primary" ? "transparent"
      : b.kind === "danger" ? Theme.a(Theme.err, b.over ? 0.28 : 0.16)
      : b.kind === "ghost" ? (b.over ? Theme.wash : "transparent")
      : (b.over ? Qt.rgba(1, 1, 1, 0.12) : Theme.wash)
    border.width: b.kind === "primary" ? 0 : 1
    border.color: b.kind === "danger" ? Theme.a(Theme.err, 0.45) : Theme.hair
    Behavior on color { enabled: !Motion.reduce; ColorAnimation { duration: 150 } }
    gradient: b.kind === "primary" ? fill : null
  }
  Gradient {
    id: fill
    orientation: Gradient.Horizontal
    GradientStop { position: 0; color: Theme.accent }
    GradientStop { position: 1; color: Theme.accent2 }
  }
  Row {
    id: row
    anchors.centerIn: parent
    spacing: 7
    Spinner { visible: b.busy; size: 14; anchors.verticalCenter: parent.verticalCenter; color: "#14101f" }
    Icon { visible: b.icon !== "" && !b.busy; name: b.icon; size: 15; anchors.verticalCenter: parent.verticalCenter; color: b.kind === "primary" ? "#14101f" : (b.kind === "danger" ? Theme.err : Theme.fg) }
    Text {
      text: b.text
      anchors.verticalCenter: parent.verticalCenter
      color: b.kind === "primary" ? "#14101f" : (b.kind === "danger" ? Theme.err : Theme.fg)
      font.family: Theme.font; font.pixelSize: b.compact ? 12 : 13; font.weight: Font.DemiBold
    }
  }
  MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: b.clicked() }
}

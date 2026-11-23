import QtQuick

Item {
  id: c
  property string text: ""
  property bool on: false
  property bool hot: false
  property string icon: ""
  signal clicked()
  width: row.width + 24; height: 32
  property real s: ma.pressed ? 0.94 : 1
  Behavior on s { enabled: !Motion.reduce; SpringAnimation { spring: 6; damping: 0.4; epsilon: 0.001 } }
  scale: s
  Rectangle { anchors.fill: parent; radius: 16
    color: c.on ? Theme.a(Theme.accent, 0.2) : (c.hot || ma.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Theme.wash)
    border.width: 1; border.color: c.on ? Theme.a(Theme.accent, 0.55) : Theme.hair
    Behavior on color { enabled: !Motion.reduce; ColorAnimation { duration: 160 } } }
  Row { id: row; anchors.centerIn: parent; spacing: 6
    Icon { visible: c.icon !== ""; anchors.verticalCenter: parent.verticalCenter; name: c.icon; size: 14; color: c.on ? Theme.accent : Theme.dim }
    Text { anchors.verticalCenter: parent.verticalCenter; text: c.text; color: c.on ? Theme.fg : Theme.dim; font.family: Theme.font; font.pixelSize: 13; font.weight: c.on ? Font.DemiBold : Font.Normal } }
  MouseArea { id: ma; anchors.fill: parent; hoverEnabled: true; onClicked: c.clicked() }
}
